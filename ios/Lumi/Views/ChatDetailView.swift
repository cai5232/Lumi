Warning: truncated output (original token count: 45625)
Total output lines: 3749

import SwiftUI
import Translation
import UIKit
import UserNotifications
import PhotosUI
import AVFoundation
import Speech
import WebKit
import UniformTypeIdentifiers

private struct ChatHistoryTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = -.greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel
    @StateObject private var musicModel = TogetherListenChatPlayback.shared
    var onClose: (() -> Void)? = nil
    @StateObject private var glassPresentation = GlassComparisonPresentation()
    @State private var showingSettings = false
    @State private var htmlMessage: ChatMessage?
    @State private var fullScreenHTMLMessage: ChatMessage?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImageData: [Data] = []
    @State private var selectedImageNames: [String] = []
    @State private var selectedGalleryItem: RemoteGalleryItem?
    @State private var showingCallDemo = false
    @State private var incomingCallID: String?
    @State private var localSystemCallID: String?
    @State private var screenRequestPending = false
    @State private var selectedCallRecord: ChatMessage?
    @State private var showingSubscriptionUsage = false
    @State private var showingTogether = false
    @State private var historyPagingArmed = false
    @State private var historyPagingPrimed = false
    @State private var didInitialScroll = false
    @AppStorage("lumi.ttsEnabled") private var ttsEnabled = false

    init(model: ChatViewModel? = nil, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: model ?? ChatViewModel())
        self.onClose = onClose
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
                            if message.contentType != "together_watch" {
                                if shouldShowTimeDivider(at: index) {
                                    timeDivider(for: message.createdAt)
                                }
                                messageBubble(message, showAvatar: shouldShowAvatar(at: index))
                            }
                        }
                        if model.isSending { thinkingBubble }
                    }
                    .animation(.easeOut(duration: 0.24), value: model.messages.count)
                    .padding(.horizontal, 16)
                    .padding(.top, 184)
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
                    LinearGradient(
                        stops: [
                            .init(color: LumiPalette.chatBackground.opacity(0.98), location: 0),
                            .init(color: LumiPalette.chatBackground.opacity(0.84), location: 0.48),
                            .init(color: LumiPalette.chatBackground.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(geometry.safeAreaInsets.top, 44) + 165)
                    .blur(radius: 18)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                    topBar
                        .padding(.top, max(geometry.safeAreaInsets.top, 44) + 12)
                        .frame(width: geometry.size.width, alignment: .top)
                        .zIndex(5)
                }
            }
        }
        .foregroundStyle(LumiPalette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
                .padding(.top, 5)
                .background(.clear)
                .background(alignment: .top) {
                    LinearGradient(
                        stops: [
                            .init(color: LumiPalette.chatBackground.opacity(0), location: 0),
                            .init(color: LumiPalette.chatBackground.opacity(0.80), location: 0.58),
                            .init(color: LumiPalette.chatBackground.opacity(0.98), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 84)
                    .blur(radius: 18)
                    .offset(y: -42)
                    .allowsHitTesting(false)
                }
        }
        .task {
            await model.load()
            await pollIncomingCall()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiRemoteMessageReceived"))) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiIncomingCall"))) { _ in
            Task { await reportPendingSystemCall() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiNativeCallAnswered"))) { notification in
            guard let callID = notification.object as? String else { return }
            if LumiNativeCalls.shared.isLocallyInitiatedCall(callID) {
                localSystemCallID = callID
                incomingCallID = nil
            } else {
                incomingCallID = callID
            }
            showingCallDemo = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiNativeCallEnded"))) { _ in
            showingCallDemo = false
        }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiScreenRequest"))) { _ in
            // ReplayKit consent can only be shown after a foreground user action.
            // Keep the request visible in the chat and expose the real system picker.
            screenRequestPending = true
        }
        .onAppear {
            if UserDefaults.standard.bool(forKey: "lumi.screenRequestPending") {
                screenRequestPending = true
                UserDefaults.standard.removeObject(forKey: "lumi.screenRequestPending")
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
            TogetherView(
                onUseInChat: { item in selectedGalleryItem = item },
                onAskAboutVideo: { watchID, text, imageBase64 in
                    if model.messages.isEmpty { await model.load() }
                    return await model.sendWatchMessage(text, imageBase64: imageBase64)
                }
            )
        }
        .overlay {
            if screenRequestPending {
                screenShareRequestOverlay
            }
        }
        .sheet(isPresented: $glassPresentation.showingThinkingDetails) {
            ThinkingDetailsSheetView(text: glassPresentation.thinkingText) { height in
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
        .fullScreenCover(item: $selectedCallRecord) { record in
            CallRecordView(record: record)
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
        VStack(spacing: 9) {
            topBarButtons
            if let song = musicModel.current, musicModel.isPlaying {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: song.cover)) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Image(systemName: "music.note").foregroundStyle(LumiPalette.iconPink).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.72)) }
                    }
                    .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(song.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("· \(song.artist)").font(.system(size: 10)).foregroundStyle(LumiPalette.textSecondary).lineLimit(1)
                        }
                        Text(musicModel.currentLyricText.isEmpty ? "正在一起听" : musicModel.currentLyricText)
                            .font(.system(size: 10)).foregroundStyle(LumiPalette.textSecondary).lineLimit(1)
                        Slider(value: Binding(get: { musicModel.position }, set: { musicModel.seek($0) }), in: 0...max(1, Double(song.durationSeconds)))
                            .tint(LumiPalette.iconPink)
                    }
                    Button { musicModel.togglePlayback() } label: {
                        Image(systemName: "pause.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(LumiPalette.iconPink)
                    }.buttonStyle(.plain).padding(.horizontal, 4)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(LumiLiquidGlass(shape: RoundedRectangle(cornerRadius: 15, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.65), lineWidth: 1))
                .padding(.horizontal, 18)
            }
        }
    }

    private var topBarButtons: some View {
        HStack(spacing: 0) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LumiPalette.iconPink)
                        .frame(width: 42, height: 42)
                        .background { LumiLiquidGlass(shape: Circle()) }
                        .overlay(Circle().stroke(.white.opacity(0.64), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回桌面")
                .zIndex(10)
            }
            Spacer(minLength: 12)
            Text("沈屿")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LumiPalette.textPrimary)
                .frame(width: 184, height: 44)
                .background { LumiLiquidGlass(shape: Capsule()) }
                .overlay(Capsule().stroke(.white.opacity(0.64), lineWidth: 1))
                .onTapGesture { showingTogether = true }

            Spacer(minLength: 12)

            Button { LumiNativeCalls.shared.startAIInitiatedCall() } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LumiPalette.iconPink)
                    .frame(width: 42, height: 42)
                    .background { LumiLiquidGlass(shape: Circle()) }
                    .overlay(Circle().stroke(.white.opacity(0.64), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("让沈屿给我打电话")
            .fullScreenCover(isPresented: $showingCallDemo) {
                CallDemoView(
                    incomingCallID: incomingCallID,
                    onRejected: { message, statusMessage in
                        model.receiveCallOutcome(message, statusMessage: statusMessage)
                        endLocalSystemCall()
                    },
                    onEnded: { record in
                        incomingCallID = nil
                        endLocalSystemCall()
                        if let record { model.receiveCallRecord(record) }
                    }
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private var composer: some View {
        ComposerInputView(
            selectedImageData: $selectedImageData,
            selectedImageNames: $selectedImageNames,
            selectedGalleryItem: $selectedGalleryItem,
            photoItems: $photoItems,
            onSend: { text in
                Task { await sendDraft(text: text) }
            }
        )
    }

    private func pollIncomingCall() async {
        while !Task.isCancelled {
            await reportPendingSystemCall()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func reportPendingSystemCall() async {
        guard !showingCallDemo else { return }
        do {
            guard let call = try await LumiAPIClient().fetchIncomingCall(from: "default") else { return }
            LumiNativeCalls.shared.reportServerIncomingCall(call.callId)
        } catch {
            // A transient poll error should not interrupt the chat.
        }
    }

    private func endLocalSystemCall() {
        guard let callID = localSystemCallID else { return }
        localSystemCallID = nil
        LumiNativeCalls.shared.end(callID)
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

    private var screenShareRequestOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("沈屿想看你的屏幕")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("点击下方按钮后，系统会弹出屏幕广播确认。iOS 不允许应用在后台替你自动确认。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                BroadcastPickerView(preferredExtension: "com.cai5232.Lumi.BroadcastUpload")
                    .frame(width: 56, height: 56)
                    .background(Color(red: 0.91, green: 0.58, blue: 0.68), in: Circle())
                    .overlay {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .allowsHitTesting(false)
                    }
                Button("稍后") {
                    screenRequestPending = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .transition(.opacity)
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
        let isScreenRequest = message.contentType == "screen_request"
        let isScreenStatus = message.contentType == "screen_status"
        let isUserSide = message.callInitiator == "user" || (message.callInitiator == nil && message.role == .user)
        VStack(alignment: isUserSide ? .trailing : .leading, spacing: 5) {
            let imageNames = message.localImageFileNames.isEmpty ? message.localImageFileName.map { [$0] } ?? [] : message.localImageFileNames
            if !isGalleryCollection, !imageNames.isEmpty {
                LocalPhotoStack(fileNames: imageNames)
            }
            HStack(alignment: .top) {
                if !isUserSide {
                    if showAvatar {
                        Button {
                            glassPresentation.thinkingText = thinkingText(for: message) ?? "这条回复没有保存心声内容。"
                            glassPresentation.showingThinkingDetails = true
                        } label: { assistantAvatar(for: message) }
                        .buttonStyle(.plain)
                    } else { Color.clear.frame(width: 42, height: 42) }
                }
                if isUserSide { Spacer(minLength: 48) }
                VStack(alignment: .leading, spacing: 7) {
                    if isScreenRequest {
                        Text("沈屿想看你的屏幕")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(LumiPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.92), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if isScreenStatus {
                        Text("已拒绝")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(LumiPalette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.92), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if isGalleryCollection,
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
                .padding(.horizontal, isGalleryCollection || isScreenRequest || isScreenStatus ? 0 : (isHTMLCard ? 8 : (isCallStatus ? 10 : 13)))
                .padding(.vertical, isGalleryCollection || isScreenRequest || isScreenStatus ? 0 : (isHTMLCard ? 5 : ((isCallStatus || isCallRecord) ? 0 : (message.audioFileName == nil ? 10 : 3))))
                .frame(width: isGalleryCollection ? 284 : ((isScreenRequest || isScreenStatus) ? nil : (message.audioFileName == nil ? nil : min(300, max(180, 150 + CGFloat(message.speechDuration ?? 2) * 8)))), alignment: .leading)
                .background(isGalleryCollection || isScreenRequest || isScreenStatus ? .clear : (isUserSide ? LumiPalette.userBubble : .white))
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
        guard !text.isEmpty || !selectedImageData.isEmpty || selectedGalleryItem != nil else { return }
        model.draft = text
        let imagesBase64 = selectedImageData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let asksToSing = text.range(of: #"(唱歌|唱一首|唱首歌|哼唱|唱给我听|用歌声|sing(?:\s+a)?\s+song)"#, options: .caseInsensitive) != nil
        let tts = makeTTSSettings(enabled: ttsEnabled || asksToSing)
        let catalogData = UserDefaults.standard.string(forKey: "lumi.emojiCatalogJSON")?.data(using: .utf8) ?? Data("[]".utf8)
        let entries = (try? JSONDecoder().decode([EmojiEntry].self, from: catalogData)) ?? []
        let catalog = Dictionary(grouping: entries, by: \.mood).mapValues { $0.map(\.face) }
        let musicContext = await musicModel.chatContext()
        await model.send(imagesBase64: imagesBase64, imageFileNames: selectedImageNames, galleryImageIDs: selectedGalleryItem.map { [$0.id] } ?? [], tts: tts, emojiCatalog: catalog, context: musicContext)
        selectedImageData = []
        selectedImageNames = []
        selectedGalleryItem = nil
        photoItems = []
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
    @Binding var selectedImageData: [Data]
    @Binding var selectedImageNames: [String]
    @Binding var selectedGalleryItem: RemoteGalleryItem?
    @Binding var photoItems: [PhotosPickerItem]
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
            if !selectedImageData.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImageData.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            selectedImageData.remove(at: index)
                                            if selectedImageNames.indices.contains(index) { selectedImageNames.remove(at: index) }
                                            photoItems = []
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, .black.opacity(0.46))
                                        }
                                        .offset(x: 5, y: -5)
                                    }
                            }
                        }
                        Text("\(selectedImageData.count)/4")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.42))
                    }
                }
                .padding(.horizontal, 4)
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 7) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LumiPalette.iconPink)
                        .frame(width: 38, height: 38)
                        .background { LumiLiquidGlass(shape: Circle()) }
                        .overlay(Circle().stroke(.white.opacity(0.64), lineWidth: 1))
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    TextField("写给沈屿…", text: $text)
                        .focused($focused)
                        .foregroundStyle(LumiPalette.textPrimary)
                        .tint(LumiPalette.iconPink)
                        .lineLimit(1)
                        .submitLabel(.send)
                        .onSubmit {
                            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if value.isEmpty && selectedImageData.isEmpty && selectedGalleryItem == nil {
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
                .background { LumiLiquidGlass(shape: Capsule()) }
                .overlay(Capsule().stroke(.white.opacity(0.64), lineWidth: 1))

                Button {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty || !selectedImageData.isEmpty || selectedGalleryItem != nil else { return }
                    text = ""
                    onSend(value)
                    focused = false
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LumiPalette.iconPink)
                        .frame(width: 38, height: 38)
                        .background { LumiLiquidGlass(shape: Circle()) }
                        .overlay(Circle().stroke(.white.opacity(0.64), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("发送")
            }
        }
        .frame(height: selectedImageData.isEmpty && selectedGalleryItem == nil ? 42 : 104)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loadedData: [Data] = []
                var loadedNames: [String] = []
                for item in items.prefix(4) {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = compactUploadData(from: image) else { continue }
                    let name = "image-\(UUID().uuidString).jpg"
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
                    guard (try? jpeg.write(to: url, options: .atomic)) != nil else { continue }
                    loadedData.append(jpeg)
                    loadedNames.append(name)
                }
                await MainActor.run {
                    selectedImageData = loadedData
                    selectedImageNames = loadedNames
                }
            }
        }
    }

    private func compactUploadData(from image: UIImage) -> Data? {
        let sourceWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let sourceHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let scale = min(1, 2048 / max(max(sourceWidth, sourceHeight), 1))
        let size = CGSize(width: (sourceWidth * scale).rounded(), height: (sourceHeight * scale).rounded())
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.jpegData(compressionQuality: 0.80)
    }
}

private struct LocalPhotoStack: View {
    let fileNames: [String]
    private let cardSize = CGSize(width: 172, height: 148)
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var incomingFromRight = true

    var body: some View {
        let count = min(fileNames.count, 4)
        let safeCount = max(count, 1)
        let frontIndex = currentIndex % safeCount
        let incomingEdge: Edge = incomingFromRight ? .trailing : .leading
        let outgoingEdge: Edge = incomingFromRight ? .leading : .trailing
        return VStack(spacing: 5) {
            ZStack(alignment: .center) {
                ForEach(0..<max(0, count - 1), id: \.self) { layer in
                    let depth = layer + 1
                    let index = (frontIndex + depth) % safeCount
                    let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    let imageURL = documentDirectory?.appendingPathComponent(fileNames[index])
                    let frontURL = documentDirectory?.appendingPathComponent(fileNames[frontIndex])
                    let image = imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
                        ?? frontURL.flatMap { UIImage(contentsOfFile: $0.path) }
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardSize.width, height: cardSize.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.92), lineWidth: 3))
                            .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
                            .rotationEffect(.degrees(Double(depth) * 5))
                            .offset(x: CGFloat(depth) * 22, y: CGFloat(depth) * 6)
                            .zIndex(Double(count - depth))
                    }
                }
                if count > 0,
                   let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                   let image = UIImage(contentsOfFile: documentDirectory.appendingPathComponent(fileNames[frontIndex]).path) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: cardSize.width, height: cardSize.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.94), lineWidth: 3))
                        .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
                        .offset(x: dragOffset)
                        .transition(.asymmetric(
                            insertion: .move(edge: incomingEdge).combined(with: .opacity),
                            removal: .move(edge: outgoingEdge).combined(with: .opacity)
                        ))
                        .zIndex(10)
                        .gesture(DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                guard count > 1, abs(value.translation.width) > 50,
                                      abs(value.translation.width) > abs(value.translation.height) else {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { dragOffset = 0 }
                                    return
                                }
                                let towardNext = value.translation.width < 0
                                incomingFromRight = towardNext
                                withAnimation(.easeOut(duration: 0.16)) {
                                    dragOffset = towardNext ? -cardSize.width : cardSize.width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                                        currentIndex = towardNext ? (frontIndex + 1) % count : (frontIndex - 1 + count) % count
                                        dragOffset = 0
                                    }
                                }
                            }
                        )
                }
            }
            .frame(width: cardSize.width + CGFloat(max(0, count - 1)) * 22, height: cardSize.height + CGFloat(max(0, count - 1)) * 12)
            .contentShape(Rectangle())
            .onChange(of: fileNames) { _, _ in currentIndex = 0; dragOffset = 0 }
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: currentIndex)
            if count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? LumiPalette.iconPink : .black.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                    Text("\(currentIndex + 1)/\(count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.42))
                        .padding(.leading, 2)
                }
            }
        }
        .frame(width: cardSize.width + CGFloat(max(0, count - 1)) * 22, height: cardSize.height + (count > 1 ? 24 : 10))
    }
}

