import Foundation
import Combine

private struct MessageMediaRecord: Codable {
    var audio: String?
    var image: String?
    var duration: Double?
    var speechScript: String?
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
    private let localConversationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("lumi-conversation.json")

    init(chatID: String = "default", api: LumiAPIClient = LumiAPIClient(), initialMessages: [ChatMessage] = [], shouldLoadFromServer: Bool = true) {
        self.chatID = chatID
        self.api = api
        self.shouldLoadFromServer = shouldLoadFromServer
        self.messages = initialMessages
    }

    func load() async {
        let localMessages = loadLocalConversation()
        guard shouldLoadFromServer else {
            if messages.isEmpty { messages = localMessages }
            return
        }
        do {
            let loaded = try await api.fetchThread(id: chatID).messages
            let remoteMessages = loaded.flatMap { message in
                let restored = restoreMedia(for: message)
                return restored.role == .assistant ? assistantBubbles(from: restored) : [restored]
            }
            let isEmptyServerSeed = remoteMessages.count == 1 && remoteMessages[0].role == .assistant && remoteMessages[0].content == "下午的风很轻，想和你说说话。"
            if !isEmptyServerSeed && !remoteMessages.isEmpty {
                // Keep locally saved messages if the backend has since been reset. Old versions
                // split AI replies into random-ID lines; suppress only those copies when the
                // canonical reply with the same timestamp and text is available from the server.
                let remoteIDs = Set(remoteMessages.map(\.id))
                let localOnly = localMessages.filter { local in
                    guard !remoteIDs.contains(local.id) else { return false }
                    if local.role == .assistant {
                        return !remoteMessages.contains { remote in
                            remote.role == .assistant
                                && abs(remote.createdAt.timeIntervalSince(local.createdAt)) < 1
                                && remote.content.contains(local.content)
                        }
                    }
                    return true
                }
                messages = (remoteMessages + localOnly).sorted { $0.createdAt < $1.createdAt }
            } else {
                messages = localMessages.isEmpty ? remoteMessages : localMessages
            }
            saveLocalConversation()
        }
        catch {
            if !localMessages.isEmpty { messages = localMessages }
            else if messages.isEmpty { errorMessage = friendlyError(error) }
        }
    }

    func send(imageBase64: String? = nil, imageFileName: String? = nil, tts: TTSRequestSettings? = nil, emojiCatalog: [String: [String]] = [:]) async {
        let typedContent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!typedContent.isEmpty || imageBase64 != nil), !isSending else { return }
        let content = typedContent.isEmpty && imageBase64 != nil ? "请描述这张图片。" : typedContent
        draft = ""
        let optimisticID = UUID()
        messages.append(ChatMessage(id: optimisticID, role: .user, content: content, createdAt: .now, localImageFileName: imageFileName))
        if let imageFileName { saveMedia(for: optimisticID, record: MessageMediaRecord(audio: nil, image: imageFileName, duration: nil, speechScript: nil)) }
        saveLocalConversation()
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.sendMessage(content, to: chatID, images: imageBase64.map { [$0] } ?? [], emojiCatalog: emojiCatalog, tts: tts)
            var confirmedUserMessage = response.userMessage
            confirmedUserMessage.localImageFileName = imageFileName
            if let optimisticIndex = messages.firstIndex(where: { $0.id == optimisticID }) {
                messages[optimisticIndex] = confirmedUserMessage
            } else if !messages.contains(where: { $0.id == confirmedUserMessage.id }) {
                messages.append(confirmedUserMessage)
            }
            if let imageFileName { saveMedia(for: confirmedUserMessage.id, record: MessageMediaRecord(audio: nil, image: imageFileName, duration: nil, speechScript: nil)) }
            saveLocalConversation()
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
                assistantMessage.speechScript = response.speechScript
                saveMedia(for: assistantMessage.id, record: MessageMediaRecord(audio: name, image: nil, duration: response.speechDuration, speechScript: response.speechScript))
            }
            let bubbles = assistantBubbles(from: assistantMessage)
            for (index, bubble) in bubbles.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(260)) }
                messages.append(bubble)
                saveLocalConversation()
            }
        } catch { errorMessage = friendlyError(error); saveLocalConversation() }
    }

    private func loadLocalConversation() -> [ChatMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: localConversationURL),
              let saved = try? decoder.decode([ChatMessage].self, from: data) else { return [] }
        return saved.map(restoreMedia(for:))
    }

    private func saveLocalConversation() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages) else { return }
        try? data.write(to: localConversationURL, options: .atomic)
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
        restored.speechScript = media.speechScript
        return restored
    }

    private func assistantBubbles(from message: ChatMessage) -> [ChatMessage] {
        let thinking = extractThinking(from: message.content)
        let visible = message.content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
        if visible.range(of: #"(?is)<(?:!doctype\s+html|/?(?:html|head|body|div|p|span|a|ul|ol|li|h[1-6]|table|thead|tbody|tr|td|th|svg|iframe|section|article|pre|code|blockquote|br|hr|style|script)\b[^>]*>"#, options: .regularExpression) != nil {
            return [ChatMessage(id: message.id, role: .assistant, content: visible, createdAt: message.createdAt, thinking: thinking)]
        }
        // Keep the requested pause/line-break rhythm as separate bubbles. The canonical server
        // message remains intact; local reconciliation matches each display line by text/time.
        let lines = visible
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var bubbles = lines.enumerated().map { index, line in
            ChatMessage(id: index == 0 && message.audioFileName == nil ? message.id : UUID(), role: .assistant, content: line, createdAt: message.createdAt, thinking: index == 0 ? thinking : nil)
        }
        if let audioFileName = message.audioFileName {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, audioFileName: audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript))
        }
        if bubbles.isEmpty, message.audioFileName != nil {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, thinking: thinking, audioFileName: message.audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript))
        }
        return bubbles.isEmpty ? [ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, thinking: thinking)] : bubbles
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
