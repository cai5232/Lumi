import Foundation
import Combine
import UIKit

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
    @Published private(set) var isLoadingOlderHistory = false

    private let chatID: String
    private let api: LumiAPIClient
    private let shouldLoadFromServer: Bool
    private let localConversationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("lumi-conversation.json")
    private var nextHistoryBefore: Date?
    private var historyFullyLoaded = false

    init(chatID: String = "default", api: LumiAPIClient = LumiAPIClient(), initialMessages: [ChatMessage] = [], shouldLoadFromServer: Bool = true) {
        self.chatID = chatID
        self.api = api
        self.shouldLoadFromServer = shouldLoadFromServer
        self.messages = initialMessages
    }

    func load(waitForRemote: Bool = true) async {
        let localMessages = loadLocalConversation().map(restoreMedia)
        if messages.isEmpty, !localMessages.isEmpty {
            messages = Self.deduplicateHTMLCards(localMessages)
        }

        // When local history exists, the UI can open immediately while a later call refreshes the server copy.
        if !waitForRemote, !messages.isEmpty { return }

        guard shouldLoadFromServer else {
            if messages.isEmpty { messages = localMessages }
            return
        }
        do {
            let thread = try await api.fetchThread(id: chatID, limit: 100)
            let loaded = thread.messages.map(restoreMedia)
            let remoteMessages = Self.deduplicateHTMLCards(loaded.flatMap { message in
                let restored = message
                return restored.role == .assistant && restored.contentType != "call_record" && restored.contentType != "call_status" ? assistantBubbles(from: restored) : [restored]
            })
            let isEmptyServerSeed = remoteMessages.count == 1 && remoteMessages[0].role == .assistant && remoteMessages[0].content == "下午的风很轻，想和你说说话。"
            if !isEmptyServerSeed && !remoteMessages.isEmpty {
                // Keep locally saved messages if the backend has since been reset. Old versions
                // split AI replies into random-ID lines; suppress only those copies when the
                // canonical reply with the same timestamp and text is available from the server.
                let remoteIDs = Set(remoteMessages.map(\.id))
                let localOnly = localMessages.filter { local in
                    guard !remoteIDs.contains(local.id) else { return false }
                    if local.role == .assistant {
                        if Self.htmlCardPayload(local) != nil {
                            return !remoteMessages.contains { remote in Self.sameHTMLCard(local, remote) }
                        }
                        return !remoteMessages.contains { remote in
                            remote.role == .assistant
                                && abs(remote.createdAt.timeIntervalSince(local.createdAt)) < 1
                                && remote.content.contains(local.content)
                        }
                    }
                    return true
                }
                messages = Self.deduplicateHTMLCards((remoteMessages + localOnly).sorted { $0.createdAt < $1.createdAt })
            } else {
                messages = Self.deduplicateHTMLCards(localMessages.isEmpty ? remoteMessages : localMessages)
            }
            saveLocalConversation()
            nextHistoryBefore = thread.nextBefore
            historyFullyLoaded = thread.hasMore != true
        }
        catch {
            if !localMessages.isEmpty { messages = Self.deduplicateHTMLCards(localMessages) }
            else if messages.isEmpty { errorMessage = friendlyError(error) }
        }
    }

    /// Called only when the reader reaches the oldest visible message. Each
    /// pull requests one earlier page, leaving the rest on the server.
    func loadOlderHistoryIfNeeded() async {
        guard shouldLoadFromServer, !isLoadingOlderHistory else { return }
        isLoadingOlderHistory = true
        defer { isLoadingOlderHistory = false }
        guard !historyFullyLoaded, let before = nextHistoryBefore else { return }
        do {
            let page = try await api.fetchThread(id: chatID, limit: 100, before: before)
            let restored = page.messages.map(restoreMedia).flatMap { message in
                message.role == .assistant && message.contentType != "call_record" && message.contentType != "call_status"
                    ? assistantBubbles(from: message) : [message]
            }
            let present = Set(messages.map(\.id))
            let missing = restored.filter { !present.contains($0.id) }
            if !missing.isEmpty {
                messages = Self.deduplicateHTMLCards((messages + missing).sorted { $0.createdAt < $1.createdAt })
                saveLocalConversation()
            }
            nextHistoryBefore = page.nextBefore
            historyFullyLoaded = page.hasMore != true || page.messages.isEmpty
        } catch {
            // Cached /newest history remains fully usable; retry on the next pull.
        }
    }

    func send(imageBase64: String? = nil, imageFileName: String? = nil, galleryImageIDs: [String] = [], tts: TTSRequestSettings? = nil, emojiCatalog: [String: [String]] = [:]) async {
        let typedContent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!typedContent.isEmpty || imageBase64 != nil || !galleryImageIDs.isEmpty), !isSending else { return }
        let content = typedContent.isEmpty ? (imageBase64 != nil ? "请描述这张图片。" : "想和你聊聊这张照片。") : typedContent
        draft = ""
        let optimisticID = UUID()
        messages.append(ChatMessage(id: optimisticID, role: .user, content: content, createdAt: .now, localImageFileName: imageFileName))
        if let imageFileName { saveMedia(for: optimisticID, record: MessageMediaRecord(audio: nil, image: imageFileName, duration: nil, speechScript: nil)) }
        saveLocalConversation()
        isSending = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Lumi response generation")
        defer {
            isSending = false
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        do {
            let provider = UserDefaults.standard.string(forKey: "lumi.modelProvider") ?? "zenmux"
            let model = UserDefaults.standard.string(forKey: "lumi.modelName.\(provider)")
                ?? (provider == "zenmux" ? (UserDefaults.standard.string(forKey: "lumi.modelName") ?? "") : "")
            let response = try await api.sendMessage(content, to: chatID, images: imageBase64.map { [$0] } ?? [], galleryImageIDs: galleryImageIDs, emojiCatalog: emojiCatalog, tts: tts, provider: provider, model: model)
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
            // New servers persist these cards with the conversation, so they
            // survive a restart and appear in every client. Keep the fallback
            // for an older server during rollout.
            let collectionMessages = response.galleryMessages ?? (response.galleryItems ?? []).enumerated().compactMap { index, item in
                let notice = GalleryCollectionNotice(id: item.id, title: item.title, firstImpression: item.firstImpression)
                guard let data = try? JSONEncoder().encode(notice),
                      let content = String(data: data, encoding: .utf8) else { return nil }
                return ChatMessage(
                    id: UUID(), role: .assistant, content: content,
                    createdAt: assistantMessage.createdAt.addingTimeInterval(0.003 * Double(index + 1)),
                    localImageFileName: imageFileName, contentType: "gallery_collected"
                )
            }
            for var collectionMessage in collectionMessages {
                collectionMessage.localImageFileName = imageFileName
                if !messages.contains(where: { $0.id == collectionMessage.id }) {
                    messages.append(collectionMessage)
                    saveLocalConversation()
                }
            }
        } catch { errorMessage = friendlyError(error); saveLocalConversation() }
    }

    func receiveCallOutcome(_ message: ChatMessage, statusMessage: ChatMessage? = nil) {
        if let statusMessage, !messages.contains(where: { $0.id == statusMessage.id }) {
            messages.append(statusMessage)
        }
        for bubble in assistantBubbles(from: message) {
            if !messages.contains(where: { $0.id == bubble.id }) { messages.append(bubble) }
        }
        saveLocalConversation()
    }

    func receiveCallRecord(_ record: ChatMessage) {
        guard !messages.contains(where: { $0.id == record.id }) else { return }
        messages.append(record)
        saveLocalConversation()
    }

    private func loadLocalConversation() -> [ChatMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: localConversationURL),
              let saved = try? decoder.decode([ChatMessage].self, from: data) else { return [] }
        return saved
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
        if message.contentType == "call_record" { return [message] }
        // Gallery collection cards are server-persisted messages. Never run
        // their JSON payload through the ordinary text-bubble splitter, or a
        // restart would turn the card into plain text and make it disappear.
        if message.contentType == "gallery_collected" { return [message] }
        if message.contentType == "call_status" {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [message] }
            // Older server records stored the AI's follow-up text inside the status card.
            // Split those records on load so they match the new compact status + chat bubble layout.
            let status = ChatMessage(
                id: message.id,
                role: message.role,
                content: "",
                createdAt: message.createdAt,
                callID: message.callID,
                callInitiator: message.callInitiator,
                callStatus: message.callStatus,
                contentType: "call_status"
            )
            let reply = ChatMessage(
                id: UUID(),
                role: .assistant,
                content: text,
                createdAt: message.createdAt.addingTimeInterval(0.001)
            )
            return [status, reply]
        }
        let thinking = extractThinking(from: message.content)
        let visible = message.content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
        let hasStoredHTML = message.htmlContent != nil
        let htmlContent = message.htmlContent ?? ((message.contentType == "html" || Self.isHTML(visible)) ? visible : nil)
        let textContent = hasStoredHTML ? visible : (htmlContent == nil ? visible : "")
        // Keep ordinary line-break rhythm as separate bubbles, but never split a code response
        // into one bubble per line. Code needs to retain its indentation and line structure.
        let lines = textContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let groupedCode = Self.looksLikeCode(textContent)
        var bubbles: [ChatMessage]
        if groupedCode {
            bubbles = [ChatMessage(id: message.id, role: .assistant, content: textContent, createdAt: message.createdAt, thinking: thinking)]
        } else {
            bubbles = lines.enumerated().map { index, line in
                ChatMessage(id: index == 0 && message.audioFileName == nil ? message.id : UUID(), role: .assistant, content: line, createdAt: message.createdAt, thinking: index == 0 ? thinking : nil)
            }
        }
        if let htmlContent {
            bubbles.append(ChatMessage(id: Self.cardID(for: message.id), role: .assistant, content: "", createdAt: message.createdAt.addingTimeInterval(0.001), contentType: "html", htmlContent: htmlContent, htmlTitle: message.htmlTitle ?? "HTML 页面"))
        }
        if let audioFileName = message.audioFileName {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt.addingTimeInterval(0.002), audioFileName: audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript))
        }
        if bubbles.isEmpty, message.audioFileName != nil {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, thinking: thinking, audioFileName: message.audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript))
        }
        // A reply that only contained the private dial marker (for example
        // `⟪拨号:…⟫`) must not leave an empty white chat bubble behind. The call
        // invite/status itself is rendered separately by the call message.
        return bubbles
    }

    private static func looksLikeCode(_ content: String) -> Bool {
        let source = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.range(of: #"(?s)```[^\n]*\n.*?```"#, options: .regularExpression) != nil { return true }
        guard source.contains("\n") else { return false }
        let markers = [
            #"\b(import|func|struct|class|enum|let|var|guard|private|public|return)\b"#,
            #"\.(onReceive|scrollTo|frame|padding|background|ignoresSafeArea)\s*\("#,
            #"\b(ScrollViewReader|DispatchQueue|NotificationCenter|UIResponder)\b"#,
            #"\{\s*(?:_|[A-Za-z][A-Za-z0-9_]*)?\s*in\b"#,
            #"[{};]"#
        ]
        let hits = markers.reduce(0) { count, pattern in
            count + (source.range(of: pattern, options: .regularExpression) == nil ? 0 : 1)
        }
        return hits >= 2
    }

    private static func isHTML(_ content: String) -> Bool {
        let source = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?is)^```(?:html|xml)?\s*|\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if source.range(of: #"(?i)^(?:<!doctype\s+html\b|<(?:html|svg)\b)"#, options: .regularExpression) != nil { return true }
        let tags = #"html|head|body|title|meta|link|div|span|p|a|ul|ol|li|h[1-6]|table|thead|tbody|tr|td|th|svg|path|iframe|section|article|main|header|footer|nav|button|input|textarea|label|form|select|option|canvas|video|audio|pre|code|blockquote|br|hr|style|script|details|summary"#
        let openingTag = #"(?i)<(?:"# + tags + #")\b[^>]*>"#
        let closingTag = #"(?i)</(?:"# + tags + #")\s*>"#
        return source.range(of: openingTag, options: .regularExpression) != nil
            && source.range(of: closingTag, options: .regularExpression) != nil
    }

    private static func cardID(for messageID: UUID) -> UUID {
        var bytes = messageID.uuid
        withUnsafeMutableBytes(of: &bytes) { buffer in
            buffer[0] ^= 0xA5
            buffer[15] ^= 0x5A
        }
        return UUID(uuid: bytes)
    }

    private static func htmlCardPayload(_ message: ChatMessage) -> String? {
        if let html = message.htmlContent { return html.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard message.contentType == "html" || isHTML(message.content) else { return nil }
        if let range = message.content.range(of: #"(?is)```(?:html|xml)?\s*(.*?)```"#, options: .regularExpression) {
            let fenced = String(message.content[range])
                .replacingOccurrences(of: #"(?is)^```(?:html|xml)?\s*|```$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isHTML(fenced) { return fenced }
        }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sameHTMLCard(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        guard lhs.role == .assistant, rhs.role == .assistant,
              abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) < 2,
              let left = htmlCardPayload(lhs), let right = htmlCardPayload(rhs) else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func deduplicateHTMLCards(_ messages: [ChatMessage]) -> [ChatMessage] {
        var keptCards: [ChatMessage] = []
        return messages.filter { candidate in
            guard htmlCardPayload(candidate) != nil else { return true }
            guard !keptCards.contains(where: { sameHTMLCard(candidate, $0) }) else { return false }
            keptCards.append(candidate)
            return true
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
