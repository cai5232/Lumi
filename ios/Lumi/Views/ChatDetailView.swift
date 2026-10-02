import SwiftUI
import UIKit
import UserNotifications
import PhotosUI
import AVFoundation
import Speech
import WebKit

private struct ChatHistoryTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = -.greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel
    @StateObject private var glassPresentation = GlassComparisonPresentation()
    @State private var showingSettings = false
    @State private var htmlMessage: ChatMessage?
    @State private var fullScreenHTMLMessage: ChatMessage?
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedImageName: String?
    @State private var selectedGalleryItem: RemoteGalleryItem?
    @State private var showingCallDemo = false
    @State private var incomingCallID: String?
    @State private var incomingCall: IncomingCallInfo?
    @State private var respondingToIncomingCallID: String?
    @State private var selectedCallRecord: ChatMessage?
    @State private var showingSubscriptionUsage = false
    @State private var showingTogether = false
    @State private var historyPagingArmed = false
    @State private var historyPagingPrimed = false
    @State private var didInitialScroll = false
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
                        Color.clear
                            .frame(height: 1)
                            .background(GeometryReader { reader in
                                Color.clear.preference(key: ChatHistoryTopOffsetKey.self, value: reader.frame(in: .named("chat-scroll")).minY)
                            })
                        // A sent message is first rendered with a local UUID and then
                        // confirmed with the server UUID. Keep the row identity stable
                        // across that replacement so SwiftUI does not briefly remove the
                        // user's bubble while the assistant reply arrives.
                        ForEach(Array(model.messages.enumerated()), id: \.offset) { index, message in
                            if shouldShowTimeDivider(at: index) {
                                timeDivider(for: message.createdAt)
                            }
                            messageBubble(message, showAvatar: shouldShowAvatar(at: index))
                        }
                        if model.isSending { thinkingBubble }
                    }
                    .animation(.easeOut(duration: 0.24), value: model.messages.count)
                    .padding(.horizontal, 16)
                    .padding(.top, 112)
                    .padding(.bottom, 20)
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom-anchor")
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "chat-scroll")
                .onPreferenceChange(ChatHistoryTopOffsetKey.self) { offset in
                    // Before the initial jump to the newest message, the top marker is
                    // naturally visible. Do not treat that as an upward history pull.
                    guard historyPagingArmed else { return }
                    if offset < 0 { historyPagingPrimed = true; return }
                    guard historyPagingPrimed, offset >= 0, !model.isLoadingOlderHistory else { return }
                    historyPagingPrimed = false
                    Task { await model.loadOlderHistoryIfNeeded() }
                }
                .scrollDismissesKeyboard(.immediately)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: model.messages.count) { _, _ in
                    guard !didInitialScroll else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                        didInitialScroll = true
                        historyPagingArmed = true
                    }
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !didInitialScroll else { return }
                    proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    didInitialScroll = true
                    historyPagingArmed = true
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.white
                            .frame(height: max(geometry.safeAreaInsets.top, 44) + 44)
                            .overlay(alignment: .bottom) {
                                TopBarWaveEdge()
                                    .fill(LumiPalette.chatBackground)
                                    .frame(height: 6)
                            }
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea(edges: .top)

                    topBar
                        .padding(.top, max(geometry.safeAreaInsets.top, 44))
                        .frame(width: geometry.size.width, alignment: .top)
                }
            }
        }
        .foregroundStyle(LumiPalette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack(alignment: .top) {
                Color.white
                    .frame(height: 52)
                composer
                    .padding(.top, 4)
            }
            .frame(height: 52)
            .background(Color.white.ignoresSafeArea(edges: .bottom))
        }
        .task {
            await model.load()
            await pollIncomingCall()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiIncomingCall"))) { _ in
            Task { incomingCall = try? await LumiAPIClient().fetchIncomingCall(from: "default") }
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
        .fullScreenCover(isPresented: $showingTogether) {
            TogetherView { item in
                selectedGalleryItem = item
            }
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
            CallDemoView(
                incomingCallID: incomingCallID,
                onRejected: { message, statusMessage in model.receiveCallOutcome(message, statusMessage: statusMessage) },
                onEnded: { record in
                    incomingCallID = nil
                    if let record { model.receiveCallRecord(record) }
                }
            )
        }
        .fullScreenCover(item: $selectedCallRecord) { record in
            CallRecordView(record: record)
        }
        .overlay {
            if let call = incomingCall {
                ZStack {
                    Color.black.opacity(0.20).ignoresSafeArea()
                    IncomingCallSheet(
                        call: call,
                        onAccept: {
                            incomingCall = nil
                            incomingCallID = call.callId
                            showingCallDemo = true
                        },
                        onDecline: { note in
                            // Close immediately; the AI follow-up is a normal chat bubble and may arrive later.
                            incomingCall = nil
                            respondingToIncomingCallID = call.callId
                            Task { await declineIncomingCall(call, note: note) }
                        }
                    )
                    .frame(maxWidth: 356, maxHeight: 510)
                    .background(LumiPalette.chatBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.66), lineWidth: 1))
                    .shadow(color: .black.opacity(0.20), radius: 28, y: 12)
                    .padding(.horizontal, 24)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
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
            Button { showingTogether = true } label: {
                PixelArtIcon(assetName: "top-icon-together")
                    .frame(width: 25, height: 25)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showingSettings = true } label: {
                PixelArtIcon(assetName: "top-icon-settings")
                    .frame(width: 25, height: 25)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            HStack(spacing: 0) {
                Button { showingCallDemo = true } label: {
                    PixelArtIcon(assetName: "top-icon-phone")
                        .frame(width: 25, height: 25)
                        .frame(width: 48, height: 42)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.gray.opacity(0.78))
        }
        .padding(.horizontal, 16)
    }

    private var composer: some View {
        ComposerInputView(
            selectedImageData: $selectedImageData,
            selectedImageName: $selectedImageName,
            selectedGalleryItem: $selectedGalleryItem,
            photoItem: $photoItem,
            onSend: { text in
                Task { await sendDraft(text: text) }
            }
        )
    }

    private func pollIncomingCall() async {
        let api = LumiAPIClient()
        while !Task.isCancelled {
            if !showingCallDemo && incomingCall == nil && respondingToIncomingCallID == nil {
                incomingCall = try? await api.fetchIncomingCall(from: "default")
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func declineIncomingCall(_ call: IncomingCallInfo, note: String? = nil) async {
        respondingToIncomingCallID = call.callId
        defer { if respondingToIncomingCallID == call.callId { respondingToIncomingCallID = nil } }
        do {
            let response = try await LumiAPIClient().answerIncomingCall(call.callId, action: "decline", to: "default", note: note)
            if let message = response.assistantMessage { model.receiveCallOutcome(message, statusMessage: response.callStatusMessage) }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func glassCircleButton(_ systemName: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.gray.opacity(0.78))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    /// A single server request can be split into several chat bubbles that share
    /// the same timestamp. Show the avatar only on the first bubble of that
    /// request; a standalone call record still gets its own avatar.
    private func shouldShowAvatar(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = model.messages[index]
        let previous = model.messages[index - 1]
        guard current.role == previous.role else { return true }
        return abs(current.createdAt.timeIntervalSince(previous.createdAt)) >= 0.01
    }

    private func shouldShowTimeDivider(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return model.messages[index].createdAt.timeIntervalSince(model.messages[index - 1].createdAt) > 30 * 60
    }

    @ViewBuilder private func messageBubble(_ message: ChatMessage, showAvatar: Bool) -> some View {
        let isHTMLCard = message.htmlContent != nil || message.contentType == "html" || isHTML(message.content)
        let isCallRecord = message.contentType == "call_record"
        let isCallStatus = message.contentType == "call_status"
        let isGalleryCollection = message.contentType == "gallery_collected"
        let isUserSide = message.callInitiator == "user" || (message.callInitiator == nil && message.role == .user)
        VStack(alignment: isUserSide ? .trailing : .leading, spacing: 5) {
            if !isGalleryCollection,
               let localName = message.localImageFileName,
               let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(localName),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 210, maxHeight: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            HStack(alignment: .top) {
                if !isUserSide {
                    if showAvatar {
                        VStack(spacing: 3) {
                            if let thinking = thinkingText(for: message) {
                                Button {
                                    glassPresentation.thinkingText = thinking
                                    glassPresentation.showingThinkingDetails = true
                                } label: { assistantAvatar(for: message) }
                                .buttonStyle(.plain)
                            } else { assistantAvatar(for: message) }
                            Text(beijingTime(message.createdAt))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(LumiPalette.textSecondary)
                                .frame(width: 48)
                        }
                    } else { Color.clear.frame(width: 42, height: 42) }
                }
                if isUserSide { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 7) {
                if isGalleryCollection,
                   let notice = try? JSONDecoder().decode(GalleryCollectionNotice.self, from: Data(message.content.utf8)) {
                    GalleryCollectionCard(notice: notice, localImageName: message.localImageFileName)
                } else if isCallRecord {
                    Button { selectedCallRecord = message } label: {
                        HStack(spacing: 8) {
                            if !isUserSide {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.56))
                            }
                            Text("通话时长 \(callDurationLabel(message.callDuration))")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            if isUserSide {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.56))
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                } else if isCallStatus {
                    HStack(spacing: 9) {
                        if !isUserSide {
                            Image(systemName: message.callStatus == "missed" ? "phone.badge.xmark" : "phone.down.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.56))
                        }
                        Text(message.callStatus == "missed" ? "对方未接听" : "对方已拒绝")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if isUserSide {
                            Image(systemName: message.callStatus == "missed" ? "phone.badge.xmark" : "phone.down.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.56))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                } else if isHTMLCard {
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
                            .foregroundStyle(LumiPalette.textPrimary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        markdownText(visibleContent(message.content))
                            .foregroundStyle(LumiPalette.textPrimary)
                            .font(.system(size: 14, weight: .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                }
                .foregroundStyle(LumiPalette.textPrimary)
                .padding(.horizontal, isGalleryCollection ? 0 : (isHTMLCard ? 8 : (isCallStatus ? 10 : 13)))
                .padding(.vertical, isGalleryCollection ? 0 : (isHTMLCard ? 5 : ((isCallStatus || isCallRecord) ? 0 : (message.audioFileName == nil ? 10 : 3))))
                .frame(width: isGalleryCollection ? 244 : (message.audioFileName == nil ? nil : min(300, max(180, 150 + CGFloat(message.speechDuration ?? 2) * 8))), alignment: .leading)
                .background(isGalleryCollection ? .clear : (isUserSide ? LumiPalette.userBubble : .white))
                .clipShape(RoundedRectangle(cornerRadius: isGalleryCollection ? 0 : 21))
                if !isUserSide { Spacer(minLength: 48) }
                if isUserSide {
                    if showAvatar { avatar(for: .user) }
                    else { Color.clear.frame(width: 42, height: 42) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserSide ? .trailing : .leading)
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
        Text(beijingTime(date))
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(LumiPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
    }

    private func visibleContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[(?:左耳|右耳|脑后|面前|贴近|退开)\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callDurationLabel(_ duration: Double?) -> String {
        let seconds = max(0, Int(duration ?? 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = compactUploadData(from: image) else { return }
        let name = "image-\(UUID().uuidString).jpg"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? jpeg.write(to: url, options: .atomic)
        selectedImageData = jpeg
        selectedImageName = name
    }

    private func compactUploadData(from image: UIImage) -> Data? {
        let sourceWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let sourceHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let largestSide = max(sourceWidth, sourceHeight)
        let scale = min(1, 2048 / max(largestSide, 1))
        let size = CGSize(width: (sourceWidth * scale).rounded(), height: (sourceHeight * scale).rounded())
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.80)
    }

    private func sendDraft(text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil || selectedGalleryItem != nil else { return }
        model.draft = text
        let imageBase64 = selectedImageData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let ttsKey = LumiKeychain.read()
        let tts = ttsEnabled && !ttsKey.isEmpty ? TTSRequestSettings(apiKey: ttsKey, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true) : nil
        let catalogData = UserDefaults.standard.string(forKey: "lumi.emojiCatalogJSON")?.data(using: .utf8) ?? Data("[]".utf8)
        let entries = (try? JSONDecoder().decode([EmojiEntry].self, from: catalogData)) ?? []
        let catalog = Dictionary(grouping: entries, by: \.mood).mapValues { $0.map(\.face) }
        await model.send(imageBase64: imageBase64, imageFileName: selectedImageName, galleryImageIDs: selectedGalleryItem.map { [$0.id] } ?? [], tts: tts, emojiCatalog: catalog)
        selectedImageData = nil
        selectedImageName = nil
        selectedGalleryItem = nil
        photoItem = nil
    }
}

private struct GalleryCollectionCard: View {
    let notice: GalleryCollectionNotice
    let localImageName: String?
    private let api = LumiAPIClient()

    private var localImage: UIImage? {
        guard let localImageName,
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(localImageName).path)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let localImage {
                        Image(uiImage: localImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        AsyncImage(url: api.galleryImageURL(id: notice.id, in: "default")) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(Color.black.opacity(0.06))
                                    .overlay { ProgressView().controlSize(.small) }
                            }
                        }
                    }
                }
                .frame(width: 54, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(red: 0.83, green: 0.55, blue: 0.61), in: Circle())
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("沈屿 收藏了")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("存进了「\(notice.title)」")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.86))
                    .lineLimit(1)
                Text(notice.firstImpression)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.black.opacity(0.52))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("沈屿收藏了，存进了\(notice.title)。\(notice.firstImpression)")
    }
}

private struct PixelArtIcon: View {
    let assetName: String

    var body: some View {
        Image(uiImage: Self.image(named: assetName))
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private static func image(named name: String) -> UIImage {
        let sourceImage = Bundle.main.url(forResource: name, withExtension: "png")
            .flatMap { UIImage(contentsOfFile: $0.path) }
            ?? UIImage(named: name)
        return sourceImage ?? UIImage()
    }
}

private struct TopBarWaveEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * 0.45
        let amplitude = min(1.25, rect.height * 0.22)
        let wavelength = max(14, rect.width / 18)
        path.move(to: CGPoint(x: 0, y: baseline))
        var x: CGFloat = 0
        while x <= rect.width {
            let y = baseline + sin((x / wavelength) * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct ComposerInputView: View {
    @Binding var selectedImageData: Data?
    @Binding var selectedImageName: String?
    @Binding var selectedGalleryItem: RemoteGalleryItem?
    @Binding var photoItem: PhotosPickerItem?
    let onSend: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let item = selectedGalleryItem {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.black.opacity(0.58))
                    Text("带入相册：\(item.title)")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button { selectedGalleryItem = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
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
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LumiPalette.iconPink)
                        .frame(width: 38, height: 38)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(LumiPalette.iconPink, lineWidth: 1))
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    TextField("输入消息", text: $text)
                        .focused($focused)
                        .foregroundStyle(LumiPalette.textPrimary)
                        .tint(LumiPalette.iconPink)
                        .lineLimit(1)
                        .submitLabel(.send)
                        .onSubmit {
                            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if value.isEmpty && selectedImageData == nil && selectedGalleryItem == nil {
                                focused = false
                                return
                            }
                            text = ""
                            onSend(value)
                            focused = false
                        }
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(LumiPalette.iconPink, lineWidth: 1))
            }
        }
        .frame(height: selectedImageData == nil && selectedGalleryItem == nil ? 40 : 92)
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.82) {
                    await MainActor.run {
                        let name = "image-\(UUID().uuidString).jpg"
                        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent(name)
                        // The chat bubble reads this same file after the optimistic
                        // message is replaced by the server-confirmed message.
                        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return }
                        selectedImageData = jpeg
                        selectedImageName = name
                    }
                }
            }
        }
    }
}

private enum LumiPalette {
    static let chatBackground = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let userBubble = Color(red: 0.9608, green: 0.9255, blue: 0.9255)
    static let iconPink = Color(red: 0.955, green: 0.745, blue: 0.800)
    static let textPrimary = Color(red: 0.20, green: 0.17, blue: 0.19)
    static let textSecondary = Color(red: 0.36, green: 0.31, blue: 0.34)
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
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP, .duckOthers])
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
    @AppStorage("lumi.proactiveActionMessage") private var proactiveActionMessage = true
    @AppStorage("lumi.proactiveActionPhone") private var proactiveActionPhone = true
    @AppStorage("lumi.proactiveActionScreen") private var proactiveActionScreen = false
    @State private var settingsLoaded = false
    @State private var syncStatus = "正在连接后端…"
    @State private var settingsSaveTask: Task<Void, Never>?
    @State private var activityState: ActivityState?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingMiniMaxSettings = false
    @State private var pushAPIToken = LumiKeychain.read(account: "push-api-token")
    @State private var modelProviders: [ModelProvider] = [
        ModelProvider(id: "zenmux", models: [], configuredModel: nil),
        ModelProvider(id: "backup", models: [], configuredModel: nil)
    ]
    @AppStorage("lumi.modelProvider") private var selectedProvider = "zenmux"
    @AppStorage("lumi.modelName.zenmux") private var zenmuxModel = ""
    @AppStorage("lumi.modelName.backup") private var backupModel = ""
    @AppStorage("lumi.modelName") private var legacyModel = ""
    private var selectedModel: String { selectedProvider == "backup" ? backupModel : (zenmuxModel.isEmpty ? legacyModel : zenmuxModel) }
    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { selectedModel },
            set: { value in
                if selectedProvider == "backup" { backupModel = value }
                else { zenmuxModel = value; legacyModel = value }
            }
        )
    }
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

                Section("模型线路") {
                    if modelProviders.isEmpty {
                        Text("正在读取中转站模型…").font(.system(size: 13)).foregroundStyle(.secondary)
                    } else {
                        Picker("线路", selection: $selectedProvider) {
                            ForEach(modelProviders) { provider in
                                Text(provider.id == "zenmux" ? "ZenMux" : "备用中转").tag(provider.id)
                            }
                        }
                        if let provider = modelProviders.first(where: { $0.id == selectedProvider }) {
                            Picker("模型", selection: selectedModelBinding) {
                                if provider.models.isEmpty {
                                    Text("暂无模型，点击刷新").tag("")
                                } else {
                                    ForEach(provider.models, id: \.self) { model in Text(model).tag(model) }
                                }
                            }
                            Button {
                                Task { await loadModelProviders() }
                            } label: {
                                Label("刷新模型列表", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    Text("切换后聊天、图片、日记、电话和保活都会使用当前线路。模型名称由中转站自动提供。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI 醒来后可以做什么")
                            .font(.system(size: 14, weight: .medium))
                        Toggle("主动消息", isOn: $proactiveActionMessage)
                        Toggle("主动电话", isOn: $proactiveActionPhone)
                        Toggle("查看屏幕", isOn: $proactiveActionScreen)
                        if proactiveActionScreen {
                            HStack {
                                Text("屏幕共享")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                BroadcastPickerView(preferredExtension: "com.cai5232.Lumi.BroadcastUpload")
                                    .frame(width: 44, height: 44)
                            }
                        }
                    }
                    .tint(Color(red: 0.72, green: 0.35, blue: 0.49))

                    Text("每次触发会走正常聊天模型并产生一次模型调用；保活默认关闭。\(syncStatus)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("主动联系")
                }

                Section {
                    HStack {
                        Label("当前状态", systemImage: activityState?.mode == "sleeping" ? "moon.zzz" : "antenna.radiowaves.left.and.right")
                        Spacer()
                        Text(activityStateLabel)
                            .foregroundStyle(.secondary)
                    }
                    Button("现在重新开始哨兵计时") {
                        Task { await updateActivity("sentinel_start") }
                    }
                    if activityState?.mode == "sleeping" {
                        Button("结束睡眠，切回自主活动") {
                            Task { await updateActivity("sleep_abort") }
                        }
                    }
                    Text("说“晚安”等告别词后，连续一小时没有新消息会进入睡眠；睡眠期间会生成连续梦境，异常醒来后可切回哨兵模式。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("自主活动与睡眠")
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
            await loadActivityState()
            await loadModelProviders()
        }
        .onChange(of: proactiveNudgeEnabled) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeInterval) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveNudgeMessage) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveActionMessage) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveActionPhone) { _, _ in saveProactiveSettings() }
        .onChange(of: proactiveActionScreen) { _, _ in saveProactiveSettings() }
        .onChange(of: selectedProvider) { _, _ in
            setSelectedModel("")
            Task { await loadModelProviders() }
        }
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
            proactiveActionMessage = settings.actions?.message ?? true
            proactiveActionPhone = settings.actions?.phone ?? true
            proactiveActionScreen = settings.actions?.screen ?? false
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

    private var activityStateLabel: String {
        switch activityState?.mode {
        case "sleeping": return "睡眠中"
        case "sentinel": return "哨兵模式"
        default: return "未同步"
        }
    }

    private func loadActivityState() async {
        activityState = try? await api.fetchActivityState()
    }

    private func updateActivity(_ action: String) async {
        activityState = try? await api.updateActivityState(action)
    }

    private func loadModelProviders() async {
        let zenmux = ModelProvider(id: "zenmux", models: [], configuredModel: nil)
        let backup = ModelProvider(id: "backup", models: [], configuredModel: nil)
        guard let fetched = try? await api.fetchModelProviders() else {
            modelProviders = [zenmux, backup]
            return
        }
        let fetchedBackup = fetched.first(where: { $0.id == "backup" }) ?? backup
        modelProviders = [zenmux, fetchedBackup]
        if !modelProviders.contains(where: { $0.id == selectedProvider }) { selectedProvider = modelProviders[0].id }
        if let provider = modelProviders.first(where: { $0.id == selectedProvider }), !provider.models.contains(selectedModel) {
            setSelectedModel(provider.configuredModel ?? provider.models.first ?? "")
        }
    }

    private func setSelectedModel(_ value: String) {
        if selectedProvider == "backup" { backupModel = value }
        else { zenmuxModel = value; legacyModel = value }
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
                    intervalMax: proactiveNudgeInterval,
                    actions: ProactiveActions(message: proactiveActionMessage, phone: proactiveActionPhone, screen: proactiveActionScreen)
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers])
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

private struct CallAudioClip: Codable, Identifiable {
    let id: String
    let fileName: String
    let script: String
    let duration: Double?
}

private enum CallAudioStore {
    private static let key = "lumi.callAudioClips"

    static func save(callID: String, fileName: String, script: String, duration: Double?) {
        var all = load()
        var clips = all[callID] ?? []
        let clip = CallAudioClip(id: UUID().uuidString, fileName: fileName, script: script, duration: duration)
        if !clips.contains(where: { $0.fileName == fileName }) { clips.append(clip) }
        all[callID] = clips
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clips(for callID: String?) -> [CallAudioClip] {
        guard let callID else { return [] }
        return load()[callID] ?? []
    }

    private static func load() -> [String: [CallAudioClip]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([String: [CallAudioClip]].self, from: data) else { return [:] }
        return value
    }
}

private struct CallRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = SpatialSpeechPlayback()
    let record: ChatMessage

    private var lines: [(speaker: String, text: String)] {
        record.content.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "：", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
    }

    private func durationLabel(_ duration: Double?) -> String {
        let seconds = max(0, Int(duration ?? 0))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [LumiPalette.chatBackground, Color(red: 0.96, green: 0.88, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    VStack(spacing: 3) {
                        Text("通话记录").font(.system(size: 16, weight: .semibold))
                        Text(durationLabel(record.callDuration)).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            let isUser = line.speaker == "我"
                            Text(line.text)
                                .font(.system(size: 15))
                                .foregroundStyle(.black.opacity(0.76))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                                .background(isUser ? LumiPalette.userBubble : .white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                                .onTapGesture {
                                    guard !isUser else { return }
                                    let clip = CallAudioStore.clips(for: record.callID).first { $0.script.contains(line.text) } ?? CallAudioStore.clips(for: record.callID).first
                                    guard let clip else { return }
                                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(clip.fileName)
                                    player.play(url: url, script: clip.script)
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct IncomingCallSheet: View {
    @State private var showingDeclineReasons = false
    @State private var declineNote = ""
    let call: IncomingCallInfo
    let onAccept: () -> Void
    let onDecline: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("来电")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.black.opacity(0.52))
            Spacer(minLength: 18)
            if let path = Bundle.main.path(forResource: "AssistantAvatar", ofType: "jpg"), let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.86), lineWidth: 1))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color(red: 0.47, green: 0.24, blue: 0.37))
                    .frame(width: 92, height: 92)
                    .background(Color(red: 1.0, green: 0.84, blue: 0.88), in: Circle())
            }
            Text("沈屿想和你通话")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .padding(.top, 18)
            Text(call.reason)
                .font(.system(size: 15))
                .foregroundStyle(.black.opacity(0.56))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)
            Spacer()
            if showingDeclineReasons {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(["在忙", "在外面", "想打字聊"], id: \.self) { reason in
                            Button(reason) { declineNote = reason }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(declineNote == reason ? Color(red: 0.90, green: 0.66, blue: 0.72) : Color.white.opacity(0.35), in: Capsule())
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("告诉他为什么没接…", text: $declineNote)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.58), in: Capsule())
                        Button("发送") { onDecline(declineNote.isEmpty ? nil : declineNote) }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(Color(red: 0.82, green: 0.47, blue: 0.58), in: Capsule())
                    }
                    Button("直接挂断") { onDecline(nil) }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black.opacity(0.55))
                }
            } else {
                HStack(spacing: 40) {
                    Button { showingDeclineReasons = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 64, height: 64)
                                .background(Color.black.opacity(0.15), in: Circle())
                            Text("挂断")
                        }
                    }
                    Button(action: onAccept) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 64, height: 64)
                                .background(Color(red: 0.92, green: 0.55, blue: 0.57), in: Circle())
                            Text("接听")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .foregroundStyle(Color.black.opacity(0.78))
        .preferredColorScheme(.light)
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
    @State private var didFinishCall = false
    @StateObject private var player = SpatialSpeechPlayback()
    @StateObject private var speechRecognition = CallSpeechRecognition()
    let incomingCallID: String?
    let onRejected: (ChatMessage, ChatMessage?) -> Void
    let onEnded: (ChatMessage?) -> Void

    var body: some View {
        ZStack {
            LumiPalette.chatBackground.ignoresSafeArea()

            if phase == .requesting && incomingCallID == nil {
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
        .task {
            if incomingCallID != nil {
                phase = .connected
                generatingReply = true
            }
            await requestCall()
        }
        .onChange(of: muted) { _, isMuted in
            if isMuted { speechRecognition.stop() }
            else { startListeningIfNeeded() }
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if !isPlaying { startListeningIfNeeded() }
        }
        .onDisappear {
            speechRecognition.stop()
            Task { await finishCallIfNeeded() }
        }
    }

    private var requestingCall: some View {
        VStack(spacing: 0) {
            HStack {
                Button { Task { await leaveCall() } } label: {
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
            Text(incomingCallID == nil ? "正在呼叫" : "正在接听")
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
                Button { Task { await leaveCall() } } label: {
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
                .offset(y: -14)
            if let requestError {
                Text(requestError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.20, blue: 0.26))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }
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
                    callAction(title: "挂断", icon: "phone.down.fill", color: Color(red: 0.92, green: 0.25, blue: 0.31)) { Task { await leaveCall() } }
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
                    .background(selected ? Color.black.opacity(0.10) : .white.opacity(0.64), in: Circle())
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
        if key.isEmpty { requestError = "请先在设置中填写 MiniMax API Key，否则电话不会生成语音" }
        let tts = !key.isEmpty
            ? TTSRequestSettings(apiKey: key, model: ttsModel, voiceID: ttsVoiceID, baseURL: ttsHost, enabled: true)
            : nil
        do {
            let response: CallStartResponse
            if let incomingCallID {
                response = try await LumiAPIClient().answerIncomingCall(incomingCallID, action: "accept", to: "default", tts: tts)
            } else {
                response = try await LumiAPIClient().startCall(to: "default", tts: tts)
            }
            guard response.status == "accepted" else {
                if let message = response.assistantMessage { onRejected(message, response.callStatusMessage) }
                dismiss()
                return
            }
            callStartedAt = .now
            callID = response.callId
            let openingBubbles = response.firstMessage.map { splitAssistantTurn($0) } ?? []
            turns = openingBubbles
            phase = .connected
            generatingReply = false
            if let encoded = response.speechAudioBase64, let data = Data(base64Encoded: encoded) {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("call-opening-\(response.callId).mp3")
                try? data.write(to: url, options: .atomic)
                CallAudioStore.save(callID: response.callId, fileName: url.lastPathComponent, script: response.speechScript ?? response.firstMessage?.content ?? "", duration: response.speechDuration)
                for bubble in openingBubbles { callAudioFiles[bubble.id] = url }
                player.play(url: url, script: response.speechScript ?? response.firstMessage?.content ?? "")
            } else if let speechError = response.speechError {
                requestError = "AI 已接通，但 MiniMax 没有返回语音：\(speechError)"
            }
            startListeningIfNeeded()
        } catch {
            generatingReply = false
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
        if key.isEmpty { requestError = "请先在设置中填写 MiniMax API Key，否则电话不会生成语音" }
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
                CallAudioStore.save(callID: callID, fileName: url.lastPathComponent, script: response.speechScript ?? response.assistantTurn.content, duration: response.speechDuration)
                for bubble in assistantBubbles { callAudioFiles[bubble.id] = url }
                player.play(url: url, script: response.speechScript ?? response.assistantTurn.content)
            } else if let speechError = response.speechError {
                requestError = "这次回复没有语音：\(speechError)"
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

    private func leaveCall() async {
        await finishCallIfNeeded()
        dismiss()
    }

    private func finishCallIfNeeded() async {
        guard !didFinishCall, let callID else { return }
        didFinishCall = true
        do {
            let response = try await LumiAPIClient().endCall(callID, to: "default")
            onEnded(response.recordMessage)
        } catch {
            requestError = error.localizedDescription
        }
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
                    .fill(Color.black.opacity(0.52))
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
