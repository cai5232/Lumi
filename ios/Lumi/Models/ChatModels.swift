import Foundation

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    let id: UUID
    var renderID: UUID? = nil
    var renderIdentity: UUID { renderID ?? id }
    let role: Role
    let content: String
    var contentType: String? = nil
    var stickerImageURL: String? = nil
    var htmlContent: String?
    var htmlTitle: String?
    let createdAt: Date
    var isThinking: Bool = false
    var thinking: String?
    var audioFileName: String?
    var speechDuration: Double?
    var speechScript: String?
    var localImageFileName: String?
    var localImageFileNames: [String] = []
    var imageAttachmentCount: Int?
    var callID: String?
    var callDuration: Double?
    var callInitiator: String?
    var callStatus: String?
    var screenStatus: String?
    var attachments: [ChatMessageAttachment] = []
    var toolCalls: [ChatToolCallTrace] = []

    enum CodingKeys: String, CodingKey { case id, role, content, contentType, stickerImageURL, htmlContent, htmlTitle, createdAt, isThinking, thinking, audioFileName, speechDuration, speechScript, localImageFileName, localImageFileNames, imageAttachmentCount, callID, callDuration, callInitiator, callStatus, screenStatus, attachments, toolCalls }

    init(id: UUID, role: Role, content: String, createdAt: Date, isThinking: Bool = false, thinking: String? = nil, audioFileName: String? = nil, speechDuration: Double? = nil, speechScript: String? = nil, localImageFileName: String? = nil, localImageFileNames: [String] = [], imageAttachmentCount: Int? = nil, callID: String? = nil, callDuration: Double? = nil, callInitiator: String? = nil, callStatus: String? = nil, screenStatus: String? = nil, contentType: String? = nil, stickerImageURL: String? = nil, htmlContent: String? = nil, htmlTitle: String? = nil, attachments: [ChatMessageAttachment] = [], toolCalls: [ChatToolCallTrace] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.contentType = contentType
        self.stickerImageURL = stickerImageURL
        self.htmlContent = htmlContent
        self.htmlTitle = htmlTitle
        self.createdAt = createdAt
        self.isThinking = isThinking
        self.thinking = thinking
        self.audioFileName = audioFileName
        self.speechDuration = speechDuration
        self.speechScript = speechScript
        self.localImageFileName = localImageFileName
        self.localImageFileNames = localImageFileNames
        self.imageAttachmentCount = imageAttachmentCount
        self.callID = callID
        self.callDuration = callDuration
        self.callInitiator = callInitiator
        self.callStatus = callStatus
        self.screenStatus = screenStatus
        self.attachments = attachments
        self.toolCalls = toolCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        stickerImageURL = try container.decodeIfPresent(String.self, forKey: .stickerImageURL)
        htmlContent = try container.decodeIfPresent(String.self, forKey: .htmlContent)
        htmlTitle = try container.decodeIfPresent(String.self, forKey: .htmlTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isThinking = try container.decodeIfPresent(Bool.self, forKey: .isThinking) ?? false
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        speechDuration = try container.decodeIfPresent(Double.self, forKey: .speechDuration)
        speechScript = try container.decodeIfPresent(String.self, forKey: .speechScript)
        localImageFileName = try container.decodeIfPresent(String.self, forKey: .localImageFileName)
        localImageFileNames = try container.decodeIfPresent([String].self, forKey: .localImageFileNames) ?? []
        imageAttachmentCount = try container.decodeIfPresent(Int.self, forKey: .imageAttachmentCount)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        callDuration = try container.decodeIfPresent(Double.self, forKey: .callDuration)
        callInitiator = try container.decodeIfPresent(String.self, forKey: .callInitiator)
        callStatus = try container.decodeIfPresent(String.self, forKey: .callStatus)
        screenStatus = try container.decodeIfPresent(String.self, forKey: .screenStatus)
        attachments = try container.decodeIfPresent([ChatMessageAttachment].self, forKey: .attachments) ?? []
        toolCalls = try container.decodeIfPresent([ChatToolCallTrace].self, forKey: .toolCalls) ?? []
    }
}

struct ChatToolCallTrace: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(name)-\(arguments.hashValue)-\(result.hashValue)" }
    let name: String
    let arguments: String
    let result: String
    let succeeded: Bool
}

struct ChatMessageAttachment: Codable, Equatable, Sendable {
    var type: String
    var items: [String]?
    var askedAt: Double?
    var answeredBy: String?
    var answeredAt: Double?
    var picked: Int?
    var of: String?
    var idx: Int?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type, items, picked, of, idx, text
        case askedAt = "asked_at"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
    }
}

