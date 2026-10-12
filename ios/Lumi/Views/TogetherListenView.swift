import AVFoundation
import AVKit
import Combine
import MediaPlayer
import SwiftUI

struct NeteaseSong: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let cover: String
    let durationSeconds: Int

    init(id: String, title: String, artist: String, album: String, cover: String, durationSeconds: Int) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.cover = cover; self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? values.decode(String.self, forKey: .id) { id = string }
        else { id = String(try values.decode(Int64.self, forKey: .id)) }
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? values.decodeIfPresent(String.self, forKey: .name) ?? "未知歌曲"
        artist = try values.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try values.decodeIfPresent(String.self, forKey: .album) ?? ""
        cover = try values.decodeIfPresent(String.self, forKey: .cover) ?? ""
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? values.decodeIfPresent(Int.self, forKey: .dur) ?? 0
    }
    private enum CodingKeys: String, CodingKey { case id, title, name, artist, album, cover, durationSeconds, dur }
}

struct NeteaseLoginStatus: Decodable {
    let logged: Bool; let nickname: String
    init(logged: Bool, nickname: String) { self.logged = logged; self.nickname = nickname }
    private enum CodingKeys: String, CodingKey { case logged, nickname }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        logged = try values.decodeIfPresent(Bool.self, forKey: .logged) ?? false
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? ""
    }
}
struct NeteaseLoginQR: Decodable {
    let key: String; let image: String
    private enum CodingKeys: String, CodingKey { case key, image, qrimg }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        image = try values.decodeIfPresent(String.self, forKey: .image) ?? values.decodeIfPresent(String.self, forKey: .qrimg) ?? ""
    }
}
struct NeteaseLoginQRStatus: Decodable { let code: Int; let logged: Bool?; let nickname: String? }
struct NeteaseSongList: Decodable { let songs: [NeteaseSong] }
struct NeteaseSongStream: Decodable { let url: String }
private struct ListenLyric: Identifiable { let id: Int; let time: Double; let text: String; let translation: String }
private struct ListenLyricsResponse: Decodable { let lyric: String; let tlyric: String }
private struct MusicPlaylist: Decodable, Identifiable {
    let id: String; let name: String; let count: Int; let cover: String; let mine: Bool
    private enum CodingKeys: String, CodingKey { case id, name, count, cover, mine }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? values.decode(String.self, forKey: .id) { id = string } else { id = String(try values.decode(Int64.self, forKey: .id)) }
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "歌单"
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? 0
        cover = try values.decodeIfPresent(String.self, forKey: .cover) ?? ""
        mine = try values.decodeIfPresent(Bool.self, forKey: .mine) ?? false
    }
}
private struct MusicPlaylistsResponse: Decodable { let playlists: [MusicPlaylist] }
private struct MusicToplistsResponse: Decodable { let lists: [MusicPlaylist] }
private struct MusicArtist: Decodable, Identifiable {
    let id: String; let name: String; let cover: String
    private enum CodingKeys: String, CodingKey { case id, name, cover }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? values.decode(String.self, forKey: .id) { id = string } else { id = String(try values.decode(Int64.self, forKey: .id)) }
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "歌手"
        cover = try values.decodeIfPresent(String.self, forKey: .cover) ?? ""
    }
}
private struct MusicArtistsResponse: Decodable { let artists: [MusicArtist] }
private struct ListenStatSong: Decodable, Identifiable {
    let id: String; let title: String; let artist: String; let cover: String; let plays: Int; let first: Double; let last: Double; let vibe: String?
    private enum CodingKeys: String, CodingKey { case id, title, artist, cover, plays, first, last, vibe }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? values.decode(String.self, forKey: .id) { id = value } else { id = String(try values.decodeIfPresent(Int64.self, forKey: .id) ?? 0) }
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "未知歌曲"
        artist = try values.decodeIfPresent(String.self, forKey: .artist) ?? ""
        cover = try values.decodeIfPresent(String.self, forKey: .cover) ?? ""
        plays = try values.decodeIfPresent(Int.self, forKey: .plays) ?? 0
        first = try values.decodeIfPresent(Double.self, forKey: .first) ?? 0
        last = try values.decodeIfPresent(Double.self, forKey: .last) ?? 0
        vibe = try values.decodeIfPresent(String.self, forKey: .vibe)
    }
    var song: NeteaseSong { NeteaseSong(id: id, title: title, artist: artist, album: "", cover: cover, durationSeconds: 0) }
}
private struct ListenStatsResponse: Decodable { let total: Int; let distinct: Int; let buckets: [String: Int]; let top: [ListenStatSong]; let recent: [ListenStatSong] }
private struct ListenSongNote: Decodable, Identifiable {
    let songID: String; let title: String; let artist: String; let cover: String; let passage: String; let thought: String; let reply: String; let timestamp: Double
    var id: String { "\(songID)-\(Int(timestamp))-\(thought)" }
    private enum CodingKeys: String, CodingKey { case songID = "song_id", title, artist, cover, passage, thought, reply, timestamp = "ts" }
}
private struct ListenNotesResponse: Decodable { let notes: [ListenSongNote] }
private struct ListenComment: Decodable, Identifiable {
    let id: UUID; let user: String; let avatar: String; let text: String; let likes: Int; let time: String
    private enum CodingKeys: String, CodingKey { case user = "u", avatar = "av", text = "t", likes = "z", time }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID(); user = try values.decodeIfPresent(String.self, forKey: .user) ?? "网易云用户"
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        likes = try values.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        time = try values.decodeIfPresent(String.self, forKey: .time) ?? ""
    }
}
private struct ListenCommentsResponse: Decodable { let comments: [ListenComment]; let total: Int }
private struct ListenAnalysisResponse: Decodable { let text: String; let source: String?; let impression: String; let impression_n: Int }
private struct GeneratedListenAnalysis: Decodable { let text: String; let source: String? }
private struct AnalysisModelsResponse: Decodable { let models: [String] }
private struct DuettoOKResponse: Decodable { let ok: Bool? }
private struct ListenSongContext: Decodable {
    let plays: Int?; let analysis: String?; let analysisSource: String?; let impression: String?; let curLyric: String?; let notes: [ListenSongNote]?
    private enum CodingKeys: String, CodingKey { case plays, analysis, analysisSource = "analysis_source", impression, curLyric = "cur_lyric", notes }
}
private struct ListenLikeListResponse: Decodable {
    let ids: [String]
    private enum CodingKeys: String, CodingKey { case ids }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var container = try values.nestedUnkeyedContainer(forKey: .ids)
        var result: [String] = []
        while !container.isAtEnd {
            if let id = try? container.decode(String.self) { result.append(id) }
            else { result.append(String(try container.decode(Int64.self))) }
        }
        ids = result
    }
}
private struct DuettoSettingsEnvelope: Decodable { let settings: DuettoAppSettings }
private struct DuettoAppSettings: Decodable {
    let userName: String; let aiName: String; let roomName: String; let roomSub: String; let ai: DuettoAISettings
    private enum CodingKeys: String, CodingKey { case userName = "user_name", aiName = "ai_name", roomName = "room_name", roomSub = "room_sub", ai }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userName = try values.decodeIfPresent(String.self, forKey: .userName) ?? "我"
        aiName = try values.decodeIfPresent(String.self, forKey: .aiName) ?? "DJ"
        roomName = try values.decodeIfPresent(String.self, forKey: .roomName) ?? "我们的听歌房"
        roomSub = try values.decodeIfPresent(String.self, forKey: .roomSub) ?? ""
        ai = try values.decode(DuettoAISettings.self, forKey: .ai)
    }
}
private struct DuettoAISettings: Decodable {
    let baseURL: String; let model: String; let persona: String; let style: String; let hasKey: Bool
    let analysisBaseURL: String; let analysisModel: String; let hasAnalysisKey: Bool; let analysisKeyHint: String
    private enum CodingKeys: String, CodingKey { case baseURL = "base_url", model, persona, style, hasKey = "has_key", analysisBaseURL = "a_base", analysisModel = "a_model", hasAnalysisKey = "has_a_key", analysisKeyHint = "a_key_hint" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? ""
        persona = try values.decodeIfPresent(String.self, forKey: .persona) ?? ""
        style = try values.decodeIfPresent(String.self, forKey: .style) ?? ""
        hasKey = try values.decodeIfPresent(Bool.self, forKey: .hasKey) ?? false
        analysisBaseURL = try values.decodeIfPresent(String.self, forKey: .analysisBaseURL) ?? ""
        analysisModel = try values.decodeIfPresent(String.self, forKey: .analysisModel) ?? ""
        hasAnalysisKey = try values.decodeIfPresent(Bool.self, forKey: .hasAnalysisKey) ?? false
        analysisKeyHint = try values.decodeIfPresent(String.self, forKey: .analysisKeyHint) ?? ""
    }
}
struct MusicRoomEnvelope: Decodable { let state: MusicRoomSnapshot? }
struct MusicRoomMessagesEnvelope: Decodable { let messages: [MusicRoomMessage] }
struct MusicRoomMessageEnvelope: Decodable { let message: MusicRoomMessage }
private struct DuettoRoomEventEnvelope: Decodable {
    struct Event: Decodable {
        struct Message: Decodable { let who: String; let t: String; let ts: Double? }
        let msg: Message; let ts: Double
    }
    let events: [Event]
}

struct MusicRoomMessage: Decodable, Identifiable, Equatable {
    let id: String
    let actorID: String
    let sender: String
    let text: String
    let createdAt: Double
}

struct MusicRoomSnapshot: Codable, Equatable {
    var room: String
    var songID: String
    var title: String
    var artist: String
    var cover: String
    var durationSeconds: Double
    var positionSeconds: Double
    var isPlaying: Bool
    var actorID: String
    var revision: Int
    var updatedAt: Double
}

private enum ListenSection: String, CaseIterable, Identifiable {
    case moment = "此刻", queue = "歌单", library = "曲库", room = "一起听"
    var id: String { rawValue }
    var symbol: String { switch self { case .moment: "record.circle"; case .queue: "text.line.first.and.arrowtriangle.forward"; case .library: "magnifyingglass"; case .room: "heart" } }
}

@MainActor
private final class TogetherListenModel: ObservableObject {
    static let shared = TogetherListenModel()

