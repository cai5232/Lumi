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
    var callID: String?
    var callDuration: Double?
    var callInitiator: String?
    var callStatus: String?

    enum CodingKeys: String, CodingKey { case id, role, content, contentType, htmlContent, htmlTitle, createdAt, isThinking, audioFileName, speechDuration, speechScript, localImageFileName, imageAttachmentCount, callID, callDuration, callInitiator, callStatus }

    init(id: UUID, role: Role, content: String, createdAt: Date, isThinking: Bool = false, thinking: String? = nil, audioFileName: String? = nil, speechDuration: Double? = nil, speechScript: String? = nil, localImageFileName: String? = nil, imageAttachmentCount: Int? = nil, callID: String? = nil, callDuration: Double? = nil, callInitiator: String? = nil, callStatus: String? = nil, contentType: String? = nil, htmlContent: String? = nil, htmlTitle: String? = nil) {
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
        self.callID = callID
        self.callDuration = callDuration
        self.callInitiator = callInitiator
        self.callStatus = callStatus
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
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        callDuration = try container.decodeIfPresent(Double.self, forKey: .callDuration)
        callInitiator = try container.decodeIfPresent(String.self, forKey: .callInitiator)
        callStatus = try container.decodeIfPresent(String.self, forKey: .callStatus)
    }
}

struct ChatThread: Codable, Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var hasMore: Bool?
    var nextBefore: Date?
}

struct DiaryLock: Codable, Equatable {
    let type: String
    let question: String?
    let choices: [String]
    let retryUntil: Date?
    let unlockAt: Date?
}

struct RemoteDiaryItem: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let title: String
    let body: String
    let isLocked: Bool
    let lock: DiaryLock
}

struct DiaryListResponse: Decodable { let items: [RemoteDiaryItem] }
struct DiaryUnlockResponse: Decodable { let item: RemoteDiaryItem }
struct ModelProvider: Decodable, Identifiable {
    let id: String
    let models: [String]
    let configuredModel: String?
}
struct ModelProvidersResponse: Decodable { let providers: [ModelProvider] }

struct SendMessageRequest: Encodable {
    let content: String
    let systemPrompt: String
    var images: [String] = []
    var galleryImageIDs: [String] = []
    var emojiCatalog: [String: [String]] = [:]
    var tts: TTSRequestSettings?
    var provider: String = "zenmux"
    var model: String = ""
}

struct SendMessageResponse: Decodable {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
    let galleryItems: [RemoteGalleryItem]?
    let galleryMessages: [ChatMessage]?
    let memorySaved: Bool?
    let speechAudioBase64: String?
    let speechDuration: Double?
    let speechScript: String?
}

/// A local-only chat card shown after the AI elects to collect an image.
/// The server keeps the gallery record; this keeps the chat presentation small
/// and stable even after the conversation is reopened.
struct GalleryCollectionNotice: Codable, Equatable {
    let id: String
    let title: String
    let firstImpression: String
}

struct RemoteGalleryItem: Codable, Identifiable, Equatable {
    let id: String
    let mimeType: String
    let fileExtension: String
    let createdAt: Date
    let updatedAt: Date
    var title: String
    let visualDescription: String
    let firstImpression: String

    enum CodingKeys: String, CodingKey {
        case id, mimeType, createdAt, updatedAt, title, visualDescription, firstImpression
        case fileExtension = "extension"
    }
}

struct GalleryListResponse: Decodable {
    let items: [RemoteGalleryItem]
}

struct TTSRequestSettings: Encodable {
    let apiKey: String
    let model: String
    let voiceID: String
    let baseURL: String
    let enabled: Bool
}

struct CallStartRequest: Encodable {
    let systemPrompt: String
    let tts: TTSRequestSettings?
}

struct CallStartResponse: Decodable {
    let callId: String
    let status: String
    let assistantMessage: ChatMessage?
    let callStatusMessage: ChatMessage?
    let firstMessage: CallTurn?
    let speechAudioBase64: String?
    let speechDuration: Double?
    let speechScript: String?
    let speechError: String?
}

struct CallTurn: Codable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date
    let speechScript: String?
}

struct CallTurnResponse: Decodable {
    let userTurn: CallTurn
    let assistantTurn: CallTurn
    let speechAudioBase64: String?
    let speechDuration: Double?
    let speechScript: String?
    let speechError: String?
}

struct CallEndResponse: Decodable {
    let callId: String
    let duration: Double
    let recordMessage: ChatMessage
}

struct IncomingCallInfo: Decodable, Identifiable {
    let callId: String
    let reason: String
    let createdAt: Date
    let expiresAt: Date

    var id: String { callId }
}

struct IncomingCallResponse: Decodable {
    let call: IncomingCallInfo?
}

struct CallTurnRequest: Encodable {
    let content: String
    let systemPrompt: String
    let tts: TTSRequestSettings?
}

struct CallAnswerRequest: Encodable {
    let action: String
    let systemPrompt: String
    let tts: TTSRequestSettings?
    let note: String?
}


struct ProactiveSettings: Codable {
    var enabled: Bool
    var threadId: String
    var message: String
    var intervalMin: Int
    var intervalMax: Int
    var nextDueAt: String?
    var scheduledForUserMessageId: String?
    var actions: ProactiveActions? = nil
}

struct ProactiveActions: Codable {
    var message: Bool
    var phone: Bool
    var screen: Bool
}

struct ActivityState: Codable {
    var mode: String
    var lastUserActivityAt: String?
    var nextWakeAt: String?
    var sleepPendingAt: String?
    var sleepStartedAt: String?
    var sleepUntil: String?
    var nextDreamAt: String?
    var dreamCycle: Int?
    var sleepStage: String?
}

struct SubscriptionUsage: Decodable {
    let plan: SubscriptionPlan
    let quota5Hour: SubscriptionQuota
    let quota7Day: SubscriptionQuota
    let fetchedAt: Date
}

struct SubscriptionPlan: Decodable {
    let tier: String
    let expiresAt: Date?
}

struct SubscriptionQuota: Decodable {
    let usagePercentage: Double
    let resetsAt: Date?
    let maxFlows: Double
    let usedFlows: Double
    let remainingFlows: Double
    let usedValueUSD: Double
    let maxValueUSD: Double
}
