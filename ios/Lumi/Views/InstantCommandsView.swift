import SwiftUI
import Combine
import UIKit

struct LumiInstantCommand: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let countdown_seconds: Int?
    let started_at: Double
    var startedAt: Date { Date(timeIntervalSince1970: started_at / 1000) }
    var deadline: Date? { countdown_seconds.map { startedAt.addingTimeInterval(Double($0)) } }

    func clock(at date: Date) -> String {
        let seconds = Int(abs((deadline ?? startedAt).timeIntervalSince(date)).rounded(.down))
        return String(format: "%@%02d:%02d", deadline.map { date >= $0 ? "+" : "" } ?? "", seconds / 60, seconds % 60)
    }
}
struct LumiInstantCommandsResponse: Decodable { let items: [LumiInstantCommand] }
struct LumiCommandActionResponse: Decodable { let ok: Bool }

@MainActor
final class LumiInstantCommandsModel: ObservableObject {
    @Published var commands: [LumiInstantCommand] = []
    @Published var error: String?
    @Published var busy = false
    private let api = LumiAPIClient()
    private var revision = 0
    private var refreshing = false

    func refresh(threadID: String) async {
        guard !busy, !refreshing else { return }
        refreshing = true
        let requestedRevision = revision
        defer { refreshing = false }
        do {
            let items = try await api.fetchInstantCommands(threadID: threadID)
            guard requestedRevision == revision else { return }
            commands = items
        } catch {
            // Keep existing timers visible when connectivity is lost.
        }
    }

    func finish(_ command: LumiInstantCommand, threadID: String, cancel: Bool) async {
        guard !busy else { return }
        busy = true
        revision += 1
        defer { busy = false }
        do {
            try await api.finishInstantCommand(command.id, threadID: threadID, cancel: cancel)
            commands.removeAll { $0.id == command.id }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch { self.error = error.localizedDescription }
    }
}

struct LumiInstantCommandsView: View {
    let threadID: String
    let refreshToken: UUID?
    @StateObject private var model = LumiInstantCommandsModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lumi.instantCommand.verticalPosition") private var position = 0.38
    @State private var expanded = false
    @State private var selectedID: String?
    @State private var translation = CGSize.zero
    @State private var pressing = false

    private var selected: LumiInstantCommand? {
        model.commands.first { $0.id == selectedID } ?? model.commands.first
    }

    var body: some View {
        GeometryReader { geometry in
            if let command = selected {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let overdue = command.deadline.map { context.date >= $0 } ?? false
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: overdue ? "timer" : "hourglass")
                            Text(command.clock(at: context.date)).monospacedDigit()
                            if !expanded { Text(command.title).lineLimit(1) }
                            if model.busy { ProgressView().controlSize(.small) }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        if expanded {
                            Text(command.title).font(.body).fixedSize(horizontal: false, vertical: true)
                            Text(overdue ? "已超时，完成后仍会记录用时" : "左滑完成 · 长按取消 · 上下拖动")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("完成") { finish(command, cancel: false) }
                                    .buttonStyle(.borderedProminent)
                                Button("取消", role: .cancel) { finish(command, cancel: true) }
                                    .buttonStyle(.bordered)
                                if model.commands.count > 1 {
                                    Button("下一条 (\(model.commands.count))") {
                                        let index = model.commands.firstIndex(of: command) ?? 0
                                        selectedID = model.commands[(index + 1) % model.commands.count].id
                                    }
                                }
                            }.font(.caption)
                        }
                    }
                    .padding(14)
                    .frame(width: expanded ? min(310, geometry.size.width - 24) : min(235, geometry.size.width - 24), alignment: .leading)
                    .foregroundStyle(overdue ? Color(red: 0.65, green: 0.27, blue: 0.19) : Color(red: 0.20, green: 0.17, blue: 0.19))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: expanded ? 22 : 28))
                    .overlay {
                        RoundedRectangle(cornerRadius: expanded ? 22 : 28)
                            .stroke(pressing ? Color.orange : (overdue ? Color.orange.opacity(0.6) : Color.pink.opacity(0.25)), lineWidth: pressing ? 3 : 1)
                    }
                    .shadow(color: .black.opacity(0.09), radius: 10, y: 4)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { expanded.toggle() } }
                    .onLongPressGesture(minimumDuration: 0.62, pressing: { pressing = $0 }) { finish(command, cancel: true) }
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .onChanged { translation = $0.translation }
                        .onEnded { value in
                            if value.translation.width < -64 && abs(value.translation.width) > abs(value.translation.height) {
                                finish(command, cancel: false)
                            } else if abs(value.translation.height) > abs(value.translation.width) {
                                position = min(1, max(0, position + value.translation.height / max(1, geometry.size.height - 280)))
                            }
                            translation = .zero
                        })
                    .offset(x: min(0, translation.width))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: 160 + max(0, geometry.size.height - 360) * position + translation.height)
                    .disabled(model.busy)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("即时指令，\(command.title)，\(command.clock(at: context.date))")
                    .accessibilityAction(named: "完成") { finish(command, cancel: false) }
                    .accessibilityAction(named: "取消") { finish(command, cancel: true) }
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refresh(threadID: threadID)
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
        .onChange(of: refreshToken) { _, _ in
            Task { await model.refresh(threadID: threadID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LumiRemoteMessageReceived"))) { _ in
            Task { await model.refresh(threadID: threadID) }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private func finish(_ command: LumiInstantCommand, cancel: Bool) {
        Task {
            await model.finish(command, threadID: threadID, cancel: cancel)
            if model.error == nil { expanded = false }
        }
    }
}