    @Published var section: ListenSection = .moment
    @Published var login: NeteaseLoginStatus?
    @Published var qr: NeteaseLoginQR?
    @Published var songs: [NeteaseSong] = []
    @Published var playlists: [MusicPlaylist] = []
    @Published var viewingPlaylist: MusicPlaylist?
    @Published var toplists: [MusicPlaylist] = []
    @Published var artists: [MusicArtist] = []
    @Published var lyrics: [ListenLyric] = []
    @Published var showingLyrics = false
    @Published var showingCover = false
    @Published var showTranslations = true
    @Published var lyricScale = 1
    @Published var queue: [NeteaseSong] = []
    @Published var current: NeteaseSong?
    @Published var messages: [MusicRoomMessage] = []
    @Published var query = ""
    @Published var messageDraft = ""
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var error: String?
    @Published var isLoading = false
    @Published var roomConnected = false
    @Published var qrHint = ""
    @Published var isThinking = false
    @Published var showingArchive = false
    @Published var listenStats: ListenStatsResponse?
    @Published var songNotes: [ListenSongNote] = []
    @Published var songComments: [ListenComment] = []
    @Published var commentsTotal = 0
    @Published var songAnalysis = ""
    @Published var songAnalysisSource = ""
    @Published var songImpression = ""
    @Published var isLiked = false
    @Published var likedSongIDs: Set<String> = []
    @Published var quoteDraft = ""
    @Published var userName = ""
    @Published var roomName = ""
    @Published var roomSub = ""
    @Published var analysisBaseURL = ""
    @Published var analysisAPIKey = ""
    @Published var analysisModel = ""
    @Published var analysisKeyHint = ""
    @Published var hasAnalysisKey = false
    @Published var availableAnalysisModels: [String] = []
    @Published var isLoadingAnalysisModels = false
    @Published var isSavingSettings = false
    @Published var player: AVPlayer?
    @Published var playMode = 0
    @Published var isFMQueue = false
    @Published var isLoadingFM = false
    @Published var sleepMinutes: Int?
    let api = LumiAPIClient()
    let actorID = UUID().uuidString
    @Published var room = UserDefaults.standard.string(forKey: "duetto-room") ?? "main"
    private var roomRevision = 0
    private var pollTask: Task<Void, Never>?
    private var pollCycle = 0
    private var qrTask: Task<Void, Never>?
    private var ticker: Any?
    private var endObserver: NSObjectProtocol?
    private var isRemotePlayback = false
    private var remoteCommandsRegistered = false
    private var artworkSongID = ""
    private var roomSocket: URLSessionWebSocketTask?
    private var roomSocketTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var hasStarted = false
    private var currentStreamURL = ""
    private var currentStreamSongID = ""
    private var hasExplicitPlaylistQueue = false
    private var prefetchedStreamURLs: [String: URL] = [:]
    private var prefetchTask: Task<Void, Never>?

