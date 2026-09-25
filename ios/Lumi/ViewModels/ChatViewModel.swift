import Foundation
import Combine

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
                message.role == .assistant ? assistantBubbles(from: message) : [message]
            }
        }
        catch {
            // 首次加载失败时保留本地示例/缓存，不用系统英文网络弹窗打断界面。
            if messages.isEmpty { errorMessage = friendlyError(error) }
        }
    }

    func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        draft = ""
        messages.append(
            ChatMessage(id: UUID(), role: .user, content: content, createdAt: .now)
        )
        isSending = true
        defer { isSending = false }
        do {
            let response = try await api.sendMessage(content, to: chatID)
            if response.memorySaved == true {
                memoryNotice = "-------沈屿记下了这一刻-------"
                Task {
                    try? await Task.sleep(for: .seconds(2.2))
                    if !Task.isCancelled { memoryNotice = nil }
                }
            }
            for (index, bubble) in assistantBubbles(from: response.assistantMessage).enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(260)) }
                messages.append(bubble)
            }
        } catch { errorMessage = friendlyError(error) }
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
