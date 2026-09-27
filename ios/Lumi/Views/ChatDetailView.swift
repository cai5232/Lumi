import SwiftUI
import UIKit
import UserNotifications
import PhotosUI
import AVFoundation
import Speech
import WebKit

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel
    @State private var keyboardVisible = false
    @StateObject private var glassPresentation = GlassComparisonPresentation()
    @State private var showingSettings = false
    @State private var htmlMessage: ChatMessage?
    @State private var fullScreenHTMLMessage: ChatMessage?
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImageName: String?
    @State private var showingCallDemo = false
    @State private var showingSubscriptionUsage = false
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
                    .animation(.easeOut(duration: 0.24), value: model.messages.count)
                    .padding(.horizontal, 16)
                    .padding(.top, 92)
                    .padding(.bottom, keyboardVisible ? 24 : 180)
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom-anchor")
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard keyboardVisible else { return }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    keyboardVisible = true
                    guard model.messages.last != nil else { return }
                    Task { @MainActor in
                        await Task.yield()
                        try? await Task.sleep(for: .milliseconds(280))
                        guard keyboardVisible else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("chat-bottom-anchor", anchor: .bottom) }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    keyboardVisible = true
                    guard !model.messages.isEmpty else { return }
                    Task { @MainActor in
                        await Task.yield()
                        try? await Task.sleep(for: .milliseconds(120))
                        guard keyboardVisible else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardVisible = false
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                    let isShowing = endFrame.map { $0.minY < UIScreen.main.bounds.height } ?? true
                    keyboardVisible = isShowing
                    guard isShowing, model.messages.last != nil else { return }
                    Task { @MainActor in
                        await Task.yield()
                        try? await Task.sleep(for: .milliseconds(320))
                        guard keyboardVisible else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("chat-bottom-anchor", anchor: .bottom) }
                    }
                }
                .onChange(of: model.messages.last?.id) { _, _ in
                                    guard keyboardVisible else { return }
                                    Task { @MainActor in
                                        await Task.yield()
                                        try? await Task.sleep(for: .milliseconds(280))
                                        guard keyboardVisible else { return }
                                        withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo("chat-bottom-anchor", anchor: .bottom) }
                                    }
                                }
            }
            GeometryReader { geometry in
                topBar
                    .padding(.top, max(geometry.safeAreaInsets.top, 54) + 8)
                    .frame(width: geometry.size.width, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .padding(.bottom, 10)
        }
        .task {
            await model.load(waitForRemote: false)
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load() }
        }
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
        .sheet(isPresented: $showingSubscriptionUsage) {
            SubscriptionUsageSheet()
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(LumiPalette.chatBackground)
        }
        .fullScreenCover(item: $fullScreenHTMLMessage) { message in
            HTMLMessageFullScreen(message: message)
        }
        .fullScreenCover(isPresented: $showingCallDemo) {
            CallDemoView { message in model.receiveCallOutcome(message) }
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
            glassCircleButton("phone") { showingCallDemo = true }
            HStack(spacing: 0) {
                Button { showingSubscriptionUsage = true } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 48, height: 42)
                }
                .buttonStyle(.plain)
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
        ComposerInputView(
            selectedImageData: $selectedImageData,
            selectedImageName: $selectedImageName,
            photoItem: $photoItem,
            onSend: { text in
                Task { await sendDraft(text: text) }
            }
        )
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
        let isHTMLCard = message.htmlContent != nil || message.contentType == "html" || isHTML(message.content)
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            if let localName = message.localImageFileName,
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(localName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 210, maxHeight: 190).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack(alignment: .top) {
                if message.role == .assistant {
                    if showAvatar {
                        if let thinking = thinkingText(for: message) {
                            Button {
                                glassPresentation.thinkingText = thinking
                                glassPresentation.showingThinkingDetails = true
                            } label: { assistantAvatar(for: message) }
                            .buttonStyle(.plain)
                        } else { assistantAvatar(for: message) }
                    } else { Color.clear.frame(width: 42, height: 42) }
                }
                if message.role == .user { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 7) {
                if isHTMLCard {
                    Button { htmlMessage = message } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color(red: 0.92, green: 0.59, blue: 0.68), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.htmlTitle ?? "HTML 页面")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.82))
                                    .lineLimit(1)
                                Text("Code · HTML")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                    }
                    .buttonStyle(.plain)
                } else if let audioFileName = message.audioFileName {
                    let hasVisibleReply = model.messages.contains { item in
                        item.role == .assistant && item.id != message.id &&
                        !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        abs(item.createdAt.timeIntervalSince(message.createdAt)) < 0.01
                    }
                    SpeechBubble(message: message, fileName: audioFileName, showsTranscript: !hasVisibleReply)
                } else {
                    if looksLikeCode(message.content) {
                        Text(codeDisplayContent(message.content))
                            .foregroundStyle(.black)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        markdownText(visibleContent(message.content))
                            .foregroundStyle(.black)
                            .font(.system(size: 14, weight: .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                }
                .padding(.horizontal, isHTMLCard ? 8 : 13)
                .padding(.vertical, isHTMLCard ? 5 : (message.audioFileName == nil ? 10 : 3))
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

    private static let beijingTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func beijingTime(_ date: Date) -> String {
        Self.beijingTimeFormatter.string(from: date)
    }

    private func assistantAvatar(for message: ChatMessage) -> some View {
            avatar(for: .assistant)
        }

    private func timeDivider(for date: Date) -> some View {
        Text("-- \(beijingTime(date)) --")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
    }

    private func visibleContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[(?:左耳|右耳|脑后|面前|贴近|退开)\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeCode(_ content: String) -> Bool {
        let source = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.range(of: #"(?s)```[^\n]*\n.*?```"#, options: .regularExpression) != nil { return true }
        guard source.contains("\n") else { return false }
        let markers = [
            #"\b(import|func|struct|class|enum|let|var|guard|private|public|return)\b"#,
            #"\.(onReceive|scrollTo|frame|padding|background|ignoresSafeArea)\s*\("#,
            #"\b(ScrollViewReader|DispatchQueue|NotificationCenter|UIResponder)\b"#,
            #"\{\s*(?:_|[A-Za-z][A-Za-z0-9_]*)?\s*in\b"#,
            #"[{};]"#
        ]
        return markers.reduce(0) { count, pattern in
            count + (source.range(of: pattern, options: .regularExpression) == nil ? 0 : 1)
        } >= 2
    }

    private func codeDisplayContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"(?m)^```[^\n]*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func thinkingText(for message: ChatMessage) -> String? {
        let thinking = message.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thinking, !thinking.isEmpty,
              !thinking.localizedCaseInsensitiveContains("speech_enabled") else { return nil }
        return thinking
    }

    private var thinkingBubble: some View {
        HStack {
            avatar(for: .assistant)
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

    private func sendDraft(text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }
        model.draft = text
        let imageBase64 = selectedImageData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let ttsKey = LumiKeychain.read()
        let tts = ttsEnabled && !ttsKey.isEmpty ? TTSRequestSettings(apiKey: ttsKey, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true) : nil
        let catalogData = UserDefaults.standard.string(forKey: "lumi.emojiCatalogJSON")?.data(using: .utf8) ?? Data("[]".utf8)
        let entries = (try? JSONDecoder().decode([EmojiEntry].self, from: catalogData)) ?? []
        let catalog = Dictionary(grouping: entries, by: \.mood).mapValues { $0.map(\.face) }
        await model.send(imageBase64: imageBase64, imageFileName: selectedImageName, tts: tts, emojiCatalog: catalog)
        selectedImageData = nil
        selectedImageName = nil
        photoItem = nil
    }
}

private struct ComposerInputView: View {
    @Binding var selectedImageData: Data?
    @Binding var selectedImageName: String?
    @Binding var photoItem: PhotosPickerItem?
    let onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let data = selectedImageData, let image = UIImage(data: data) {
                HStack(spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        selectedImageData = nil
                        selectedImageName = nil
                        photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            TextField("", text: $text)
                .focused($focused)
                .lineLimit(1)
                .submitLabel(.send)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
                .onSubmit {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        focused = false
                        return
                    }
                    text = ""
                    onSend(value)
                    focused = false
                }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(width: 42, height: 42)
                }
                Spacer()
                Button { focused = true } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                Button {
                    let value = text
                    text = ""
                    focused = false
                    onSend(value)
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(Color(red: 0.31, green: 0.22, blue: 0.26), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: selectedImageData == nil ? 96 : 140)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32))
        .background(Color(red: 0.965, green: 0.905, blue: 0.925).opacity(0.92), in: RoundedRectangle(cornerRadius: 32))
        .shadow(color: Color(red: 0.55, green: 0.38, blue: 0.45).opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        selectedImageData = data
                        selectedImageName = "image-\(UUID().uuidString).jpg"
                    }
                }
            }
        }
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
    let showsTranscript: Bool
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
                if showsTranscript {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expandedTranscript.toggle() } } label: {
                        Image(systemName: expandedTranscript ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expandedTranscript ? "收起转文字" : "展开转文字")
                }
            }
            if showsTranscript && expandedTranscript {
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // The player can still attempt playback on the current route.
        }
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
    @State private var showingCode = false

    private var htmlSource: String { message.htmlContent ?? message.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HTML 预览").font(.system(size: 21, weight: .semibold))
                    Text("隔离预览 · 不会修改 Lumi").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onExpand() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black.opacity(0.72))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("全屏预览")
            }
            HStack(spacing: 8) {
                previewTab("预览", selected: !showingCode) { showingCode = false }
                previewTab("代码", selected: showingCode) { showingCode = true }
                Spacer(minLength: 0)
            }
            Group {
                if showingCode {
                    ScrollView([.vertical, .horizontal]) {
                        Text(htmlSource)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                    .background(.white)
                } else {
                    HTMLWebContent(source: htmlSource)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.06), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(LumiPalette.chatBackground)
    }

    private func previewTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? .black.opacity(0.76) : .secondary)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(selected ? Color.white.opacity(0.8) : Color.white.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HTMLMessageFullScreen: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    private var htmlSource: String { message.htmlContent ?? message.content }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LumiPalette.chatBackground.ignoresSafeArea()
            HTMLWebContent(source: htmlSource)
                .ignoresSafeArea()
                .offset(x: dragOffset)
                .gesture(DragGesture(minimumDistance: 16).onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) { dragOffset = value.translation.width }
                }.onEnded { value in
                    if abs(value.translation.width) > 110 && abs(value.translation.width) > abs(value.translation.height) { dismiss() }
                    else { withAnimation(.spring(response: 0.28)) { dragOffset = 0 } }
                })
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
        let html: String
        if document.range(of: #"(?is)^\s*(?:<!doctype\s+html\b|<html\b)"#, options: .regularExpression) != nil {
            html = document
        } else {
            html = "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>body{font-family:-apple-system; padding:18px; color:#222;}</style>\(document)"
        }
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

