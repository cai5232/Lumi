import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    var isThinking: Bool = false
}

struct ChatThread: Codable, Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
}

struct SendMessageRequest: Encodable {
    let content: String
}

struct SendMessageResponse: Decodable {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
}