struct ChatOptionPick: Codable, Equatable {
    var msgID: String
    var idx: Int
    var text: String

    enum CodingKeys: String, CodingKey { case msgID = "msg_id", idx, text }
}

struct LumiDrawerItem: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let content: String
    let createdAt: Date
    let seen: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, content, seen
        case createdAt = "created_at"
    }
}

struct LumiActivityEvent: Decodable, Identifiable, Equatable {
    let id: String
    let time: Date
    let kind: String
    let title: String
    let content: String
}

struct LumiActivityHistoryResponse: Decodable {
    let events: [LumiActivityEvent]
}

struct LumiDrawerListResponse: Decodable {
    let items: [LumiDrawerItem]
}

struct LumiDrawerUnseenResponse: Decodable {
    let count: Int
}

struct LumiDrawerSeenRequest: Encodable {
    let ids: [String]
}

struct ChatThread: Codable, Identifiable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var hasMore: Bool?
    var nextBefore: Date?
}

struct ChatRemarkState: Codable, Equatable {
    var assistantRemark: String
    var aiRemark: String
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

struct LumiWatchAnalysisConfig: Decodable {
    let configured: Bool
    let model: String?
}

struct LumiWatchAnalysisResponse: Decodable {
    let summary: String
    let risk: Bool
    let model: String?

    private enum CodingKeys: String, CodingKey { case summary, risk, model }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        summary = try values.decode(String.self, forKey: .summary)
        risk = try values.decodeIfPresent(Bool.self, forKey: .risk) ?? false
        model = try values.decodeIfPresent(String.self, forKey: .model)
    }
}

struct WatchRuntimeSessionEnvelope: Decodable {
    let session: WatchRuntimeSession
}

struct WatchRuntimeSession: Decodable {
    let id: String
    let tickets: [WatchRuntimeTicket]?
}

struct WatchRuntimeTicket: Codable, Identifiable {
    let id: String
    let playheadMS: Int
    let title: String
    let note: String
    let episodeIndex: Int?
}

struct McpServerSettings: Codable {
    var servers: [McpRemoteServer]
    var revision: Int
}

struct McpRemoteServer: Codable, Identifiable {
    var id: String
    var name: String
    var enabled: Bool
    var url: String
    var transport: String?
    var headers: [String: String]
    var tools: [McpToolDefinition]
    var connectedAt: String?
    var error: String?

    static func empty(name: String = "新 MCP 服务器") -> McpRemoteServer {
        McpRemoteServer(id: UUID().uuidString, name: name, enabled: true, url: "", transport: "streamable-http", headers: [:], tools: [], connectedAt: nil, error: nil)
    }
}

struct McpToolDefinition: Codable, Identifiable {
    var name: String
    var description: String?
    var inputSchema: JSONValue?
    var disabled: Bool?
    var id: String { name }
}

indirect enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if try container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON value") }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct McpConnectResponse: Decodable { let tools: [McpToolDefinition]; let serverInfo: McpServerInfo? }
struct McpServerInfo: Decodable { let name: String?; let version: String? }
struct McpToolResult: Decodable { let content: [McpResultContent]?; let isError: Bool? }
struct McpResultContent: Decodable { let type: String?; let text: String? }

struct LumiAPIProviderProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var preset: String
    var baseURL: String
    var model: String
    var models: [String]
    var apiFormat: String
    var chatPath: String

    init(id: String, name: String, preset: String, baseURL: String, model: String, models: [String] = [], apiFormat: String, chatPath: String) {
        self.id = id
        self.name = name
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.models = models
        self.apiFormat = apiFormat
        self.chatPath = chatPath
    }

    private enum CodingKeys: String, CodingKey { case id, name, preset, baseURL, model, models, apiFormat, chatPath }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        preset = try values.decode(String.self, forKey: .preset)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        models = try values.decodeIfPresent([String].self, forKey: .models) ?? (model.isEmpty ? [] : [model])
        apiFormat = try values.decode(String.self, forKey: .apiFormat)
        chatPath = try values.decode(String.self, forKey: .chatPath)
    }

    var keychainAccount: String { "lumi-provider-key-\(id)" }
    var requestConfig: LumiCustomAPIRequestConfig {
        LumiCustomAPIRequestConfig(apiKey: LumiKeychain.read(account: keychainAccount), baseURL: baseURL, apiFormat: apiFormat, chatPath: chatPath)
    }
}

struct LumiCustomAPIRequestConfig: Encodable {
    let apiKey: String
    let baseURL: String
    let apiFormat: String
    let chatPath: String
}

