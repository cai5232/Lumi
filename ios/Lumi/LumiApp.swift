import SwiftUI
import UIKit
import UserNotifications
import PushKit
import CallKit

@main
struct LumiApp: App {
    @UIApplicationDelegateAdaptor(LumiAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LumiRootView()
                .task {
                    while !Task.isCancelled {
                        if scenePhase == .active {
                            try? await LumiAPIClient().updateForegroundPresence(true)
                        }
                        try? await Task.sleep(for: .seconds(8))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    Task { try? await LumiAPIClient().updateForegroundPresence(phase == .active) }
                }
        }
    }
}

@MainActor
private struct LumiRootView: View {
    @StateObject private var model: ChatViewModel
    @State private var showingChat = false
    @State private var showingSettings = false
    @State private var showingFood = false
    @State private var showingGallery = false
    @State private var showingDiary = false
    @State private var showingTogetherWatch = false
    @State private var showingTogetherListen = false
    @State private var showingLettersMap = false
    @State private var showingCalendar = false

    init() {
        _model = StateObject(wrappedValue: ChatViewModel(
            initialMessages: [
                ChatMessage(id: UUID(), role: .assistant, content: "下午的风很轻，想和你说说话。", createdAt: .now),
                ChatMessage(id: UUID(), role: .user, content: "我在，慢慢说。", createdAt: .now),
                ChatMessage(id: UUID(), role: .assistant, content: "那就从窗边的云开始吧。", createdAt: .now)
            ],
            shouldLoadFromServer: true
        ))
    }

    var body: some View {
        LumiHomeView(openChat: { showingChat = true }, openSettings: { showingSettings = true }, openFood: { showingFood = true }, openGallery: { showingGallery = true }, openDiary: { showingDiary = true }, openTogetherWatch: { showingTogetherWatch = true }, openTogetherListen: { showingTogetherListen = true }, openLettersMap: { showingLettersMap = true }, openCalendar: { showingCalendar = true })
            .fullScreenCover(isPresented: $showingChat) {
                ZStack {
                    ChatDetailView(model: model, onClose: { showingChat = false })
                    DraggableClawdPet(assetName: model.isSending ? "clawd-working-thinking" : "clawd-idle-follow")
                }
            }
            .fullScreenCover(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingFood) {
                FoodNotebookView()
            }
            .fullScreenCover(isPresented: $showingGallery) {
                TogetherView()
            }
            .fullScreenCover(isPresented: $showingDiary) {
                TogetherView(startOnDiary: true)
            }
            .fullScreenCover(isPresented: $showingTogetherWatch) {
                TogetherWatchView(onAskAboutVideo: { _, text, imageBase64 in
                    if model.messages.isEmpty { await model.load() }
                    return await model.sendWatchMessage(text, imageBase64: imageBase64)
                })
            }
            .fullScreenCover(isPresented: $showingTogetherListen) {
                TogetherListenView()
            }
            .fullScreenCover(isPresented: $showingLettersMap) {
                LettersMapView()
            }
            .fullScreenCover(isPresented: $showingCalendar) {
                SharedCalendarView()
            }
            .onOpenURL { url in
                guard url.scheme == "ourcalendar", url.host == "day",
                      let dayKey = url.pathComponents.dropFirst().first else { return }
                showingCalendar = true
                SharedCalendarDayRouter.shared.open(dayKey: dayKey)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenSharedCalendarDay"))) { notification in
                guard let dayKey = notification.object as? String else { return }
                showingCalendar = true
                SharedCalendarDayRouter.shared.open(dayKey: dayKey)
            }
            .overlay {
                TogetherListenMiniPlayer { showingTogetherListen = true }
            }
    }
}

private struct LumiHomeView: View {
    let openChat: () -> Void
    let openSettings: () -> Void
    let openFood: () -> Void
    let openGallery: () -> Void
    let openDiary: () -> Void
    let openTogetherWatch: () -> Void
    let openTogetherListen: () -> Void
    let openLettersMap: () -> Void
    let openCalendar: () -> Void

    private let gap: CGFloat = 10
    private let apps: [LumiHomeApp] = [
        .init(title: "Chat", symbol: "bubble.left.and.bubble.right.fill", tint: Color(red: 0.40, green: 0.55, blue: 0.94), action: .chat),
        .init(title: "相册", symbol: "photo.on.rectangle.angled", tint: Color(red: 0.96, green: 0.53, blue: 0.48), action: .gallery),
        .init(title: "日记", symbol: "book.closed.fill", tint: Color(red: 0.91, green: 0.56, blue: 0.67), action: .diary),
        .init(title: "日历", symbol: "calendar", tint: Color(red: 0.89, green: 0.36, blue: 0.38), action: .calendar),
        .init(title: "吃了么", symbol: "fork.knife", tint: Color(red: 0.96, green: 0.67, blue: 0.37), action: .food),
        .init(title: "一起听", symbol: "headphones", tint: Color(red: 0.95, green: 0.56, blue: 0.67), action: .togetherListen),
        .init(title: "共看", symbol: "play.rectangle.fill", tint: Color(red: 0.92, green: 0.48, blue: 0.57), action: .togetherWatch),
        .init(title: "设置", symbol: "gearshape.fill", tint: Color(red: 0.43, green: 0.49, blue: 0.61), action: .settings),
        .init(title: "行迹", symbol: "figure.walk", tint: Color(red: 0.43, green: 0.49, blue: 0.61)),
        .init(title: "心迹", symbol: "heart.text.square", tint: Color(red: 0.43, green: 0.49, blue: 0.61)),
        .init(title: "藏宝地图", symbol: "map.fill", tint: Color(red: 0.91, green: 0.56, blue: 0.67), action: .lettersMap)
    ]

