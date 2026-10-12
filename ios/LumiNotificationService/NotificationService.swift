import UserNotifications
import Foundation
import Intents

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNNotificationContent?
    private let deliveryLock = NSLock()
    private var didDeliver = false

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            deliver(request.content)
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

        // Calls and screen requests aren't messages from the conversation.
        let kind = content.userInfo["kind"] as? String
        guard kind != "incoming_call", kind != "screen_request",
              let avatarURL = Bundle.main.url(forResource: "AssistantAvatar", withExtension: "jpg"),
              let avatarData = try? Data(contentsOf: avatarURL) else {
            deliver(content)
            return
        }

        let sender = INPerson(
            personHandle: INPersonHandle(value: "lumi-assistant-shenyu", type: .unknown),
            nameComponents: nil,
            displayName: "沈屿",
            image: INImage(imageData: avatarData),
            contactIdentifier: nil,
            customIdentifier: "lumi-assistant-shenyu",
            isMe: false
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: content.userInfo["threadId"] as? String ?? "default",
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { [self] error in
            guard error == nil, let updated = try? content.updating(from: intent) else {
                deliver(content)
                return
            }
            deliver(updated)
        }
    }

    private static func visibleText(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: #"(?is)<(?:thinking|think|analysis|reasoning)\b[^>]*>.*?(?:</(?:thinking|think|analysis|reasoning)>|$)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</?(?:thinking|think|analysis|reasoning)\b[^>]*>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttemptContent { deliver(bestAttemptContent) }
    }

    private func deliver(_ content: UNNotificationContent) {
        deliveryLock.lock()
        guard !didDeliver else { deliveryLock.unlock(); return }
        didDeliver = true
        let handler = contentHandler
        deliveryLock.unlock()
        handler?(content)
    }
}
