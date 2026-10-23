import Foundation
import Combine
import UIKit

private struct MessageMediaRecord: Codable {
    var audio: String?
    var image: String?
    var images: [String]?
    var duration: Double?
    var speechScript: String?
}

@MainActor
final class ChatStreamState: ObservableObject {
    @Published var text = ""
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var isSending = false
    @Published private(set) var isAwaitingReply = false
    @Published private(set) var pendingReplyMessageIDs: Set<UUID> = []
    @Published private(set) var arrivingReplyMessageID: UUID?
    let stream = ChatStreamState()
    private(set) var streamingText: String {
        get { stream.text }
        set { stream.text = newValue }
    }
    @Published private(set) var pendingOptionPick: ChatOptionPick?
    @Published var errorMessage: String?
    @Published var memoryNotice: String?
    @Published private(set) var isLoadingOlderHistory = false
    @Published private(set) var contextUsagePercentage: Int?
    @Published private(set) var assistantRemark = ""
    @Published private(set) var aiRemark = ""

    var instantCommandThreadID: String? { shouldLoadFromServer ? chatID : nil }
    let chatID: String
    private let api: LumiAPIClient
    private let shouldLoadFromServer: Bool
    private var localConversationURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard chatID != "default" else { return documents.appendingPathComponent("lumi-conversation.json") }
        let safeID = chatID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return documents.appendingPathComponent("lumi-conversation-\(safeID).json")
    }
    private var nextHistoryBefore: Date?
    private var historyFullyLoaded = false
    private let conversationWriteQueue = DispatchQueue(label: "lumi.conversation.persistence", qos: .utility)
    private static var cachedMediaRecords: [String: MessageMediaRecord]?
    private var isLoadingRemoteHistory = false
    private var takeoutPollingTask: Task<Void, Never>?
    private var pendingStreamText = ""
    private var streamFlushTask: Task<Void, Never>?

    static func currentModelRoute(defaults: UserDefaults = .standard) throws -> (provider: String, model: String, customProvider: LumiCustomAPIRequestConfig?) {
        var activeCustomID = defaults.string(forKey: "lumi.activeAPIProviderID") ?? ""
        let profiles = defaults.data(forKey: "lumi.apiProviderProfiles")
            .flatMap { try? JSONDecoder().decode([LumiAPIProviderProfile].self, from: $0) } ?? []
        let savedRoute = defaults.string(forKey: "lumi.modelProvider") ?? "zenmux"
        let activeIDIsStale = !activeCustomID.isEmpty && !profiles.contains(where: { $0.id == activeCustomID })
        let shouldRecoverSavedPreset = profiles.count == 1 &&
            (activeIDIsStale || (activeCustomID.isEmpty && (savedRoute == "custom" || !defaults.bool(forKey: "lumi.apiProviderRouteExplicitlySelected"))))
        if shouldRecoverSavedPreset, let onlyProfile = profiles.first {
            activeCustomID = onlyProfile.id
            defaults.set(activeCustomID, forKey: "lumi.activeAPIProviderID")
            defaults.set("custom", forKey: "lumi.modelProvider")
        }
        let customProfile = profiles.first(where: { $0.id == activeCustomID })
        let configuredProvider = defaults.string(forKey: "lumi.modelProvider") ?? "zenmux"
        if customProfile == nil && configuredProvider == "custom" {
            throw NSError(domain: "LumiAPIProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "自定义 API 预设未选中，请到设置里的「API 预设与线路」点选要使用的预设。"])
        }
        let provider = customProfile == nil ? configuredProvider : "custom"
        let model = customProfile?.model ?? defaults.string(forKey: "lumi.modelName.\(provider)")
            ?? (provider == "zenmux" ? (defaults.string(forKey: "lumi.modelName") ?? "") : "")
        return (provider, model, customProfile?.requestConfig)
    }

    init(chatID: String = "default", api: LumiAPIClient = LumiAPIClient(), initialMessages: [ChatMessage] = [], shouldLoadFromServer: Bool = true) {
        self.chatID = chatID
        self.api = api
        self.shouldLoadFromServer = shouldLoadFromServer
        self.messages = initialMessages
    }

    func load(waitForRemote: Bool = true) async {
        guard !isLoadingRemoteHistory, !isSending else { return }
        isLoadingRemoteHistory = true
        defer { isLoadingRemoteHistory = false }
        Task { await refreshContextUsage() }
        Task { await loadRemarks() }
        let localMessages = (await loadLocalConversation()).map(restoreMedia)
        if messages.isEmpty, !localMessages.isEmpty {
            messages = Self.deduplicateMessages(localMessages)
        }

        // When local history exists, the UI can open immediately while a later call refreshes the server copy.
        if !waitForRemote, !messages.isEmpty { return }

        guard shouldLoadFromServer else {
            if messages.isEmpty { messages = localMessages }
            return
        }
        do {
            let thread = try await api.fetchThread(id: chatID, limit: 100)
            let identities = Dictionary(messages.map { ($0.id, $0.renderIdentity) }, uniquingKeysWith: { first, _ in first })
            let loaded = thread.messages.map { message in
                var restored = restoreMedia(for: message)
                restored.renderID = identities[message.id]
                return restored
            }
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
                messages = Self.deduplicateMessages((remoteMessages + localOnly).sorted { $0.createdAt < $1.createdAt })
            } else {
                messages = Self.deduplicateMessages(localMessages.isEmpty ? remoteMessages : localMessages)
            }
            saveLocalConversation()
            nextHistoryBefore = thread.nextBefore
            historyFullyLoaded = thread.hasMore != true
        }
        catch {
            if !localMessages.isEmpty { messages = Self.deduplicateMessages(localMessages) }
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
                messages = Self.deduplicateMessages((messages + missing).sorted { $0.createdAt < $1.createdAt })
                saveLocalConversation()
            }
            nextHistoryBefore = page.nextBefore
            historyFullyLoaded = page.hasMore != true || page.messages.isEmpty
        } catch {
            // Cached /newest history remains fully usable; retry on the next pull.
        }
    }

    private func receiveStreamText(_ fragment: String) {
        guard !fragment.isEmpty else { return }
        pendingStreamText += fragment
        guard streamFlushTask == nil else { return }
        streamFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.flushStreamText()
        }
    }

    private func flushStreamText() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        guard !pendingStreamText.isEmpty else { return }
        streamingText += pendingStreamText
        pendingStreamText = ""
    }

    func send(imageBase64: String? = nil, imageFileName: String? = nil, imagesBase64: [String] = [], imageFileNames: [String] = [], galleryImageIDs: [String] = [], tts: TTSRequestSettings? = nil, emojiCatalog: [String: [String]] = [:], contentType: String? = nil, stickerImageURL: String? = nil, stickerName: String? = nil) async {
        let typedContent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedImages = imagesBase64.isEmpty ? imageBase64.map { [$0] } ?? [] : imagesBase64
        let localImages = imageFileNames.isEmpty ? imageFileName.map { [$0] } ?? [] : imageFileNames
        let hasSticker = contentType == "sticker" && stickerImageURL != nil
        guard (!typedContent.isEmpty || !encodedImages.isEmpty || !galleryImageIDs.isEmpty || hasSticker), !isSending else { return }
        let content = typedContent.isEmpty && hasSticker ? "[表情: \(stickerName ?? "表情包")]" : typedContent.isEmpty ? (encodedImages.isEmpty ? "想和你聊聊这张照片。" : (encodedImages.count > 1 ? "看看这些照片。" : "请描述这张图片。")) : typedContent
        let selectedPick = pendingOptionPick.flatMap { $0.text == content ? $0 : nil }
        pendingOptionPick = nil
        draft = ""
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamText = ""
        streamingText = ""
        let optimisticID = UUID()
        let pickAttachments = selectedPick.map { [ChatMessageAttachment(type: "pick", of: $0.msgID, idx: $0.idx, text: $0.text)] } ?? []
        messages.append(ChatMessage(id: optimisticID, role: .user, content: content, createdAt: .now, localImageFileName: localImages.first, localImageFileNames: localImages, contentType: contentType, stickerImageURL: stickerImageURL, attachments: pickAttachments))
        if let first = localImages.first { saveMedia(for: optimisticID, record: MessageMediaRecord(audio: nil, image: first, images: localImages, duration: nil, speechScript: nil)) }
        saveLocalConversation()
        isSending = true
        isAwaitingReply = true
        // Let SwiftUI render the optimistic user bubble and sending indicator
        // before request construction and network work begin on the main actor.
        await Task.yield()
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Lumi response generation")
        defer {
            isSending = false
            isAwaitingReply = false
            takeoutPollingTask?.cancel()
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        do {
            takeoutPollingTask = Task { [api] in
                while !Task.isCancelled {
                    try? await api.pollTakeoutBridge()
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
            let route = try Self.currentModelRoute(defaults: .standard)
            let response = try await api.sendMessage(content, to: chatID, images: encodedImages, galleryImageIDs: galleryImageIDs, emojiCatalog: emojiCatalog, tts: tts, provider: route.provider, model: route.model, customProvider: route.customProvider, contentType: contentType, stickerImageURL: stickerImageURL, stickerName: stickerName, context: stickerName.map { "用户这次发送的表情包名称是：\($0)。这是用户为表情包填写的文字名称，请结合名称和配文理解；名称不等于图片视觉识别。" }, pick: selectedPick, onTextDelta: { [weak self] fragment in
                self?.receiveStreamText(fragment)
            })
            flushStreamText()
            isAwaitingReply = false
            var confirmedUserMessage = response.userMessage
            confirmedUserMessage.localImageFileName = localImages.first
            confirmedUserMessage.localImageFileNames = localImages
            if let stickerImageURL { confirmedUserMessage.stickerImageURL = stickerImageURL }
            if let optimisticIndex = messages.firstIndex(where: { $0.id == optimisticID }) {
                confirmedUserMessage.renderID = messages[optimisticIndex].renderIdentity
                messages[optimisticIndex] = confirmedUserMessage
            } else if !messages.contains(where: { $0.id == confirmedUserMessage.id }) {
                messages.append(confirmedUserMessage)
            }
            if let first = localImages.first { saveMedia(for: confirmedUserMessage.id, record: MessageMediaRecord(audio: nil, image: first, images: localImages, duration: nil, speechScript: nil)) }
            saveLocalConversation()
            if let updatedOptionMessage = response.updatedOptionMessage {
                if let optionIndex = messages.lastIndex(where: { $0.attachments.contains(where: { $0.type == "options" }) }) {
                    messages[optionIndex].attachments = updatedOptionMessage.attachments
                } else if let index = messages.firstIndex(where: { $0.id == updatedOptionMessage.id }) {
                    messages[index].attachments = updatedOptionMessage.attachments
                }
                saveLocalConversation()
            }
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
                do {
                    try audio.write(to: destination, options: .atomic)
                    assistantMessage.audioFileName = name
                    assistantMessage.speechDuration = response.speechDuration
                    assistantMessage.speechScript = response.speechScript
                    saveMedia(for: assistantMessage.id, record: MessageMediaRecord(audio: name, image: nil, duration: response.speechDuration, speechScript: response.speechScript))
                } catch {
                    errorMessage = "语音已生成，但保存到聊天失败：\(error.localizedDescription)"
                }
            }
            if let speechError = response.speechError {
                errorMessage = "AI 回复了，但语音没有生成：\(speechError)"
            }
            if assistantMessage.contentType == "sticker" || !assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistantMessage.audioFileName != nil || !assistantMessage.attachments.isEmpty || !assistantMessage.toolCalls.isEmpty {
                let bubbles = assistantBubbles(from: assistantMessage)
                await revealReply(bubbles)
            }
            streamingText = ""
            await refreshContextUsage()
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
            if let aiRemark = response.aiRemark {
                self.aiRemark = aiRemark
            } else {
                await loadRemarks()
            }
        } catch {
            flushStreamText()
            let partial = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                messages.append(ChatMessage(id: UUID(), role: .assistant, content: partial, createdAt: .now))
                saveLocalConversation()
            }
            streamingText = ""
            errorMessage = friendlyError(error)
            saveLocalConversation()
        }
    }

    private func revealReply(_ bubbles: [ChatMessage]) async {
        guard !bubbles.isEmpty else { return }
        pendingReplyMessageIDs = Set(bubbles.map(\.id))
        // Save the complete turn before presentation starts, so leaving the app
        // during the animation cannot discard the bubbles still waiting to appear.
        messages.append(contentsOf: bubbles)
        saveLocalConversation()
        defer { pendingReplyMessageIDs.removeAll() }
        for (index, bubble) in bubbles.enumerated() {
            if index > 0 {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { break }
            }
            arrivingReplyMessageID = bubble.id
            pendingReplyMessageIDs.remove(bubble.id)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                if self?.arrivingReplyMessageID == bubble.id {
                    self?.arrivingReplyMessageID = nil
                }
            }
        }
    }

    func refreshContextUsage() async {
        guard let usage = try? await api.fetchContextUsage() else { return }
        contextUsagePercentage = usage.percentage
    }

    func loadRemarks() async {
        guard let state = try? await api.fetchChatRemarks(for: chatID) else { return }
        assistantRemark = state.assistantRemark
        aiRemark = state.aiRemark
    }

    func saveAssistantRemark(_ remark: String) async throws {
        let state = try await api.saveChatRemark(remark, for: chatID)
        assistantRemark = state.assistantRemark
        aiRemark = state.aiRemark
    }

    func sendOptionPick(messageID: UUID, index: Int, text: String) {
        guard !isSending else { return }
        pendingOptionPick = ChatOptionPick(msgID: messageID.uuidString, idx: index, text: text)
        draft = text
        Task { await send() }
    }

    func sendOptionReply(_ text: String) {
        guard !isSending else { return }
        pendingOptionPick = nil
        draft = text
        Task { await send() }
    }

    func sendWatchMessage(_ text: String, imageBase64: String) async -> String? {
        let existingAssistantIDs = Set(messages.lazy.filter { $0.role == .assistant }.map(\.id))
        draft = text
        await send(imageBase64: imageBase64, contentType: "together_watch")
        let replyLines = messages.filter {
            $0.role == .assistant && !existingAssistantIDs.contains($0.id) &&
            $0.contentType != "gallery_collected" && $0.contentType != "html" && !$0.content.isEmpty
        }
        guard !replyLines.isEmpty else { return nil }
        return replyLines.map(\.content).joined(separator: "\n")
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

    func rejectScreenShare(_ request: ChatMessage) async {
        guard request.contentType == "screen_request" else { return }
        let status = ChatMessage(id: UUID(), role: .assistant, content: "已拒绝", createdAt: .now, screenStatus: "rejected", contentType: "screen_status")
        if !messages.contains(where: { $0.contentType == "screen_status" && $0.createdAt.timeIntervalSince(request.createdAt) >= 0 }) {
            messages.append(status)
            saveLocalConversation()
        }
        try? await api.updateScreenShareDecision("rejected")
    }

    private func loadLocalConversation() async -> [ChatMessage] {
        let source = localConversationURL
        return await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: source),
                  let saved = try? decoder.decode([ChatMessage].self, from: data) else { return [] }
            return saved
        }.value
    }

    private func saveLocalConversation() {
        let snapshot = messages
        let destination = localConversationURL
        // One serial queue preserves write order without encoding the entire history on the UI thread.
        conversationWriteQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }

    private func mediaRecords() -> [String: MessageMediaRecord] {
        if let cachedMediaRecords = Self.cachedMediaRecords { return cachedMediaRecords }
        let records = UserDefaults.standard.data(forKey: "lumi.messageMedia")
            .flatMap { try? JSONDecoder().decode([String: MessageMediaRecord].self, from: $0) } ?? [:]
        Self.cachedMediaRecords = records
        return records
    }

    private func saveMedia(for id: UUID, record: MessageMediaRecord) {
        var records = mediaRecords()
        records[id.uuidString] = record
        Self.cachedMediaRecords = records
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: "lumi.messageMedia") }
    }

    private func restoreMedia(for message: ChatMessage) -> ChatMessage {
        guard let media = mediaRecords()[message.id.uuidString] else { return message }
        var restored = message
        restored.audioFileName = media.audio
        restored.localImageFileName = media.image
        restored.localImageFileNames = media.images ?? media.image.map { [$0] } ?? []
        restored.speechDuration = media.duration
        restored.speechScript = media.speechScript
        return restored
    }

    private func assistantBubbles(from message: ChatMessage) -> [ChatMessage] {
        // Keep co-watch replies intact as one hidden-in-main-chat turn. They stay
        // in the same model thread for memory, while the co-watch screen renders
        // its own local conversation transcript.
        if message.contentType == "together_watch" || message.contentType == "together_music" { return [message] }
        if message.contentType == "call_record" || message.contentType == "sticker" { return [message] }
        if message.contentType == "screen_request" || message.contentType == "screen_status" { return [message] }
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
        let storedThinking = message.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        let thinking = storedThinking?.isEmpty == false ? storedThinking : extractThinking(from: message.content)
        let visible = message.content
            .replacingOccurrences(of: #"(?is)<(thinking|think|analysis|reasoning)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?(thinking|think|analysis|reasoning)\b[^>]*>"#, with: "", options: .regularExpression)
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
            bubbles = [ChatMessage(id: message.id, role: .assistant, content: textContent, createdAt: message.createdAt, thinking: thinking, toolCalls: message.toolCalls)]
        } else {
            bubbles = lines.enumerated().map { index, line in
                ChatMessage(id: index == 0 && message.audioFileName == nil ? message.id : Self.bubbleID(for: message.id, index: index + 1), role: .assistant, content: line, createdAt: message.createdAt, thinking: index == 0 ? thinking : nil, attachments: index == 0 && message.audioFileName == nil ? message.attachments : [])
            }
        }
        if let htmlContent {
            bubbles.append(ChatMessage(id: Self.cardID(for: message.id), role: .assistant, content: "", createdAt: message.createdAt.addingTimeInterval(0.001), contentType: "html", htmlContent: htmlContent, htmlTitle: message.htmlTitle ?? "HTML 页面"))
        }
        if let audioFileName = message.audioFileName {
            let audioBubbleID = bubbles.contains(where: { $0.id == message.id })
                ? Self.bubbleID(for: message.id, index: bubbles.count + 1)
                : message.id
            bubbles.append(ChatMessage(id: audioBubbleID, role: .assistant, content: "", createdAt: message.createdAt.addingTimeInterval(0.002), audioFileName: audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript, attachments: message.attachments))
        }
        if bubbles.isEmpty, message.audioFileName != nil {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, thinking: thinking, audioFileName: message.audioFileName, speechDuration: message.speechDuration, speechScript: message.speechScript, attachments: message.attachments))
        }
        if bubbles.isEmpty, !message.toolCalls.isEmpty {
            bubbles.append(ChatMessage(id: message.id, role: .assistant, content: "", createdAt: message.createdAt, toolCalls: message.toolCalls))
        }
        if let thinking, !bubbles.isEmpty, bubbles[0].thinking == nil {
            bubbles[0].thinking = thinking
        }
        if !message.toolCalls.isEmpty, let lastIndex = bubbles.indices.last {
            bubbles[lastIndex].toolCalls = message.toolCalls
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

    private static func bubbleID(for messageID: UUID, index: Int) -> UUID {
        var bytes = messageID.uuid
        withUnsafeMutableBytes(of: &bytes) { buffer in
            buffer[0] ^= 0xB7
            let value = UInt64(index)
            for offset in 0..<8 { buffer[8 + offset] ^= UInt8(truncatingIfNeeded: value >> (offset * 8)) }
        }
        return UUID(uuid: bytes)
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

    private static func deduplicateMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        var seen = Set<String>()
        return messages.filter { message in
            let normalized = message.content
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let timeBucket = Int(message.createdAt.timeIntervalSince1970.rounded() / 5)
            let contentType = message.contentType ?? ""
            let key = "\(message.role.rawValue)|\(contentType)|\(normalized)|\(timeBucket)"
            return seen.insert(key).inserted
        }
    }

    private func extractThinking(from content: String) -> String? {
        guard let range = content.range(of: #"(?is)<(thinking|think|analysis|reasoning)\b[^>]*>(.*?)</\1>"#, options: .regularExpression) else { return nil }
        return String(content[range])
            .replacingOccurrences(of: #"(?is)^<(thinking|think|analysis|reasoning)\b[^>]*>|</(thinking|think|analysis|reasoning)>$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "暂时无法连接网络，请稍后重试"
        }
        return error.localizedDescription
    }
}