private enum LumiPalette {
    static let chatBackground = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let userBubble = Color(red: 0.9608, green: 0.9255, blue: 0.9255)
    static let iconPink = Color(red: 0.955, green: 0.745, blue: 0.800)
    static let textPrimary = Color(red: 0.20, green: 0.17, blue: 0.19)
    static let textSecondary = Color(red: 0.36, green: 0.31, blue: 0.34)
}

private struct LumiLiquidGlass<S: Shape>: View {
    let shape: S

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.white.opacity(0.62)), in: shape)
                .allowsHitTesting(false)
        } else {
            shape.fill(Color.white.opacity(0.64)).allowsHitTesting(false)
        }
    }
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
                    Text((message.speechScript ?? message.content).replacingOccurrences(of: #"\[(?:左耳|右耳|脑后|面前|贴近|退开|singing)\]"#, with: "", options: [.regularExpression, .caseInsensitive]))
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

struct SettingsView: View {
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
    @State private var showingVoiceSettings = false
    @AppStorage("lumi.ttsProvider") private var ttsProvider = "minimax"
    @State private var pushAPIToken = LumiKeychain.read(account: "push-api-token")
    private let api = LumiAPIClient()

    var body: some View {
        NavigationStack {
            List {
                Section("语音") {
                    Button { showingVoiceSettings = true } label: {
                        settingsCard(title: "语音设置", subtitle: "\(ttsProvider == "elevenlabs" ? "ElevenLabs" : "MiniMax") · 选择服务、模型和音色", icon: "waveform")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(destination: EmojiManagementView()) {
                        settingsCard(title: "颜文字管理", subtitle: "按心情整理，供沈屿自然选用", icon: "face.smiling")
                    }
                }

                Section("世界书") {
                    NavigationLink(destination: LumiWorldBookView()) {
                        settingsCard(title: "世界书管理", subtitle: "添加设定、编辑触发规则、导入和导出", icon: "books.vertical")
                    }
                }

                Section("工具") {
                    NavigationLink(destination: McpSettingsView()) {
                        settingsCard(title: "MCP 工具", subtitle: "连接服务器、管理工具并供聊天调用", icon: "point.3.connected.trianglepath.dotted")
                    }
                }

                Section("模型线路") {
                    NavigationLink(destination: LumiAPIProvidersView()) {
                        settingsCard(
                            title: "API 预设与线路",
                            subtitle: activeAPIProviderSummary,
                            icon: "point.3.connected.trianglepath.dotted"
                        )
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

                    VStack(alignment: .leading, spacing: 0) {
                        Text("AI 醒来后可以做什么")
                            .font(.system(size: 14, weight: .medium))…5625 tokens truncated…smiss() }
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

private struct ThinkingDetailsSheetView: View {
    let text: String
    let onHeightChange: (CGFloat) -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *) {
            ThinkingDetailsView(text: text, onHeightChange: onHeightChange)
        } else {
            ThinkingDetailsLegacyView(text: text, onHeightChange: onHeightChange)
        }
    }
}

@available(iOS 18.0, *)
private struct ThinkingDetailsView: View {
    let text: String
    let onHeightChange: (CGFloat) -> Void
    private let horizontalPadding: CGFloat = 24
    private let verticalPadding: CGFloat = 26
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translatedText: String?
    @State private var translationError: String?
    @State private var isTranslating = false

    private var displayedText: String { translatedText ?? text }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Text("Thought process")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.black)
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            if translatedText != nil {
                                translatedText = nil
                            } else if translationConfiguration == nil {
                                translationError = nil
                                isTranslating = true
                                translationConfiguration = TranslationSession.Configuration(
                                    source: nil,
                                    target: Locale.Language(identifier: "zh-Hans")
                                )
                            }
                        } label: {
                            Group {
                                if isTranslating {
                                    ProgressView().tint(LumiPalette.iconPink)
                                } else {
                                    Image(systemName: translatedText == nil ? "translate" : "arrow.uturn.backward")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(LumiPalette.iconPink)
                                }
                            }
                            .frame(width: 38, height: 38)
                            .background(.white, in: Circle())
                            .overlay(Circle().stroke(LumiPalette.iconPink.opacity(0.20), lineWidth: 1))
                            .shadow(color: LumiPalette.iconPink.opacity(0.12), radius: 7, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isTranslating)
                        .accessibilityLabel(isTranslating ? "正在翻译" : (translatedText == nil ? "翻译成中文" : "显示原文"))
                    }
                }
                Text(displayedText)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(6)
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ThinkingTextHeightKey.self, value: proxy.size.height)
                        }
                    }
                if let translationError {
                    Text(translationError)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumiPalette.chatBackground)
        .onPreferenceChange(ThinkingTextHeightKey.self) { textHeight in
            let desired = textHeight + 36 + verticalPadding * 2
            let screenLimit = UIScreen.main.bounds.height * 0.88
            onHeightChange(min(max(desired, 220), screenLimit))
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(text)
                translatedText = response.targetText
                translationError = nil
            } catch {
                translationError = "系统翻译暂不可用，请稍后重试。"
                translationConfiguration = nil
            }
            isTranslating = false
        }
    }
}

