import Foundation
import Combine

private struct MessageMediaRecord: Codable {
    var audio: String?
    var image: String?
    var duration: Double?
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var memoryNotice: String?

    private let chatID: String
    private let api: LumiAPIClient
    private let shouldLoadFromServer: Bool

    init(chatID: String = "default", api: LumiAPIClient = LumiAPIClient(), initialMessages: [ChatMessage] = [], shouldLoadFromServer: Bool = true) {
        self.chatID = chatID
        self.api = api
        self.shouldLoadFromServer = shouldLoadFromServer
        self.messages = initialMessages
    }

    func load() async {
        guard shouldLoadFromServer else { return }
        do {
            let loaded = try await api.fetchThread(id: chatID).messages
            messages = loaded.flatMap { message in
                let restored = restoreMedia(for: message)
                return restored.role == .assistant && restored.audioFileName == nil ? assistantBubbles(from: restored) : [restored]
            }
        }
        catch {
            // 首次加载失败时保留本地示例/缓存，不用系统英文网络弹窗打断界面。
            if messages.isEmpty { errorMessage = friendlyError(error) }
        }
    }

    func send(imageBase64: String? = nil, imageFileName: String? = nil, tts: TTSRequestSettings? = nil, emojiCatalog: [String: [String]] = [:]) async {
        let typedContent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!typedContent.isEmpty || imageBase64 != nil), !isSending else { return }
        let content = typedContent.isEmpty && imageBase64 != nil ? "请描述这张图片。" : typedContent
        draft = ""
        messages.append(
            ChatMessage(id: UUID(), role: .user, content: content, createdAt: .now, localImageFileName: imageFileName)
        )
        if let imageFileName { saveMedia(for: messages[messages.count - 1].id, record: MessageMediaRecord(audio: nil, image: imageFileName, duration: nil)) }
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.sendMessage(content, to: chatID, images: imageBase64.map { [$0] } ?? [], emojiCatalog: emojiCatalog, tts: tts)
            if response.memorySaved == true {
                memoryNotice = "-------沈屿记下了这一刻-------"
                Task {
                    try? await Task.sleep(for: .seconds(2.2))
                    if !Task.isCancelled { memoryNotice = nil }
                }
            }
            var assistantMessage = response.assistantMessage
            if let encoded = response.speechAudioBase64, let audio = Data(base64Encoded: encoded) {
                let name = "speech-\(assistantMessage.id.uuidString).mp3"
                let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
                try? audio.write(to: destination, options: .atomic)
                assistantMessage.audioFileName = name
                assistantMessage.speechDuration = response.speechDuration
                saveMedia(for: assistantMessage.id, record: MessageMediaRecord(audio: name, image: nil, duration: response.speechDuration))
            }
            let bubbles = assistantMessage.audioFileName == nil ? assistantBubbles(from: assistantMessage) : [assistantMessage]
            for (index, bubble) in bubbles.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(260)) }
                messages.append(bubble)
            }
        } catch { errorMessage = friendlyError(error) }
    }

    private func mediaRecords() -> [String: MessageMediaRecord] {
        guard let data = UserDefaults.standard.data(forKey: "lumi.messageMedia"),
              let records = try? JSONDecoder().decode([String: MessageMediaRecord].self, from: data) else { return [:] }
        return records
    }

    private func saveMedia(for id: UUID, record: MessageMediaRecord) {
        var records = mediaRecords()
        records[id.uuidString] = record
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: "lumi.messageMedia") }
    }

    private func restoreMedia(for message: ChatMessage) -> ChatMessage {
        guard let media = mediaRecords()[message.id.uuidString] else { return message }
        var restored = message
        restored.audioFileName = media.audio
        restored.localImageFileName = media.image
        restored.speechDuration = media.duration
        return restored
    }

    private func assistantBubbles(from message: ChatMessage) -> [ChatMessage] {
        let thinking = extractThinking(from: message.content)
        let visible = message.content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
        let parts = visible
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count > 1 else {
            return [ChatMessage(id: message.id, role: .assistant, content: parts.first ?? "", createdAt: message.createdAt, thinking: thinking)]
        }
        return parts.enumerated().map { index, part in
            ChatMessage(id: UUID(), role: .assistant, content: part, createdAt: message.createdAt, thinking: index == 0 ? thinking : nil)
        }
    }

    private func extractThinking(from content: String) -> String? {
        guard let range = content.range(of: #"(?is)<thinking>(.*?)</thinking>"#, options: .regularExpression) else { return nil }
        return String(content[range])
            .replacingOccurrences(of: #"(?is)^<thinking>|</thinking>$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "暂时无法连接网络，请稍后重试"
        }
        return error.localizedDescription
    }
}
