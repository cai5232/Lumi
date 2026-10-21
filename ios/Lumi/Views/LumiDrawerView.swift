import Charts
import SwiftUI

@MainActor
struct LumiDrawerView: View {
    private enum Page: String, CaseIterable {
        case moment = "此刻"
        case drawer = "抽屉"
        case traces = "行迹"

        var symbol: String {
            switch self {
            case .moment: "waveform.path"
            case .drawer: "archivebox"
            case .traces: "point.topleft.down.curvedto.point.bottomright.up"
            }
        }
    }

    let chatID: String
    let onClose: () -> Void

    @State private var page: Page = .moment
    @State private var items: [LumiDrawerItem] = []
    @State private var events: [LumiActivityEvent] = []
    @State private var emotion: LumiEmotionStateResponse?
    @State private var history: [LumiEmotionHistoryEntry] = []
    @State private var activity: ActivityState?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRefreshing = false
    @State private var refreshedAt = Date()
    @State private var isLoading = true
    @State private var showingFavorites = false
    @State private var errorMessage: String?
    @AppStorage("lumi.drawer.favorites.v1") private var favoriteIDs = ""
    @AppStorage("lumi.appearance.fontSize") private var fontSize = 15.0
    @AppStorage("lumi.appearance.textColor") private var textColor = "#332B30"
    @Namespace private var pageSelection

    private let api = LumiAPIClient()
    private let accent = DrawerPalette.iconPink
    private let muted = DrawerPalette.textSecondary
    private var ink: Color { LumiAppearanceColor.color(from: textColor) }
    private var bodySize: CGFloat { CGFloat(fontSize) }
    private let driveSymbols: [String: String] = [
        "attachment": "heart", "tenderness": "hands.sparkles", "heartache": "heart.slash",
        "curiosity": "sparkle.magnifyingglass", "mischief": "face.smiling", "restless": "wind",
        "regret": "arrow.uturn.backward", "desire": "flame", "gloom": "cloud", "jealousy": "eye",
        "fatigue": "moon.zzz", "anger": "flame"
    ]

