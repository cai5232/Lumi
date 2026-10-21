import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
private final class SleepRadioPlayback: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    private var player: AVAudioPlayer?

    func load(_ data: Data, at position: Double = 0, fraction: Double? = nil) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let next = try AVAudioPlayer(data: SleepRadioMP3.playableData(data))
        next.prepareToPlay()
        next.currentTime = min(max(0, fraction.map { $0 * next.duration } ?? position), max(0, next.duration - 0.05))
        player = next
        duration = next.duration
        self.position = next.currentTime
        next.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func seek(_ value: Double) {
        guard let player else { return }
        player.pause()
        player.currentTime = min(max(0, value), max(0, player.duration - 0.05))
        position = player.currentTime
    }

    func skip(_ seconds: Double) { seek(position + seconds) }
    func tick() {
        guard let player else { return }
        position = player.currentTime
        isPlaying = player.isPlaying
        duration = player.duration
    }
}

@MainActor
private final class SleepRadioAmbience: ObservableObject {
    private var rain: AVAudioPlayer?

    func setActive(_ active: Bool) throws {
        guard active else { rain?.pause(); return }
        if rain == nil {
            guard let asset = NSDataAsset(name: "SleepRadioRain") else {
                throw LumiAPIError.server("雨声素材暂时无法加载。")
            }
            let player = try AVAudioPlayer(data: asset.data)
            player.numberOfLoops = -1
            player.prepareToPlay()
            rain = player
        }
        guard let rain, !rain.isPlaying else { return }
        rain.volume = 0
        guard rain.play() else { throw LumiAPIError.server("雨声暂时无法播放，请再试一次。") }
        rain.setVolume(0.22, fadeDuration: 0.7)
    }
}