struct LumiAPIProviderPreset: Identifiable {
    let name: String
    let baseURL: String
    let apiFormat: String
    var id: String { name }

    static let values: [LumiAPIProviderPreset] = [
        .init(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiFormat: "openai"),
        .init(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", apiFormat: "openai"),
        .init(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", apiFormat: "openai"),
        .init(name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1", apiFormat: "openai"),
        .init(name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", apiFormat: "openai"),
        .init(name: "Moonshot", baseURL: "https://api.moonshot.cn/v1", apiFormat: "openai"),
        .init(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiFormat: "openai"),
        .init(name: "智谱 AI", baseURL: "https://open.bigmodel.cn/api/paas/v4", apiFormat: "openai"),
        .init(name: "Anthropic Claude", baseURL: "https://api.anthropic.com/v1", apiFormat: "anthropic"),
        .init(name: "自定义 OpenAI 兼容", baseURL: "", apiFormat: "openai"),
        .init(name: "自定义 Claude 兼容", baseURL: "", apiFormat: "anthropic")
    ]
}

enum LumiAPIModelCatalog {
    static func fetch(baseURL: String, apiKey: String, apiFormat: String) async throws -> [String] {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw URLError(.badURL)
        }
        let rootPath = "/" + components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalized = rootPath.replacingOccurrences(of: #"/(chat/completions|messages|models)/?$"#, with: "", options: .regularExpression)
        components.path = normalized.isEmpty || normalized == "/" ? "/v1/models" : normalized + "/models"
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if apiFormat == "anthropic" {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LumiAPIModelCatalog", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "获取模型失败，请检查 API Key、基址和服务商支持情况。"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            ?? (json?["models"] as? [[String: Any]])?.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
            ?? []
    }
}

struct SendMessageRequest: Encodable {
    let content: String
    let systemPrompt: String
    var context: String?
    var contentType: String?
    var stickerName: String?
    var stickerImageURL: String?
    var images: [String] = []
    var galleryImageIDs: [String] = []
    var emojiCatalog: [String: [String]] = [:]
    var tts: TTSRequestSettings?
    var provider: String = "zenmux"
    var model: String = ""
    var customProvider: LumiCustomAPIRequestConfig?
    var pick: ChatOptionPick?
    var timeZone: String = TimeZone.current.identifier
    var stream: Bool = false
}

struct RemoteSticker: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String
    let image: String
    let mimeType: String
    let createdAt: String
}

struct RemoteStickerLibrary: Codable, Sendable {
    var categories: [String]
    var stickers: [RemoteSticker]
}

struct StickerUploadResponse: Decodable {
    let sticker: RemoteSticker
}

struct SendMessageResponse: Decodable {
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
    let galleryItems: [RemoteGalleryItem]?
    let galleryMessages: [ChatMessage]?
    let memorySaved: Bool?
    let aiRemark: String?
    let updatedOptionMessage: ChatMessage?
    let speechAudioBase64: String?
    let speechDuration: Double?
    let speechScript: String?
    let speechError: String?
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

struct TTSRequestSettings: Codable {
    let provider: String
    let apiKey: String
    let model: String
    let voiceID: String
    let baseURL: String
    let enabled: Bool
}

struct CallStartRequest: Encodable {
    let systemPrompt: String
    let tts: TTSRequestSettings?
    var softVoice: Bool = false
    var provider: String = "zenmux"
    var model: String = ""
    var customProvider: LumiCustomAPIRequestConfig?
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
    let hangupAfterPlayback: Bool?
    let nextWakeSeconds: Int?
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
    let hangupAfterPlayback: Bool?
    let nextWakeSeconds: Int?
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
    var voiceContext: String? = nil
    var softVoice: Bool = false
    var provider: String = "zenmux"
    var model: String = ""
    var customProvider: LumiCustomAPIRequestConfig?
    var noResponse: Bool = false
    var wakeFollowUp: Bool = false
}

struct CallAnswerRequest: Encodable {
    let action: String
    let systemPrompt: String
    let tts: TTSRequestSettings?
    let note: String?
    let softVoice: Bool
    var provider: String = "zenmux"
    var model: String = ""
    var customProvider: LumiCustomAPIRequestConfig?
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
    var dnd: Bool? = nil
}

struct ProactiveActions: Codable {
    var message: Bool
    var phone: Bool
    var screen: Bool
    var surf: Bool? = nil
}

struct LumiSoloSettings: Codable, Equatable {
    var enabled: Bool = true
    var mode: String = "mix"
    var desireThreshold: Double = 0.78
    var idleMinutes: Int = 30
    var touchDecayMinutes: Int = 30
    var running: Bool = false
}

struct LumiSoloMetric: Codable, Identifiable {
    var id: String
    var mode: String
    var trigger: String
    var desire: Double
    var chord: String?
    var touchInfluence: Double?
    var durationSeconds: Int
    var completedAt: String
    var interrupted: Bool
}

struct ActivityState: Codable {
    var mode: String
    var lastUserActivityAt: String?
    var lastWakeAt: String?
    var nextWakeAt: String?
    var sleepPendingAt: String?
    var sleepStartedAt: String?
    var sleepUntil: String?
    var nextDreamAt: String?
    var dreamCycle: Int?
    var sleepStage: String?
    var lastSleepError: String?
    var lastDreamAt: String?
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

struct ModelUsageDay: Decodable, Identifiable {
    let date: String
    let requests: Int
    let tokens: Int
    var id: String { date }
}

struct ModelUsageWeek: Decodable {
    let tokens: Int
    let requests: Int
    let cacheRate: Double
}

struct ModelRequestLog: Decodable, Identifiable {
    let id: String
    let createdAt: Date
    let provider: String
    let model: String
    let status: Int
    let durationMs: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let requestJSON: String
    let responseJSON: String
}

extension ModelRequestLog {
    var hasDetails: Bool { !requestJSON.isEmpty || !responseJSON.isEmpty }
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, provider, model, status, durationMs, inputTokens, outputTokens, cachedTokens, requestJSON, responseJSON
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        provider = try values.decode(String.self, forKey: .provider)
        model = try values.decode(String.self, forKey: .model)
        status = try values.decode(Int.self, forKey: .status)
        durationMs = try values.decode(Int.self, forKey: .durationMs)
        inputTokens = try values.decode(Int.self, forKey: .inputTokens)
        outputTokens = try values.decode(Int.self, forKey: .outputTokens)
        cachedTokens = try values.decode(Int.self, forKey: .cachedTokens)
        requestJSON = try values.decodeIfPresent(String.self, forKey: .requestJSON) ?? ""
        responseJSON = try values.decodeIfPresent(String.self, forKey: .responseJSON) ?? ""
    }
}

struct ModelUsageActivityDay: Decodable, Identifiable {
    let date: String
    let requests: Int
    let tokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cacheInputTokens: Int
    let estimatedCacheRequests: Int
    let durationMs: Double
    let errors: Int
    var id: String { date }
}

struct ModelUsageActivity: Decodable {
    let timeZone: String
    let generatedAt: Date
    let firstDate: String
    let retainedRequests: Int
    let days: [ModelUsageActivityDay]
}

struct ModelUsageResponse: Decodable {
    let activity: ModelUsageActivity?
    let days: [ModelUsageDay]
    let week: ModelUsageWeek
    let requests: [ModelRequestLog]
}

struct LumiContextUsageResponse: Decodable {
    let compaction: Compaction

    struct Compaction: Decodable {
        let activeHistoryTokensEstimate: Int
        let lastMeasuredInputTokens: Int
        let triggerTokensEstimate: Int
        let contextLimitTokens: Int?
    }

    var percentage: Int {
        let trigger = max(1, compaction.triggerTokensEstimate)
        let used = max(compaction.activeHistoryTokensEstimate, compaction.lastMeasuredInputTokens)
        return min(100, max(0, Int((Double(used) / Double(trigger) * 100).rounded())))
    }
}

struct LumiContextCompressionSettings: Decodable {
    let triggerRatio: Double
    let defaultTriggerRatio: Double
    let contextLimitTokens: Int
    let triggerTokensEstimate: Int
    let minimumTriggerTokens: Int?
    let maximumTriggerTokens: Int?
}

/// Keyboard and custom input views can report a transient zero or candidate-bar
/// height during replacement. Preserve the established composer position.
struct ChatKeyboardTransitionState {
    private(set) var visibleHeight: CGFloat = 0
    private(set) var showingPanel = false
    private(set) var isSwitching = false
    private var lockedHeight: CGFloat = 0
    private var pendingHeight: CGFloat?

    mutating func begin(panel: Bool, fallbackHeight: CGFloat) {
        lockedHeight = visibleHeight > 0 ? visibleHeight : max(0, fallbackHeight)
        visibleHeight = lockedHeight
        showingPanel = panel
        isSwitching = true
        pendingHeight = nil
    }
    mutating func receive(height: CGFloat) {
        if showingPanel { return }
        if isSwitching { pendingHeight = max(0, height) }
        else { visibleHeight = max(0, height) }
    }
    mutating func finish() {
        isSwitching = false
        if !showingPanel, let pendingHeight, pendingHeight > 0 {
            visibleHeight = max(lockedHeight, pendingHeight)
        }
        pendingHeight = nil
    }
    mutating func dismiss() {
        showingPanel = false
        isSwitching = false
        lockedHeight = 0
        pendingHeight = nil
        visibleHeight = 0
    }
}

struct StickerLinkImportEntry: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
}

struct StickerLinkImportList {
    var entries: [StickerLinkImportEntry] = []
    var errors: [String] = []

    static func parse(_ text: String) -> Self {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Self()
        var pairs: [(Int, String, String)] = []
        if let data = input.data(using: .utf8),
           let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            pairs = objects.enumerated().map { ($0.offset + 1, $0.element["name"] as? String ?? "", $0.element["url"] as? String ?? $0.element["image"] as? String ?? "") }
        } else {
            for (offset, rawLine) in input.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                if line.hasPrefix("["), let middle = line.range(of: "]("), line.hasSuffix(")") {
                    pairs.append((offset + 1, String(line[line.index(after: line.startIndex)..<middle.lowerBound]), String(line[middle.upperBound..<line.index(before: line.endIndex)])))
                } else if let range = line.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
                    let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|,，:：\""))
                    pairs.append((offset + 1, String(line[..<range.lowerBound]).trimmingCharacters(in: trim), String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))))
                    if !line[range.upperBound...].trimmingCharacters(in: trim).isEmpty {
                        result.errors.append("第 \(offset + 1) 行：链接后还有内容，请每行只放一个名称和链接。")
                    }
                } else { result.errors.append("第 \(offset + 1) 行：缺少图片直链。") }
            }
        }
        if pairs.count > 100 { result.errors.append("一次最多导入 100 张，请分批粘贴。") }
        var seen = Set<String>()
        for (line, rawName, rawURL) in pairs.prefix(100) {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80 else { result.errors.append("第 \(line) 项：名称不能为空，且不能超过 80 字。") ; continue }
            guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else {
                result.errors.append("第 \(line) 项：请填写完整的 HTTPS 图片直链。")
                continue
            }
            let key = name + "\n" + url.absoluteString
            guard seen.insert(key).inserted else { result.errors.append("第 \(line) 项：名称和链接重复。") ; continue }
            result.entries.append(StickerLinkImportEntry(name: name, url: url))
        }
        if result.entries.isEmpty && result.errors.isEmpty { result.errors.append("先粘贴名称和直链，每行一张。") }
        return result
    }
}