    var currentLyricText: String { lyrics.last(where: { $0.time <= position })?.text ?? "" }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        registerRemoteCommands()
        Task { await refreshLogin(); await refreshRoom(); await refreshMessages() }
        Task { await refreshLikeStatus() }
        roomSocketTask?.cancel()
        roomSocketTask = Task {
            while !Task.isCancelled {
                if roomSocket == nil { await connectRoomSocket() }
                try? await Task.sleep(for: roomSocket == nil ? .seconds(12) : .seconds(3))
            }
        }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                pollCycle += 1
                if !roomConnected || pollCycle % 3 == 0 {
                    await refreshRoom()
                    await refreshMessages()
                }
                if isPlaying && !isRemotePlayback && pollCycle % 2 == 0 { await publishRoomState() }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stop() {
        pollTask?.cancel(); qrTask?.cancel(); roomSocketTask?.cancel(); sleepTask?.cancel(); roomSocket?.cancel(with: .goingAway, reason: nil); roomSocket = nil
        if let ticker, let player { player.removeTimeObserver(ticker) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    fileprivate func duettoToken() async throws -> String {
        let cached = LumiKeychain.read(account: "duetto-access-token")
        if !cached.isEmpty { return cached }
        guard let push = api.pushAPIToken, !push.isEmpty else {
            throw LumiAPIError.server("Lumi 服务授权尚未配置。请先在 Lumi 聊天设置中配置服务器口令。")
        }
        var request = URLRequest(url: api.baseURL.appending(path: "/api/auth/session"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(push)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = payload["token"] as? String else {
            throw LumiAPIError.server("无法取得 Duetto 服务授权。")
        }
        LumiKeychain.write(token, account: "duetto-access-token")
        return token
    }

    fileprivate func duetto<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let token = try await duettoToken()
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var components = URLComponents(url: api.baseURL.appending(path: String(parts[0])), resolvingAgainstBaseURL: false)!
        if parts.count > 1, !parts[1].isEmpty { components.percentEncodedQuery = String(parts[1]) }
        guard let url = components.url else { throw LumiAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path.contains("song-analysis") ? 125 : 35
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var lastError: Error = LumiAPIError.invalidResponse
        for attempt in 0..<(method == "GET" ? 3 : 1) {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw LumiAPIError.invalidResponse }
                if http.statusCode == 401 {
                    LumiKeychain.write("", account: "duetto-access-token")
                    throw LumiAPIError.server("服务授权失效，请重试。")
                }
                guard (200..<300).contains(http.statusCode) else {
                    let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "请求失败"
                    throw LumiAPIError.server("HTTP \(http.statusCode)：\(detail)")
                }
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                lastError = error
                if attempt < (method == "GET" ? 2 : 0) { try? await Task.sleep(for: .milliseconds(400 * (attempt + 1))) }
            }
        }
        throw lastError
    }

    private func queryPath(_ path: String, items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        guard let query = components.percentEncodedQuery, !query.isEmpty else { return path }
        return "\(path)?\(query)"
    }

    func refreshLogin() async {
        do { login = try await duetto("/api/ncm/status") }
        catch { self.error = error.localizedDescription }
    }

    func beginQRLogin() async {
        do {
            qr = try await duetto("/api/ncm/qr")
            qrHint = "请用网易云音乐 App 扫码登录"
            qrTask?.cancel()
            guard let key = qr?.key else { return }
            qrTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    do {
                        let result: NeteaseLoginQRStatus = try await duetto(queryPath("/api/ncm/check", items: [URLQueryItem(name: "key", value: key)]))
                        if result.code == 803 || result.logged == true {
                            login = NeteaseLoginStatus(logged: true, nickname: result.nickname ?? "已登录")
                            await refreshLikeStatus()
                            qr = nil; qrHint = "登录成功"; return
                        }
                        if result.code == 800 { qr = nil; qrHint = "二维码已过期，请重新获取"; return }
                    } catch { qrHint = error.localizedDescription }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let result: NeteaseSongList = try await duetto(queryPath("/api/ncm/search", items: [URLQueryItem(name: "kw", value: query)]))
            songs = result.songs; viewingPlaylist = nil
        } catch { self.error = error.localizedDescription }
    }

    func loadRecommendations() async {
        isLoading = true; defer { isLoading = false }
        do { let result: NeteaseSongList = try await duetto("/api/ncm/recommend"); songs = result.songs; viewingPlaylist = nil }
        catch { self.error = error.localizedDescription }
    }

    func loadPlaylists() async {
        do { let result: MusicPlaylistsResponse = try await duetto("/api/ncm/playlists"); playlists = result.playlists }
        catch { self.error = error.localizedDescription }
    }

    func loadPlaylist(_ playlist: MusicPlaylist) async {
        isLoading = true; defer { isLoading = false }
        do { let result: NeteaseSongList = try await duetto(queryPath("/api/ncm/playlist", items: [URLQueryItem(name: "id", value: playlist.id)])); songs = result.songs; viewingPlaylist = playlist }
        catch { self.error = error.localizedDescription }
    }

    func loadToplists() async {
        do { let result: MusicToplistsResponse = try await duetto("/api/ncm/toplist"); toplists = result.lists }
        catch { self.error = error.localizedDescription }
    }

    func loadToplist(_ list: MusicPlaylist) async {
        isLoading = true; defer { isLoading = false }
        do { let result: NeteaseSongList = try await duetto(queryPath("/api/ncm/toplist", items: [URLQueryItem(name: "id", value: list.id)])); songs = result.songs; viewingPlaylist = nil }
        catch { self.error = error.localizedDescription }
    }

    func loadRecentNetease() async {
        isLoading = true; defer { isLoading = false }
        do { let result: NeteaseSongList = try await duetto("/api/ncm/record"); songs = result.songs; viewingPlaylist = nil }
        catch { self.error = error.localizedDescription }
    }

    func searchArtists() async {
        do { let result: MusicArtistsResponse = try await duetto(queryPath("/api/ncm/search-artist", items: [URLQueryItem(name: "kw", value: query)])); artists = result.artists }
        catch { self.error = error.localizedDescription }
    }

    func loadArtist(_ artist: MusicArtist) async {
        isLoading = true; defer { isLoading = false }
        do { let result: NeteaseSongList = try await duetto(queryPath("/api/ncm/artist-songs", items: [URLQueryItem(name: "id", value: artist.id)])); songs = result.songs; viewingPlaylist = nil }
        catch { self.error = error.localizedDescription }
    }

    func addSongToQueue(_ song: NeteaseSong) {
        if !queue.contains(where: { $0.id == song.id }) { queue.append(song) }
        hasExplicitPlaylistQueue = true
    }
    func removeFromQueue(_ song: NeteaseSong) { queue.removeAll { $0.id == song.id } }

    func moveInQueue(_ song: NeteaseSong, by offset: Int) {
        guard let index = queue.firstIndex(where: { $0.id == song.id }) else { return }
        let target = min(max(index + offset, 0), queue.count - 1)
        guard index != target else { return }
        queue.swapAt(index, target)
    }

    func removeFromPlaylist(_ song: NeteaseSong) async {
        guard let viewingPlaylist, viewingPlaylist.mine else { return }
        do {
            let _: [String: AnyCodableValue] = try await duetto(queryPath("/api/ncm/playlist-del", items: [URLQueryItem(name: "pid", value: viewingPlaylist.id), URLQueryItem(name: "id", value: song.id)]), method: "POST")
            songs.removeAll { $0.id == song.id }
        } catch { self.error = error.localizedDescription }
    }

    func addSong(_ song: NeteaseSong, to playlist: MusicPlaylist) async {
        do {
            guard playlist.mine else { throw LumiAPIError.server("只能添加到自己创建的歌单。") }
            let before: NeteaseSongList = try await duetto(queryPath("/api/ncm/playlist", items: [URLQueryItem(name: "id", value: playlist.id)]))
            let _: [String: AnyCodableValue] = try await duetto(queryPath("/api/ncm/playlist-add", items: [URLQueryItem(name: "pid", value: playlist.id), URLQueryItem(name: "id", value: song.id)]), method: "POST")
            let result: NeteaseSongList = try await duetto(queryPath("/api/ncm/playlist", items: [URLQueryItem(name: "id", value: playlist.id)]))
            let matchedCount = result.songs.filter { $0.id == song.id }.count
            let previousIDs = Set(before.songs.map(\.id))
            let unexpectedNewIDs = Set(result.songs.map(\.id)).subtracting(previousIDs).subtracting([song.id])
            guard matchedCount <= 1, unexpectedNewIDs.isEmpty else {
                throw LumiAPIError.server("网易云歌单没有只添加所选歌曲，请检查歌单后重试。")
            }
            error = "已将《\(song.title)》加入「\(playlist.name)」"
        } catch { self.error = error.localizedDescription }
    }

    func play(_ song: NeteaseSong, in list: [NeteaseSong]? = nil) async {
        if let list { queue = list; isFMQueue = false; hasExplicitPlaylistQueue = true }
        else if !queue.contains(where: { $0.id == song.id }) {
            queue = [song]
            isFMQueue = false
            hasExplicitPlaylistQueue = false
        }
        current = song; position = 0; isRemotePlayback = false
        Task { await loadLyrics(song) }
        Task { await refreshLikeStatus() }
        do {
            let url: URL
            if let cached = prefetchedStreamURLs.removeValue(forKey: song.id) { url = cached }
            else {
                let stream: NeteaseSongStream = try await duetto(queryPath("/api/ncm/song-url", items: [URLQueryItem(name: "id", value: song.id)]))
                guard let resolved = URL(string: stream.url), resolved.scheme == "https" else { throw LumiAPIError.server("这首歌暂时没有可播放的音源。") }
                url = resolved
            }
            currentStreamURL = url.absoluteString
            currentStreamSongID = song.id
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 12
            let nextPlayer = AVPlayer(playerItem: item)
            nextPlayer.automaticallyWaitsToMinimizeStalling = true
            if let ticker, let player { player.removeTimeObserver(ticker) }
            player?.pause(); player = nextPlayer; nextPlayer.play(); isPlaying = true
            installEndObserver(for: nextPlayer)
            ticker = nextPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
                Task { @MainActor in self?.position = time.seconds.isFinite ? max(0, time.seconds) : 0; self?.updateNowPlaying() }
            }
            updateNowPlaying()
            prefetchNextStreams(after: song)
            if !hasExplicitPlaylistQueue && !isFMQueue && queue.count == 1 {
                Task { await self.prepareContinuousQueue(after: song) }
            }
            Task { await self.publishRoomState() }
            let _: [String: AnyCodableValue] = try await duetto("/api/listen-log", method: "POST", body: ["id": song.id, "title": song.title, "artist": song.artist, "cover": song.cover, "dur": song.durationSeconds, "url": url.absoluteString])
        } catch { self.error = error.localizedDescription; isPlaying = false }
    }

    func togglePlayback() {
        isRemotePlayback = false
        guard let player else { if let current { Task { await play(current) } }; return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle(); updateNowPlaying(); Task { await publishRoomState() }
    }

    func setSleepTimer(_ minutes: Int?) {
        sleepTask?.cancel(); sleepMinutes = minutes
        guard let minutes else { return }
        sleepTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            player?.pause(); isPlaying = false; sleepMinutes = nil; updateNowPlaying()
            await publishRoomState()
        }
    }

    func seek(_ value: Double) { isRemotePlayback = false; position = value; player?.seek(to: CMTime(seconds: value, preferredTimescale: 600)); Task { await publishRoomState() } }

    func skip(_ delta: Int) {
        guard !queue.isEmpty else { return }
        let currentIndex = queue.firstIndex(where: { $0.id == current?.id }) ?? 0
        if delta > 0 && queue.count == 1 && !hasExplicitPlaylistQueue { Task { await advanceAfterTrackEnds() }; return }
        if isFMQueue && delta > 0 && currentIndex == queue.count - 1 { Task { await appendFMPage() }; return }
        let next = playMode == 2 && delta > 0 ? Int.random(in: 0..<queue.count) : (currentIndex + delta + queue.count) % queue.count
        Task { await play(queue[next]) }
    }

    private func advanceAfterTrackEnds() async {
        guard let current else { return }
        if playMode == 1 { player?.seek(to: .zero); player?.play(); position = 0; return }
        let index = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        if queue.count > 1 {
            if !hasExplicitPlaylistQueue && index == queue.count - 1 && playMode != 2 {
                do {
                    let result: NeteaseSongList = try await duetto("/api/ncm/recommend")
                    let known = Set(queue.map(\.id))
                    let more = result.songs.filter { !known.contains($0.id) }
                    if let first = more.first {
                        queue.append(contentsOf: more)
                        await play(first)
                        return
                    }
                } catch { }
            }
            let next = playMode == 2 ? Int.random(in: 0..<queue.count) : (index + 1) % queue.count
            await play(queue[next])
            return
        }
        if hasExplicitPlaylistQueue {
            player?.seek(to: .zero); player?.play(); position = 0; isPlaying = true
            return
        }
        // A single manually selected track is not a playlist: continue with NCM daily recommendations.
        do {
            let result: NeteaseSongList = try await duetto("/api/ncm/recommend")
            let candidates = result.songs.filter { $0.id != current.id }
            let fallback = songs.filter { $0.id != current.id }
            let continuousSongs = candidates.isEmpty ? fallback : candidates
            guard !continuousSongs.isEmpty else { player?.seek(to: .zero); player?.play(); position = 0; isPlaying = true; return }
            let next = playMode == 2 ? continuousSongs.randomElement()! : continuousSongs[0]
            queue = [current] + continuousSongs
            hasExplicitPlaylistQueue = false
            await play(next)
        } catch {
            // If NCM recommendations are down, continue from songs already loaded in the library.
            let fallback = songs.filter { $0.id != current.id }
            guard !fallback.isEmpty else { player?.seek(to: .zero); player?.play(); position = 0; isPlaying = true; return }
            let next = playMode == 2 ? fallback.randomElement()! : fallback[0]
            queue = [current] + fallback
            hasExplicitPlaylistQueue = false
            await play(next)
        }
    }

    private func prepareContinuousQueue(after song: NeteaseSong) async {
        guard !hasExplicitPlaylistQueue, !isFMQueue, queue.count == 1, current?.id == song.id else { return }
        do {
            let result: NeteaseSongList = try await duetto("/api/ncm/recommend")
            guard current?.id == song.id else { return }
            let known = Set(queue.map(\.id))
            let nextSongs = result.songs.filter { !known.contains($0.id) }
            guard !nextSongs.isEmpty else { return }
            queue.append(contentsOf: nextSongs)
            prefetchNextStreams(after: song)
        } catch {
            guard current?.id == song.id else { return }
            let known = Set(queue.map(\.id))
            let fallback = songs.filter { !known.contains($0.id) }
            guard !fallback.isEmpty else { return }
            queue.append(contentsOf: fallback)
            prefetchNextStreams(after: song)
        }
    }

    private func prefetchNextStreams(after song: NeteaseSong) {
        prefetchTask?.cancel()
        let index = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        let nextSongs: [NeteaseSong]
        if queue.count > 1 {
            nextSongs = (1...min(3, queue.count - 1)).compactMap { offset in queue[(index + offset) % queue.count] }
        } else { nextSongs = [] }
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for next in nextSongs where self.prefetchedStreamURLs[next.id] == nil {
                guard !Task.isCancelled else { return }
                if let stream: NeteaseSongStream = try? await self.duetto(self.queryPath("/api/ncm/song-url", items: [URLQueryItem(name: "id", value: next.id)])),
                   let url = URL(string: stream.url), url.scheme == "https" { self.prefetchedStreamURLs[next.id] = url }
            }
        }
    }

    func chatListeningContext() async -> String? {
        guard let current, isPlaying || player != nil else { return nil }
        let analysis: GeneratedListenAnalysis? = try? await duetto("/api/song-analysis", method: "POST", body: ["id": current.id, "title": current.title, "artist": current.artist, "audio_url": currentStreamSongID == current.id ? currentStreamURL : ""])
        let context: ListenSongContext? = try? await duetto(queryPath("/api/song-context", items: [URLQueryItem(name: "id", value: current.id), URLQueryItem(name: "pos", value: String(position))]))
        let lyric = lyrics.last(where: { $0.time <= position })?.text ?? context?.curLyric ?? "暂无当前歌词"
        let time = "\(Int(position) / 60):\(String(format: "%02d", Int(position) % 60))"
        var lines = ["一起听实时上下文：歌曲《\(current.title)》- \(current.artist)，播放到 \(time)，当前歌词：\(lyric)。"]
        if let plays = context?.plays { lines.append("你们一起听过这首歌 \(plays) 次。") }
        let analysisText = analysis?.text ?? context?.analysis
        let source = analysis?.source ?? context?.analysisSource ?? "unknown"
        let sourceLabel = source == "audio" ? "模型实际听完整首音频后的赏析" : (source == "lyrics" ? "仅根据歌词推断（模型没有听到音频）" : "已保存的听歌分析，来源未记录")
        if let analysisText, !analysisText.isEmpty { lines.append("\(sourceLabel)：\(analysisText)") }
        if let impression = context?.impression, !impression.isEmpty { lines.append("这首歌积累的共同回忆：\(impression)") }
        if let notes = context?.notes, !notes.isEmpty {
            lines.append("最近关于这首歌的交流：" + notes.suffix(12).map { "用户：\($0.thought)；AI：\($0.reply)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    func startFM() async {
        isLoadingFM = true; defer { isLoadingFM = false }
        do {
            let result: NeteaseSongList = try await duetto("/api/ncm/personal-fm")
            guard let first = result.songs.first else { throw LumiAPIError.server("私人 FM 暂时没有新歌") }
            queue = result.songs; isFMQueue = true; hasExplicitPlaylistQueue = false
            await play(first)
            isFMQueue = true
        } catch { self.error = error.localizedDescription }
    }

    private func appendFMPage() async {
        guard !isLoadingFM else { return }
        isLoadingFM = true; defer { isLoadingFM = false }
        do {
            let result: NeteaseSongList = try await duetto("/api/ncm/personal-fm")
            let known = Set(queue.map(\.id))
            let newSongs = result.songs.filter { !known.contains($0.id) }
            guard !newSongs.isEmpty else { throw LumiAPIError.server("私人 FM 暂时没有更多新歌") }
            queue.append(contentsOf: newSongs)
            await play(newSongs[0])
            isFMQueue = true
        } catch { self.error = error.localizedDescription }
    }

    private func installEndObserver(for player: AVPlayer) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        guard let item = player.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.advanceAfterTrackEnds()
            }
        }
    }

