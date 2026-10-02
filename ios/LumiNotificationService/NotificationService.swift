import UserNotifications
import Foundation
import Intents

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard var content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        // Older server builds could put the private reasoning block directly
        // into the alert body. Strip it again at the device boundary so it
        // can never appear in a notification even while a rollout is mixed.
        content.body = Self.visibleText(content.body)
        content.subtitle = Self.visibleText(content.subtitle)
        if content.title.isEmpty { content.title = "沈屿" }
        if let path = Bundle.main.path(forResource: "AssistantAvatar", ofType: "jpg") {
            let url = URL(fileURLWithPath: path)
            if let attachment = try? UNNotificationAttachment(identifier: "shen-yu-avatar", url: url) {
                content.attachments = [attachment]
            }
            // Use Apple's communication-notification layout so the sender
            // avatar is prominent and iOS keeps the Lumi app icon as the badge.
            if let imageData = try? Data(contentsOf: url) {
                let handle = INPersonHandle(value: "shen-yu", type: .unknown)
                let sender = INPerson(personHandle: handle,
                                       nameComponents: nil,
                                       displayName: "沈屿",
                                       image: INImage(imageData: imageData),
                                       contactIdentifier: nil,
                                       customIdentifier: "lumi-shen-yu")
                let intent = INSendMessageIntent(recipients: nil,
                                                 outgoingMessageType: .outgoingMessageText,
                                                 content: content.body,
                                                 speakableGroupName: nil,
                                                 conversationIdentifier: "lumi-default",
                                                 serviceName: "Lumi",
                                                 sender: sender,
                                                 attachments: nil)
                if let updated = try? content.updating(from: intent) as? UNMutableNotificationContent {
                    content = updated
                }
            }
        }
        contentHandler(self.bestAttemptContent ?? content)
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
