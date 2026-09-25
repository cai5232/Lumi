import SwiftUI

@main
struct LumiApp: App {
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