    private func registerRemoteCommands() {
        guard !remoteCommandsRegistered else { return }
        remoteCommandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.play(); self?.isPlaying = true; self?.updateNowPlaying(); Task { await self?.publishRoomState() } }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.pause(); self?.isPlaying = false; self?.updateNowPlaying(); Task { await self?.publishRoomState() } }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(1) }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-1) }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album,
            MPMediaItemPropertyPlaybackDuration: Double(current.durationSeconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard artworkSongID != current.id, let url = URL(string: current.cover) else { return }
        artworkSongID = current.id
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data), self.current?.id == current.id else { return }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    func refreshRoom() async {
        do {
            guard let snapshot = try await api.fetchMusicRoomState(room: room) else { roomConnected = true; return }
            roomConnected = true; roomRevision = max(roomRevision, snapshot.revision)
            if snapshot.actorID == actorID { return }
            isRemotePlayback = true
            if current?.id != snapshot.songID {
                let remote = NeteaseSong(id: snapshot.songID, title: snapshot.title, artist: snapshot.artist, album: "", cover: snapshot.cover, durationSeconds: Int(snapshot.durationSeconds))
                current = remote
                do {
                    let stream: NeteaseSongStream = try await duetto(queryPath("/api/ncm/song-url", items: [URLQueryItem(name: "id", value: remote.id)]))
                    guard let url = URL(string: stream.url), url.scheme == "https" else { throw LumiAPIError.server("这首歌暂时没有可播放的音源。") }
                    player?.pause(); player = AVPlayer(url: url); if let player { installEndObserver(for: player) }
                    await player?.seek(to: CMTime(seconds: snapshot.positionSeconds, preferredTimescale: 600))
                    if snapshot.isPlaying { player?.play() }
                    isPlaying = snapshot.isPlaying
                } catch { self.error = error.localizedDescription }
            } else if abs(position - snapshot.positionSeconds) > 4 {
                await player?.seek(to: CMTime(seconds: snapshot.positionSeconds, preferredTimescale: 600)); position = snapshot.positionSeconds
            }
        } catch {
            roomSocket?.cancel(with: .goingAway, reason: nil)
            roomSocket = nil
            roomConnected = false
        }
    }

    private func publishRoomState() async {
        guard let current else { return }
        let snapshot = MusicRoomSnapshot(room: room, songID: current.id, title: current.title, artist: current.artist,
            cover: current.cover, durationSeconds: Double(current.durationSeconds), positionSeconds: position,
            isPlaying: isPlaying, actorID: actorID, revision: roomRevision, updatedAt: Date().timeIntervalSince1970 * 1000)
        do { _ = try await api.updateMusicRoomState(snapshot); roomConnected = true }
        catch { roomConnected = false }
        let payload: [String: Any] = [
            "action": isPlaying ? "play" : "pause", "idx": 0, "time": position,
            "song": ["id": current.id, "title": current.title, "artist": current.artist, "album": current.album, "cover": current.cover, "dur": current.durationSeconds]
        ]
        try? await sendSocket(payload)
    }

    func refreshMessages() async {
        do {
            let response: DuettoRoomEventEnvelope = try await duetto(queryPath("/api/room/events", items: [URLQueryItem(name: "room", value: room), URLQueryItem(name: "limit", value: "120")]))
            let duettoMessages = response.events.map { event in
                let id = String(Int64(event.msg.ts ?? event.ts))
                return MusicRoomMessage(id: id, actorID: event.msg.who, sender: event.msg.who, text: event.msg.t, createdAt: event.msg.ts ?? event.ts)
            }
            let fallbackMessages = (try? await api.fetchMusicRoomMessages(room: room)) ?? []
            var merged = duettoMessages
            for message in fallbackMessages where !merged.contains(where: {
                $0.id == message.id || ($0.sender == message.sender && $0.text == message.text && abs($0.createdAt - message.createdAt) < 2_000)
            }) { merged.append(message) }
            for message in messages where !merged.contains(where: {
                $0.id == message.id || ($0.sender == message.sender && $0.text == message.text && abs($0.createdAt - message.createdAt) < 2_000)
            }) { merged.append(message) }
            messages = Array(merged.sorted { $0.createdAt < $1.createdAt }.suffix(120))
        } catch {
            do { messages = try await api.fetchMusicRoomMessages(room: room) }
            catch { }
        }
    }

    func loadArchive() async {
        async let statsRequest: ListenStatsResponse = duetto("/api/listen-stats")
        async let notesRequest: ListenNotesResponse = duetto(queryPath("/api/song-notes", items: [URLQueryItem(name: "limit", value: "80")]))
        do {
            let (stats, noteResult) = try await (statsRequest, notesRequest)
            listenStats = stats; songNotes = noteResult.notes
        } catch { self.error = error.localizedDescription }
    }

    func loadSettings() async {
        do {
            let response: DuettoSettingsEnvelope = try await duetto("/api/settings")
            userName = response.settings.userName
            roomName = response.settings.roomName; roomSub = response.settings.roomSub
            analysisBaseURL = response.settings.ai.analysisBaseURL
            analysisModel = response.settings.ai.analysisModel
            hasAnalysisKey = response.settings.ai.hasAnalysisKey
            analysisKeyHint = response.settings.ai.analysisKeyHint
        } catch { self.error = error.localizedDescription }
    }

    func saveSettings(roomID: String) async {
        isSavingSettings = true; defer { isSavingSettings = false }
        do {
            let _: [String: AnyCodableValue] = try await duetto("/api/settings", method: "POST", body: [
                "user_name": userName, "room_name": roomName, "room_sub": roomSub,
                "ai": ["a_base": analysisBaseURL, "a_model": analysisModel, "a_key": analysisAPIKey]
            ])
            analysisAPIKey = ""
            await loadSettings()
            let nextRoom = String(roomID.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
            if !nextRoom.isEmpty, nextRoom != room {
                room = nextRoom; UserDefaults.standard.set(nextRoom, forKey: "duetto-room")
                roomSocket?.cancel(with: .goingAway, reason: nil); roomSocket = nil; roomConnected = false
            }
        } catch { self.error = error.localizedDescription }
    }

    func loadLyrics(_ song: NeteaseSong) async {
        do {
            let response: ListenLyricsResponse = try await duetto(queryPath("/api/ncm/lyric", items: [URLQueryItem(name: "id", value: song.id)]))
            let translations = Self.parseLRC(response.tlyric)
            lyrics = Self.parseLRC(response.lyric).enumerated().map { index, item in
                ListenLyric(id: index, time: item.0, text: item.1, translation: translations.first(where: { abs($0.0 - item.0) < 1 })?.1 ?? "")
            }
        } catch { lyrics = [] }
    }

    func loadSongDetails(_ song: NeteaseSong) async {
        async let commentsRequest: ListenCommentsResponse = duetto(queryPath("/api/ncm/comments", items: [URLQueryItem(name: "id", value: song.id)]))
        async let analysisRequest: ListenAnalysisResponse = duetto(queryPath("/api/song-analysis", items: [URLQueryItem(name: "id", value: song.id)]))
        async let notesRequest: ListenNotesResponse = duetto(queryPath("/api/song-notes", items: [URLQueryItem(name: "id", value: song.id), URLQueryItem(name: "limit", value: "60")]))
        do {
            let (comments, analysis, notes) = try await (commentsRequest, analysisRequest, notesRequest)
            songComments = comments.comments; commentsTotal = comments.total
            songAnalysis = analysis.text; songAnalysisSource = analysis.source ?? "unknown"; songImpression = analysis.impression
            songNotes = notes.notes
        } catch { self.error = error.localizedDescription }
    }

    func generateSongAnalysis(_ song: NeteaseSong) async {
        do {
            let payload: [String: Any] = ["id": song.id, "title": song.title, "artist": song.artist,
                "audio_url": currentStreamSongID == song.id ? currentStreamURL : ""]
            let result: GeneratedListenAnalysis = try await duetto("/api/song-analysis", method: "POST", body: payload)
            songAnalysis = result.text; songAnalysisSource = result.source ?? "unknown"
        } catch { self.error = error.localizedDescription }
    }

    func fetchAnalysisModels() async {
        isLoadingAnalysisModels = true; defer { isLoadingAnalysisModels = false }
        do {
            let response: AnalysisModelsResponse = try await duetto("/api/analysis-models", method: "POST", body: ["base_url": analysisBaseURL, "api_key": analysisAPIKey])
            availableAnalysisModels = response.models
        }
        catch { self.error = error.localizedDescription }
    }

    func refreshLikeStatus() async {
        do {
            let response: ListenLikeListResponse = try await duetto("/api/ncm/likelist")
            likedSongIDs = Set(response.ids); isLiked = likedSongIDs.contains(current?.id ?? "")
        } catch { }
    }

    func toggleLike() async {
        guard let current else { return }
        await setLike(!isLiked, for: current)
    }

    func setLike(_ next: Bool, for song: NeteaseSong) async {
        do {
            let _: [String: AnyCodableValue] = try await duetto(queryPath("/api/ncm/like", items: [URLQueryItem(name: "id", value: song.id), URLQueryItem(name: "like", value: next ? "1" : "0")]), method: "POST")
            if next { likedSongIDs.insert(song.id) } else { likedSongIDs.remove(song.id) }
            if current?.id == song.id { isLiked = next }
        } catch { self.error = error.localizedDescription }
    }

    func dislikeFM(_ song: NeteaseSong) async {
        let wasCurrent = current?.id == song.id
        let oldIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        do {
            let _: [String: AnyCodableValue] = try await duetto(queryPath("/api/ncm/fm-trash", items: [URLQueryItem(name: "id", value: song.id)]), method: "POST")
            queue.removeAll { $0.id == song.id }
            if wasCurrent {
                if oldIndex < queue.count { await play(queue[oldIndex]) }
                else if isFMQueue { await appendFMPage() }
                else { skip(1) }
            }
        }
        catch { self.error = error.localizedDescription }
    }

    func logoutNetease() async {
        do {
            let _: [String: AnyCodableValue] = try await duetto("/api/ncm/logout", method: "POST")
            login = NeteaseLoginStatus(logged: false, nickname: ""); qr = nil; playlists = []; likedSongIDs = []; isLiked = false
        } catch { self.error = error.localizedDescription }
    }

    private static func parseLRC(_ text: String) -> [(Double, String)] {
        let expression = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)"#)
        return text.components(separatedBy: .newlines).compactMap { line in
            guard let expression, let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let minRange = Range(match.range(at: 1), in: line), let secRange = Range(match.range(at: 2), in: line),
                  let contentRange = Range(match.range(at: 4), in: line) else { return nil }
            let fraction: Double = Range(match.range(at: 3), in: line).flatMap { Double("0.\(line[$0])") } ?? 0
            let time = (Double(line[minRange]) ?? 0) * 60 + (Double(line[secRange]) ?? 0) + fraction
            let value = line[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : (time, value)
        }.sorted { $0.0 < $1.0 }
    }
    func sendMessage() async {
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let sender = login?.nickname.isEmpty == false ? login!.nickname : "我"
            if roomSocket == nil { await connectRoomSocket() }
            if roomSocket != nil {
                let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
                try await sendSocket(["t": "chat", "msg": ["who": sender, "t": text, "time": formatter.string(from: .now), "sys": false, "ts": Date().timeIntervalSince1970 * 1000]])
            } else { _ = try await api.sendMusicRoomMessage(text, room: room, actorID: actorID, sender: sender) }
            messageDraft = ""; await refreshMessages()
        }
        catch { self.error = error.localizedDescription }
    }

    func askRoomAI() async {
        let prompt = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        do {
            isThinking = true
            messageDraft = ""
            let sender = login?.nickname.isEmpty == false ? login!.nickname : "我"
            let route = try ChatViewModel.currentModelRoute()
            var liveContext = ["场景：用户正在 Lumi「一起听」里和你听歌。回复要延续你们原有聊天关系和语气，不创建新的人设。"]
            if let current {
                let generatedAnalysis: GeneratedListenAnalysis? = try? await duetto("/api/song-analysis", method: "POST", body: ["id": current.id, "title": current.title, "artist": current.artist, "audio_url": currentStreamSongID == current.id ? currentStreamURL : ""])
                let elapsed = "\(Int(position) / 60):\(String(format: "%02d", Int(position) % 60))"
                let duration = "\(current.durationSeconds / 60):\(String(format: "%02d", current.durationSeconds % 60))"
                liveContext.append("当前歌曲：《\(current.title)》— \(current.artist)，播放进度 \(elapsed)/\(duration)。")
                let songContext: ListenSongContext? = try? await duetto(queryPath("/api/song-context", items: [URLQueryItem(name: "id", value: current.id), URLQueryItem(name: "pos", value: String(position))]))
                if let plays = songContext?.plays { liveContext.append("你们一起听过这首歌 \(plays) 次。") }
                if let text = songContext?.analysis, !text.isEmpty {
                    let source = songContext?.analysisSource == "audio" ? "模型实际听完整首音频后的赏析" : (songContext?.analysisSource == "lyrics" ? "仅根据歌词推断（没有听到音频）" : "历史分析（来源未记录）")
                    liveContext.append("\(source)：\n\(text)")
                } else if let text = generatedAnalysis?.text, !text.isEmpty {
                    let source = generatedAnalysis?.source == "audio" ? "模型实际听完整首音频后的赏析" : "仅根据歌词推断（没有听到音频）"
                    liveContext.append("\(source)：\n\(text)")
                }
                if let impression = songContext?.impression, !impression.isEmpty { liveContext.append("你们关于这首歌的长期回忆：\n\(impression)") }
                if let notes = songContext?.notes, !notes.isEmpty {
                    let history = notes.map { note in
                        "\(note.passage.isEmpty ? "" : "歌词「\(note.passage)」")\(note.thought.isEmpty ? "" : "用户：\(note.thought)")\(note.reply.isEmpty ? "" : " 你：\(note.reply)")"
                    }.joined(separator: "\n")
                    liveContext.append("这首歌最近的共同聆听记录：\n\(history)")
                }
                if let lyric = songContext?.curLyric, !lyric.isEmpty { liveContext.append("当前歌词：\(lyric)") }
            }
            if let lyric = lyrics.last(where: { $0.time <= position })?.text, !lyric.isEmpty, !liveContext.contains(where: { $0.hasPrefix("当前歌词：") }) {
                liveContext.append("当前歌词：\(lyric)")
            }
            if !quoteDraft.isEmpty { liveContext.append("用户引用的歌词/内容：\(quoteDraft)") }

            let response = try await api.sendMessage(
                prompt,
                to: "default",
                provider: route.provider,
                model: route.model,
                customProvider: route.customProvider,
                contentType: "together_music",
                context: liveContext.joined(separator: "\n")
            )

            let userTime = response.userMessage.createdAt.timeIntervalSince1970 * 1000
            let assistantTime = response.assistantMessage.createdAt.timeIntervalSince1970 * 1000
            let question = MusicRoomMessage(id: response.userMessage.id.uuidString, actorID: actorID, sender: sender, text: prompt, createdAt: userTime)
            let answerText = response.assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answerText.isEmpty else {
                throw LumiAPIError.server("聊天模型没有返回内容，请重试。")
            }
            let answer = MusicRoomMessage(id: response.assistantMessage.id.uuidString, actorID: "assistant", sender: "Lumi 聊天", text: answerText, createdAt: assistantTime)
            messages.append(question)
            messages.append(answer)
            await postRoomMessage(prompt, sender: sender, timestamp: userTime)
            await postRoomMessage(answerText, sender: "Lumi 聊天", timestamp: assistantTime)
            if let current {
                let _: DuettoOKResponse? = try? await duetto("/api/song-note", method: "POST", body: [
                    "id": current.id, "title": current.title, "artist": current.artist, "cover": current.cover,
                    "passage": quoteDraft.isEmpty ? (lyrics.last(where: { $0.time <= position })?.text ?? "") : quoteDraft,
                    "thought": prompt, "reply": answerText
                ])
            }
            NotificationCenter.default.post(name: Notification.Name("LumiRemoteMessageReceived"), object: nil)
            quoteDraft = ""
            if response.memorySaved == true { qrHint = "这段听歌对话已记入 Lumi 记忆" }
        } catch { isThinking = false; self.error = error.localizedDescription }
        isThinking = false
    }

    private func postRoomMessage(_ text: String, sender: String, timestamp: Double) async {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        if roomSocket == nil { await connectRoomSocket() }
        if roomSocket != nil {
            do {
                try await sendSocket(["t": "chat", "msg": ["who": sender, "t": text, "time": formatter.string(from: Date(timeIntervalSince1970: timestamp / 1000)), "sys": false, "ts": timestamp]])
                return
            } catch { }
        }
        if let persisted = try? await api.sendMusicRoomMessage(text, room: room, actorID: actorID, sender: sender),
           !messages.contains(where: { $0.id == persisted.id }) {
            messages.append(persisted)
        }
    }

    private func connectRoomSocket() async {
        guard roomSocket == nil else { return }
        do {
            let token = try await duettoToken()
            var components = URLComponents(url: api.baseURL, resolvingAgainstBaseURL: false)!
            components.scheme = components.scheme == "http" ? "ws" : "wss"
            components.path = "/ws"
            components.queryItems = [URLQueryItem(name: "room", value: room), URLQueryItem(name: "token", value: token)]
            guard let url = components.url else { return }
            let socket = URLSession.shared.webSocketTask(with: url)
            roomSocket = socket; socket.resume(); roomConnected = false
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                socket.sendPing { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            roomConnected = true
            Task { @MainActor [weak self] in await self?.receiveSocket(socket) }
        } catch { roomConnected = false }
    }

    private func receiveSocket(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if (payload["t"] as? String) == "ai", let reply = payload["reply"] as? String {
                    isThinking = false
                    let stamp = Date().timeIntervalSince1970 * 1000
                    let answer = MusicRoomMessage(id: String(Int64(stamp)), actorID: "ai", sender: "TA", text: reply, createdAt: stamp)
                    messages.append(answer)
                    let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
                    try? await sendSocket(["t": "chat", "msg": ["who": "yu", "t": reply, "time": formatter.string(from: .now), "sys": false, "ts": stamp]])
                } else if (payload["t"] as? String) == "chat", let raw = payload["msg"] as? [String: Any] {
                    let sender = raw["who"] as? String ?? "一起听的人"
                    let text = raw["t"] as? String ?? ""
                    let stamp = raw["ts"] as? Double ?? Date().timeIntervalSince1970 * 1000
                    let id = String(Int64(stamp))
                    if !messages.contains(where: { $0.id == id }) { messages.append(MusicRoomMessage(id: id, actorID: sender, sender: sender, text: text, createdAt: stamp)) }
                } else if let song = payload["song"] as? [String: Any],
                          let songData = try? JSONSerialization.data(withJSONObject: song),
                          let remoteSong = try? JSONDecoder().decode(NeteaseSong.self, from: songData) {
                    await applyRemoteSong(remoteSong, position: payload["time"] as? Double ?? 0, playing: (payload["action"] as? String) == "play")
                }
            } catch {
                isThinking = false
                if roomSocket === socket { roomSocket = nil; roomConnected = false }
                return
            }
        }
    }

    private func sendSocket(_ payload: [String: Any]) async throws {
        guard let roomSocket else { throw LumiAPIError.server("房间连接尚未建立") }
        let data = try JSONSerialization.data(withJSONObject: payload)
        do { try await roomSocket.send(.data(data)) }
        catch {
            if self.roomSocket === roomSocket { self.roomSocket = nil; roomConnected = false }
            throw error
        }
    }

    private func applyRemoteSong(_ song: NeteaseSong, position: Double, playing: Bool) async {
        isRemotePlayback = true
        if current?.id != song.id {
            current = song; queue = [song]; hasExplicitPlaylistQueue = false
            do {
                let stream: NeteaseSongStream = try await duetto(queryPath("/api/ncm/song-url", items: [URLQueryItem(name: "id", value: song.id)]))
                guard let url = URL(string: stream.url), url.scheme == "https" else { return }
                player?.pause(); player = AVPlayer(url: url)
                if let player { installEndObserver(for: player); await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)); if playing { player.play() } }
            } catch { self.error = error.localizedDescription }
        } else {
            await player?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
            if playing { player?.play() } else { player?.pause() }
        }
        self.position = position; isPlaying = playing; updateNowPlaying()
    }
}

