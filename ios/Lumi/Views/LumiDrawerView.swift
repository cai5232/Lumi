import Charts
import SwiftUI

@MainActor
struct LumiDrawerView: View {
    private enum Page: String, CaseIterable {
        case traces = "行迹"
        case heart = "心迹"
        var symbol: String { self == .traces ? "point.topleft.down.curvedto.point.bottomright.up" : "heart" }
    }
    let chatID: String
    let onClose: () -> Void
    @State private var page: Page = .traces
    @State private var events: [LumiActivityEvent] = []
    @State private var emotion: LumiEmotionStateResponse?
    @State private var history: [LumiEmotionHistoryEntry] = []
    @State private var activity: ActivityState?
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var refreshedAt = Date()
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lumi.appearance.fontSize") private var fontSize = 15.0
    @Namespace private var selection
    private let api = LumiAPIClient()
    private var pink: Color { LumiPalette.iconPink }
    private let driveSymbols: [String: String] = [
        "attachment": "heart", "tenderness": "hands.sparkles", "heartache": "heart.slash",
        "curiosity": "sparkle.magnifyingglass", "mischief": "face.smiling", "restless": "wind",
        "regret": "arrow.uturn.backward", "desire": "flame", "gloom": "cloud", "jealousy": "eye",
        "fatigue": "moon.zzz", "anger": "flame"
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LumiPalette.chatBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                pagePicker.padding(.horizontal, 20)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Group {
                            if page == .traces { tracesPage } else { heartPage }
                        }
                        .id(page)
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                        if let errorMessage { errorCard(errorMessage) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 32)
                }
                .refreshable { await refresh() }
            }
        }
        .foregroundStyle(.black)
        .tint(.black)
        .preferredColorScheme(.light)
        .task {
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                await refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("行迹与心迹").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(Date.now.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.black)
            Spacer()
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 38, height: 38).modifier(DrawerGlassControl())
            }
            .disabled(isRefreshing).accessibilityLabel("刷新行迹与心迹")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 38, height: 38).modifier(DrawerGlassControl())
            }
            .accessibilityLabel("关闭行迹与心迹")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private var pagePicker: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) { pagePickerContent }
            } else {
                pagePickerContent
            }
        }
        .padding(5)
        .background(.white.opacity(0.24), in: Capsule())
    }

    private var pagePickerContent: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { option in
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.86)) { page = option }
                } label: {
                    Label(option.rawValue, systemImage: option.symbol)
                        .font(.system(size: 14, weight: page == option ? .semibold : .regular))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .modifier(DrawerTabGlass(selected: page == option, namespace: selection))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == option ? .isSelected : [])
            }
        }
    }

    private var tracesPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("日常留下的足迹").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("醒来、入梦，和独自经过的片刻。")
                        .font(.system(size: 12)).lineSpacing(3)
                }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("\(events.count)").font(.system(size: 32, weight: .light, design: .rounded).monospacedDigit())
                    Text("条记录").font(.system(size: 10, weight: .medium))
                }
                .frame(minWidth: 56)
            }
            .padding(22).modifier(DrawerGlassSurface())
            if isLoading && events.isEmpty {
                loadingCard("正在整理行迹")
            } else if events.isEmpty {
                emptyCard(symbol: "moon.stars", title: "故事还在慢慢发生", detail: "活动和梦境会按时间留在这里。")
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(eventDays) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(dayTitle(day.date)).font(.system(size: 17, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(day.events.count) 条").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            ForEach(day.events) { event in timelineCard(event) }
                        }
                    }
                }
            }
        }
    }

    private func timelineCard(_ event: LumiActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: event.kind == "dream" ? "moon.stars" : "sparkles")
                    .font(.system(size: 15, weight: .light))
                    .frame(width: 32, height: 32)
                    .background(pink.opacity(0.11), in: Circle())
                Text(event.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 4)
                Text(clockTime(event.time)).font(.system(size: 10, weight: .medium).monospacedDigit())
            }
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.system(size: max(13, CGFloat(fontSize) - 1)))
                    .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DrawerGlassSurface())
    }

    private var heartPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let emotion {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("此刻的心绪").font(.system(size: 11, weight: .medium))
                        Text(emotion.top.label).font(.system(size: 28, weight: .semibold, design: .rounded))
                        Label(activityLabel, systemImage: activity?.mode == "sleeping" ? "moon.zzz" : "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(pink.opacity(0.10), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().stroke(pink.opacity(0.14), lineWidth: 5)
                        Circle().trim(from: 0, to: min(1, max(0, emotion.top.value)))
                            .stroke(pink, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 5) {
                            Image(systemName: driveSymbols[emotion.top.drive] ?? "heart").font(.system(size: 18, weight: .light))
                            Text("\(Int(min(1, max(0, emotion.top.value)) * 100))%")
                                .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                        }
                    }
                    .frame(width: 88, height: 88)
                }
                .padding(24).modifier(DrawerGlassSurface())
            } else if isLoading {
                loadingCard("正在读取心迹")
            } else {
                emptyCard(symbol: "heart", title: "等心绪慢慢浮现", detail: "暂时没有可用的情绪记录，稍后下拉刷新。")
            }
            chartCard
            if let emotion {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeading("心绪明细", detail: "此刻")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                        ForEach(emotion.drives.keys.sorted {
                            let left = emotion.drives[$0]?.v ?? 0
                            let right = emotion.drives[$1]?.v ?? 0
                            return left == right ? $0 < $1 : left > right
                        }, id: \.self) { drive in
                            if let value = emotion.drives[drive] { moodTile(drive, item: value) }
                        }
                    }
                }
                .padding(20).modifier(DrawerGlassSurface())
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("心绪曲线", detail: "最近 24 小时")
            if chartPoints.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "waveform.path").font(.system(size: 25, weight: .light))
                    Text(isLoading ? "正在整理心迹" : "还没有足够的记录").font(.system(size: 12))
                }
                .frame(maxWidth: .infinity).frame(height: 150)
            } else {
                Chart(chartPoints) { point in
                    AreaMark(x: .value("时间", point.time), yStart: .value("基线", 0), yEnd: .value("强度", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [pink.opacity(0.30), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", point.time), y: .value("强度", point.value))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).foregroundStyle(pink)
                    if point.isCurrent { PointMark(x: .value("时间", point.time), y: .value("强度", point.value)).symbolSize(28).foregroundStyle(pink) }
                }
                .chartXScale(domain: chartStart...refreshedAt).chartYScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: chartAxisDates) { _ in
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                            .font(.system(size: 9)).foregroundStyle(.black)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 0.5, 1.0]) { value in
                        AxisGridLine().foregroundStyle(pink.opacity(0.15))
                        AxisValueLabel {
                            if let level = value.as(Double.self) { Text("\(Int(level * 100))").font(.system(size: 9)).foregroundStyle(.black) }
                        }
                    }
                }
                .frame(height: 150).accessibilityLabel("最近二十四小时的心绪强度")
            }
            Text(emotionFootnote).font(.system(size: 10))
        }
        .padding(20).modifier(DrawerGlassSurface())
    }

    private func moodTile(_ drive: String, item: LumiEmotionDriveValue) -> some View {
        let value = min(1, max(0, item.v))
        return VStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: driveSymbols[drive] ?? "heart").font(.system(size: 11))
                Text(item.z).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text("\(Int(value * 100))").font(.system(size: 10).monospacedDigit())
            }
            GeometryReader { geometry in
                Capsule().fill(pink.opacity(0.12))
                    .overlay(alignment: .leading) { Capsule().fill(pink).frame(width: geometry.size.width * value) }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(detail).font(.system(size: 10, weight: .medium))
        }
    }
    private func emptyCard(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .ultraLight))
                .frame(width: 68, height: 68).background(pink.opacity(0.10), in: Circle())
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 12)).lineSpacing(4).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24).padding(.vertical, 34)
        .frame(maxWidth: .infinity).modifier(DrawerGlassSurface())
    }
    private func loadingCard(_ title: String) -> some View {
        HStack(spacing: 10) { ProgressView().tint(.black); Text(title).font(.system(size: 12)) }
            .padding(.vertical, 34).frame(maxWidth: .infinity).modifier(DrawerGlassSurface())
    }
    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂时未能更新", systemImage: "arrow.clockwise").font(.system(size: 12, weight: .medium))
            Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Button("重新加载") { Task { await refresh() } }.font(.system(size: 12, weight: .semibold)).disabled(isRefreshing)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).modifier(DrawerGlassSurface())
    }

    private var eventDays: [DrawerTimelineDay] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.time) }
            .map { DrawerTimelineDay(date: $0.key, events: $0.value.sorted { $0.time > $1.time }) }
            .sorted { $0.date > $1.date }
    }
    private var chartStart: Date { refreshedAt.addingTimeInterval(-24 * 60 * 60) }
    private var chartAxisDates: [Date] { (0...4).map { chartStart.addingTimeInterval(Double($0) * 6 * 60 * 60) } }
    private var chartPoints: [DrawerChartPoint] {
        var points = history.compactMap { entry -> DrawerChartPoint? in
            guard let time = parseDate(entry.time), time >= chartStart, time <= refreshedAt else { return nil }
            return DrawerChartPoint(id: entry.id, time: time, value: min(1, max(0, entry.top.value)), isCurrent: false)
        }.sorted { $0.time < $1.time }
        if let emotion, let time = parseDate(emotion.time), time >= chartStart, time <= refreshedAt, time > (points.last?.time ?? .distantPast) {
            points.append(DrawerChartPoint(id: "now", time: time, value: min(1, max(0, emotion.top.value)), isCurrent: true))
        }
        return points
    }
    private var emotionFootnote: String {
        guard let time = emotion.flatMap({ parseDate($0.time) }) else { return isLoading ? "正在读取心迹" : "暂无情绪记录" }
        return "更新于 \(clockTime(time)) · \(history.count) 次记录"
    }
    private var activityLabel: String {
        switch activity?.mode { case "sleeping": "睡眠中"; case "sentinel": "自主活动"; default: "状态待同步" }
    }
    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
    }
    private func clockTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }
    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; isLoading = false }
        async let emotionError = loadSection("心迹", fetch: { try await api.fetchEmotionState(chatID: chatID) }, update: { emotion = $0; refreshedAt = Date() })
        async let historyError = loadSection("心绪曲线", fetch: { try await api.fetchEmotionHistory(chatID: chatID) }, update: { history = $0 })
        async let tracesError = loadSection("行迹", fetch: { try await api.fetchActivityHistory(for: chatID) }, update: { events = $0.sorted { $0.time > $1.time } })
        async let activityError = loadSection("活动状态", fetch: { try await api.fetchActivityState(for: chatID) }, update: { activity = $0 })
        let errors = await [emotionError, historyError, tracesError, activityError].compactMap { $0 }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
    private func loadSection<Value>(_ title: String, fetch: () async throws -> Value, update: @MainActor (Value) -> Void) async -> String? {
        do { update(try await fetch()); return nil }
        catch { return "\(title)更新失败：\(error.localizedDescription)" }
    }
}

private struct DrawerChartPoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let isCurrent: Bool
}
private struct DrawerTimelineDay: Identifiable {
    let date: Date
    let events: [LumiActivityEvent]
    var id: Date { date }
}
private struct DrawerGlassSurface: ViewModifier {
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.42)), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
private struct DrawerGlassControl: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}

private struct DrawerTabGlass: ViewModifier {
    let selected: Bool
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if selected {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular.tint(.white.opacity(0.5)).interactive(), in: Capsule())
                    .glassEffectID("drawer-selection", in: namespace)
            } else {
                content.background(.white.opacity(0.8), in: Capsule())
                    .matchedGeometryEffect(id: "drawer-selection", in: namespace)
            }
        } else {
            content
        }
    }
}