    var body: some View {
        GeometryReader { geometry in
            let sideInset: CGFloat = 20
            let cell = (geometry.size.width - sideInset * 2 - gap * 3) / 4
            ZStack {
                Color(red: 0.984, green: 0.949, blue: 0.957)
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // 2 × 4 profile card with half of the avatar floating above its edge.
                        ZStack(alignment: .top) {
                            VStack(spacing: 0) {
                                Text("林言")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .padding(.top, 39)
                                Text("这个人很懒，什么都没有留下")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(red: 0.36, green: 0.31, blue: 0.34).opacity(0.70))
                                    .padding(.top, 4)
                                Spacer(minLength: 14)
                                HStack(spacing: 5) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.91, green: 0.56, blue: 0.67))
                                    Text("浙江 杭州")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color(red: 0.36, green: 0.31, blue: 0.34).opacity(0.72))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 12)
                            }
                            .frame(height: cell * 2 - 31)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
                            .padding(.top, 31)

                            if let path = Bundle.main.path(forResource: "AssistantAvatar", ofType: "jpg"), let avatar = UIImage(contentsOfFile: path) {
                                Image(uiImage: avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 62, height: 62)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                                    .offset(y: 0)
                            }
                        }
                        .frame(height: cell * 2)

                        // Live week strip: the dates and selected day follow the device calendar.
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            let days = weekDays(containing: timeline.date)
                            HStack(spacing: 2) {
                                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                    let isToday = Calendar.current.isDate(day, inSameDayAs: timeline.date)
                                    VStack(spacing: 3) {
                                        Text(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index])
                                            .font(.system(size: 10, weight: .medium))
                                        Text(day.formatted(.dateTime.day()))
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(isToday ? Color.white : Color(red: 0.20, green: 0.17, blue: 0.19))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(isToday ? Color(red: 0.20, green: 0.19, blue: 0.20) : .clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                            }
                            .foregroundStyle(Color(red: 0.20, green: 0.17, blue: 0.19))
                            .padding(.horizontal, 14)
                            .frame(height: cell * 0.68, alignment: .center)
                            .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                            ForEach(Array(apps.prefix(8))) { app in appTile(app, cell: cell) }
                        }
                        .padding(.top, 2)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                            ForEach(apps.dropFirst(8)) { app in appTile(app, cell: cell) }
                        }
                    }
                    .padding(.horizontal, sideInset)
                    .padding(.top, 8)
                    .padding(.bottom, 25)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func weekDays(containing date: Date) -> [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let sunday = calendar.date(byAdding: .day, value: 1 - weekday, to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }

    private func appTile(_ app: LumiHomeApp, cell: CGFloat) -> some View {
        Button {
            switch app.action {
            case .chat: openChat()
            case .settings: openSettings()
            case .food: openFood()
            case .gallery: openGallery()
            case .diary: openDiary()
            case .togetherWatch: openTogetherWatch()
            case .togetherListen: openTogetherListen()
            case .lettersMap: openLettersMap()
            case .calendar: openCalendar()
            case .none: break
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: app.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.56, blue: 0.67))
                    .frame(width: min(cell - 6, 58), height: min(cell - 6, 58))
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                Text(app.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.25, green: 0.29, blue: 0.37))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.title)
    }

}

private struct LumiPulseLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: mid))
        path.addLine(to: CGPoint(x: rect.width * 0.34, y: mid))
        path.addLine(to: CGPoint(x: rect.width * 0.47, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.width * 0.59, y: rect.maxY - 2))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
        return path
    }
}

private struct FoodNotebookView: View {
    var body: some View { FoodNotebookNativeView() }
}

private struct LumiHomeApp: Identifiable {
    enum Action { case chat, settings, food, gallery, diary, togetherWatch, togetherListen, lettersMap, calendar }
    let id = UUID()
    let title: String
    let symbol: String
    let tint: Color
    var action: Action? = nil
}