@MainActor
final class TogetherListenChatPlayback: ObservableObject {
    static let shared = TogetherListenChatPlayback()
    @Published private(set) var current: NeteaseSong?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var currentLyricText = ""
    private let model = TogetherListenModel.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Publishers.CombineLatest4(model.$current, model.$isPlaying, model.$position, model.$lyrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] song, playing, position, lyrics in
                self?.current = song
                self?.isPlaying = playing
                self?.position = position
                self?.currentLyricText = lyrics.last(where: { $0.time <= position })?.text ?? ""
            }
            .store(in: &cancellables)
    }

    func togglePlayback() { model.togglePlayback() }
    func seek(_ position: Double) { model.seek(position) }
    func chatContext() async -> String? { await model.chatListeningContext() }
}

private struct AnyCodableValue: Decodable { init(from decoder: Decoder) throws { _ = try decoder.singleValueContainer() } }

struct TogetherListenView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = TogetherListenModel.shared
    var onOpenChat: (() -> Void)? = nil
    @State private var showError = false
    @State private var showSongDetail = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                ListenColors.background.ignoresSafeArea()
                TabView(selection: $model.section) {
                    sectionScroll(momentPage)
                        .tabItem { Label("此刻", systemImage: ListenSection.moment.symbol) }
                        .tag(ListenSection.moment)
                    sectionScroll(queuePage)
                        .tabItem { Label("歌单", systemImage: ListenSection.queue.symbol) }
                        .tag(ListenSection.queue)
                    sectionScroll(libraryPage)
                        .tabItem { Label("曲库", systemImage: ListenSection.library.symbol) }
                        .tag(ListenSection.library)
                    sectionScroll(roomPage)
                        .tabItem { Label("一起听", systemImage: ListenSection.room.symbol) }
                        .tag(ListenSection.room)
                }
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
            .navigationTitle("一起听")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ListenColors.heart).frame(width: 40, height: 40)
                            .background(.white.opacity(0.85), in: Circle())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) { Circle().fill(model.roomConnected ? ListenColors.heart : .gray.opacity(0.6)).frame(width: 8, height: 8); Text(model.roomConnected ? "已连接" : "未连接").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(ListenColors.heart) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onOpenChat?() } label: { Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(ListenColors.heart) }
                        .accessibilityLabel("边听边聊")
                }
            }
            .toolbarBackground(ListenColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(ListenColors.heart)
            .preferredColorScheme(.light)
            .task { model.start() }
            .onChange(of: model.section) { _, section in
                if section == .library && model.songs.isEmpty { Task { await model.loadRecommendations() } }
            }
            .alert("一起听", isPresented: $showError, presenting: model.error) { _ in Button("好") { model.error = nil } } message: { Text($0) }
            .onChange(of: model.error) { _, value in showError = value != nil }
            .sheet(isPresented: $showSongDetail) {
                if let song = model.current { ListenSongDetailView(model: model, song: song) }
            }
            .sheet(isPresented: $showSettings) { ListenSettingsView(model: model) }
        }
    }

    private func sectionScroll<Content: View>(_ content: Content) -> some View {
        ScrollView(showsIndicators: false) {
            content
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ListenColors.background)
    }

    private var momentPage: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("一起听").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Text("此刻").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(ListenColors.plumBrown)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(model.roomConnected ? ListenColors.heart : .gray.opacity(0.55)).frame(width: 8, height: 8)
                    Text(model.roomConnected ? "房间在线" : "等待连接").font(.system(size: 12, weight: .medium)).foregroundStyle(ListenColors.plumBrown)
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(.white.opacity(0.82), in: Capsule())
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ListenColors.heart)
                    .frame(width: 42, height: 42)
                    .background(ListenColors.heart.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.roomName.isEmpty ? "我们的听歌房" : model.roomName)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(ListenColors.plumBrown)
                    Text("房间 \(model.room) · 同步歌曲与播放进度")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture { model.section = .room }

            Group {
                if model.current == nil {
                    emptyPlayerCard
                } else if model.showingLyrics {
                    lyricsPanel
                } else if model.showingCover {
                    coverCard
                } else {
                    record
                }
            }

            if let current = model.current {
                VStack(spacing: 5) {
                    Text(current.title).font(.system(size: 21, weight: .semibold)).foregroundStyle(ListenColors.plumBrown).lineLimit(1)
                    Text(current.artist).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                    Button { showSongDetail = true } label: {
                        Text("查看歌曲与评论").font(.system(size: 13, weight: .medium)).foregroundStyle(ListenColors.heart)
                    }.padding(.top, 3)
                }
                HStack(spacing: 30) {
                    Button { Task { await model.toggleLike() } } label: { Image(systemName: model.isLiked ? "heart.fill" : "heart").font(.system(size: 20)) }
                    Button { model.section = .queue } label: { Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.system(size: 19)) }
                    Menu {
                        Button("15 分钟") { model.setSleepTimer(15) }
                        Button("30 分钟") { model.setSleepTimer(30) }
                        Button("45 分钟") { model.setSleepTimer(45) }
                        Button("60 分钟") { model.setSleepTimer(60) }
                        Button("关闭定时") { model.setSleepTimer(nil) }
                    } label: { Image(systemName: model.sleepMinutes == nil ? "moon.zzz" : "moon.fill").font(.system(size: 19)) }
                    Menu {
                        Button("播放封面") { model.showingCover = true; model.showingLyrics = false }
                        Button("查看歌词") { model.showingLyrics = true; model.showingCover = false }
                    } label: { Image(systemName: model.showingLyrics ? "text.quote" : "square.stack").font(.system(size: 19)) }
                }
                .buttonStyle(.plain).foregroundStyle(ListenColors.plumBrown.opacity(0.78))

                VStack(spacing: 5) {
                    Slider(value: Binding(get: { model.position }, set: { model.seek($0) }), in: 0...max(1, Double(current.durationSeconds)))
                        .tint(ListenColors.heart)
                    HStack { Text(time(model.position)); Spacer(); Text("网易云音乐"); Spacer(); Text(time(Double(current.durationSeconds))) }
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                HStack(spacing: 32) {
                    Button { model.playMode = (model.playMode + 1) % 3 } label: { Image(systemName: playModeSymbol).font(.system(size: 19)) }
                    Button { model.skip(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: 21)) }
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 68, height: 68).background(ListenColors.heart, in: Circle())
                    }
                    Button { model.skip(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: 21)) }
                    Button { model.section = .queue } label: { Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.system(size: 19)) }
                }.buttonStyle(.plain).foregroundStyle(ListenColors.plumBrown.opacity(0.82))
            }
        }
        .padding(.bottom, 10)
    }

    private var emptyPlayerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(ListenColors.heart)
                .frame(width: 58, height: 58)
                .background(ListenColors.heart.opacity(0.11), in: Circle())
            VStack(spacing: 4) {
                Text("还没有播放").font(.system(size: 17, weight: .semibold)).foregroundStyle(ListenColors.plumBrown)
                Text("选一首歌，和房间里的设备同步听").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Button {
                model.section = .library
                if model.songs.isEmpty { Task { await model.loadRecommendations() } }
            } label: {
                Label("浏览曲库", systemImage: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ListenColors.heart)
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color(red: 0.055, green: 0.05, blue: 0.047))
            ForEach(0..<13, id: \.self) { index in Circle().stroke(Color.white.opacity(index.isMultiple(of: 3) ? 0.10 : 0.045), lineWidth: 1).padding(CGFloat(12 + index * 8)) }
            Circle().fill(Color(red: 0.16, green: 0.15, blue: 0.15)).frame(width: 164, height: 164)
            AsyncImage(url: URL(string: model.current?.cover ?? "")) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "music.note").font(.system(size: 44, weight: .light)).foregroundStyle(ListenColors.heart.opacity(0.75)) }
            }.frame(width: 104, height: 104).clipShape(Circle())
            Circle().fill(ListenColors.background).frame(width: 17, height: 17).overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 2))
        }
        .frame(width: min(UIScreen.main.bounds.width * 0.60, 270), height: min(UIScreen.main.bounds.width * 0.60, 270))
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) { Circle().fill(ListenColors.plumBrown.opacity(0.6)).frame(width: 17, height: 17); RoundedRectangle(cornerRadius: 3).fill(ListenColors.plumBrown.opacity(0.65)).frame(width: 21, height: 12) }
                .frame(width: 23, height: 108, alignment: .top).rotationEffect(.degrees(3), anchor: .top).offset(x: 12, y: 6)
        }
        .shadow(color: ListenColors.plumBrown.opacity(0.13), radius: 16, y: 10)
    }

    private var coverCard: some View {
        AsyncImage(url: URL(string: model.current?.cover ?? "")) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: 54, weight: .light)).foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) }
        }
        .frame(width: min(UIScreen.main.bounds.width * 0.68, 292), height: min(UIScreen.main.bounds.width * 0.68, 292))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: ListenColors.plumBrown.opacity(0.16), radius: 18, y: 10)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                .overlay(alignment: .bottomLeading) { VStack(alignment: .leading, spacing: 3) { Text(model.current?.title ?? "一起听").font(.system(size: 17, weight: .semibold)); Text(model.current?.artist ?? "网易云音乐").font(.system(size: 12)) }.foregroundStyle(.white).padding(17) }
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var lyricsPanel: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
            HStack {
                Text("歌词").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(model.showTranslations ? "译文开" : "译文关") { model.showTranslations.toggle() }.font(.system(size: 11, weight: .medium)).foregroundStyle(ListenColors.heart)
                Button("A−") { model.lyricScale = max(0, model.lyricScale - 1) }.font(.system(size: 12, weight: .medium)).foregroundStyle(ListenColors.heart).padding(.leading, 6)
                Button("A+") { model.lyricScale = min(2, model.lyricScale + 1) }.font(.system(size: 12, weight: .medium)).foregroundStyle(ListenColors.heart)
            }.padding(.horizontal, 6)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 17) {
                    if model.lyrics.isEmpty {
                        Text(model.current == nil ? "播放歌曲后显示歌词" : "暂无歌词")
                            .font(.system(size: 16, design: .serif)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 100)
                    } else {
                        ForEach(model.lyrics) { line in
                            Button { model.seek(line.time) } label: {
                                VStack(spacing: 4) {
                                    Text(line.text).font(.system(size: (lineIsCurrent(line) ? 19 : 14) + CGFloat(model.lyricScale * 2), weight: lineIsCurrent(line) ? .semibold : .regular, design: .serif))
                                    if model.showTranslations && !line.translation.isEmpty { Text(line.translation).font(.system(size: 11 + CGFloat(model.lyricScale))).opacity(0.7) }
                                }.foregroundStyle(lineIsCurrent(line) ? ListenColors.plumBrown : ListenColors.plumBrown.opacity(0.48))
                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(line.id)
                                .contextMenu { Button("引用并问 TA", systemImage: "quote.bubble") { model.quoteDraft = line.text; model.section = .room } }
                        }
                    }
                }.padding(.horizontal, 14).padding(.vertical, 24)
            }
            .frame(height: 278)
            .onChange(of: activeLyricID) { _, id in if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } } }
            }
        }
    }

    private var activeLyricID: Int? { model.lyrics.last(where: { $0.time <= model.position })?.id }
    private func lineIsCurrent(_ line: ListenLyric) -> Bool { line.id == activeLyricID }
    private var playModeSymbol: String { switch model.playMode { case 1: "repeat.1"; case 2: "shuffle"; default: "repeat" } }

    private var loginCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "headphones").font(.system(size: 19)).foregroundStyle(ListenColors.heart)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.login?.logged == true ? "网易云音乐已连接" : "连接网易云音乐").font(.system(size: 15, weight: .semibold)).foregroundStyle(ListenColors.plumBrown)
                    Text(model.login?.nickname.isEmpty == false ? model.login!.nickname : "登录后搜索歌曲并同步播放").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.login?.logged == true {
                    Button("退出") { Task { await model.logoutNetease() } }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                } else { Button("扫码登录") { Task { await model.beginQRLogin() } }.font(.system(size: 13, weight: .semibold)).foregroundStyle(ListenColors.heart) }
            }
            if let qr = model.qr, let data = qr.image.components(separatedBy: ",").last.flatMap({ Data(base64Encoded: $0) }) {
                if let image = UIImage(data: data) { Image(uiImage: image).interpolation(.none).resizable().frame(width: 150, height: 150).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 18)) }
                Text(model.qrHint).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(16).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
    }

    private var queuePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("歌单", caption: "接下来播放")
            if model.queue.isEmpty { emptyCard("还没有待播歌曲", symbol: "text.line.first.and.arrowtriangle.forward") }
            ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, song in
                songRow(song, index: index + 1) { Task { await model.play(song) } }
            }
            if !model.messages.isEmpty { Text("房间最近动态").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown).padding(.top, 12) }
            ForEach(model.messages.suffix(8)) { message in HStack(alignment: .top, spacing: 10) { Circle().fill(ListenColors.pulse.opacity(0.55)).frame(width: 8, height: 8).padding(.top, 6); VStack(alignment: .leading, spacing: 3) { Text(message.sender).font(.system(size: 11, weight: .medium)).foregroundStyle(ListenColors.heart); Text(message.text).font(.system(size: 14)).foregroundStyle(ListenColors.plumBrown) } }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16)) }
        }
    }

    private var libraryPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            pageHeading("曲库", caption: "搜索 · 推荐 · 网易云音乐")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(ListenColors.heart)
                TextField("搜索歌曲、歌手", text: $model.query).submitLabel(.search).onSubmit { Task { await model.search() } }
                Button { Task { await model.search() } } label: { Image(systemName: "arrow.right.circle.fill").font(.system(size: 24)).foregroundStyle(ListenColors.heart) }
            }.padding(14).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 17))
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { Task { await model.loadRecommendations() } } label: { Label("每日推荐", systemImage: "sun.max") }
                    .buttonStyle(ListenChipStyle())
                Button { Task { await model.loadPlaylists() } } label: { Label("我的歌单", systemImage: "music.note.list") }.buttonStyle(ListenChipStyle())
                Button { Task { await model.startFM() } } label: { Label("私人 FM", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(ListenChipStyle())
                Button { Task { await model.loadToplists() } } label: { Label("排行榜", systemImage: "chart.bar") }.buttonStyle(ListenChipStyle())
                Button { Task { await model.loadRecentNetease() } } label: { Label("最近听过", systemImage: "clock") }.buttonStyle(ListenChipStyle())
                Button { Task { await model.searchArtists() } } label: { Label("搜歌手", systemImage: "person.wave.2") }.buttonStyle(ListenChipStyle())
            }.padding(.vertical, 1)
            }
            if model.isLoading { ProgressView().tint(ListenColors.heart).frame(maxWidth: .infinity).padding() }
            if model.isLoadingFM { Label("私人 FM 正在调频…", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6) }
            if !model.artists.isEmpty {
                Text("歌手").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown)
                ForEach(model.artists) { artist in
                    Button { Task { await model.loadArtist(artist) } } label: {
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: artist.cover)) { phase in if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "person.fill").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) } }.frame(width: 40, height: 40).clipShape(Circle())
                            Text(artist.name).font(.system(size: 14, weight: .medium)).foregroundStyle(ListenColors.plumBrown)
                            Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(10).background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
            if !model.toplists.isEmpty {
                Text("网易云排行榜").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown)
                ForEach(model.toplists) { chart in
                    Button { Task { await model.loadToplist(chart) } } label: {
                        HStack(spacing: 10) { AsyncImage(url: URL(string: chart.cover)) { phase in if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "chart.bar.fill").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) } }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 3) { Text(chart.name).font(.system(size: 14, weight: .medium)).foregroundStyle(ListenColors.plumBrown); Text("\(chart.count) · 网易云音乐榜单").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(9).background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
            if !model.playlists.isEmpty {
                Text("我的歌单").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown).padding(.top, 4)
                ForEach(model.playlists) { playlist in
                    Button { Task { await model.loadPlaylist(playlist) } } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: playlist.cover)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "music.note.list").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) }
                            }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 3) { Text(playlist.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ListenColors.plumBrown); Text("\(playlist.count) 首歌曲").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        }.padding(10).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
            ForEach(Array(model.songs.enumerated()), id: \.element.id) { index, song in songRow(song, index: index + 1) { Task { await model.play(song, in: model.songs) } } }
            loginCard
        }
    }

    private var roomPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("一起听", caption: "房间 \(model.room) · 播放进度实时同步")
            HStack(spacing: 9) {
                Button { model.showingArchive = false } label: { Label("播放与聊天", systemImage: "headphones").frame(maxWidth: .infinity).padding(.vertical, 11).background(!model.showingArchive ? .white : .clear, in: Capsule()) }
                Button { model.showingArchive = true; if model.listenStats == nil { Task { await model.loadArchive() } } } label: { Label("听歌档案", systemImage: "books.vertical").frame(maxWidth: .infinity).padding(.vertical, 11).background(model.showingArchive ? .white : .clear, in: Capsule()) }
            }.font(.system(size: 13, weight: .medium)).foregroundStyle(ListenColors.plumBrown)
                .padding(4).background(ListenColors.background.opacity(0.8), in: Capsule())
            if model.showingArchive {
                archiveContent
            } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "headphones").font(.system(size: 22)).foregroundStyle(ListenColors.heart).frame(width: 48, height: 48).background(ListenColors.background, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 3) { Text(model.roomName.isEmpty ? "我们的听歌房" : model.roomName).font(.system(size: 16, weight: .semibold)); Text(model.roomConnected ? "房间已连接 · 播放进度同步中" : "连接中…").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer(); Circle().fill(model.roomConnected ? .green.opacity(0.75) : .gray.opacity(0.5)).frame(width: 9, height: 9)
                }
                Text("播放时可以离开此页。音乐会继续，聊天顶部会显示正在播放的歌曲、进度和当前歌词。")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Button { onOpenChat?() } label: {
                    Label("去聊天，边听边聊", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15).background(ListenColors.heart, in: Capsule())
                }.buttonStyle(.plain).disabled(onOpenChat == nil)
                if let current = model.current {
                    HStack(spacing: 10) {
                        Text("正在播放").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text("\(current.title) · \(current.artist)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Button { model.togglePlayback() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(ListenColors.heart) }
                    }
                }
            }.padding(16).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
            loginCard
            }
        }
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("你们一起听过的歌").font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown)
                Spacer()
                Button { Task { await model.loadArchive() } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(ListenColors.heart) }
            }
            if let stats = model.listenStats {
                HStack(spacing: 10) {
                    statCard("\(stats.total)", title: "次播放", symbol: "play.circle")
                    statCard("\(stats.distinct)", title: "首歌曲", symbol: "music.note")
                    statCard(stats.buckets.max(by: { $0.value < $1.value })?.key ?? "—", title: "常听时段", symbol: "clock")
                }
                Text("常听歌曲").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown).padding(.top, 4)
                ForEach(Array(stats.top.prefix(12).enumerated()), id: \.element.id) { index, item in
                    songRow(item.song, index: index + 1) { Task { await model.play(item.song) } }
                }
            } else {
                ProgressView().tint(ListenColors.heart).frame(maxWidth: .infinity).padding(25)
            }
            Text("在场记录").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown).padding(.top, 5)
            if model.songNotes.isEmpty {
                emptyCard("还没有歌曲回忆", symbol: "heart.text.square")
            } else {
                ForEach(model.songNotes) { note in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            AsyncImage(url: URL(string: note.cover)) { phase in if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "music.note").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) } }.frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) { Text(note.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ListenColors.plumBrown); Text(note.artist).font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        if !note.passage.isEmpty { Text("“\(note.passage)”").font(.system(size: 13, design: .serif)).italic().foregroundStyle(ListenColors.heart) }
                        if !note.thought.isEmpty { Text(note.thought).font(.system(size: 13)).foregroundStyle(ListenColors.plumBrown) }
                        if !note.reply.isEmpty { Text(note.reply).font(.system(size: 13)).foregroundStyle(.secondary) }
                        Text(Date(timeIntervalSince1970: note.timestamp / 1000).formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func statCard(_ value: String, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(ListenColors.heart)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(ListenColors.plumBrown)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }

    private func pageHeading(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 35, weight: .regular, design: .serif)).italic().foregroundStyle(ListenColors.plumBrown); Text(caption).font(.system(size: 13)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }

    private func songRow(_ song: NeteaseSong, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index)).font(.system(size: 12, design: .monospaced)).foregroundStyle(ListenColors.heart.opacity(0.6)).frame(width: 25)
                AsyncImage(url: URL(string: song.cover)) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "music.note").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) }
                }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) { Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(ListenColors.plumBrown).lineLimit(1); Text(song.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                Image(systemName: song.id == model.current?.id && model.isPlaying ? "waveform" : "play.circle").font(.system(size: 20)).foregroundStyle(ListenColors.heart)
            }.padding(10).background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
            .contextMenu {
                Button("立即播放", systemImage: "play.fill", action: action)
                Button("添加到待播", systemImage: "text.badge.plus") { model.addSongToQueue(song) }
                Button(model.likedSongIDs.contains(song.id) ? "取消红心" : "添加红心", systemImage: "heart") { Task { await model.setLike(!model.likedSongIDs.contains(song.id), for: song) } }
                if model.queue.contains(where: { $0.id == song.id }) { Button("从待播移除", systemImage: "trash", role: .destructive) { model.removeFromQueue(song) } }
                if model.queue.contains(where: { $0.id == song.id }) {
                    Button("在队列中上移", systemImage: "arrow.up") { model.moveInQueue(song, by: -1) }
                    Button("在队列中下移", systemImage: "arrow.down") { model.moveInQueue(song, by: 1) }
                }
                if model.viewingPlaylist?.mine == true { Button("从此歌单删除", systemImage: "minus.circle", role: .destructive) { Task { await model.removeFromPlaylist(song) } } }
                if !model.playlists.isEmpty {
                    Menu("收藏到歌单", systemImage: "music.note.list") {
                        ForEach(model.playlists) { playlist in Button(playlist.name) { Task { await model.addSong(song, to: playlist) } } }
                    }
                }
                if model.queue.contains(where: { $0.id == song.id }) { Button("FM 不喜欢", systemImage: "hand.thumbsdown") { Task { await model.dislikeFM(song) } } }
            }
    }

    private func emptyCard(_ text: String, symbol: String) -> some View {
        VStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(ListenColors.heart.opacity(0.7)); Text(text).font(.system(size: 14)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(35).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
    }

    private func time(_ seconds: Double) -> String { guard seconds.isFinite else { return "0:00" }; return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))" }
}

