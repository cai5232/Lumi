import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct ChatDetailView: View {
    @StateObject private var model: ChatViewModel
    @FocusState private var composerFocused: Bool
    @StateObject private var glassPresentation = GlassComparisonPresentation()
    @State private var showingSettings = false

    init(model: ChatViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ChatViewModel())
    }

    var body: some View {
        ZStack {
            Color(red: 0.984, green: 0.949, blue: 0.957).ignoresSafeArea()

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
                .presentationBackground(Color(red: 0.9608, green: 0.9255, blue: 0.9255))
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
            TextField("", text: $model.draft)
            .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
                .focused($composerFocused)
                .onTapGesture { composerFocused = true }
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                Spacer()
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 36)
                Button { Task { await model.send() } } label: {
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
            Text(visibleContent(message.content))
                .foregroundStyle(.black)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .font(.system(size: 14, weight: .regular))
                .background(message.role == .user ? Color(red: 0.9608, green: 0.9255, blue: 0.9255) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 21))
            if message.role == .assistant { Spacer(minLength: 48) }
            if message.role == .user {
                if showAvatar { avatar(for: .user) }
                else { Color.clear.frame(width: 42, height: 42) }
            }
        }
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
            HStack(spacing: 4) {
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
                Text("正在想")
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white)
            .clipShape(Capsule())
            Spacer()
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.proactiveNudgeEnabled") private var proactiveNudgeEnabled = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

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
                    Text("允许后，未来保活功能才能在你没有打开 App 时提醒你。")
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
        .task { await refreshNotificationStatus() }
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
        .background(Color(red: 0.9608, green: 0.9255, blue: 0.9255))
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