private struct ThinkingDetailsLegacyView: View {
    let text: String
    let onHeightChange: (CGFloat) -> Void

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
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumiPalette.chatBackground)
        .onPreferenceChange(ThinkingTextHeightKey.self) { textHeight in
            let desired = textHeight + 19 + 24 + 52
            onHeightChange(min(max(desired, 220), UIScreen.main.bounds.height * 0.88))
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
        let tts = makeTTSSettings(enabled: true)
        if tts == nil { requestError = "请先在语音设置中填写所选服务的 API Key 和 Voice ID" }
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
                requestError = "AI 已接通，但语音服务没有返回音频：\(speechError)"
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
        let tts = makeTTSSettings(enabled: true)
        if tts == nil { requestError = "请先在语音设置中填写所选服务的 API Key 和 Voice ID" }
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

struct LumiWorldBookSettings: Codable {
    var books: [LumiWorldBook] = []
    var activeBookIds: [String] = []
    var revision: Int = 0
}
struct LumiWorldBookSelection: Codable { var bookIds: [String]? }
struct LumiWorldBook: Codable, Identifiable {
    var id = UUID().uuidString
    var name = "新世界书"
    var description = ""
    var enabled = true
    var entries: [LumiWorldBookEntry] = []
}
struct LumiWorldBookEntry: Codable, Identifiable {
    var id = UUID().uuidString
    var name = "新条目"
    var enabled = true
    var priority = 0
    var position = "AFTER_SYSTEM_PROMPT"
    var content = ""
    var injectDepth = 4
    var role = "USER"
    var keywords: [String] = []
    var useRegex = false
    var caseSensitive = false
    var scanDepth = 4
    var constantActive = false
    var sticky = 0
    var cooldown = 0
    var delay = 0
}
private struct LumiWorldBookDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
private struct LumiWorldBookView: View {
    @State private var settings = LumiWorldBookSettings()
    @State private var baseline = LumiWorldBookSettings()
    @State private var baselineSelection = LumiWorldBookSelection(bookIds: nil)
    @State private var selection = LumiWorldBookSelection(bookIds: nil)
    @State private var loaded = false
    @State private var busy = false
    @State private var status = "正在读取世界书…"
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = LumiWorldBookDocument(data: Data())
    @State private var previewText = ""
    @State private var confirmingRefresh = false
    private let api = LumiAPIClient()
    private var dirty: Bool { (try? JSONEncoder().encode(settings)) != (try? JSONEncoder().encode(baseline)) || selection.bookIds != baselineSelection.bookIds }
    var body: some View {
        List {
            Section {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                if loaded {
                    Text(dirty ? "有未保存的修改；保存后同步到后端。" : "已与后端同步。")
                        .font(.footnote).foregroundStyle(dirty ? Color.orange : Color.secondary)
                }
            }
            if loaded {
                Section("当前聊天") {
                    Toggle("使用全局选择", isOn: Binding(get: { selection.bookIds == nil }, set: { selection.bookIds = $0 ? nil : settings.activeBookIds }))
                    Text("全局选择适用于聊天和主动联系；关闭后可只为当前聊天选择世界书。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("世界书 · \(settings.books.count)") {
                    ForEach($settings.books) { $book in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { LumiWorldBookEditor(book: $book) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name.isEmpty ? "未命名世界书" : book.name)
                                    Text("\(book.entries.filter { $0.enabled }.count)/\(book.entries.count) 个条目启用")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Toggle("全局选用", isOn: activeBinding(book.id)).disabled(!book.enabled)
                            if selection.bookIds != nil {
                                Toggle("当前聊天选用", isOn: localBinding(book.id)).disabled(!book.enabled)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { settings.books[$0].id }
                        settings.books.remove(atOffsets: offsets)
                        settings.activeBookIds.removeAll { ids.contains($0) }
                        selection.bookIds?.removeAll { ids.contains($0) }
                    }
                    .onMove { settings.books.move(fromOffsets: $0, toOffset: $1) }
                    Button { settings.books.append(LumiWorldBook()) } label: { Label("添加世界书", systemImage: "plus") }
                }
                Section("文件") {
                    Button("导入 Kelivo 世界书 JSON") { importing = true }
                    Button("导出全部世界书") {
                        do {
                            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            exportDocument = LumiWorldBookDocument(data: try encoder.encode(settings.books)); exporting = true
                        } catch { status = error.localizedDescription }
                    }
                }
                Section("触发预览") {
                    TextField("输入一段聊天内容", text: $previewText, axis: .vertical)
                    ForEach(previewEntries) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.subheadline.bold())
                            Text(entry.content).font(.caption).lineLimit(4)
                        }
                    }
                    Text("预览检查关键词或常驻匹配；实际持续、冷却、延迟按服务器聊天记录计算。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .modifier(LumiWorldBookPageStyle())
        .navigationTitle("世界书")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(!loaded || busy) }
            ToolbarItem(placement: .bottomBar) {
                Button(busy ? "同步中…" : "保存到后端") { Task { await save() } }.disabled(!loaded || busy)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("刷新") { if dirty { confirmingRefresh = true } else { Task { await load() } } }.disabled(busy)
            }
        }
        .task { if !loaded { await load() } }
        .confirmationDialog("放弃本页尚未保存的修改并刷新？", isPresented: $confirmingRefresh, titleVisibility: .visible) {
            Button("放弃修改并刷新", role: .destructive) { Task { await load() } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try importBooks(Data(contentsOf: url)); status = "已导入；点击保存同步到后端。"
            } catch { status = "导入失败：\(error.localizedDescription)" }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Lumi-世界书") { result in
            if case .failure(let error) = result { status = error.localizedDescription }
        }
    }
    private func activeBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.activeBookIds.contains(id) }, set: { value in
            settings.activeBookIds.removeAll { $0 == id }; if value { settings.activeBookIds.append(id) }
        })
    }
    private func localBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { selection.bookIds?.contains(id) ?? false }, set: { value in
            selection.bookIds?.removeAll { $0 == id }; if value { selection.bookIds?.append(id) }
        })
    }
    private var previewEntries: [LumiWorldBookEntry] {
        let ids = selection.bookIds ?? settings.activeBookIds
        return settings.books.filter { $0.enabled && ids.contains($0.id) }.flatMap(\.entries).filter { e in
            guard e.enabled && !e.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if e.constantActive { return true }
            return e.keywords.contains { keyword in
                if e.useRegex { return previewText.range(of: keyword, options: e.caseSensitive ? [.regularExpression] : [.regularExpression, .caseInsensitive]) != nil }
                return previewText.range(of: keyword, options: e.caseSensitive ? [] : [.caseInsensitive]) != nil
            }
        }.sorted { $0.priority > $1.priority }
    }
    @MainActor private func load() async {
        busy = true; defer { busy = false }
        do {
            let remote = try await api.fetchWorldBooks()
            let local = try await api.fetchWorldBookSelection()
            settings = remote; baseline = remote; selection = local; baselineSelection = local; loaded = true; status = "可以自行添加和编辑世界书。"
        } catch { status = "读取失败：\(error.localizedDescription)。请检查设置中的后端口令。" }
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }
        do {
            settings.activeBookIds = settings.activeBookIds.filter { id in settings.books.contains { $0.id == id && $0.enabled } }
            selection.bookIds = selection.bookIds.map { ids in ids.filter { id in settings.books.contains { $0.id == id && $0.enabled } } }
            settings = try await api.saveWorldBooks(settings); baseline = settings
            try await api.saveWorldBookSelection(selection)
            baselineSelection = selection
            status = "已保存，下一轮聊天开始生效。"
        } catch { status = "保存失败：\(error.localizedDescription)。本页修改仍保留。" }
    }
    private func importBooks(_ data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data)
        let books: [[String: Any]]
        if let array = raw as? [[String: Any]] { books = array }
        else if let object = raw as? [String: Any], let array = object["books"] as? [[String: Any]] { books = array }
        else if let object = raw as? [String: Any], object["entries"] is [Any] { books = [object] }
        else { throw LumiAPIError.server("需要 Kelivo 世界书 JSON") }
        guard books.count + settings.books.count <= 200 else { throw LumiAPIError.server("最多 200 本世界书") }
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var imported: [LumiWorldBook] = []
        for book in books {
            var normalized = try JSONSerialization.jsonObject(with: encoder.encode(LumiWorldBook())) as! [String: Any]
            normalized.merge(book) { _, new in new }; normalized["id"] = UUID().uuidString
            guard let entries = book["entries"] as? [[String: Any]], entries.count <= 2000 else { throw LumiAPIError.server("条目格式无效或超过 2000 条") }
            normalized["entries"] = try entries.map { entry in
                var item = try JSONSerialization.jsonObject(with: encoder.encode(LumiWorldBookEntry())) as! [String: Any]
                item.merge(entry) { _, new in new }; item["id"] = UUID().uuidString; return item
            }
            imported.append(try decoder.decode(LumiWorldBook.self, from: JSONSerialization.data(withJSONObject: normalized)))
        }
        settings.books.append(contentsOf: imported)
    }
}
private struct LumiWorldBookEditor: View {
    @Binding var book: LumiWorldBook
    var body: some View {
        List {
            Section("基本信息") {
                TextField("名称", text: $book.name)
                TextField("简介", text: $book.description, axis: .vertical)
                Toggle("启用世界书", isOn: $book.enabled)
            }
            Section("条目 · \(book.entries.count)") {
                ForEach($book.entries) { $entry in
                    NavigationLink { LumiWorldBookEntryEditor(entry: $entry) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name.isEmpty ? "未命名条目" : entry.name)
                            Text(entry.enabled ? (entry.constantActive ? "常驻 · 优先级 \(entry.priority)" : "\(entry.keywords.joined(separator: "、")) · 优先级 \(entry.priority)") : "已停用")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .onDelete { book.entries.remove(atOffsets: $0) }
                .onMove { book.entries.move(fromOffsets: $0, toOffset: $1) }
                Button { book.entries.append(LumiWorldBookEntry()) } label: { Label("添加条目", systemImage: "plus") }
            }
            Text("编辑完成后返回世界书列表，点击「保存到后端」。").font(.footnote).foregroundStyle(.secondary)
        }
        .modifier(LumiWorldBookPageStyle())
        .navigationTitle(book.name).toolbar { EditButton() }
    }
}
private struct LumiWorldBookEntryEditor: View {
    @Binding var entry: LumiWorldBookEntry
    private let positions = [("BEFORE_SYSTEM_PROMPT", "系统提示词之前"), ("AFTER_SYSTEM_PROMPT", "系统提示词之后"), ("TOP_OF_CHAT", "聊天顶部"), ("BOTTOM_OF_CHAT", "最后一条消息之前"), ("AT_DEPTH", "指定消息深度")]
    var body: some View {
        Form {
            Section("条目") {
                TextField("名称", text: $entry.name)
                Toggle("启用", isOn: $entry.enabled)
                TextEditor(text: $entry.content)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                Text("在这里填写角色、背景、事件或其他希望模型遵循的设定。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("触发") {
                Toggle("始终激活", isOn: $entry.constantActive)
                TextField("关键词，每行一个", text: Binding(get: { entry.keywords.joined(separator: "\n") }, set: { entry.keywords = $0.components(separatedBy: .newlines).filter { !$0.isEmpty } }), axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("使用正则表达式", isOn: $entry.useRegex)
                Toggle("区分大小写", isOn: $entry.caseSensitive)
                Stepper("扫描最近 \(entry.scanDepth) 条消息", value: $entry.scanDepth, in: 1...200)
            }
            Section("插入位置") {
                Picker("位置", selection: $entry.position) { ForEach(positions, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.menu)
                Picker("消息角色", selection: $entry.role) { Text("用户").tag("USER"); Text("助手").tag("ASSISTANT") }.pickerStyle(.menu)
                if entry.position == "AT_DEPTH" { Stepper("距结尾 \(entry.injectDepth) 条消息", value: $entry.injectDepth, in: 1...200) }
                Stepper("优先级 \(entry.priority)", value: $entry.priority, in: -10000...10000)
                Text("优先级越高越靠前；相同优先级遵循列表顺序。深度 1 表示最后一条消息之前。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("时间规则") {
                Stepper("持续 \(entry.sticky) 条消息", value: $entry.sticky, in: 0...10000)
                Stepper("冷却 \(entry.cooldown) 条消息", value: $entry.cooldown, in: 0...10000)
                Stepper("延迟 \(entry.delay) 条消息", value: $entry.delay, in: 0...10000)
                Text("按真实聊天消息数计算，用户和助手消息各计一条；0 表示关闭该规则。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .modifier(LumiWorldBookPageStyle())
        .navigationTitle("编辑条目")
    }
}

private struct LumiAPIProvidersView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.activeAPIProviderID") private var activeID = ""
    @AppStorage("lumi.modelProvider") private var selectedProvider = "zenmux"
    @AppStorage("lumi.apiProviderRouteExplicitlySelected") private var routeWasExplicitlySelected = false
    @State private var profiles: [LumiAPIProviderProfile] = []
    @State private var addingProvider = false

    var body: some View {
        List {
            Section {
                builtInRoute("ZenMux", id: "zenmux", detail: "使用 Lumi 服务端配置")

                if profiles.isEmpty {
                    ContentUnavailableView("还没有自定义 API 预设", systemImage: "point.3.connected.trianglepath.dotted", description: Text("可添加服务预设、填写 API Key 并获取模型列表。"))
                    .listRowBackground(Color.white.opacity(0.72))
                } else {
                    ForEach(profiles) { profile in
                        HStack(spacing: 10) {
                            Button {
                                activeID = profile.id
                                selectedProvider = "custom"
                                routeWasExplicitlySelected = true
                            } label: {
                                Image(systemName: activeID == profile.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(LumiPalette.iconPink)
                            }
                            .buttonStyle(.plain)
                            NavigationLink {
                                LumiAPIProviderEditor(profile: profile) { updated, key in
                                    save(updated, key: key)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(LumiPalette.textPrimary)
                                    Text("\(profile.preset) · \(profile.model.isEmpty ? "尚未选择模型" : profile.model)")
                                        .font(.system(size: 12)).foregroundStyle(LumiPalette.textSecondary).lineLimit(1)
                                }
                            }
                            .tint(LumiPalette.iconPink)
                        }
                        .listRowBackground(Color.white.opacity(0.76))
                    }
                    .onDelete(perform: delete)
                }
            } footer: {
                Text(activeID.isEmpty ? "普通聊天会使用 Lumi 服务端 ZenMux 配置。" : "当前自定义 API 仅用于普通聊天；API Key 保存在本机钥匙串。电话和后台主动任务仍使用 Lumi 服务端默认线路。")
                    .font(.system(size: 12))
                    .foregroundStyle(LumiPalette.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LumiPalette.chatBackground)
        .tint(LumiPalette.iconPink)
        .navigationTitle("API 预设与线路")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LumiPalette.chatBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingProvider = true } label: { Image(systemName: "plus").foregroundStyle(LumiPalette.iconPink) }
            }
        }
        .task { load() }
        .sheet(isPresented: $addingProvider) {
            NavigationStack {
                LumiAPIProviderEditor(profile: nil) { profile, key in save(profile, key: key) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(LumiPalette.chatBackground)
        }
    }

    private func builtInRoute(_ title: String, id: String, detail: String) -> some View {
        Button {
            activeID = ""
            selectedProvider = id
            routeWasExplicitlySelected = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: activeID.isEmpty && selectedProvider == id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(LumiPalette.iconPink)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(LumiPalette.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(LumiPalette.textSecondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.76))
    }

    private func load() {
        let data = UserDefaults.standard.data(forKey: "lumi.apiProviderProfiles")
        profiles = data.flatMap { try? JSONDecoder().decode([LumiAPIProviderProfile].self, from: $0) } ?? []
        if !activeID.isEmpty && profiles.contains(where: { $0.id == activeID }) {
            selectedProvider = "custom"
        } else if !routeWasExplicitlySelected && profiles.count == 1 {
            // Migrate a single saved frontend preset from builds that did not
            // persist the selected route consistently.
            activeID = profiles[0].id
            selectedProvider = "custom"
        } else {
            if !activeID.isEmpty { activeID = "" }
            if selectedProvider == "custom" { selectedProvider = "zenmux" }
            if selectedProvider == "backup" { selectedProvider = "zenmux" }
        }
    }

    private func save(_ profile: LumiAPIProviderProfile, key: String) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        LumiKeychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: profile.keychainAccount)
        activeID = profile.id
        selectedProvider = "custom"
        routeWasExplicitlySelected = true
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "lumi.apiProviderProfiles") }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let profile = profiles[index]
            LumiKeychain.write("", account: profile.keychainAccount)
            if activeID == profile.id { activeID = ""; selectedProvider = "zenmux"; routeWasExplicitlySelected = true }
        }
        profiles.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "lumi.apiProviderProfiles") }
    }
}

private struct LumiAPIProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existingID: String?
    let onSave: (LumiAPIProviderProfile, String) -> Void
    @State private var name: String
    @State private var preset: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var apiFormat: String
    @State private var chatPath: String
    @State private var models: [String]
    @State private var isLoadingModels = false
    @State private var errorMessage: String?

    init(profile: LumiAPIProviderProfile?, onSave: @escaping (LumiAPIProviderProfile, String) -> Void) {
        existingID = profile?.id
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "OpenAI")
        _preset = State(initialValue: profile?.preset ?? "OpenAI")
        _baseURL = State(initialValue: profile?.baseURL ?? "https://api.openai.com/v1")
        _apiKey = State(initialValue: profile.map { LumiKeychain.read(account: $0.keychainAccount) } ?? "")
        _model = State(initialValue: profile?.model ?? "")
        _models = State(initialValue: profile.map { $0.models.isEmpty && !$0.model.isEmpty ? [$0.model] : $0.models } ?? [])
        _apiFormat = State(initialValue: profile?.apiFormat ?? "openai")
        _chatPath = State(initialValue: profile?.chatPath ?? "/chat/completions")
    }