private struct ListenSettingsView: View {
    @ObservedObject var model: TogetherListenModel
    @Environment(\.dismiss) private var dismiss
    @State private var roomID = "main"

    var body: some View {
        NavigationStack {
            Form {
                Section("房间") {
                    TextField("房间暗号", text: $roomID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("房间名称", text: $model.roomName)
                    TextField("房间副标题", text: $model.roomSub)
                    TextField("你的昵称", text: $model.userName)
                }
                Section("聊天模型") {
                    Label("使用 Lumi 当前选择的聊天模型", systemImage: "bubble.left.and.bubble.right")
                    Text("一起听的对话会继续使用主聊天记录、上下文摘要和长期记忆。当前歌曲、歌词和播放进度会作为本次听歌场景提供给模型。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("听歌分析模型（多模态）") {
                    TextField("兼容 OpenAI 的 HTTPS 服务地址", text: $model.analysisBaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(model.hasAnalysisKey ? "API Key 已保存（输入可替换）" : "API Key", text: $model.analysisAPIKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("支持音频输入的模型名称", text: $model.analysisModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        if model.isLoadingAnalysisModels { ProgressView() }
                        Button { Task { await model.fetchAnalysisModels() } } label: { Label("拉取模型列表", systemImage: "arrow.clockwise") }
                            .disabled(model.isLoadingAnalysisModels || model.analysisBaseURL.isEmpty)
                    }
                    if !model.availableAnalysisModels.isEmpty {
                        Menu("选择模型") {
                            ForEach(model.availableAnalysisModels, id: \.self) { item in
                                Button(item) { model.analysisModel = item }
                            }
                        }
                    }
                    Text(model.hasAnalysisKey ? "Key 已安全保存在服务端（\(model.analysisKeyHint)）。每首歌首次播放时，服务端会下载实际播放音流并完整分析一次；未填写的字段沿用服务端已有配置。" : "仅用于整首音频赏析与歌曲回忆。请填写支持音频输入的服务地址和 API Key；Key 仅保存到服务端。首次播放会分析实际音流并永久缓存，同一首歌不重复分析。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { Task { await model.saveSettings(roomID: roomID); dismiss() } } label: {
                        HStack { Spacer(); if model.isSavingSettings { ProgressView().tint(.white) } else { Text("保存设置") }; Spacer() }
                    }.listRowBackground(ListenColors.heart).foregroundStyle(.white).disabled(model.isSavingSettings)
                }
            }
            .scrollContentBackground(.hidden).background(ListenColors.background)
            .tint(ListenColors.heart)
            .navigationTitle("一起听设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.foregroundStyle(ListenColors.heart) } }
            .task { roomID = model.room; await model.loadSettings() }
        }
    }
}

private struct ListenSongDetailView: View {
    @ObservedObject var model: TogetherListenModel
    let song: NeteaseSong
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: song.cover)) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "music.note").foregroundStyle(ListenColors.heart).frame(maxWidth: .infinity, maxHeight: .infinity).background(ListenColors.background) }
                        }.frame(width: 78, height: 78).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) { Text(song.title).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(ListenColors.plumBrown); Text(song.artist).font(.system(size: 14)).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("听后赏析").font(.system(size: 18, weight: .semibold, design: .serif)); Spacer(); Button { Task { await model.generateSongAnalysis(song) } } label: { Label("生成", systemImage: "sparkles").font(.system(size: 12, weight: .medium)) }.foregroundStyle(ListenColors.heart) }
                        if !model.songAnalysis.isEmpty {
                            Text(model.songAnalysisSource == "audio" ? "听觉模型已分析实际播放的完整音频" : (model.songAnalysisSource == "lyrics" ? "这份内容仅依据歌词推断，模型没有听到音频" : "这份分析的音频来源未记录"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(model.songAnalysis.isEmpty ? "还没有听后赏析。" : model.songAnalysis).font(.system(size: 14)).foregroundStyle(model.songAnalysis.isEmpty ? .secondary : ListenColors.plumBrown).fixedSize(horizontal: false, vertical: true)
                        if !model.songImpression.isEmpty { Divider(); Text("你们的印象").font(.system(size: 13, weight: .semibold)).foregroundStyle(ListenColors.heart); Text(model.songImpression).font(.system(size: 13)).foregroundStyle(ListenColors.plumBrown).fixedSize(horizontal: false, vertical: true) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 11) {
                        HStack { Text("网易云评论").font(.system(size: 18, weight: .semibold, design: .serif)); Spacer(); Text("\(model.commentsTotal)").font(.system(size: 12)).foregroundStyle(.secondary) }
                        if model.songComments.isEmpty { Text("暂无评论").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 8) }
                        ForEach(model.songComments) { comment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(comment.user).font(.system(size: 12, weight: .semibold)).foregroundStyle(ListenColors.heart); Spacer(); Text(comment.time).font(.system(size: 10)).foregroundStyle(.tertiary) }
                                Text(comment.text).font(.system(size: 13)).foregroundStyle(ListenColors.plumBrown).fixedSize(horizontal: false, vertical: true)
                                if comment.likes > 0 { Label("\(comment.likes)", systemImage: "heart").font(.system(size: 10)).foregroundStyle(.secondary) }
                            }.padding(12).background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("在场记录").font(.system(size: 18, weight: .semibold, design: .serif))
                        ForEach(model.songNotes) { note in
                            VStack(alignment: .leading, spacing: 5) {
                                if !note.passage.isEmpty { Text("“\(note.passage)”").font(.system(size: 13, design: .serif)).italic().foregroundStyle(ListenColors.heart) }
                                if !note.thought.isEmpty { Text(note.thought).font(.system(size: 13)).foregroundStyle(ListenColors.plumBrown) }
                                if !note.reply.isEmpty { Text(note.reply).font(.system(size: 13)).foregroundStyle(.secondary) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }.padding(18)
            }
            .background(ListenColors.background.ignoresSafeArea())
            .navigationTitle("歌曲详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.foregroundStyle(ListenColors.heart) } }
            .task(id: song.id) { await model.loadSongDetails(song) }
        }
    }
}

private struct ListenChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(ListenColors.plumBrown)
            .padding(.horizontal, 11).padding(.vertical, 10).background(.white.opacity(configuration.isPressed ? 0.6 : 0.85), in: Capsule())
    }
}

