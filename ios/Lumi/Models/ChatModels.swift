import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    var isThinking: Bool = false
    var thinking: String?

    enum CodingKeys: String, CodingKey { case id, role, content, createdAt, isThinking }

    init(id: UUID, role: Role, content: String, createdAt: Date, isThinking: Bool = false, thinking: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isThinking = isThinking
        self.thinking = thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        thinking = nil
    }
}

struct ChatThread: Codable, Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
}

struct SendMessageRequest: Encodable {
    let content: String
    let systemPrompt: String
}

struct SendMessageResponse: Decodable {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
}