    var body: some View {
        Form {
            Section("服务预设") {
                Picker("预设", selection: $preset) {
                    ForEach(LumiAPIProviderPreset.values, id: \.name) { item in Text(item.name).tag(item.name) }
                }
                .onChange(of: preset) { oldValue, value in
                    let shouldRename = name == oldValue || name == "OpenAI"
                    applyPreset(value)
                    if shouldRename { name = value.replacingOccurrences(of: "自定义 ", with: "") }
                }
                TextField("线路名称", text: $name)
                TextField("API 基址", text: $baseURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Picker("API 协议", selection: $apiFormat) {
                    Text("OpenAI 兼容").tag("openai")
                    Text("Anthropic Claude").tag("anthropic")
                }
                .onChange(of: apiFormat) { _, value in chatPath = value == "anthropic" ? "/messages" : "/chat/completions" }
                TextField("聊天接口路径", text: $chatPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("认证和模型") {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack(spacing: 10) {
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        if isLoadingModels { ProgressView().tint(LumiPalette.iconPink) }
                        else { Label("获取模型", systemImage: "arrow.clockwise").labelStyle(.iconOnly).foregroundStyle(LumiPalette.iconPink) }
                    }
                    .disabled(isLoadingModels || apiKey.isEmpty || baseURL.isEmpty)
                }
                if !models.isEmpty {
                    ForEach(models, id: \.self) { item in
                        Button(item) { model = item }
                            .font(.system(size: 13)).foregroundStyle(LumiPalette.textSecondary)
                    }
                }
                Text("Key 仅保存在这台设备的钥匙串；获取模型会直接连接服务商。")
                    .font(.system(size: 12)).foregroundStyle(LumiPalette.textSecondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LumiPalette.chatBackground)
        .tint(LumiPalette.iconPink)
        .navigationTitle(existingID == nil ? "添加 API 线路" : "编辑 API 线路")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LumiPalette.chatBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(LumiPalette.textSecondary) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }.fontWeight(.semibold).foregroundStyle(LumiPalette.iconPink)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func applyPreset(_ selected: String) {
        guard let item = LumiAPIProviderPreset.values.first(where: { $0.name == selected }) else { return }
        baseURL = item.baseURL
        apiFormat = item.apiFormat
        chatPath = item.apiFormat == "anthropic" ? "/messages" : "/chat/completions"
    }

    private func fetchModels() async {
        isLoadingModels = true
        errorMessage = nil
        defer { isLoadingModels = false }
        do {
            models = try await LumiAPIModelCatalog.fetch(baseURL: baseURL, apiKey: apiKey, apiFormat: apiFormat)
            if models.isEmpty { errorMessage = "服务已响应，但没有返回可识别的模型列表；可以手动填写模型名称。" }
        } catch {
            errorMessage = "连接服务商失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        guard let parsed = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), parsed.scheme == "https", parsed.host != nil else {
            errorMessage = "请填写有效的 HTTPS API 基址。"
            return
        }
            let profile = LumiAPIProviderProfile(
                id: existingID ?? UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                preset: preset,
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                models: models,
                apiFormat: apiFormat,
                chatPath: chatPath.hasPrefix("/") ? chatPath : "/\(chatPath)"
            )
        onSave(profile, apiKey)
        dismiss()
    }
}

private struct LumiWorldBookPageStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(LumiPalette.chatBackground)
            .tint(Color(red: 0.66, green: 0.35, blue: 0.47))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LumiPalette.chatBackground, for: .navigationBar, .bottomBar)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .preferredColorScheme(.light)
    }
}
