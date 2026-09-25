import SwiftUI
import UIKit
import UserNotifications
import PhotosUI
import AVFoundation
import WebKit

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel
    @FocusState private var composerFocused: Bool
    @StateObject private var glassPresentation = GlassComparisonPresentation()
    @State private var showingSettings = false
    @State private var htmlMessage: ChatMessage?
    @State private var fullScreenHTMLMessage: ChatMessage?
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImageName: String?
    @AppStorage("lumi.ttsEnabled") private var ttsEnabled = false
    @AppStorage("lumi.ttsModel") private var ttsModel = "speech-2.8-hd"
    @AppStorage("lumi.ttsVoiceID") private var ttsVoiceID = "moss_audio_9b73ea77-9ada-11f1-b714-6a6575e57454"
    @AppStorage("lumi.ttsVoiceIDCustomMigration") private var customVoiceMigrated = false
    @AppStorage("lumi.ttsHost") private var ttsHost = "https://api.minimaxi.com"

    init(model: ChatViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ChatViewModel())
    }

    var body: some View {
        ZStack {
            LumiPalette.chatBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            messageBubble(message, showAvatar: index == 0 || model.messages[index - 1].role != message.role)
                                .id(message.id)
                        }
                        if model.isSending { thinkingBubble }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 92)
                    .padding(.bottom, 180)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.messages.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            GeometryReader { geometry in
                topBar
                    .padding(.top, max(geometry.safeAreaInsets.top, 54) + 8)
                    .frame(width: geometry.size.width, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .padding(.bottom, 10)
        }
        .task { await model.load() }
        .onAppear {
            if !customVoiceMigrated {
                ttsVoiceID = "moss_audio_9b73ea77-9ada-11f1-b714-6a6575e57454"
                customVoiceMigrated = true
            }
        }
        .sheet(isPresented: $glassPresentation.showing) {
            GlassComparisonView()
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $glassPresentation.showingThinkingDetails) {
            ThinkingDetailsView(text: glassPresentation.thinkingText) { height in
                glassPresentation.thinkingHeight = height
            }
                .presentationDetents([.height(glassPresentation.thinkingHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
        }
        .sheet(item: $htmlMessage) { message in
            HTMLMessageSheet(message: message) { fullScreenHTMLMessage = message; htmlMessage = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
        }
        .fullScreenCover(item: $fullScreenHTMLMessage) { message in
            HTMLMessageFullScreen(message: message)
        }
        .overlay(alignment: .top) {
            if let error = model.errorMessage {
                HStack(spacing: 10) {
                    Text(error).font(.system(size: 13))
                    Button("关闭") { model.errorMessage = nil }
                }
                .foregroundStyle(.black.opacity(0.78))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(red: 1.0, green: 0.90, blue: 0.93).opacity(0.94), in: Capsule())
                .padding(.top, 48)
                .padding(.horizontal, 18)
            }
        }
        .overlay {
            if let notice = model.memoryNotice {
                Text(notice)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.78))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.9608, green: 0.9255, blue: 0.9255), in: Capsule())
                    .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack {
            glassCircleButton("line.3.horizontal") { glassPresentation.showing = true }
            Spacer()
            glassCircleButton("phone")
            HStack(spacing: 0) {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 48, height: 42)
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 1, height: 24)
                Button { showingSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 48, height: 42)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.black.opacity(0.58))
            .background(.regularMaterial, in: Capsule())
            .background(Color(red: 0.965, green: 0.905, blue: 0.925).opacity(0.92), in: Capsule())
            .shadow(color: Color(red: 0.55, green: 0.38, blue: 0.45).opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedImageData, let image = UIImage(data: selectedImageData) {
                HStack {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("已添加图片").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button { self.selectedImageData = nil; selectedImageName = nil; photoItem = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            TextField("", text: $model.draft)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
                .focused($composerFocused)
                .onTapGesture { composerFocused = true }
                .submitLabel(.send)
                .onSubmit { Task { await sendDraft() } }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadSelectedImage(newItem) }
                }
                Spacer()
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                Button { Task { await sendDraft() } } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 36)
                        .background(Color(red: 0.28, green: 0.20, blue: 0.24).opacity(0.86), in: Circle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 30))
        .simultaneousGesture(TapGesture().onEnded { composerFocused = true })
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
        .background(Color(red: 0.965, green: 0.905, blue: 0.925).opacity(0.92), in: RoundedRectangle(cornerRadius: 30))
        .padding(.horizontal, 16)
        .shadow(color: Color(red: 0.45, green: 0.32, blue: 0.38).opacity(0.07), radius: 8, x: 0, y: 3)
    }

    private func glassCircleButton(_ systemName: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .background(Color(red: 0.965, green: 0.905, blue: 0.925).opacity(0.92), in: Circle())
                .shadow(color: Color(red: 0.55, green: 0.38, blue: 0.45).opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func messageBubble(_ message: ChatMessage, showAvatar: Bool) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            if let localName = message.localImageFileName,
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(localName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 210, maxHeight: 190).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack {
                if message.role == .assistant {
                    if showAvatar {
                        Button {
                            glassPresentation.thinkingText = thinkingText(for: message)
                            glassPresentation.showingThinkingDetails = true
                        } label: { avatar(for: .assistant) }
                        .buttonStyle(.plain)
                    } else { Color.clear.frame(width: 42, height: 42) }
                }
                if message.role == .user { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 7) {
                if message.contentType == "html" || isHTML(message.content) {
                    Button { htmlMessage = message } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                            Text("HTML 卡片 · 点击开始预览")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                } else if let audioFileName = message.audioFileName {
                    SpeechBubble(message: message, fileName: audioFileName)
                } else {
                    markdownText(visibleContent(message.content))
                        .foregroundStyle(.black)
                        .font(.system(size: 14, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, message.audioFileName == nil ? 10 : 3)
                .frame(width: message.audioFileName == nil ? nil : min(300, max(180, 150 + CGFloat(message.speechDuration ?? 2) * 8)), alignment: .leading)
                .background(message.role == .user ? LumiPalette.userBubble : .white)
                .clipShape(RoundedRectangle(cornerRadius: 21))
                if message.role == .assistant { Spacer(minLength: 48) }
                if message.role == .user {
                    if showAvatar { avatar(for: .user) }
                    else { Color.clear.frame(width: 42, height: 42) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder private func avatar(for role: ChatMessage.Role) -> some View {
        let name = role == .assistant ? "AssistantAvatar" : "UserAvatar"
        Group {
            if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: role == .assistant ? "sparkles" : "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(role == .assistant ? Color(red: 0.65, green: 0.38, blue: 0.48) : .black.opacity(0.55))
                    .background(role == .assistant ? Color(red: 1.0, green: 0.86, blue: 0.90) : Color.white.opacity(0.72))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.58), lineWidth: 0.8))
    }

    private func visibleContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[(?:左耳|右耳|脑后|面前|贴近|退开)\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func thinkingText(for message: ChatMessage) -> String {
        if let thinking = message.thinking, !thinking.isEmpty { return thinking }
        guard let range = message.content.range(of: #"(?is)<thinking>(.*?)</thinking>"#, options: .regularExpression) else { return "正在整理这条回复。" }
        return String(message.content[range])
            .replacingOccurrences(of: #"(?is)^<thinking>|</thinking>$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var thinkingBubble: some View {
        HStack {
            Button {
                glassPresentation.thinkingText = "正在整理你的话。"
                glassPresentation.showingThinkingDetails = true
            } label: {
                avatar(for: .assistant)
            }
            .buttonStyle(.plain)
            ThinkingDots()
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white)
            .clipShape(Capsule())
            Spacer()
        }
    }

    private func markdownText(_ content: String) -> Text {
        if let parsed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .full)) { return Text(parsed) }
        return Text(content)
    }

    private func isHTML(_ content: String) -> Bool {
        content.range(of: #"(?is)^```(?:html|xml)\b|(?:<!doctype\s+html\b|<(?:html|svg|main|section|article|div|table|button|form|canvas)\b)"#, options: .regularExpression) != nil
            || (content.range(of: #"(?i)<(?:html|head|body|title|meta|link|div|span|p|a|ul|ol|li|h[1-6]|table|thead|tbody|tr|td|th|svg|path|iframe|section|article|main|header|footer|nav|button|input|textarea|label|form|select|option|canvas|video|audio|pre|code|blockquote|br|hr|style|script|details|summary)\b[^>]*>"#, options: .regularExpression) != nil
                && content.range(of: #"(?i)</(?:html|head|body|title|div|span|p|a|ul|ol|li|h[1-6]|table|thead|tbody|tr|td|th|svg|path|iframe|section|article|main|header|footer|nav|button|textarea|label|form|select|option|canvas|video|audio|pre|code|blockquote|style|script|details|summary)\s*>"#, options: .regularExpression) != nil)
    }

    private func loadSelectedImage(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) else { return }
        let name = "image-\(UUID().uuidString).jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? jpeg.write(to: url, options: .atomic)
        selectedImageData = jpeg
        selectedImageName = name
    }

    private func sendDraft() async {
        let imageBase64 = selectedImageData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let ttsKey = LumiKeychain.read()
        let tts = ttsEnabled && !ttsKey.isEmpty ? TTSRequestSettings(apiKey: ttsKey, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true) : nil
        let catalogData = UserDefaults.standard.string(forKey: "lumi.emojiCatalogJSON")?.data(using: .utf8) ?? Data("[]".utf8)
        let entries = (try? JSONDecoder().decode([EmojiEntry].self, from: catalogData)) ?? []
        let catalog = Dictionary(grouping: entries, by: \.mood).mapValues { $0.map(\.face) }
        composerFocused = false
        await model.send(imageBase64: imageBase64, imageFileName: selectedImageName, tts: tts, emojiCatalog: catalog)
        selectedImageData = nil
        selectedImageName = nil
        photoItem = nil
    }
}

private enum LumiPalette {
    static let chatBackground = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let userBubble = Color(red: 0.9608, green: 0.9255, blue: 0.9255)
}

private struct ThinkingDots: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1 : 0.45)
                    .opacity(animate ? 1 : 0.38)
                    .animation(.easeInOut(duration: 0.48).repeatForever().delay(Double(index) * 0.16), value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

private struct SpeechBubble: View {
    let message: ChatMessage
    let fileName: String
    @StateObject private var player = SpatialSpeechPlayback()
    @State private var expandedTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: expandedTranscript ? 4 : 0) {
            HStack(spacing: 2) {
                Button(action: togglePlayback) {
                    HStack(spacing: 9) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 20)
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .medium))
                        Spacer(minLength: 2)
                        Text(durationLabel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "暂停语音" : "播放语音")
                Button { withAnimation(.easeInOut(duration: 0.2)) { expandedTranscript.toggle() } } label: {
                    Image(systemName: expandedTranscript ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expandedTranscript ? "收起转文字" : "展开转文字")
            }
            if expandedTranscript {
                Rectangle().fill(.black.opacity(0.08)).frame(height: 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("语音转文字").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text((message.speechScript ?? message.content).replacingOccurrences(of: #"\[(?:左耳|右耳|脑后|面前|贴近|退开)\]"#, with: "", options: .regularExpression))
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.black.opacity(0.82))
        .buttonStyle(.plain)
    }

    private var durationLabel: String {
        let seconds = max(0, Int(ceil(message.speechDuration ?? player.duration)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePlayback() {
        if player.isPlaying { player.pause(); return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        player.play(url: url, script: message.speechScript ?? message.content)
    }
}

@MainActor
private final class SpatialSpeechPlayback: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    private struct RouteSegment {
        let startTime: Double
        let endTime: Double
        let startAzimuth: Double
        let azimuthDelta: Double
        let startDistance: Double
        let distanceDelta: Double
    }
    private let engine = AVAudioEngine()
    private let source = AVAudioPlayerNode()
    private let space = AVAudioEnvironmentNode()
    private var connected = false
    private var movementTask: Task<Void, Never>?
    private var speechClock: [Double] = []
    private var route: [RouteSegment] = []
    private var initialPosition = (azimuth: 270.0, distance: 0.25)

    func play(url: URL, script: String) {
        guard FileManager.default.fileExists(atPath: url.path), let file = try? AVAudioFile(forReading: url) else { return }
        source.stop()
        movementTask?.cancel()
        movementTask = nil
        duration = Double(file.length) / file.processingFormat.sampleRate
        speechClock = makeSpeechClock(file: file)
        // Reading the whole file to build the spatial clock advances AVAudioFile to EOF.
        // Reset it before scheduling, or playback can start from the final fragment.
        file.framePosition = 0
        buildRoute(for: script)
        if !connected {
            engine.attach(source)
            engine.attach(space)
            space.renderingAlgorithm = .HRTFHQ
            space.distanceAttenuationParameters.referenceDistance = 0.25
            engine.connect(source, to: space, format: file.processingFormat)
            engine.connect(space, to: engine.mainMixerNode, format: nil)
            connected = true
        }
        do {
            if !engine.isRunning { try engine.start() }
            source.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.isPlaying = false }
            }
            apply(azimuth: initialPosition.azimuth, distance: initialPosition.distance)
            source.play()
            isPlaying = true
            startMovement()
        } catch { isPlaying = false }
    }

    func pause() {
        source.pause()
        movementTask?.cancel()
        movementTask = nil
        isPlaying = false
    }

    private func makeSpeechClock(file: AVAudioFile) -> [Double] {
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              let channels = buffer.floatChannelData,
              file.processingFormat.commonFormat == .pcmFormatFloat32 else { return [0, duration] }
        do { try file.read(into: buffer) } catch { return [0, duration] }
        let samples = Int(buffer.frameLength)
        let hop = max(1, Int(file.processingFormat.sampleRate / 100))
        var rms: [Double] = []
        rms.reserveCapacity((samples + hop - 1) / hop)
        var peak = 0.0
        for start in stride(from: 0, to: samples, by: hop) {
            let end = min(samples, start + hop)
            var sum = 0.0
            for frame in start..<end {
                for channel in 0..<Int(file.processingFormat.channelCount) {
                    let sample = Double(channels[channel][frame])
                    sum += sample * sample
                }
            }
            let value = sqrt(sum / Double(max(1, (end - start) * Int(file.processingFormat.channelCount))))
            rms.append(value)
            peak = max(peak, value)
        }
        guard peak > 0 else { return [0, duration] }
        var voiced = rms.map { $0 > peak * 0.05 }
        var index = 0
        while index < voiced.count {
            if voiced[index] { index += 1; continue }
            let start = index
            while index < voiced.count && !voiced[index] { index += 1 }
            if start > 0 && index < voiced.count && index - start < 40 {
                for gap in start..<index { voiced[gap] = true }
            }
        }
        var clock = Array(repeating: 0.0, count: voiced.count + 1)
        for sample in voiced.indices { clock[sample + 1] = clock[sample] + (voiced[sample] ? Double(hop) / file.processingFormat.sampleRate : 0) }
        return clock
    }

    private func speechTime(at wallTime: Double) -> Double {
        guard speechClock.count > 1 else { return max(0, wallTime) }
        let index = min(speechClock.count - 1, max(0, Int(wallTime * 100)))
        return speechClock[index]
    }

    private func buildRoute(for script: String) {
        let expression = try? NSRegularExpression(pattern: #"\[(左耳|右耳|脑后|面前|贴近|退开)\]"#)
        let fullRange = NSRange(script.startIndex..<script.endIndex, in: script)
        let matches = expression?.matches(in: script, range: fullRange) ?? []
        let totalCharacters = max(script.utf16.count, 1)
        let totalSpeechTime = speechClock.last ?? duration
        var cues: [(Double, String)] = []
        for match in matches {
            guard match.numberOfRanges > 1, let tagRange = Range(match.range(at: 1), in: script) else { continue }
            let estimatedWallTime = duration * Double(match.range.location) / Double(totalCharacters)
            cues.append((speechTime(at: estimatedWallTime), String(script[tagRange])))
        }
        if cues.isEmpty {
            let first = Bool.random() ? "左耳" : "右耳"
            let other = first == "左耳" ? "右耳" : "左耳"
            switch Int.random(in: 0..<4) {
            case 0: cues = [(0, first)]
            case 1: cues = totalSpeechTime > 6 ? [(0, first), (totalSpeechTime * 0.2, "脑后"), (totalSpeechTime * 0.6, other)] : [(0, first), (totalSpeechTime * 0.3, other)]
            case 2: cues = [(0, "脑后"), (totalSpeechTime * 0.35, first)]
            default: cues = [(0, "面前"), (totalSpeechTime * 0.35, first)]
            }
        }
        cues.sort { $0.0 < $1.0 }
        if let first = cues.first, first.0 < 0.3, let place = place(for: first.1) {
            initialPosition = place
            cues.removeFirst()
        } else {
            let ear = Bool.random() ? "左耳" : "右耳"
            initialPosition = place(for: ear) ?? (270, 0.25)
        }
        route.removeAll()
        for (time, cue) in cues { appendRoute(to: cue, at: time, totalSpeechTime: totalSpeechTime) }
    }

    private func place(for cue: String) -> (azimuth: Double, distance: Double)? {
        switch cue {
        case "左耳": return (90, 0.25)
        case "右耳": return (270, 0.25)
        case "脑后": return (180, 0.31)
        case "面前": return (0, 0.42)
        default: return nil
        }
    }

    private func position(at time: Double) -> (azimuth: Double, distance: Double) {
        guard let segment = route.last(where: { time >= $0.startTime }) else { return initialPosition }
        let progress = min(1, max(0, (time - segment.startTime) / max(0.001, segment.endTime - segment.startTime)))
        let eased = (1 - cos(.pi * progress)) / 2
        return (segment.startAzimuth + segment.azimuthDelta * eased, segment.startDistance + segment.distanceDelta * eased)
    }

    private func appendRoute(to cue: String, at time: Double, totalSpeechTime: Double) {
        let current = position(at: time)
        var targetAzimuth = current.azimuth
        var targetDistance = current.distance
        var azimuthDelta = 0.0
        var nominalDuration = 1.5
        if let target = place(for: cue) {
            targetAzimuth = target.azimuth
            targetDistance = target.distance
            azimuthDelta = (targetAzimuth - current.azimuth + 540).truncatingRemainder(dividingBy: 360) - 180
            if abs(abs(azimuthDelta) - 180) < 0.1 { azimuthDelta = current.azimuth < targetAzimuth ? 180 : -180 }
            nominalDuration = abs(azimuthDelta) > 1 ? abs(azimuthDelta) / 180 * 4.5 : 1.5
        } else if cue == "贴近" { targetDistance = 0.25 }
        else if cue == "退开" { targetDistance = 0.5 }
        else { return }
        let remaining = max(0, totalSpeechTime - time)
        let travelDuration = max(min(nominalDuration, remaining * 0.9), nominalDuration * 0.6)
        route.append(RouteSegment(startTime: time, endTime: time + travelDuration, startAzimuth: current.azimuth, azimuthDelta: azimuthDelta, startDistance: current.distance, distanceDelta: targetDistance - current.distance))
    }

    private func startMovement() {
        movementTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            while !Task.isCancelled && self.isPlaying {
                let elapsed = Date().timeIntervalSince(startedAt)
                let voicedTime = self.speechTime(at: elapsed)
                let position = self.position(at: voicedTime)
                self.apply(azimuth: position.azimuth, distance: position.distance)
                if elapsed >= self.duration { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func apply(azimuth: Double, distance: Double) {
        let radians = azimuth * .pi / 180
        source.position = AVAudio3DPoint(x: Float(sin(radians) * distance), y: 0, z: Float(-cos(radians) * distance))
    }
}

private struct HTMLMessageSheet: View {
    let message: ChatMessage
    let onExpand: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HTMLWebContent(source: message.content)
                .navigationTitle("HTML 内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button { onExpand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") } }
                }
        }
    }
}

private struct HTMLMessageFullScreen: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LumiPalette.chatBackground.ignoresSafeArea()
            HTMLWebContent(source: message.content)
                .ignoresSafeArea()
                .offset(x: dragOffset)
                .gesture(DragGesture(minimumDistance: 16).onChanged { value in
                    if value.startLocation.x < 72 && value.translation.width > 0 { dragOffset = value.translation.width }
                }.onEnded { value in
                    if value.startLocation.x < 72 && value.translation.width > 110 { dismiss() }
                    else { withAnimation(.spring(response: 0.28)) { dragOffset = 0 } }
                })
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.secondary) }
                .padding(.top, 18).padding(.trailing, 18)
        }
    }
}

private struct HTMLWebContent: UIViewRepresentable {
    let source: String
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.984, green: 0.949, blue: 0.957, alpha: 1)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let document = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?is)^```(?:html|xml)?\s*|\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let html = "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>body{font-family:-apple-system; padding:18px; color:#222;}</style>\(document)"
        uiView.loadHTMLString(html, baseURL: nil)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.proactiveNudgeEnabled") private var proactiveNudgeEnabled = false
    @AppStorage("lumi.proactiveNudgeInterval") private var proactiveNudgeInterval = 60
    @AppStorage("lumi.proactiveNudgeMessage") private var proactiveNudgeMessage = "有一段时间没聊了，结合我们的上下文自然地来找我说句话。"
    @State private var settingsLoaded = false
    @State private var syncStatus = "正在连接后端…"
    @State private var settingsSaveTask: Task<Void, Never>?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingMiniMaxSettings = false
    @State private var pushAPIToken = LumiKeychain.read(account: "push-api-token")
    private let api = LumiAPIClient()

    var body: some View {
        NavigationStack {
            List {
                Section("语音") {
                    Button { showingMiniMaxSettings = true } label: {
                        settingsCard(title: "MiniMax 语音", subtitle: "设置语音模型、音色和自动语音回复", icon: "waveform")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(destination: EmojiManagementView()) {
                        settingsCard(title: "颜文字管理", subtitle: "按心情整理，供沈屿自然选用", icon: "face.smiling")
                    }
                }

                Section {
                    SecureField("Zeabur 的 LUMI_PUSH_API_TOKEN", text: $pushAPIToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存口令并重试同步") {
                        LumiKeychain.write(pushAPIToken.trimmingCharacters(in: .whitespacesAndNewlines), account: "push-api-token")
                        Task { await loadProactiveSettings() }
                    }
                    Text("从 Zeabur 的 lumi-server 服务变量复制 LUMI_PUSH_API_TOKEN；口令保存在本机钥匙串，不会写入聊天记录。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("后端连接")
                }

                Section {
                    Toggle(isOn: $proactiveNudgeEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("保活")
                                .font(.system(size: 16, weight: .medium))
                            Text("长时间没有新消息时，允许沈屿主动发起一次对话")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color(red: 0.72, green: 0.35, blue: 0.49))

                    Stepper("静默 \(proactiveNudgeInterval) 分钟后触发", value: $proactiveNudgeInterval, in: 10...1440, step: 10)

                    TextField("主动联系内容", text: $proactiveNudgeMessage, axis: .vertical)
                        .lineLimit(2...5)

                    Text("每次触发会走正常聊天模型并产生一次模型调用；保活默认关闭。\(syncStatus)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("主动联系")
                }

                Section {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        HStack {
                            Label("消息通知", systemImage: "bell.badge")
                            Spacer()
                            Text(notificationStatusLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("通知")
                } footer: {
                    Text("允许通知后，后端会在设定的静默时间到达时生成一条主动消息，并通过 Apple 推送到手机。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.984, green: 0.949, blue: 0.957))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("返回") { dismiss() }
                }
            }
        }
        .task {
            await refreshNotificationStatus()
            await loadProactiveSettings()
        }
        .onChange(of: proactiveNudgeEnabled) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeInterval) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeMessage) { _, _ in saveProactiveSettings() }
        .background(Color(red: 0.984, green: 0.949, blue: 0.957))
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingMiniMaxSettings) {
            MiniMaxSettingsView()
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
        }
    }

    private func settingsCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(Color(red: 0.66, green: 0.35, blue: 0.47)).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "去系统设置开启"
        case .notDetermined: return "请求权限"
        @unknown default: return "请求权限"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted == false {
            await MainActor.run { notificationStatus = .denied }
        } else {
            await refreshNotificationStatus()
            if notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    private func loadProactiveSettings() async {
        do {
            let settings = try await api.fetchProactiveSettings()
            proactiveNudgeEnabled = settings.enabled
            proactiveNudgeInterval = settings.intervalMin
            proactiveNudgeMessage = settings.message
            syncStatus = "已同步到后端"
            let authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if authorization == .authorized || authorization == .provisional || authorization == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            syncStatus = syncErrorMessage(error)
        }
        settingsLoaded = true
    }

    private func saveProactiveSettings() {
        guard settingsLoaded else { return }
        settingsSaveTask?.cancel()
        syncStatus = "正在保存…"
        settingsSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                _ = try await api.updateProactiveSettings(ProactiveSettings(
                    enabled: proactiveNudgeEnabled,
                    threadId: "default",
                    message: proactiveNudgeMessage,
                    intervalMin: proactiveNudgeInterval,
                    intervalMax: proactiveNudgeInterval
                ))
                syncStatus = "已同步到后端"
            } catch {
                syncStatus = syncErrorMessage(error)
            }
            settingsSaveTask = nil
        }
    }

    private func syncErrorMessage(_ error: Error) -> String {
        let details = error.localizedDescription
        if details.contains("401") || details.localizedCaseInsensitiveContains("unauthorized") {
            return "同步被拒绝：请检查上方的 LUMI_PUSH_API_TOKEN 是否与 Zeabur 一致"
        }
        if details.contains("404") || details.contains("not_found") {
            return "线上后端版本过旧，缺少保活接口；需要部署 lumi-server 新版本"
        }
        return "同步失败：\(details)"
    }
}

private struct MiniMaxSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.ttsEnabled") private var ttsEnabled = false
    @AppStorage("lumi.ttsModel") private var model = "speech-2.8-hd"
    @AppStorage("lumi.ttsVoiceID") private var voiceID = "moss_audio_9b73ea77-9ada-11f1-b714-6a6575e57454"
    @AppStorage("lumi.ttsHost") private var ttsHost = "https://api.minimaxi.com"
    @State private var apiKey = LumiKeychain.read()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("允许 AI 自主选择是否发语音", isOn: $ttsEnabled).tint(Color(red: 0.72, green: 0.35, blue: 0.49))
                    SecureField("MiniMax API Key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("MiniMax 区域", selection: $ttsHost) {
                        Text("中国大陆").tag("https://api.minimaxi.com")
                        Text("国际版").tag("https://api.minimax.io")
                    }
                    Picker("语音模型", selection: $model) {
                        ForEach(["speech-2.8-hd", "speech-2.8-turbo", "speech-2.6-hd", "speech-2.6-turbo"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Voice ID", text: $voiceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("直接填写你购买的音色 ID；当前已填入你给的 moss_audio ID，不会拉取音色列表。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                } footer: {
                    Text("Key 保存在 iPhone 钥匙串中。打开许可后，AI 自己决定是否值得生成语音；没选择发语音时不会调用 TTS。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LumiPalette.chatBackground)
            .navigationTitle("MiniMax 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { LumiKeychain.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } }
            }
            .tint(Color(red: 0.66, green: 0.35, blue: 0.47))
        }
    }
}

private struct EmojiManagementView: View {
    @AppStorage("lumi.emojiCatalogJSON") private var catalogJSON = "{}"
    @State private var entries: [EmojiEntry] = []
    @State private var showingAdd = false

    var body: some View {
        List {
            if entries.isEmpty {
                Text("还没有颜文字。点右上角 +，添加颜文字和心情标签。")
                    .font(.system(size: 14)).foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.face).font(.system(size: 19))
                        Text(entry.mood).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in entries.remove(atOffsets: offsets); persist() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LumiPalette.chatBackground)
        .navigationTitle("颜文字管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        }
        .tint(Color(red: 0.66, green: 0.35, blue: 0.47))
        .preferredColorScheme(.light)
        .onAppear { load() }
        .sheet(isPresented: $showingAdd) {
            AddEmojiSheet { entry in entries.append(entry); persist() }
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
        }
    }

    private func load() {
        guard let data = catalogJSON.data(using: .utf8), let decoded = try? JSONDecoder().decode([EmojiEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries), let value = String(data: data, encoding: .utf8) { catalogJSON = value }
    }
}

private struct EmojiEntry: Codable, Identifiable {
    var id = UUID()
    var face: String
    var mood: String
}

private struct AddEmojiSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var face = ""
    @State private var mood = ""
    let onSave: (EmojiEntry) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("颜文字", text: $face)
                TextField("心情标签（如：开心、害羞、难过）", text: $mood)
            }
            .scrollContentBackground(.hidden)
            .background(LumiPalette.chatBackground)
            .navigationTitle("添加颜文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        let value = face.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tag = mood.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !tag.isEmpty else { return }
                        onSave(EmojiEntry(face: value, mood: tag)); dismiss()
                    }.disabled(face.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(Color(red: 0.66, green: 0.35, blue: 0.47))
            .preferredColorScheme(.light)
        }
    }
}

private struct LegacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.proactiveNudgeEnabled") private var proactiveNudgeEnabled = false
    @AppStorage("lumi.proactiveNudgeInterval") private var proactiveNudgeInterval = 60
    @AppStorage("lumi.proactiveNudgeMessage") private var proactiveNudgeMessage = "有一段时间没聊了，结合我们的上下文自然地来找我说句话。"
    @State private var settingsLoaded = false
    @State private var syncStatus = "正在连接后端…"
    @State private var settingsSaveTask: Task<Void, Never>?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    private let api = LumiAPIClient()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $proactiveNudgeEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("保活")
                                .font(.system(size: 16, weight: .medium))
                            Text("长时间没有新消息时，允许沈屿主动发起一次对话")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color(red: 0.72, green: 0.35, blue: 0.49))

                    Stepper("静默 \(proactiveNudgeInterval) 分钟后触发", value: $proactiveNudgeInterval, in: 10...1440, step: 10)

                    TextField("主动联系内容", text: $proactiveNudgeMessage, axis: .vertical)
                        .lineLimit(2...5)

                    Text("每次触发会走正常聊天模型并产生一次模型调用；保活默认关闭。\(syncStatus)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("主动联系")
                }

                Section {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        HStack {
                            Label("消息通知", systemImage: "bell.badge")
                            Spacer()
                            Text(notificationStatusLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("通知")
                } footer: {
                    Text("允许通知后会注册这台设备；锁屏推送还需要在后端安全配置 Apple APNs 密钥。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.984, green: 0.949, blue: 0.957))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("返回") { dismiss() }
                }
            }
        }
        .task {
            await refreshNotificationStatus()
            await loadProactiveSettings()
        }
        .onChange(of: proactiveNudgeEnabled) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeInterval) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeMessage) { _, _ in saveProactiveSettings() }
        .background(Color(red: 0.984, green: 0.949, blue: 0.957))
        .preferredColorScheme(.light)
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "去系统设置开启"
        case .notDetermined: return "请求权限"
        @unknown default: return "请求权限"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted == false {
            await MainActor.run { notificationStatus = .denied }
        } else {
            await refreshNotificationStatus()
            if notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    private func loadProactiveSettings() async {
        do {
            let settings = try await api.fetchProactiveSettings()
            proactiveNudgeEnabled = settings.enabled
            proactiveNudgeInterval = settings.intervalMin
            proactiveNudgeMessage = settings.message
            syncStatus = "已同步到后端"
        } catch {
            syncStatus = "后端连接失败，设置尚未同步"
        }
        settingsLoaded = true
    }

    private func saveProactiveSettings() {
        guard settingsLoaded else { return }
        settingsSaveTask?.cancel()
        syncStatus = "正在保存…"
        settingsSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                _ = try await api.updateProactiveSettings(ProactiveSettings(
                    enabled: proactiveNudgeEnabled,
                    threadId: "default",
                    message: proactiveNudgeMessage,
                    intervalMin: proactiveNudgeInterval,
                    intervalMax: proactiveNudgeInterval
                ))
                syncStatus = "已同步到后端"
            } catch {
                syncStatus = "后端连接失败，设置尚未同步"
            }
            settingsSaveTask = nil
        }
    }
}

@MainActor
private final class GlassComparisonPresentation: ObservableObject {
    @Published var showing = false
    @Published var showingThinkingDetails = false
    @Published var thinkingText = "正在整理你的话。"
    @Published var thinkingHeight: CGFloat = 260
}

private struct ThinkingDetailsView: View {
    let text: String
    let onHeightChange: (CGFloat) -> Void
    private let horizontalPadding: CGFloat = 24
    private let verticalPadding: CGFloat = 26

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
            Text("Thought process")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(6)
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ThinkingTextHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumiPalette.chatBackground)
        .onPreferenceChange(ThinkingTextHeightKey.self) { textHeight in
            let desired = textHeight + 19 + 24 + verticalPadding * 2
            let screenLimit = UIScreen.main.bounds.height * 0.88
            onHeightChange(min(max(desired, 220), screenLimit))
        }
    }
}

private struct ThinkingTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GlassComparisonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("材质对比")
                    .font(.system(size: 24, weight: .bold))
                Text("原生 Liquid Glass 会根据背景实时折射、提亮边缘并保持内容层级，不是单纯降低透明度。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                glassSample(title: "毛玻璃", detail: "Ultra Thin Material", kind: .frosted)
                glassSample(title: "磨砂玻璃", detail: "更厚、更不透明", kind: .matte)
                glassSample(title: "Liquid Glass", detail: "iOS 原生材质", kind: .liquid)
            }
            .padding(22)
        }
        .background(Color(red: 0.984, green: 0.949, blue: 0.957).ignoresSafeArea())
    }

    private enum Kind { case frosted, matte, liquid }

    @ViewBuilder
    private func glassSample(title: String, detail: String, kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "plus")
                Text("Lumi")
                Spacer()
                Image(systemName: "mic")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.black.opacity(0.7))
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background {
                switch kind {
                case .frosted:
                    RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                case .matte:
                    RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.30)))
                case .liquid:
                    RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.16)))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.85), lineWidth: 0.8))
        }
    }
}