    var body: some View {
        ZStack {
            LumiAppearanceBackground()
            VStack(spacing: 14) {
                header
                pagePicker
                    .padding(.horizontal, 18)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Group {
                            switch page {
                            case .moment: momentPage
                            case .drawer: drawerPage
                            case .traces: tracesPage
                            }
                        }
                        if let errorMessage { errorBanner(errorMessage) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .refreshable { await refresh() }
                .id(page)
            }
        }
        .tint(accent)
        .task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .modifier(DrawerGlassControl())
            }
            .accessibilityLabel("关闭抽屉")
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                Text("抽屉")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text(Date.now.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(muted.opacity(0.7))
            }
            Spacer(minLength: 0)
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .modifier(DrawerGlassControl())
            }
            .disabled(isRefreshing)
            .accessibilityLabel("刷新抽屉")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var pagePicker: some View {
        HStack(spacing: 4) {
            ForEach(Page.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { page = option }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.system(size: 12, weight: .medium))
                        Text(option.rawValue).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(page == option ? ink : muted.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if page == option {
                            Capsule().fill(DrawerPalette.userBubble)
                                .matchedGeometryEffect(id: "drawer-page", in: pageSelection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background { LumiAppearanceSurface(cornerRadius: 28) }
    }

    private var momentPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("此刻的心绪", detail: "一点点起伏，也值得被好好收着。")
            if let emotion {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: driveSymbols[emotion.top.drive] ?? "heart")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(accent)
                        .frame(width: 62, height: 62)
                        .background(DrawerPalette.userBubble.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("现在的心情").font(.system(size: 11)).foregroundStyle(muted.opacity(0.75))
                        Text(emotion.top.label)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink)
                        Label(activityLabel, systemImage: activity?.mode == "sleeping" ? "moon.zzz" : "sparkles")
                            .font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(min(1, max(0, emotion.top.value)) * 100))%")
                        .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(muted)
                }
                .padding(20)
                .drawerSurface()
            } else if isLoading {
                loadingCard("正在读取此刻的心情")
            } else {
                emptyCard(symbol: "heart", title: "等心绪慢慢浮现", detail: "暂时没有可用的情绪记录，可以稍后刷新。")
            }
            chartCard
            if let emotion {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeading("心绪细节", detail: "此刻")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(emotion.drives.keys.sorted { (emotion.drives[$0]?.v ?? 0) > (emotion.drives[$1]?.v ?? 0) }, id: \.self) { drive in
                            if let value = emotion.drives[drive] { moodTile(drive: drive, item: value) }
                        }
                    }
                }
                .padding(18)
                .drawerSurface()
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("心绪曲线", detail: "最近 24 小时")
            if chartPoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.system(size: 26, weight: .light)).foregroundStyle(accent)
                    Text(isLoading ? "正在整理心绪" : "还没有足够的记录")
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity).frame(height: 140)
            } else {
                Chart(chartPoints) { point in
                    AreaMark(x: .value("时间", point.time), yStart: .value("基线", 0), yEnd: .value("强度", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.32), accent.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("时间", point.time), y: .value("强度", point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .foregroundStyle(accent)
                    if point.isCurrent {
                        PointMark(x: .value("时间", point.time), y: .value("强度", point.value))
                            .symbolSize(35).foregroundStyle(accent)
                    }
                }
                .chartXScale(domain: chartStart...refreshedAt)
                .chartYScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: chartAxisDates) { _ in
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                            .font(.system(size: 9)).foregroundStyle(muted.opacity(0.65))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 0.5, 1.0]) { value in
                        AxisGridLine().foregroundStyle(accent.opacity(0.13))
                        AxisValueLabel {
                            if let level = value.as(Double.self) {
                                Text("\(Int(level * 100))").font(.system(size: 9)).foregroundStyle(muted.opacity(0.6))
                            }
                        }
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("最近二十四小时的心绪强度")
            }
            Text(emotionFootnote).font(.system(size: 10)).foregroundStyle(muted.opacity(0.7))
        }
        .padding(18)
        .drawerSurface()
    }

    private func moodTile(drive: String, item: LumiEmotionDriveValue) -> some View {
        let value = min(1, max(0, item.v))
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: driveSymbols[drive] ?? "heart").foregroundStyle(accent)
                Text(item.z).foregroundStyle(ink)
                Spacer(minLength: 0)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(muted.opacity(0.8))
            }
            .font(.system(size: 11, weight: .medium))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.14))
                    Capsule().fill(accent).frame(width: geometry.size.width * value)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(DrawerPalette.userBubble.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var drawerPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeading("悄悄收好的东西", detail: "小画、念头，和舍不得丢掉的瞬间。")
            HStack(spacing: 8) {
                collectionFilter("全部", count: items.count, favorite: false)
                collectionFilter("收藏", count: items.filter { isFavorite($0.id) }.count, favorite: true)
                Spacer()
            }
            if isLoading && items.isEmpty {
                loadingCard("正在打开抽屉")
            } else if filteredItems.isEmpty {
                emptyCard(symbol: showingFavorites ? "bookmark" : "archivebox", title: showingFavorites ? "还没有收藏" : "留一点空位给惊喜", detail: showingFavorites ? "点一下卡片上的书签，就能把喜欢的内容留下。" : "TA 放进来的东西，会安静地躺在这里。")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(filteredItems.sorted { $0.createdAt > $1.createdAt }) { item in drawerCard(item) }
                }
            }
        }
    }

    private func collectionFilter(_ title: String, count: Int, favorite: Bool) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { showingFavorites = favorite } } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text("\(count)").font(.system(size: 10).monospacedDigit()).opacity(0.65)
            }
            .foregroundStyle(showingFavorites == favorite ? ink : muted)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(showingFavorites == favorite ? DrawerPalette.userBubble : Color.white.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showingFavorites == favorite ? .isSelected : [])
    }

    private func drawerCard(_ item: LumiDrawerItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.kind == "pixel" ? "square.grid.3x3" : "text.alignleft")
                    .foregroundStyle(accent)
                Text(item.kind == "pixel" ? "一幅小画" : "一则随记")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                Spacer()
                Button { toggleFavorite(item.id) } label: {
                    Image(systemName: isFavorite(item.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isFavorite(item.id) ? accent : muted.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite(item.id) ? "取消收藏" : "收藏")
            }
            if item.kind == "pixel" {
                if let art = DrawerPixelArt.decode(item.content) {
                    pixelArt(art)
                        .padding(.vertical, 10)
                        .background(DrawerPalette.userBubble.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("这幅小画暂时无法显示。")
                        .font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 14)
                }
            } else {
                Text(item.content)
                    .font(.system(size: bodySize)).lineSpacing(6)
                    .foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(relativeTime(item.createdAt))
                .font(.system(size: 10)).foregroundStyle(muted.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, 8)
        .drawerSurface()
    }

    private var tracesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeading("那些安静的行迹", detail: "醒来、入梦，以及独自经过的片刻。")
            if isLoading && events.isEmpty {
                loadingCard("正在整理行迹")
            } else if events.isEmpty {
                emptyCard(symbol: "moon.stars", title: "故事还在慢慢发生", detail: "醒来时的活动和睡着后的梦，都会留在这里。")
            } else {
                ForEach(eventDays) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading(dayTitle(day.date), detail: "\(day.events.count) 条行迹")
                        ForEach(day.events) { event in timelineRow(event) }
                    }
                }
            }
        }
    }

    private func timelineRow(_ event: LumiActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                Text(event.time.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(muted.opacity(0.7))
                Image(systemName: event.kind == "dream" ? "moon.stars" : "sparkles")
                    .font(.system(size: 13, weight: .light)).foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background { LumiAppearanceSurface(cornerRadius: 17) }
            }
            .frame(width: 42).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(size: max(13, bodySize - 1))).lineSpacing(5)
                        .foregroundStyle(ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .drawerSurface()
        }
    }

    private var eventDays: [DrawerTimelineDay] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.time) }
            .map { DrawerTimelineDay(date: $0.key, events: $0.value.sorted { $0.time > $1.time }) }
            .sorted { $0.date > $1.date }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
    }

    private func clockTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    private func pageHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            Text(detail).font(.system(size: 12)).foregroundStyle(muted.opacity(0.75))
        }
        .padding(.vertical, 4)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(ink)
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(muted.opacity(0.7))
        }
    }

    private func emptyCard(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .light)).foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .background(DrawerPalette.userBubble.opacity(0.55), in: Circle())
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(ink)
            Text(detail).font(.system(size: 12)).lineSpacing(4)
                .multilineTextAlignment(.center).foregroundStyle(muted.opacity(0.8))
        }
        .padding(.horizontal, 26).padding(.vertical, 38)
        .frame(maxWidth: .infinity).drawerSurface()
    }

    private func loadingCard(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(accent)
            Text(title).font(.system(size: 12)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).drawerSurface()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(accent)
            Text(message).font(.system(size: 11)).foregroundStyle(muted)
            Spacer(minLength: 0)
            Button("重试") { Task { await refresh() } }.font(.system(size: 11, weight: .medium))
                .disabled(isRefreshing)
        }
        .padding(14).drawerSurface()
    }

    private var filteredItems: [LumiDrawerItem] {
        showingFavorites ? items.filter { isFavorite($0.id) } : items
    }

    private var chartPoints: [DrawerChartPoint] {
        let now = refreshedAt
        let start = now.addingTimeInterval(-24 * 60 * 60)
        var points = history.compactMap { entry -> DrawerChartPoint? in
            guard let time = parseDate(entry.time), time >= start, time <= now else { return nil }
            return DrawerChartPoint(id: entry.id, time: time, value: min(1, max(0, entry.top.value)), isCurrent: false)
        }.sorted { $0.time < $1.time }
        if let emotion, let recordedAt = parseDate(emotion.time), recordedAt >= start,
           recordedAt > (points.last?.time ?? .distantPast) {
            points.append(DrawerChartPoint(id: "now", time: recordedAt, value: min(1, max(0, emotion.top.value)), isCurrent: true))
        }
        return points
    }

    private var emotionFootnote: String {
        if isLoading && emotion == nil { return "正在读取心绪" }
        guard let time = emotion.flatMap({ parseDate($0.time) }) else { return "暂时没有可用的情绪记录" }
        return "更新于 \(clockTime(time)) · \(history.count) 次记录"
    }

    private var chartStart: Date { refreshedAt.addingTimeInterval(-24 * 60 * 60) }
    private var chartAxisDates: [Date] { (0...4).map { chartStart.addingTimeInterval(Double($0) * 6 * 60 * 60) } }

    private var activityLabel: String {
        switch activity?.mode {
        case "sleeping": return "睡眠中"
        case "sentinel": return "自主活动"
        default: return "状态未同步"
        }
    }

    private var favoriteSet: Set<String> { Set(favoriteIDs.split(separator: "|").map(String.init)) }
    private func isFavorite(_ id: String) -> Bool { favoriteSet.contains(id) }

    private func toggleFavorite(_ id: String) {
        var favorites = favoriteSet
        if !favorites.insert(id).inserted { favorites.remove(id) }
        favoriteIDs = favorites.sorted().joined(separator: "|")
    }

    private func pixelArt(_ art: DrawerPixelArt) -> some View {
        Canvas { context, size in
            let cell = min(size.width / CGFloat(art.width), size.height / CGFloat(art.height))
            let height = cell * CGFloat(art.height)
            let origin = CGPoint(x: (size.width - cell * CGFloat(art.width)) / 2, y: (size.height - height) / 2)
            for (index, paletteIndex) in art.grid.enumerated() {
                guard art.colors.indices.contains(paletteIndex), let color = art.colors[paletteIndex] else { continue }
                let rect = CGRect(x: origin.x + CGFloat(index % art.width) * cell,
                                  y: origin.y + CGFloat(index / art.width) * cell,
                                  width: cell, height: cell)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .frame(height: min(280, max(120, CGFloat(art.height) * 12)))
        .accessibilityLabel("TA 留下的一幅像素小画")
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        if seconds < 172800 { return "昨天" }
        return date.formatted(date: .numeric, time: .omitted)
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; isLoading = false }
        errorMessage = nil
        async let emotionError = loadSection("情绪", fetch: { try await api.fetchEmotionState(chatID: chatID) }, update: {
            emotion = $0
            refreshedAt = Date()
        })
        async let historyError = loadSection("情绪曲线", fetch: { try await api.fetchEmotionHistory(chatID: chatID) }, update: { history = $0 })
        async let drawerError = loadSection("抽屉", fetch: { try await api.fetchDrawerItems(for: chatID) }, update: { items = $0 })
        async let tracesError = loadSection("行迹", fetch: { try await api.fetchActivityHistory(for: chatID) }, update: { events = $0.sorted { $0.time > $1.time } })
        async let activityError = loadSection("活动状态", fetch: { try await api.fetchActivityState(for: chatID) }, update: { activity = $0 })
        let errors = await [emotionError, historyError, drawerError, tracesError, activityError].compactMap { $0 }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
        let unseenIDs = items.filter { !$0.seen }.map(\.id)
        if !unseenIDs.isEmpty {
            do { try await api.markDrawerItemsSeen(unseenIDs, for: chatID) }
            catch { errorMessage = [errorMessage, "内容已显示，已读状态暂未保存。"].compactMap { $0 }.joined(separator: "\n") }
        }
    }

    @MainActor
    private func loadSection<Value>(_ title: String, fetch: () async throws -> Value, update: @MainActor (Value) -> Void) async -> String? {
        do { update(try await fetch()); return nil }
        catch { return "\(title)更新失败：\(error.localizedDescription)" }
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct DrawerChartPoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let isCurrent: Bool
}

private struct DrawerPixelArt: Decodable {
    let w: Int
    let h: Int
    let palette: [String]
    let grid: [Int]

    var width: Int { w }
    var height: Int { h }
    var colors: [Color?] { palette.map(Self.color) }

    static func decode(_ source: String) -> DrawerPixelArt? {
        guard let data = source.data(using: .utf8),
              let art = try? JSONDecoder().decode(DrawerPixelArt.self, from: data),
              (1...64).contains(art.w), (1...64).contains(art.h),
              art.grid.count == art.w * art.h,
              !art.palette.isEmpty,
              art.grid.allSatisfy({ art.palette.indices.contains($0) }) else { return nil }
        return art
    }

    private static func color(_ value: String) -> Color? {
        if ["#0000", "#00000000", "transparent"].contains(value.lowercased()) { return nil }
        var hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let red = Double((number >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = Double((number >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = Double((number >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? Double(number & 0xff) / 255 : 1
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}


private struct DrawerTimelineDay: Identifiable {
    let date: Date
    let events: [LumiActivityEvent]
    var id: Date { date }
}

private struct DrawerSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background { LumiAppearanceSurface() }
    }
}

private extension View {
    func drawerSurface() -> some View { modifier(DrawerSurface()) }
}

private struct DrawerGlassControl: ViewModifier {
    func body(content: Content) -> some View { content.background(.white.opacity(0.8), in: Circle()) }
}
private struct SnapshotScroll<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
    }
}

private enum LumiAppearanceColor {
    static func color(from value: String) -> Color {
        let raw = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard raw.count == 6, let rgb = UInt32(raw, radix: 16) else { return DrawerPalette.textPrimary }
        return Color(.sRGB,
                     red: Double((rgb >> 16) & 0xff) / 255,
                     green: Double((rgb >> 8) & 0xff) / 255,
                     blue: Double(rgb & 0xff) / 255,
                     opacity: 1)
    }
}

private struct LumiAppearanceBackground: View {
    var body: some View { DrawerPalette.chatBackground.ignoresSafeArea() }
}

private enum DrawerPalette {
    static let chatBackground = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let userBubble = Color(red: 0.9608, green: 0.9255, blue: 0.9255)
    static let iconPink = Color(red: 0.955, green: 0.745, blue: 0.800)
    static let textPrimary = Color(red: 0.20, green: 0.17, blue: 0.19)
    static let textSecondary = Color(red: 0.36, green: 0.31, blue: 0.34)
}

private struct LumiAppearanceSurface: View {
    var base: Color = .white
    var cornerRadius: CGFloat = 22
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(base.opacity(0.78))
    }
}