@MainActor
private struct SubscriptionUsageSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let api = LumiAPIClient()
    @State private var usage: SubscriptionUsage?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("订阅额度")
                        .font(.system(size: 22, weight: .bold))
                    Text("Max 订阅 · 实时同步 5 小时与每周窗口")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(loading)
            }

            if loading && usage == nil {
                Spacer()
                ProgressView("正在读取额度")
                Spacer()
            } else if let usage {
                quotaCard(title: "5 小时额度", quota: usage.quota5Hour, tint: Color(red: 0.55, green: 0.32, blue: 0.43))
                quotaCard(title: "每周额度", quota: usage.quota7Day, tint: Color(red: 0.34, green: 0.43, blue: 0.56))
                Text("当前为 \(usage.plan.tier.capitalized) 订阅 · 更新于 \(usage.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(error ?? "暂时无法读取订阅额度")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button("关闭") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(Color(red: 0.31, green: 0.22, blue: 0.26), in: Capsule())
        }
        .padding(22)
        .task { await refresh() }
    }

    private func quotaCard(title: String, quota: SubscriptionQuota, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("剩余 \(flow(quota.remainingFlows)) Flow")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(max(quota.usagePercentage, 0), 1))
                .tint(tint)
            HStack {
                Text("已用 \(Int((quota.usagePercentage * 100).rounded()))%")
                Spacer()
                Text(resetText(quota.resetsAt))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "等待第一次请求" }
        return "重置：\(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func flow(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func refresh() async {
        loading = true
        defer { loading = false }

        do {
            usage = try await api.fetchSubscriptionUsage()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
private final class CallSpeechRecognition: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?
    private var isStarting = false
    private var tapInstalled = false
    private var silenceTask: Task<Void, Never>?

    func start(onFinal: @escaping (String) -> Void) {
        guard !isListening, !isStarting else { return }
        isStarting = true
        self.onFinal = onFinal
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.isStarting = false
                    self.errorMessage = "请允许语音识别后再说话"
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.isStarting = false
                            self.errorMessage = "请允许麦克风后再说话"
                            return
                        }
                        self.beginRecognition()
                    }
                }
            }
        }
    }

    func stop() {
        isStarting = false
        silenceTask?.cancel()
        silenceTask = nil
        tearDownAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
    }

    private func tearDownAudio() {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func beginRecognition() {
        guard !isListening, let recognizer, recognizer.isAvailable else {
            isStarting = false
            errorMessage = "语音识别暂时不可用"
            return
        }
        tearDownAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                isStarting = false
                errorMessage = "麦克风设备还没准备好，请再试一次"
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isStarting = false
            isListening = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finishTranscript()
                            return
                        }
                        let observedTranscript = self.transcript
                        self.silenceTask?.cancel()
                        self.silenceTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(900))
                            guard !Task.isCancelled, let self,
                                  self.isListening,
                                  self.transcript == observedTranscript else { return }
                            self.finishTranscript()
                        }
                    }
                    if error != nil && !self.transcript.isEmpty {
                        self.finishTranscript()
                    } else if error != nil {
                        self.stop()
                        self.errorMessage = "没听清，再说一次试试"
                    }
                }
            }
        } catch {
            stop()
            errorMessage = "无法启动麦克风：\(error.localizedDescription)"
        }
    }

    private func finishTranscript() {
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = onFinal
        stop()
        if !finalText.isEmpty { handler?(finalText) }
    }
}

