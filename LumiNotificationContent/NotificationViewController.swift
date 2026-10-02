import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let avatarView = UIImageView()
    private let appIconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 18
        avatarView.image = UIImage(named: "AssistantAvatar.jpg")
        appIconView.contentMode = .scaleAspectFill
        appIconView.clipsToBounds = true
        appIconView.layer.cornerRadius = 10
        appIconView.image = UIImage(named: "AppIcon.png")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        text.axis = .vertical
        text.spacing = 5
        let imageStack = UIView()
        imageStack.addSubview(avatarView)
        imageStack.addSubview(appIconView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: imageStack.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: imageStack.topAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 104),
            avatarView.heightAnchor.constraint(equalToConstant: 104),
            appIconView.trailingAnchor.constraint(equalTo: imageStack.trailingAnchor, constant: 4),
            appIconView.bottomAnchor.constraint(equalTo: imageStack.bottomAnchor, constant: 4),
            appIconView.widthAnchor.constraint(equalToConstant: 34),
            appIconView.heightAnchor.constraint(equalToConstant: 34),
            imageStack.widthAnchor.constraint(equalToConstant: 110),
            imageStack.heightAnchor.constraint(equalToConstant: 110)
        ])
        let row = UIStackView(arrangedSubviews: [imageStack, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
    }

    func didReceive(_ notification: UNNotification) {
        titleLabel.text = notification.request.content.title.isEmpty ? "沈屿" : notification.request.content.title
        bodyLabel.text = notification.request.content.body
    }
}
