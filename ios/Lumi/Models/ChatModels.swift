import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    let id: UUID
    let role: Role
    let content: String
    var contentType: String?
    var htmlContent: String?
    var htmlTitle: String?
    let createdAt: Date
    var isThinking: Bool = false
    var thinking: String?
    var audioFileName: String?
    var speechDuration: Double?
    var speechScript: String?
    var localImageFileName: String?
    var imageAttachmentCount: Int?

    enum CodingKeys: String, CodingKey { case id, role, content, contentType, htmlContent, htmlTitle, createdAt, isThinking, audioFileName, speechDuration, speechScript, localImageFileName, imageAttachmentCount }

    init(id: UUID, role: Role, content: String, createdAt: Date, isThinking: Bool = false, thinking: String? = nil, audioFileName: String? = nil, speechDuration: Double? = nil, speechScript: String? = nil, localImageFileName: String? = nil, imageAttachmentCount: Int? = nil, contentType: String? = nil, htmlContent: String? = nil, htmlTitle: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.contentType = contentType
        self.htmlContent = htmlContent
        self.htmlTitle = htmlTitle
        self.createdAt = createdAt
        self.isThinking = isThinking
        self.thinking = thinking
        self.audioFileName = audioFileName
        self.speechDuration = speechDuration
        self.speechScript = speechScript
        self.localImageFileName = localImageFileName
        self.imageAttachmentCount = imageAttachmentCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        htmlContent = try container.decodeIfPresent(String.self, forKey: .htmlContent)
        htmlTitle = try container.decodeIfPresent(String.self, forKey: .htmlTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        thinking = nil
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        speechDuration = try container.decodeIfPresent(Double.self, forKey: .speechDuration)
        speechScript = try container.decodeIfPresent(String.self, forKey: .speechScript)
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
    let speechScript: String?
}

struct TTSRequestSettings: Encodable {
    let apiKey: String
    let model: String
    let voiceID: String
    let baseURL: String
    let enabled: Bool
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
