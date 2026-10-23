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

// Presentation is separate from polling so the exact shipped card can be previewed.
struct LumiInstantCommandCard: View {
    let command: LumiInstantCommand
    let date: Date
    let expanded: Bool
    let busy: Bool
    var count = 1
    var pressing = false
    let onToggle: () -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void
    let onNext: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var overdue: Bool { command.deadline.map { date >= $0 } ?? false }
    private var commandPink: Color { Color(red: 0.76, green: 0.46, blue: 0.56) }
    private var accent: Color {
        overdue ? Color(red: 0.65, green: 0.34, blue: 0.43) : commandPink
    }
    private var ink: Color { colorScheme == .dark ? .primary : LumiPalette.textPrimary }
    private var secondaryInk: Color { colorScheme == .dark ? .secondary : LumiPalette.textSecondary.opacity(0.78) }
    private var accentInk: Color {
        colorScheme == .dark ? LumiPalette.iconPink : Color(red: 0.65, green: 0.36, blue: 0.45)
    }
    private var remaining: Double {
        guard let deadline = command.deadline, let duration = command.countdown_seconds else { return 1 }
        return min(1, max(0, deadline.timeIntervalSince(date) / Double(duration)))
    }

    var body: some View {
        Group {
            if expanded { expandedCard } else { edgePill }
        }
        .foregroundStyle(ink)
        .background {
            RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
                        .fill(LumiPalette.chatBackground.opacity(colorScheme == .dark ? 0.07 : 0.92))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
                .strokeBorder(colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.85), lineWidth: 0.6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: expanded ? 26 : 20, style: .continuous)
                .trim(from: 0, to: pressing ? 1 : 0)
                .stroke(accent.opacity(0.65), lineWidth: 1.5)
                .animation(.linear(duration: pressing ? 0.62 : 0.12), value: pressing)
                .allowsHitTesting(false)
        }
        .shadow(color: colorScheme == .dark ? .black.opacity(0.22) : LumiPalette.iconPink.opacity(0.10), radius: expanded ? 22 : 10, x: -2, y: expanded ? 10 : 4)
        .scaleEffect(pressing ? 0.98 : 1, anchor: .trailing)
        .animation(.easeOut(duration: 0.18), value: pressing)
        .disabled(busy)
    }

    private var edgePill: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ink.opacity(0.08), lineWidth: 1.6)
                    Circle().trim(from: 0, to: remaining)
                        .stroke(overdue ? accent : commandPink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if busy { ProgressView().controlSize(.mini) }
                    else { Circle().fill(overdue ? accent : commandPink).frame(width: 4, height: 4) }
                }.frame(width: 20, height: 20)
                Text(command.clock(at: date))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overdue ? accent : ink.opacity(0.86))
            }
            .frame(width: 58, height: 76)
            .padding(.trailing, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(command.title)，\(command.clock(at: date))，展开指令")
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(overdue ? "再给自己一点时间" : "即时指令")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(accentInk)
                Spacer(minLength: 8)
                Button(action: onToggle) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(secondaryInk)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起指令")
            }
            .padding(.top, -5)
            .padding(.trailing, -6)

            Text(command.title)
                .font(.system(size: 17, weight: .medium))
                .lineSpacing(5)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(command.clock(at: date))
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .tracking(-1.2)
                    .foregroundStyle(overdue ? accentInk : ink)
                Text(command.deadline == nil ? "已用时" : (overdue ? "已超时" : "剩余"))
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryInk)
            }
            .padding(.top, 20)
            .contentTransition(.numericText())

            GeometryReader { geometry in
                Capsule().fill(commandPink.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule().fill(overdue ? accent : commandPink)
                            .frame(width: geometry.size.width * remaining)
                    }
            }
            .frame(height: 3)
            .padding(.top, 13)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryInk)
                        .frame(minWidth: 38, minHeight: 36)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if count > 1 {
                    Button(action: onNext) {
                        HStack(spacing: 4) {
                            Text("\(count) 条")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryInk)
                        .frame(minHeight: 36)
                    }.buttonStyle(.plain).accessibilityLabel("下一条指令，共 \(count) 条")
                }
                Button(action: onComplete) {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)) }
                        Text("完成了").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(overdue ? accent : commandPink, in: Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.top, 19)
        }
        .padding(20)
        .frame(width: 278, alignment: .leading)
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
                    LumiInstantCommandCard(
                        command: command, date: context.date, expanded: expanded, busy: model.busy,
                        count: model.commands.count, pressing: pressing,
                        onToggle: { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded.toggle() } },
                        onComplete: { finish(command, cancel: false) },
                        onCancel: { finish(command, cancel: true) },
                        onNext: {
                            guard !model.commands.isEmpty else { return }
                            let index = model.commands.firstIndex(of: command) ?? 0
                            selectedID = model.commands[(index + 1) % model.commands.count].id
                        }
                    )
                    .onLongPressGesture(minimumDuration: 0.62, pressing: { pressing = $0 }) { finish(command, cancel: true) }
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .onChanged { translation = $0.translation }
                        .onEnded { value in
                            if value.translation.width < -64 && abs(value.translation.width) > abs(value.translation.height) {
                                finish(command, cancel: false)
                            } else if abs(value.translation.height) > abs(value.translation.width) {
                                position = min(1, max(0, position + value.translation.height / max(1, geometry.size.height - 360)))
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { translation = .zero }
                        })
                    .offset(x: min(0, translation.width))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, expanded ? 14 : -8)
                    .offset(y: min(max(100, 120 + max(0, geometry.size.height - 420) * position + translation.height), max(100, geometry.size.height - (expanded ? 320 : 110))))
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
