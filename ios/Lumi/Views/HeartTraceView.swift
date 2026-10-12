import Charts
import SwiftUI

struct HeartTraceView: View {
    let onClose: () -> Void

    @State private var state: LumiEmotionStateResponse?
    @State private var murmurs: [LumiEmotionArcEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshedAt = Date()

    private let api = LumiAPIClient()
    private let ink = Color(red: 0.27, green: 0.20, blue: 0.24)
    private let muted = Color(red: 0.56, green: 0.47, blue: 0.51)
    private let rose = Color(red: 0.83, green: 0.38, blue: 0.51)
    private let paper = Color(red: 0.985, green: 0.957, blue: 0.963)
    private let driveOrder = ["attachment", "tenderness", "heartache", "curiosity", "mischief", "restless", "regret", "desire", "gloom", "jealousy"]
    private let driveSymbols: [String: String] = [
        "attachment": "heart.fill", "tenderness": "hands.sparkles.fill", "heartache": "heart.slash.fill",
        "curiosity": "sparkle.magnifyingglass", "mischief": "face.smiling.inverse", "restless": "wind",
        "regret": "arrow.uturn.backward", "desire": "flame.fill", "gloom": "cloud.fill", "jealousy": "eye.fill"
    ]

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    chartCard
                    moodCard
                    murmurCard
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .refreshable { await refresh() }
        }
        .task { await refresh() }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("心迹")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text("把心里的起伏，慢慢看清")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ink.opacity(0.78))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.85), in: Circle())
            }
            .accessibilityLabel("关闭心迹")
        }
        .padding(.bottom, 2)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近 24 小时")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("情绪独白里的心绪强度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(muted)
                }
                Spacer()
                if let state {
                    HStack(spacing: 5) {
                        Circle().fill(rose).frame(width: 7, height: 7)
                        Text(state.top.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(rose)
                    }
                }
            }

            Chart(chartPoints) { point in
                AreaMark(
                    x: .value("时间", point.time),
                    yStart: .value("基线", 0),
                    yEnd: .value("强度", point.value),
                    series: .value("曲线", "murmur")
                )
                .foregroundStyle(LinearGradient(colors: [rose.opacity(0.22), rose.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("时间", point.time),
                    y: .value("强度", point.value),
                    series: .value("曲线", "murmur")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(rose)
                PointMark(x: .value("时间", point.time), y: .value("强度", point.value))
                    .symbolSize(point.isCurrent ? 48 : 28)
                    .foregroundStyle(rose.opacity(point.isCurrent ? 1 : 0.72))
            }
            .chartYScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4])).foregroundStyle(ink.opacity(0.11))
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                        .foregroundStyle(muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 0.5, 1.0]) { value in
                    AxisGridLine().foregroundStyle(ink.opacity(0.08))
                    AxisValueLabel {
                        if let level = value.as(Double.self) {
                            Text("\(Int(level * 100))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(muted)
                        }
                    }
                }
            }
            .frame(height: 176)

            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text(isLoading ? "正在读取心绪" : "更新于 \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(muted.opacity(0.85))
        }
        .padding(18)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(rose.opacity(0.08), lineWidth: 1))
        .shadow(color: rose.opacity(0.06), radius: 15, x: 0, y: 7)
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("此刻的情绪")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Text("驱动力")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(muted)
            }

            if let state {
                ForEach(driveOrder, id: \.self) { drive in
                    if let item = state.drives[drive] {
                        moodSlider(drive: drive, item: item)
                    }
                }
            } else if isLoading {
                ProgressView().tint(rose).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                Text("暂时读不到情绪状态，下拉可以重试。")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
            }
        }
        .padding(18)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(rose.opacity(0.08), lineWidth: 1))
    }

    private func moodSlider(drive: String, item: LumiEmotionDriveValue) -> some View {
        let value = min(1, max(0, item.v))
        return HStack(spacing: 10) {
            Image(systemName: driveSymbols[drive] ?? "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(rose.opacity(0.92))
                .frame(width: 18)
            Text(item.z)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.opacity(0.9))
                .frame(width: 42, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(rose.opacity(0.11))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.62, blue: 0.68), rose], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geometry.size.width * value))
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(rose.opacity(0.72), lineWidth: 2))
                        .offset(x: max(0, min(geometry.size.width - 12, geometry.size.width * value - 6)))
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text("\(Int(value * 100))")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(muted)
                .frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.z)，\(Int(value * 100))")
    }

    private var murmurCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(rose)
                Text("最近的心声")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                if let latest = latestMurmur, let date = date(from: latest.time) {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(muted)
                }
            }
            if let latest = latestMurmur {
                Text(latest.text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .lineSpacing(5)
                    .foregroundStyle(ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(latest.zh) · murmur")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(rose.opacity(0.9))
            } else {
                Text("还没有新的心声记录，情绪曲线会随着 murmur 慢慢生长。")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.93, blue: 0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var chartPoints: [HeartTracePoint] {
        let now = refreshedAt
        let start = now.addingTimeInterval(-24 * 60 * 60)
        let records = murmurs.compactMap { entry -> HeartTracePoint? in
            guard let time = date(from: entry.time), time >= start, time <= now else { return nil }
            return HeartTracePoint(id: entry.id, time: time, value: min(1, max(0, entry.val)), isCurrent: false)
        }.sorted { $0.time < $1.time }
        guard let state else { return records }
        let current = HeartTracePoint(id: "current", time: now, value: min(1, max(0, state.top.value)), isCurrent: true)
        if records.last?.time.timeIntervalSince(now) ?? -3600 > -120 {
            return records
        }
        return records + [current]
    }

    private var latestMurmur: LumiEmotionArcEntry? {
        murmurs.max { (date(from: $0.time) ?? .distantPast) < (date(from: $1.time) ?? .distantPast) }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            async let currentState = api.fetchEmotionState()
            async let recentMurmurs = api.fetchEmotionMurmurs()
            let (newState, newMurmurs) = try await (currentState, recentMurmurs)
            state = newState
            murmurs = newMurmurs
            refreshedAt = .now
        } catch {
            errorMessage = "心迹暂时没有连上服务器：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct HeartTracePoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let isCurrent: Bool
}