struct SleepRadioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatModel: ChatViewModel
    @StateObject private var playback = SleepRadioPlayback()
    @StateObject private var ambience = SleepRadioAmbience()
    @AppStorage("lumi.sleepRadio.rainEnabled") private var rainEnabled = true
    @State private var followingResumeTask: Task<Void, Never>?
    @State private var api = LumiAPIClient()
    @State private var subscription = SleepRadioSubscription(enabled: false, time: "21:30", timeZone: TimeZone.current.identifier, minChars: 4000)
    @State private var episodes: [SleepRadioEpisode] = []
    @State private var current: SleepRadioEpisode?
    @State private var loadedEpisodeID: String?
    @State private var followingPlayback = true
    @State private var showingGenerationPrompt = false
    @State private var generationTopic = ""
    @State private var showingSubscription = false
    @State private var showingHistory = false
    @State private var showingFavorites = false
    @State private var selectedTime = Date()
    @State private var selectedMinChars = 4000.0
    @State private var busy = false
    @State private var error: String?
    @State private var lastSavedPosition = 0.0
    @AppStorage("lumi.ttsProvider") private var ttsProvider = "minimax"
    @AppStorage("lumi.ttsHost") private var ttsHost = "https://api.minimaxi.com"
    @AppStorage("lumi.ttsModel") private var miniMaxModel = "speech-2.8-hd"
    @AppStorage("lumi.ttsVoiceID") private var miniMaxVoiceID = "moss_audio_9b73ea77-9ada-11f1-b714-6a6575e57454"
    @AppStorage("lumi.elevenLabsModel") private var elevenModel = "eleven_v4_turbo"
    @AppStorage("lumi.elevenLabsVoiceID") private var elevenVoiceID = ""


    // Match Lumi's existing blush chat background and soft pink icon tint.
    private let accent = Color(red: 0.955, green: 0.745, blue: 0.800)
    private let pageBackground = Color(red: 0.984, green: 0.949, blue: 0.957)

    var body: some View {
        NavigationStack {
            lyrics
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(pageBackground)
                .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(episodeNavigationTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("返回")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        prepareSubscription()
                        showingSubscription = true
                    } label: {
                        Image(systemName: subscription.enabled ? "bell.badge.fill" : "bell.badge")
                    }
                    .accessibilityLabel("订阅时间和台本字数")
                    Button { showingGenerationPrompt = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(busy)
                    .accessibilityLabel("生成新一期电台")
                }
                if #available(iOS 26.0, *) {
                    ToolbarItemGroup(placement: .bottomBar) {
                        historyToolbarButton
                        rainToolbarButton
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        playbackToolbarButton
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        historyToolbarButton
                        rainToolbarButton
                        Spacer()
                        playbackToolbarButton
                    }
                }
            }
            .toolbarBackground(.hidden, for: .bottomBar)
        }
        .tint(accent)
        .task { await refresh() }
        .onChange(of: playback.isPlaying) { _, _ in updateAmbience() }
        .onChange(of: rainEnabled) { _, _ in updateAmbience() }
        .onDisappear {
            followingResumeTask?.cancel()
            try? ambience.setActive(false)
        }
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
            playback.tick()
            if let current, loadedEpisodeID == current.id, abs(playback.position - lastSavedPosition) >= 10 {
                lastSavedPosition = playback.position
                Task { try? await api.updateSleepRadioEpisode(current, position: playback.position) }
            }
        }
        .sheet(isPresented: $showingSubscription) { subscriptionSheet }
        .sheet(isPresented: $showingHistory) { episodeList(title: "历史电台", items: episodes) }
        .sheet(isPresented: $showingFavorites) { episodeList(title: "收藏", items: episodes.filter(\.favorite)) }
        .alert("今晚想听什么？", isPresented: $showingGenerationPrompt) {
            TextField("比如：海边故事、冥想、聊聊今天", text: $generationTopic)
            Button("开始生成") {
                let topic = generationTopic.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await generate(topic: topic) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("写下想听的内容或方向，留空就让沈屿来选。")
        }
        .alert("睡前电台", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var lyrics: some View {
        Group {
            if let current {
                let transcript = SleepRadioTranscript(script: current.script, subtitles: current.subtitles)
                let position = loadedEpisodeID == current.id ? playback.position : current.position
                let duration = loadedEpisodeID == current.id ? playback.duration : (current.duration ?? 0)
                let active = transcript.activeLine(at: position, duration: duration)
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 18) {
                                ForEach(Array(transcript.lines.enumerated()), id: \.offset) { index, line in
                                    Button {
                                        Task { await playFromLine(index, transcript: transcript, episode: current) }
                                    } label: {
                                        Text(line.text)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                            .lineSpacing(6)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(index == active ? Color(red: 0.67, green: 0.35, blue: 0.44) : Color.primary.opacity(0.40))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(busy)
                                    .accessibilityLabel("从这一句播放：\(line.text)")
                                    .id(index)
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical, max(40, geometry.size.height / 2 - 50))
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                            followingResumeTask?.cancel()
                            followingPlayback = false
                        }.onEnded { _ in
                            followingResumeTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(4))
                                guard !Task.isCancelled else { return }
                                followingPlayback = true
                            }
                        })
                        .task(id: current.id) {
                            followingPlayback = true
                            proxy.scrollTo(active, anchor: .center)
                        }
                        .onChange(of: followingPlayback) { _, follow in
                            guard follow else { return }
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(active, anchor: .center)
                            }
                        }
                        .onChange(of: active) { _, value in
                            guard followingPlayback else { return }
                            withAnimation(.easeInOut(duration: 0.45)) {
                                proxy.scrollTo(value, anchor: .center)
                            }
                        }

                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(accent)
                    Text(busy ? "正在准备电台" : "今晚还没有电台")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(busy ? "写好台本后会自动生成语音。" : "订阅一个时间，让 Lumi 为你准备睡前声音。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !busy {
                        Button("现在生成") { showingGenerationPrompt = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    } else {
                        ProgressView().tint(accent)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private var historyToolbarButton: some View {
        Button { showingHistory = true } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("历史电台")
    }

    private var rainToolbarButton: some View {
        Button { rainEnabled.toggle() } label: {
            Image(systemName: rainEnabled ? "cloud.rain.fill" : "cloud.rain")
                .foregroundStyle(rainEnabled ? accent : Color.secondary)
        }
        .accessibilityLabel(rainEnabled ? "关闭雨声背景音" : "开启雨声背景音")
        .accessibilityValue(rainEnabled ? "已开启" : "已关闭")
    }

    private var playbackToolbarButton: some View {
        Button {
            if let current {
                if loadedEpisodeID == current.id {
                    playback.toggle()
                    if playback.isPlaying { followingPlayback = true }
                }
                else { Task { await play(current) } }
            } else { showingGenerationPrompt = true }
        } label: {
            if busy {
                ProgressView()
            } else {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .disabled(busy)
        .accessibilityLabel(playback.isPlaying ? "暂停" : "播放")
    }

    private var subscriptionSheet: some View {
        NavigationStack {
            Form {
                Section("订阅时间") {
                    Toggle("每天生成并准备好电台", isOn: $subscription.enabled)
                    DatePicker("时间", selection: $selectedTime, displayedComponents: .hourAndMinute)
                }
                Section("台本") {
                    LabeledContent("最低字数", value: "\(Int(selectedMinChars)) 字")
                    Slider(value: $selectedMinChars, in: 4000...10000, step: 500)
                    Text("使用聊天模型和近期聊天上下文写作，并为台本标注语气。不会朗读语文课本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("语音") {
                    Label("使用 Lumi 设置里的全局语音服务", systemImage: "waveform")
                    Text("订阅开启时，语音服务配置会通过 HTTPS 发送到 Lumi 服务端，用于到点后台合成。关闭订阅后会清除服务端保存的配置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let lastError = subscription.lastError {
                    Section("最近一次生成") {
                        Text(lastError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("订阅电台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingSubscription = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "保存中…" : "保存") { Task { await saveSubscription() } }
                        .disabled(busy)
                }
            }
        }
        .tint(accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func episodeList(title: String, items: [SleepRadioEpisode]) -> some View {
        NavigationStack {
            List(items) { episode in
                Button {
                    showingHistory = false
                    showingFavorites = false
                    Task { await play(episode) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 20))
                            .foregroundStyle(accent)
                            .frame(width: 44, height: 44)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(episode.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack {
                                Text(episode.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text(timeText(episode.position))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: episode.duration.map { $0 > 0 ? min(1, episode.position / $0) : 0 } ?? 0)
                                .tint(accent)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(title, systemImage: "moon.zzz", description: Text("准备好的电台会出现在这里。"))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showingHistory = false
                        showingFavorites = false
                    }
                }
            }
        }
        .tint(accent)
        .presentationDetents([.medium, .large])
    }

    private func updateAmbience() {
        do { try ambience.setActive(rainEnabled && playback.isPlaying) }
        catch { self.error = error.localizedDescription }
    }

    private func prepareSubscription() {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: subscription.time) { selectedTime = date }
        selectedMinChars = Double(subscription.minChars)
    }

    private func globalTTS() -> TTSRequestSettings? {
        let provider = ttsProvider == "elevenlabs" ? "elevenlabs" : "minimax"
        let key = LumiKeychain.read(account: provider == "elevenlabs" ? "elevenlabs-api-key" : "minimax-api-key")
        let voice = provider == "elevenlabs" ? elevenVoiceID : miniMaxVoiceID
        guard !key.isEmpty, !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return TTSRequestSettings(provider: provider, apiKey: key, model: provider == "elevenlabs" ? elevenModel : miniMaxModel, voiceID: voice, baseURL: provider == "elevenlabs" ? "https://api.elevenlabs.io" : ttsHost, enabled: true)
    }

    private func saveSubscription() async {
        busy = true; defer { busy = false }
        let tts = subscription.enabled ? globalTTS() : nil
        if subscription.enabled && tts == nil { error = "请先到全局语音设置配置服务、API Key 和 Voice ID。"; return }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        subscription.time = formatter.string(from: selectedTime)
        subscription.timeZone = TimeZone.current.identifier
        subscription.minChars = Int(selectedMinChars)
        do {
            subscription = try await api.saveSleepRadioSubscription(subscription, tts: tts)
            showingSubscription = false
        } catch { self.error = error.localizedDescription }
    }

    private func refresh() async {
        do {
            await chatModel.load(waitForRemote: true)
            async let fetchedSettings = api.fetchSleepRadioSubscription()
            async let fetchedEpisodes = api.fetchSleepRadioEpisodes()
            subscription = try await fetchedSettings
            episodes = try await fetchedEpisodes
            if let first = episodes.first, current == nil { current = first }
        } catch { self.error = error.localizedDescription }
    }

    private func generate(topic: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let tts = globalTTS() else { error = "请先到全局语音设置配置服务、API Key 和 Voice ID。"; return }
            let route = try ChatViewModel.currentModelRoute()
            let episode = try await api.generateSleepRadioEpisode(tts: tts, topic: topic, provider: route.provider, model: route.model, customProvider: route.customProvider)
            episodes.insert(episode, at: 0); current = episode
            let audio = try await api.fetchSleepRadioAudio(episode)
            try playback.load(audio)
            loadedEpisodeID = episode.id
            lastSavedPosition = 0
        } catch { self.error = error.localizedDescription }
    }

    private func play(_ episode: SleepRadioEpisode) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let audio = try await api.fetchSleepRadioAudio(episode)
            current = episode
            try playback.load(audio, at: episode.position)
            loadedEpisodeID = episode.id
            lastSavedPosition = episode.position
        } catch { self.error = error.localizedDescription }
    }

    private func playFromLine(_ index: Int, transcript: SleepRadioTranscript, episode: SleepRadioEpisode) async {
        guard !busy, transcript.lines.indices.contains(index) else { return }
        let line = transcript.lines[index]
        if loadedEpisodeID == episode.id {
            playback.seek(transcript.startTime(for: index, duration: playback.duration))
            playback.resume()
            followingPlayback = true
            return
        }
        busy = true; defer { busy = false }
        do {
            let audio = try await api.fetchSleepRadioAudio(episode)
            try playback.load(audio, at: transcript.hasTimestamps ? line.start : 0, fraction: transcript.hasTimestamps ? nil : line.start)
            current = episode
            loadedEpisodeID = episode.id
            lastSavedPosition = playback.position
            followingPlayback = true
        } catch { self.error = error.localizedDescription }
    }

    private func toggleFavorite() async {
        guard let current else { return }
        let changed = SleepRadioEpisode(id: current.id, title: current.title, createdAt: current.createdAt, script: current.script, audioURL: current.audioURL, duration: current.duration, position: current.position, favorite: !current.favorite, subtitles: current.subtitles)
        do {
            try await api.updateSleepRadioEpisode(changed, favorite: changed.favorite)
            self.current = changed
            if let index = episodes.firstIndex(where: { $0.id == changed.id }) { episodes[index] = changed }
        } catch { self.error = error.localizedDescription }
    }

    private var episodeNavigationTitle: String {
        guard let current else { return "晚风电台" }
        let date = current.createdAt.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
        return "晚风电台 · \(date)"
    }

    private func timeText(_ value: Double) -> String { String(format: "%d:%02d", max(0, Int(value)) / 60, max(0, Int(value)) % 60) }
}

// Older episodes have no speech timestamps. Weight sentences by spoken length
// and pauses rather than assigning an equal duration to every displayed line.
private struct SleepRadioTranscript {
    struct Line {
        let text: String
        let start: Double
        let end: Double
    }

    let lines: [Line]
    let hasTimestamps: Bool

    init(script: String, subtitles: [SleepRadioSubtitle]? = nil) {
        let timed = (subtitles ?? []).filter {
            !$0.text.isEmpty && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start
        }.sorted { $0.start < $1.start }
        if !timed.isEmpty {
            hasTimestamps = true
            lines = timed.map { Line(text: $0.text, start: $0.start, end: $0.end) }
            return
        }
        hasTimestamps = false
        let cleaned = script.replacingOccurrences(of: #"\[[^\]\n]{1,40}\]"#, with: "", options: .regularExpression)
        var sentences: [String] = []
        var buffer = ""
        func flush() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
            sentences.append(text)
        }
        for character in cleaned {
            if character.isNewline {
                flush()
            } else {
                buffer.append(character)
                if "。！？!?；;".contains(character) || (buffer.count >= 32 && "，,、".contains(character)) {
                    flush()
                }
            }
        }
        flush()
        let weights = sentences.map { text in
            text.reduce(0.0) { weight, character in
                weight + (character.isLetter || character.isNumber ? 1 : "，,、。！？!?；;…".contains(character) ? 0.55 : 0)
            } + 1.5
        }
        let total = max(1, weights.reduce(0, +))
        var cursor = 0.0
        lines = zip(sentences, weights).map { text, weight in
            let start = cursor / total
            cursor += weight
            return Line(text: text, start: start, end: cursor / total)
        }
    }

    func activeLine(at position: Double, duration: Double) -> Int {
        guard !lines.isEmpty, duration > 0 else { return 0 }
        if hasTimestamps {
            return lines.lastIndex(where: { $0.start <= position }) ?? 0
        }
        let progress = min(1, max(0, position / duration))
        return lines.firstIndex(where: { progress < $0.end }) ?? lines.count - 1
    }

    func startTime(for index: Int, duration: Double) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        return hasTimestamps ? lines[index].start : lines[index].start * max(0, duration)
    }
}

// Independent TTS MP3 files each carry their own ID3/Xing/Info headers. Leaving
// them concatenated makes AVAudioPlayer use the first file's duration and seek
// table for the whole episode. Rebuild a single frame stream before loading it.
private enum SleepRadioMP3 {
    static func playableData(_ data: Data) -> Data {
        var frames = Data()
        frames.reserveCapacity(data.count)
        var offset = 0
        var metadataHeaders = 0
        var id3Headers = 0
        func matches(_ text: String, at index: Int) -> Bool {
            let bytes = Array(text.utf8)
            guard index >= 0, index + bytes.count <= data.count else { return false }
            return bytes.indices.allSatisfy { data[index + $0] == bytes[$0] }
        }
        while offset + 4 <= data.count {
            if matches("ID3", at: offset), offset + 10 <= data.count {
                let size = (Int(data[offset + 6] & 127) << 21)
                    | (Int(data[offset + 7] & 127) << 14)
                    | (Int(data[offset + 8] & 127) << 7)
                    | Int(data[offset + 9] & 127)
                id3Headers += 1
                offset += 10 + size + (data[offset + 5] & 16 != 0 ? 10 : 0)
                continue
            }
            let first = data[offset], second = data[offset + 1]
            let third = data[offset + 2], fourth = data[offset + 3]
            let version = (second >> 3) & 3
            let bitrateIndex = Int(third >> 4)
            let rateIndex = Int((third >> 2) & 3)
            guard first == 255, second & 224 == 224, version != 1,
                  (second >> 1) & 3 == 1, bitrateIndex > 0, bitrateIndex < 15, rateIndex < 3 else {
                offset += 1
                continue
            }
            let rates = version == 3
                ? [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
                : [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
            let sampleRate = [44100, 48000, 32000][rateIndex] / (version == 3 ? 1 : version == 2 ? 2 : 4)
            let size = (version == 3 ? 144 : 72) * rates[bitrateIndex] * 1000 / sampleRate + Int((third >> 1) & 1)
            guard offset + size <= data.count else { break }
            let mono = fourth >> 6 == 3
            let sideInfo = version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17)
            let xing = offset + 4 + (second & 1 == 0 ? 2 : 0) + sideInfo
            let metadata = matches("Xing", at: xing) || matches("Info", at: xing) || matches("VBRI", at: offset + 36)
            if metadata { metadataHeaders += 1 }
            else { frames.append(data[offset..<(offset + size)]) }
            offset += size
        }
        // Leave ordinary standalone files and unknown formats untouched.
        return !frames.isEmpty && (metadataHeaders > 1 || id3Headers > 1) ? frames : data
    }
}
