import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var draft = ""
    var isSending = false
    var errorMessage: String?

    private let chatID: String
    private let api: LumiAPIClient

    init(chatID: String = "default", api: LumiAPIClient = LumiAPIClient(), initialMessages: [ChatMessage] = []) {
        self.chatID = chatID
        self.api = api
        self.messages = initialMessages
    }

    func load() async {
        do { messages = try await api.fetchThread(id: chatID).messages }
        catch { errorMessage = error.localizedDescription }
    }

    func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.sendMessage(content, to: chatID)
            messages.append(response.userMessage)
            messages.append(response.assistantMessage)
        } catch { errorMessage = error.localizedDescription }
    }
}
