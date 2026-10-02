import WidgetKit
import SwiftUI

struct WakeEntry: TimelineEntry {
    let date: Date
    let lastWakeAt: Date?
    let nextWakeAt: Date?
}

struct WakeProvider: TimelineProvider {
    private let endpoint = URL(string: "https://lumi-tokyo-api.zeabur.app/v1/chats/default/activity")!

    func placeholder(in context: Context) -> WakeEntry { WakeEntry(date: .now, lastWakeAt: nil, nextWakeAt: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        Task { completion(await load()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        Task {
            let entry = await load()
            let refresh = entry.nextWakeAt.map { max(Date().addingTimeInterval(60), $0) } ?? Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func load() async -> WakeEntry {
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(ActivityPayload.self, from: data)
            return WakeEntry(date: .now, lastWakeAt: value.lastWakeAt.flatMap(Self.date), nextWakeAt: value.nextWakeAt.flatMap(Self.date))
        } catch {
            return WakeEntry(date: .now, lastWakeAt: nil, nextWakeAt: nil)
        }
    }

    private static func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }
}

private struct ActivityPayload: Decodable {
    let lastWakeAt: String?
    let nextWakeAt: String?
}

struct LumiWidgetView: View {
    let entry: WakeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("沈屿")
                .font(.headline)
                .foregroundStyle(Color(red: 0.72, green: 0.31, blue: 0.48))
            Text("上次醒来：\(time(entry.lastWakeAt))")
            Text("下次醒来：\(time(entry.nextWakeAt))")
        }
        .font(.system(size: 14, design: .rounded))
        .containerBackground(for: .widget) { Color(red: 1.0, green: 0.94, blue: 0.96) }
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "暂无" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

@main
struct LumiWidget: Widget {
    let kind = "LumiWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WakeProvider()) { entry in
            LumiWidgetView(entry: entry)
        }
        .configurationDisplayName("沈屿醒来时间")
        .description("显示真实的上次和下次自主唤醒时间")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}