private struct CallDemoView: View {
    private enum Phase { case requesting, connected }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.ttsModel") private var ttsModel = "speech-2.8-hd"
    @AppStorage("lumi.ttsVoiceID") private var ttsVoiceID = "moss_audio_9b73ea77-9ada-11f1-b714-6a6575e57454"
    @AppStorage("lumi.ttsHost") private var ttsHost = "https://api.minimaxi.com"
    @State private var phase: Phase = .requesting
    @State private var callStartedAt: Date?
    @State private var muted = false
    @State private var speakerOn = true
    @State private var requestError: String?
    @State private var callID: String?
    @State private var turns: [CallTurn] = []
    @State private var callDraft = ""
    @State private var sendingTurn = false
    @State private var generatingReply = false
    @State private var callAudioFiles: [UUID: URL] = [:]
    @StateObject private var player = SpatialSpeechPlayback()
    @StateObject private var speechRecognition = CallSpeechRecognition()
    let onRejected: (ChatMessage) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LumiPalette.chatBackground, Color(red: 0.98, green: 0.91, blue: 0.93), Color(red: 0.94, green: 0.86, blue: 0.89)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle().fill(.white.opacity(0.76)).frame(width: 440, height: 440).blur(radius: 38).offset(x: 150, y: -300)
            Circle().fill(Color(red: 0.79, green: 0.54, blue: 0.65).opacity(0.13)).frame(width: 360, height: 360).blur(radius: 48).offset(x: -145, y: 320)