private enum ListenColors {
    // Matches Duetto's default 藕荷 skin in listen.css.
    static let background = Color(red: 245.0 / 255.0, green: 238.0 / 255.0, blue: 240.0 / 255.0)
    static let heart = Color(red: 192.0 / 255.0, green: 140.0 / 255.0, blue: 155.0 / 255.0)
    static let pulse = Color(red: 180.0 / 255.0, green: 143.0 / 255.0, blue: 138.0 / 255.0)
    static let plumBrown = Color(red: 50.0 / 255.0, green: 42.0 / 255.0, blue: 45.0 / 255.0)
}

struct TogetherListenMiniPlayer: View {
    let onOpen: () -> Void
    @ObservedObject private var model = TogetherListenModel.shared
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            if let song = model.current {
                ZStack(alignment: .bottomTrailing) {
                    Button(action: onOpen) {
                        ZStack {
                            Circle().fill(.white).shadow(color: ListenColors.plumBrown.opacity(0.22), radius: 12, x: 0, y: 5)
                            if let url = URL(string: song.cover) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "music.note").font(.system(size: 22, weight: .medium)).foregroundStyle(ListenColors.heart)
                                }
                                .frame(width: 58, height: 58)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "music.note").font(.system(size: 22, weight: .medium)).foregroundStyle(ListenColors.heart)
                            }
                            Circle().stroke(.white.opacity(0.95), lineWidth: 2)
                        }
                        .frame(width: 62, height: 62)
                        .overlay {
                            if model.isPlaying {
                                Circle().stroke(ListenColors.heart.opacity(0.74), lineWidth: 2).padding(-4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回一起听：\(song.title)")

                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 25, height: 25)
                            .background(ListenColors.heart, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isPlaying ? "暂停播放" : "继续播放")
                    .offset(x: 2, y: 2)
                }
                .position(x: geometry.size.width - 48 + offset.width, y: geometry.size.height - 148 + offset.height)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            let proposedX = dragOrigin.width + value.translation.width
                            let proposedY = dragOrigin.height + value.translation.height
                            offset = CGSize(
                                width: min(0, max(48 - geometry.size.width, proposedX)),
                                height: min(100, max(328 - geometry.size.height, proposedY))
                            )
                        }
                        .onEnded { _ in dragOrigin = offset }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: model.current?.id)
    }
}

