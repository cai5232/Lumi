import UserNotifications
import Foundation

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        if let path = Bundle.main.path(forResource: "AssistantAvatar", ofType: "jpg") {
            let url = URL(fileURLWithPath: path)
            if let attachment = try? UNNotificationAttachment(identifier: "shen-yu-avatar", url: url) {
                content.attachments = [attachment]
            }
        }
        contentHandler(self.bestAttemptContent ?? content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttemptContent { contentHandler?(bestAttemptContent) }
    }
}