            if phase == .requesting {
                requestingCall
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                activeCall
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .preferredColorScheme(.light)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.28), value: phase == .connected)
        .task { await requestCall() }
        .onChange(of: muted) { _, isMuted in
            if isMuted { speechRecognition.stop() }
            else { startListeningIfNeeded() }
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if !isPlaying { startListeningIfNeeded() }
        }
        .onDisappear { speechRecognition.stop() }
    }

    private var requestingCall: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Lumi 通话")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.55))
                Spacer()
                Color.clear.frame(width: 42, height: 42)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Spacer(minLength: 32)
            callAvatar(size: 142)
                .overlay(Circle().stroke(.white.opacity(0.84), lineWidth: 1))
                .shadow(color: Color(red: 0.55, green: 0.38, blue: 0.45).opacity(0.18), radius: 24, y: 12)
            Text("沈屿")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .padding(.top, 24)
            Text("正在呼叫")
                .font(.system(size: 16))
                .foregroundStyle(.black.opacity(0.52))
                .padding(.top, 7)
            Text(requestError ?? "等待对方接受邀请…")
                .font(.system(size: 15))
                .foregroundStyle(.black.opacity(0.70))
                .padding(.top, 26)
                .padding(.horizontal, 28)
                .multilineTextAlignment(.center)

            Spacer()
            callAction(title: "取消", icon: "phone.down.fill", color: Color(red: 0.92, green: 0.25, blue: 0.31)) { dismiss() }
            .padding(.bottom, 46)
        }
        .foregroundStyle(.black.opacity(0.82))
    }

    private var activeCall: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 3) {
                    Text("沈屿")
                        .font(.system(size: 16, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(callDuration(at: timeline.date))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.52))
                    }
                }
                Spacer()
                Color.clear.frame(width: 42, height: 42)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Spacer(minLength: 20)
            callAvatar(size: 112)
                .overlay(Circle().stroke(.white.opacity(0.84), lineWidth: 1))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(turns) { turn in
                        Text(turn.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.black.opacity(0.72))
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(turn.role == "user" ? LumiPalette.userBubble : .white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                            .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)
                            .onTapGesture {
                                if turn.role == "assistant" { replayTurn(turn) }
                            }
                    }
                    if generatingReply {
                        HStack(spacing: 8) {
                            CallTypingDots()
                            Text("沈屿正在准备语音")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.black.opacity(0.48))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 28).padding(.top, 18)
            }
            .frame(maxHeight: 220)

            Spacer()
            VStack(spacing: 16) {
                if muted {
                    HStack(spacing: 9) {
                        TextField("给沈屿发消息…", text: $callDraft)
                            .submitLabel(.send)
                            .onSubmit { Task { await sendTypedTurn() } }
                        Button { Task { await sendTypedTurn() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)) }
                            .disabled(callDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendingTurn)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(.white.opacity(0.70), in: Capsule())
                    .padding(.horizontal, 25)
                } else if speechRecognition.isListening || !speechRecognition.transcript.isEmpty {
                    Text(speechRecognition.transcript.isEmpty ? "正在听…" : speechRecognition.transcript)
                        .font(.system(size: 15))
                        .foregroundStyle(.black.opacity(0.54))
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.52), in: Capsule())
                        .padding(.horizontal, 25)
                }
                HStack(spacing: 10) {
                    callControl(title: muted ? "已静音" : "静音", icon: muted ? "mic.slash.fill" : "mic.fill", selected: muted) { muted.toggle() }
                    callAction(title: "挂断", icon: "phone.down.fill", color: Color(red: 0.92, green: 0.25, blue: 0.31)) { dismiss() }
                    callControl(title: speakerOn ? "扬声器" : "听筒", icon: speakerOn ? "speaker.wave.2.fill" : "speaker.fill", selected: speakerOn) { speakerOn.toggle() }
                }
            }
            .padding(.bottom, 44)
        }
        .foregroundStyle(.black.opacity(0.82))
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach([14.0, 28, 43, 32, 52, 35, 18, 29, 46, 24, 15], id: \.self) { height in
                Capsule()
                    .fill(Color(red: 0.60, green: 0.33, blue: 0.45).opacity(0.72))
                    .frame(width: 4, height: height)
            }
        }
        .frame(height: 56)
    }

    @ViewBuilder private func callAvatar(size: CGFloat) -> some View {
        if let path = Bundle.main.path(forResource: "AssistantAvatar", ofType: "jpg"), let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(Color(red: 0.47, green: 0.24, blue: 0.37))
                .frame(width: size, height: size)
                .background(Color(red: 1.0, green: 0.84, blue: 0.88), in: Circle())
        }
    }

    private func callAction(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .background(color, in: Circle())
                Text(title).font(.system(size: 14, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(width: 104)
    }

    private func callControl(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(selected ? Color(red: 0.82, green: 0.62, blue: 0.69).opacity(0.70) : .white.opacity(0.64), in: Circle())
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .frame(width: 104)
        }
        .buttonStyle(.plain)
    }

    private func callDuration(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(callStartedAt ?? date)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func requestCall() async {
        let key = LumiKeychain.read()
        let tts = !key.isEmpty
            ? TTSRequestSettings(apiKey: key, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true)
            : nil
        do {
            let response = try await LumiAPIClient().startCall(to: "default", tts: tts)
            guard response.status == "accepted" else {
                if let message = response.assistantMessage { onRejected(message) }
                dismiss()
                return
            }
            callStartedAt = .now
            callID = response.callId
            let openingBubbles = response.firstMessage.map { splitAssistantTurn($0) } ?? []
            turns = openingBubbles
            phase = .connected
            if let encoded = response.speechAudioBase64, let data = Data(base64Encoded: encoded) {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("call-opening-\(response.callId).mp3")
                try? data.write(to: url, options: .atomic)
                for bubble in openingBubbles { callAudioFiles[bubble.id] = url }
                player.play(url: url, script: response.speechScript ?? response.firstMessage?.content ?? "")
            }
            startListeningIfNeeded()
        } catch {
            requestError = error.localizedDescription
        }
    }

    private func sendTypedTurn(_ submittedText: String? = nil) async {
        let text = (submittedText ?? callDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let callID, !sendingTurn else { return }
        callDraft = ""
        speechRecognition.stop()
        sendingTurn = true
        generatingReply = true
        let provisionalTurn = CallTurn(id: UUID(), role: "user", content: text, createdAt: .now, speechScript: nil)
        turns.append(provisionalTurn)
        defer {
            sendingTurn = false
            generatingReply = false
        }
        let key = LumiKeychain.read()
        let tts = !key.isEmpty ? TTSRequestSettings(apiKey: key, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true) : nil
        do {
            let response = try await LumiAPIClient().sendCallTurn(text, callID: callID, to: "default", tts: tts)
            if let index = turns.firstIndex(where: { $0.id == provisionalTurn.id }) {
                turns[index] = response.userTurn
            } else {
                turns.append(response.userTurn)
            }
            let assistantBubbles = splitAssistantTurn(response.assistantTurn)
            turns.append(contentsOf: assistantBubbles)
            if let encoded = response.speechAudioBase64, let data = Data(base64Encoded: encoded) {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("call-turn-\(response.assistantTurn.id.uuidString).mp3")
                try? data.write(to: url, options: .atomic)
                for bubble in assistantBubbles { callAudioFiles[bubble.id] = url }
                player.play(url: url, script: response.speechScript ?? response.assistantTurn.content)
            }
        } catch { requestError = error.localizedDescription }
    }

    private func startListeningIfNeeded() {
        guard phase == .connected, !muted, !player.isPlaying, !sendingTurn else { return }
        speechRecognition.start { text in
            Task { await sendTypedTurn(text) }
        }
    }

    private func replayTurn(_ turn: CallTurn) {
        guard let url = callAudioFiles[turn.id] else { return }
        player.play(url: url, script: turn.speechScript ?? turn.content)
    }

    private func splitAssistantTurn(_ turn: CallTurn) -> [CallTurn] {
        let pieces = turn.content
            .components(separatedBy: .newlines)
            .flatMap(sentencePieces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard pieces.count > 1 else { return [turn] }
        return pieces.map { piece in
            CallTurn(id: UUID(), role: turn.role, content: piece, createdAt: turn.createdAt, speechScript: piece)
        }
    }

    private func sentencePieces(_ line: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in line {
            current.append(character)
            if "。！？!?；;".contains(character) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pieces.append(current) }
        return pieces
    }
}

private struct CallTypingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.47, green: 0.24, blue: 0.37))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1 : 0.45)
                    .opacity(animating ? 0.9 : 0.35)
                    .animation(.easeInOut(duration: 0.52).repeatForever().delay(Double(index) * 0.14), value: animating)
            }
        }
        .frame(width: 28, height: 20)
        .onAppear { animating = true }
    }
}