enum StickerImageFormat {
    static func mimeType(_ data: Data) -> String? {
        if data.count >= 3, data[0] == 0xff, data[1] == 0xd8, data[2] == 0xff { return "image/jpeg" }
        if data.count >= 8, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] { return "image/png" }
        if data.count >= 6, ["GIF87a", "GIF89a"].contains(String(data: data.prefix(6), encoding: .ascii) ?? "") { return "image/gif" }
        if data.count >= 12, String(data: data[0..<4], encoding: .ascii) == "RIFF", String(data: data[8..<12], encoding: .ascii) == "WEBP" { return "image/webp" }
        return nil
    }
}

extension StickerLinkImportList {
    static func replacingHost(in text: String, with replacement: String) throws -> String {
        let parsed = parse(text)
        guard parsed.errors.isEmpty else {
            throw NSError(domain: "StickerImport", code: 1, userInfo: [NSLocalizedDescriptionKey: parsed.errors.joined(separator: "\n")])
        }
        let input = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = input.contains("://") ? input : "https://" + input
        guard let base = URLComponents(string: raw), base.scheme?.lowercased() == "https",
              let host = base.host, !host.isEmpty, base.user == nil, base.password == nil,
              base.path.isEmpty || base.path == "/", base.query == nil, base.fragment == nil else {
            throw NSError(domain: "StickerImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "只填写新的 HTTPS 图床域名，不要带图片路径。"])
        }
        let values: [[String: String]] = try parsed.entries.map { entry in
            guard var parts = URLComponents(url: entry.url, resolvingAgainstBaseURL: false) else {
                throw NSError(domain: "StickerImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "原链接格式无效。"])
            }
            parts.scheme = "https"
            parts.host = host
            parts.port = base.port
            guard let url = parts.url else { throw URLError(.badURL) }
            return ["name": entry.name, "url": url.absoluteString]
        }
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
