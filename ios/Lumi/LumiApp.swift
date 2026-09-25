import SwiftUI
import UIKit
import UserNotifications

@main
struct LumiApp: App {
    @UIApplicationDelegateAdaptor(LumiAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ChatDetailView(model: ChatViewModel(
                initialMessages: [
                    ChatMessage(id: UUID(), role: .assistant, content: "下午的风很轻，想和你说说话。", createdAt: .now),
                    ChatMessage(id: UUID(), role: .user, content: "我在，慢慢说。", createdAt: .now),
                    ChatMessage(id: UUID(), role: .assistant, content: "那就从窗边的云开始吧。", createdAt: .now)
                ],
                shouldLoadFromServer: true
            ))
        }
    }
}


final class LumiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerIfAuthorized(application)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        registerIfAuthorized(application)
    }

    private func registerIfAuthorized(_ application: UIApplication) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
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
        [.banner, .sound, .list]
    }
}