final class LumiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "LUMI_MESSAGE", actions: [], intentIdentifiers: [], options: [])
        ])
        registerIfAuthorized(application)
        LumiNativeCalls.shared.start()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        registerIfAuthorized(application)
    }

    private func registerIfAuthorized(_ application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async { application.registerForRemoteNotifications() }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task {
            do { try await LumiAPIClient().registerPushToken(token, environment: environment) }
            catch { print("Push token registration failed: \(error.localizedDescription)") }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Remote notification registration failed: \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        NotificationCenter.default.post(name: Notification.Name("LumiRemoteMessageReceived"), object: nil)
        if notification.request.content.userInfo["kind"] as? String == "screen_request" {
            UserDefaults.standard.set(true, forKey: "lumi.screenRequestPending")
            NotificationCenter.default.post(name: Notification.Name("LumiScreenRequest"), object: nil)
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let dayKey = response.notification.request.content.userInfo["calendar_day"] as? String {
            NotificationCenter.default.post(name: Notification.Name("OpenSharedCalendarDay"), object: dayKey)
        }
        if response.notification.request.content.userInfo["kind"] as? String == "incoming_call" {
            NotificationCenter.default.post(name: Notification.Name("LumiIncomingCall"), object: nil)
        }
        if response.notification.request.content.userInfo["kind"] as? String == "screen_request" {
            UserDefaults.standard.set(true, forKey: "lumi.screenRequestPending")
            NotificationCenter.default.post(name: Notification.Name("LumiScreenRequest"), object: nil)
        }
    }
}

final class LumiNativeCalls: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
    static let shared = LumiNativeCalls()
    private let provider: CXProvider
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private(set) var answeredCallID: String?
    private(set) var ringingCallID: String?
    private var locallyInitiatedCallIDs = Set<String>()

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Lumi")
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func start() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        Task {
            do { try await LumiAPIClient().registerVoIPToken(token, environment: environment) }
            catch { print("VoIP token registration failed: \(error.localizedDescription)") }
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("VoIP push token invalidated")
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP,
              let callID = payload.dictionaryPayload["callId"] as? String,
              let uuid = UUID(uuidString: callID) else {
            completion()
            return
        }
        reportIncomingCall(callID: callID, callerName: payload.dictionaryPayload["callerName"] as? String ?? "沈屿", completion: completion)
    }

    func startAIInitiatedCall() {
        let callID = UUID().uuidString.lowercased()
        locallyInitiatedCallIDs.insert(callID)
        reportIncomingCall(callID: callID, callerName: "沈屿")
    }

    func reportServerIncomingCall(_ callID: String, callerName: String = "沈屿") {
        reportIncomingCall(callID: callID, callerName: callerName)
    }

    func isLocallyInitiatedCall(_ callID: String) -> Bool {
        locallyInitiatedCallIDs.contains(callID.lowercased())
    }

    private func reportIncomingCall(callID: String, callerName: String, completion: (() -> Void)? = nil) {
        guard let uuid = UUID(uuidString: callID) else { completion?(); return }
        let normalizedCallID = callID.lowercased()
        // Pending-call polling and PushKit can report the same invite. Ignore
        // duplicates even after the user has answered, until that call ends.
        guard ringingCallID?.lowercased() != normalizedCallID,
              answeredCallID?.lowercased() != normalizedCallID else {
            completion?()
            return
        }
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = false
        ringingCallID = callID
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                print("System incoming call failed: \(error.localizedDescription)")
                self.ringingCallID = nil
                self.locallyInitiatedCallIDs.remove(callID.lowercased())
            }
            completion?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.ringingCallID?.lowercased() == normalizedCallID else { return }
            self.ringingCallID = nil
            self.locallyInitiatedCallIDs.remove(callID.lowercased())
            self.provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        ringingCallID = nil
        answeredCallID = nil
        locallyInitiatedCallIDs.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let callID = action.callUUID.uuidString.lowercased()
        answeredCallID = callID
        ringingCallID = nil
        NotificationCenter.default.post(name: Notification.Name("LumiNativeCallAnswered"), object: callID)
        action.fulfill()
        if !locallyInitiatedCallIDs.contains(callID), let url = URL(string: "lumi://call?callId=\(callID)") {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let callID = action.callUUID.uuidString.lowercased()
        let wasAnswered = answeredCallID?.lowercased() == callID
        let wasLocallyInitiated = locallyInitiatedCallIDs.remove(callID) != nil
        ringingCallID = nil
        answeredCallID = nil
        if wasAnswered {
            NotificationCenter.default.post(name: Notification.Name("LumiNativeCallEnded"), object: callID)
        } else if !wasLocallyInitiated {
            Task { _ = try? await LumiAPIClient().answerIncomingCall(callID, action: "decline", to: "default") }
        }
        action.fulfill()
    }

    func end(_ callID: String) {
        guard let uuid = UUID(uuidString: callID), answeredCallID?.lowercased() == callID.lowercased() else { return }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { error in
            if let error { print("System call end failed: \(error.localizedDescription)") }
        }
    }
}
