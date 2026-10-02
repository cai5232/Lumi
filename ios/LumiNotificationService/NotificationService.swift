import UserNotifications
import Foundation

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard var content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        // Older server builds could put the private reasoning block directly
        // into the alert body. Strip it again at the device boundary so it
        // can never appear in a notification even while a rollout is mixed.
        content.body = Self.visibleText(content.body)
        content.subtitle = Self.visibleText(content.subtitle)
        if content.title.isEmpty { content.title = "沈屿" }
        content.categoryIdentifier = "LUMI_MESSAGE"
        bestAttemptContent = content
        contentHandler(content)
    }

    private static func visibleText(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: #"(?is)<(?:thinking|think|analysis|reasoning)\b[^>]*>.*?(?:</(?:thinking|think|analysis|reasoning)>|$)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</?(?:thinking|think|analysis|reasoning)\b[^>]*>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttemptContent { contentHandler?(bestAttemptContent) }
    }
}
