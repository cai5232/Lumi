import SwiftUI
import UIKit
import UserNotifications

@main
struct LumiApp: App {
    @UIApplicationDelegateAdaptor(LumiAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LumiRootView()
        }
    }
}

@MainActor
private struct LumiRootView: View {
    @StateObject private var model: ChatViewModel

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
        ZStack {
            ChatDetailView(model: model)
            DraggableClawdPet(assetName: model.isSending ? "clawd-working-thinking" : "clawd-idle-follow")
        }
    }
}


final class LumiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "LUMI_MESSAGE", actions: [], intentIdentifiers: [], options: [])
        ])
        registerIfAuthorized(application)
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
        if notification.request.content.userInfo["kind"] as? String == "screen_request" {
            UserDefaults.standard.set(true, forKey: "lumi.screenRequestPending")
            NotificationCenter.default.post(name: Notification.Name("LumiScreenRequest"), object: nil)
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["kind"] as? String == "incoming_call" {
            NotificationCenter.default.post(name: Notification.Name("LumiIncomingCall"), object: nil)
        }
        if response.notification.request.content.userInfo["kind"] as? String == "screen_request" {
            UserDefaults.standard.set(true, forKey: "lumi.screenRequestPending")
            NotificationCenter.default.post(name: Notification.Name("LumiScreenRequest"), object: nil)
        }
    }
}
