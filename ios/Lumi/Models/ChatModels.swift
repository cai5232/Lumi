import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date
    var isThinking: Bool = false
    var thinking: String?
    var audioFileName: String?
    var speechDuration: Double?
    var localImageFileName: String?
    var imageAttachmentCount: Int?

    enum CodingKeys: String, CodingKey { case id, role, content, createdAt, isThinking, audioFileName, speechDuration, localImageFileName, imageAttachmentCount }

    init(id: UUID, role: Role, content: String, createdAt: Date, isThinking: Bool = false, thinking: String? = nil, audioFileName: String? = nil, speechDuration: Double? = nil, localImageFileName: String? = nil, imageAttachmentCount: Int? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isThinking = isThinking
        self.thinking = thinking
        self.audioFileName = audioFileName
        self.speechDuration = speechDuration
        self.localImageFileName = localImageFileName
        self.imageAttachmentCount = imageAttachmentCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        thinking = nil
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        speechDuration = try container.decodeIfPresent(Double.self, forKey: .speechDuration)
        localImageFileName = try container.decodeIfPresent(String.self, forKey: .localImageFileName)
        imageAttachmentCount = try container.decodeIfPresent(Int.self, forKey: .imageAttachmentCount)
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
    var images: [String] = []
    var emojiCatalog: [String: [String]] = [:]
    var tts: TTSRequestSettings?
}

struct SendMessageResponse: Decodable {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
    let memorySaved: Bool?
    let speechAudioBase64: String?
    let speechDuration: Double?
}

struct TTSRequestSettings: Encodable {
    let apiKey: String
    let model: String
    let voiceID: String
}

struct ProactiveSettings: Codable {
    var enabled: Bool
    var threadId: String
    var message: String
    var intervalMin: Int
    var intervalMax: Int
    var nextDueAt: String?
    var scheduledForUserMessageId: String?
}

struct ProactiveSettings: Codable {
    var enabled: Bool
    var threadId: String
    var message: String
    var intervalMin: Int
    var intervalMax: Int
    var nextDueAt: String?
    var scheduledForUserMessageId: String?
}
