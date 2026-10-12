import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct TogetherWatchView: View {
    @Environment(\.dismiss) private var dismiss
    let onAskAboutVideo: (String, String, String) async -> String?

    @State private var player: AVPlayer?
    @State private var localVideoURL: URL?
    @State private var holdsVideoAccess = false
    @State private var videoTitle = ""
    @State private var editedVideoTitle = ""
    @State private var showingRenameVideo = false
    @State private var question = ""
    @State private var conversation: [WatchConversationLine] = []
    @State private var activeWatch: WatchHistoryRecord?
    @State private var showingHistory = false
    @State private var showingTicketShelf = false
    @State private var isAnalysisCardExpanded = true
    @State private var isWatchToolsCardExpanded = true
    @State private var historyRecords: [WatchHistoryRecord] = []
    @State private var subtitleLines: [WatchSubtitleLine] = []
    @State private var analysisMoments: [WatchAnalysisMoment] = []
    @State private var danmakuItems: [WatchDanmakuItem] = []
    @State private var ticketItems: [WatchTicketItem] = []
    @State private var riskProtectionEnabled = false
    @State private var isEpisodeMode = false
    @State private var subtitlePickerPresented = false
    @State private var danmakuDraft = ""
    @State private var playheadRefresh = Date()
    @State private var riskAcknowledgedMomentID: UUID?
    @State private var endingRuntimeSessions: Set<UUID> = []
    @State private var runtimeAPIAvailable = false
    @State private var runtimeSetupTask: Task<Void, Never>?
    @State private var lastObservedPlayhead: Double?
    @State private var lastObservedWatchID: UUID?
    @FocusState private var questionFocused: Bool
    @State private var isPickingVideo = false
    @State private var isSendingQuestion = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var analysisConfig: LumiWatchAnalysisConfig?
    @State private var analysisSummary = ""
    @State private var isAnalyzing = false
    @AppStorage("lumi.watchAnalysis.baseURL") private var analysisBaseURL = ""
    @AppStorage("lumi.watchAnalysis.model") private var analysisModel = ""
    @State private var analysisAPIKey = ""
    @State private var showingAnalysisSettings = false
    @AppStorage("lumi.watchAnalysis.continuous") private var continuousAnalysisEnabled = true
    private let api = LumiAPIClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    playerCard
                    if player != nil {
                        analysisCard
                        watchToolsCard
                    }
                    conversationPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(WatchPalette.background.ignoresSafeArea())
            .onAppear { reloadWatchHistory() }
            .onChange(of: showingHistory) { _, isShowing in
                if isShowing { reloadWatchHistory() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomComposer
            }
            .navigationTitle("一起看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { exitWatch() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            // History is its own local library. Loading it must not depend on
                            // there being a video in the player to persist first.
                            reloadWatchHistory()
                            showingHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .medium))
                                .accessibilityLabel("历史观看")
                        }
                        Button {
                            ticketItems = activeWatch?.tickets ?? []
                            showingTicketShelf = true
                        } label: {
                            Image(systemName: "ticket")
                                .font(.system(size: 14, weight: .medium))
                                .accessibilityLabel("票夹")
                        }
                        Button { showingAnalysisSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .medium))
                                .accessibilityLabel("配置分析模型")
                        }
                        Button { isPickingVideo = true } label: {
                            Label("选视频", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAnalysisSettings) {
                WatchAnalysisSettingsView(baseURL: $analysisBaseURL, model: $analysisModel, apiKey: $analysisAPIKey)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingHistory) {
                WatchHistorySheet(records: $historyRecords, onSelect: restoreWatch, onDelete: deleteWatchRecord)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(WatchPalette.background)
            }
            .alert("修改视频名称", isPresented: $showingRenameVideo) {
                TextField("视频名称", text: $editedVideoTitle)
                Button("取消", role: .cancel) {}
                Button("保存", action: renameCurrentVideo)
            } message: {
                Text("修改后的名称会保存在观看历史中。")
            }
            .sheet(isPresented: $showingTicketShelf) {
                WatchTicketShelf(items: ticketItems, onSelect: { item in
                    if let player { Task { await player.seek(to: CMTime(seconds: item.playheadSeconds, preferredTimescale: 600)) } }
                    showingTicketShelf = false
                }, onDelete: { item in
                    ticketItems.removeAll { $0.id == item.id }
                    activeWatch?.tickets = ticketItems
                    persistWatchRecord()
                    syncRuntimeTickets()
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fileImporter(isPresented: $isPickingVideo, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false, onCompletion: importVideo)
        }
        .tint(WatchPalette.plum)
        .overlay {
            if showError {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("暂时无法继续")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(WatchPalette.plum)
                        Text(errorMessage ?? "请稍后重试。")
                            .font(.system(size: 14)).foregroundStyle(WatchPalette.plum.opacity(0.82))
                        Button("好") { showError = false }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(WatchPalette.heart, in: Capsule())
                    }
                    .padding(20).frame(maxWidth: 320)
                    .background(WatchPalette.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: WatchPalette.plum.opacity(0.18), radius: 22, y: 8)
                }
                .transition(.opacity)
            }
        }
        .onDisappear {
            persistWatchRecord()
            if let activeWatch { closeRuntimeSession(activeWatch, action: "save_progress") }
            player?.pause()
            if holdsVideoAccess, let localVideoURL { localVideoURL.stopAccessingSecurityScopedResource() }
        }
        .task {
            analysisAPIKey = LumiKeychain.read(account: "watch-analysis-api-key")
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                persistWatchRecord()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard runtimeAPIAvailable else { continue }
                guard let record = activeWatch, let runtimeID = record.runtimeSessionID else { continue }
                let playhead = max(0, player?.currentTime().seconds ?? record.playheadSeconds)
                let rawDuration = player?.currentItem?.duration.seconds ?? record.durationSeconds
                let duration = rawDuration.isFinite ? max(record.durationSeconds, rawDuration) : record.durationSeconds
                do {
                    try await api.heartbeatWatchRuntimeSession(clientID: WatchHistoryStore.clientID, sessionID: runtimeID.uuidString)
                    try await api.updateWatchRuntimePlayback(
                        clientID: WatchHistoryStore.clientID,
                        sessionID: runtimeID.uuidString,
                        playheadMS: Int(playhead * 1000),
                        durationMS: Int(duration * 1000),
                        isPlaying: (player?.rate ?? 0) > 0,
                        timelineEpoch: record.timelineEpoch,
                        snapshotSeq: record.snapshotSeq,
                        playbackRate: Double(player?.rate ?? 1)
                    )
                } catch let error as LumiAPIError {
                    if case .server(let message) = error, message.contains("HTTP 404") || message.contains("HTTP 410") {
                        var renewed = record
                        renewed.runtimeSessionID = UUID()
                        activeWatch = renewed
                        persistWatchRecord()
                        beginRuntimeSession(renewed)
                    }
                } catch { }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                playheadRefresh = .now
                guard let player, let watchID = activeWatch?.id else { continue }
                let seconds = player.currentTime().seconds
                guard seconds.isFinite, seconds >= 0 else { continue }
                if lastObservedWatchID != watchID {
                    lastObservedWatchID = watchID
                    lastObservedPlayhead = seconds
                    continue
                }
                if let previous = lastObservedPlayhead, abs(seconds - previous) > 2.5 {
                    activeWatch?.timelineEpoch += 1
                }
                activeWatch?.snapshotSeq += 1
                lastObservedPlayhead = seconds
                let duration = player.currentItem?.duration.seconds ?? 0
                if duration.isFinite, duration > 0, seconds >= duration - 0.35,
                   let record = activeWatch, !record.isCompleted {
                    persistWatchRecord(isCompleted: true)
                    closeRuntimeSession(record, action: record.isEpisodeMode ? "save_progress" : "complete")
                    player.pause()
                }
            }
        }
        .task {
            var lastSampleBucket = 0
            var sampledWatchID: UUID?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard continuousAnalysisEnabled, isAnalysisConfigured, !isAnalyzing,
                      let player, player.rate > 0, let watchID = activeWatch?.id else { continue }
                if sampledWatchID != watchID { sampledWatchID = watchID; lastSampleBucket = 0 }
                let seconds = player.currentTime().seconds
                guard seconds.isFinite, seconds >= 300 else { continue }
                let bucket = Int(seconds / 300)
                guard bucket > lastSampleBucket else { continue }
                lastSampleBucket = bucket
                analyzeCurrentFrame()
            }
        }
        .onChange(of: playheadRefresh) { _, _ in
            if let moment = activeRiskMoment, riskAcknowledgedMomentID != moment.id { player?.pause() }
        }
    }

    private var bottomComposer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 9) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WatchPalette.heart)
                    .frame(width: 34, height: 38)
                    .accessibilityLabel("发送时附带当前画面")
                TextField("聊聊现在的画面…", text: $question)
                    .focused($questionFocused)
                    .font(.system(size: 15))
                    .foregroundStyle(WatchPalette.plum)
                    .tint(WatchPalette.heart)
                    .submitLabel(.send)
                    .onSubmit(askAboutCurrentFrame)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38)
                Button(action: askAboutCurrentFrame) {
                    Group {
                        if isSendingQuestion { ProgressView().tint(.white) }
                        else { Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(WatchPalette.heart, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(player == nil || isSendingQuestion)
                .opacity(player == nil ? 0.45 : 1)
                .accessibilityLabel("带上当前画面发送")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.94), lineWidth: 1))
            .shadow(color: WatchPalette.plum.opacity(0.07), radius: 12, y: 3)

            Text("发送时附带当前画面 · 完整视频留在设备上")
                .font(.system(size: 10))
                .foregroundStyle(.black.opacity(0.40))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [WatchPalette.background.opacity(0.02), WatchPalette.background.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .foregroundStyle(WatchPalette.heart)
                Text("共看对话")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WatchPalette.plum)
                Spacer()
                Text("使用当前聊天模型 · 共看记录独立保存")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.black.opacity(0.40))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if conversation.isEmpty {
                            Text("和沈屿边看边聊。对话保存在这段共看记录里；回答也会参考 Lumi 主聊天的上下文。")
                                .font(.system(size: 13))
                                .foregroundStyle(.black.opacity(0.48))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(13)
                                .background(WatchPalette.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            ForEach(conversation) { line in
                                HStack {
                                    if line.isUser { Spacer(minLength: 42) }
                                    Text(line.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(WatchPalette.plum)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 10)
                                        .background(
                                            line.isUser ? WatchPalette.heart.opacity(0.18) : WatchPalette.background.opacity(0.82),
                                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        )
                                    if !line.isUser { Spacer(minLength: 42) }
                                }
                                .id(line.id)
                            }
                        }
                        if isSendingQuestion {
                            HStack {
                                ProgressView().tint(WatchPalette.heart)
                                Text("沈屿正在看着画面想怎么回答…")
                                    .font(.system(size: 12)).foregroundStyle(.black.opacity(0.45))
                                Spacer()
                            }
                            .padding(.leading, 4)
                            .id("watch-thinking")
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
                .frame(height: 292)
                .onChange(of: conversation.count) { _, _ in
                    guard let lastLine = conversation.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastLine.id, anchor: .bottom) }
                }
                .onChange(of: isSendingQuestion) { _, sending in
                    if sending { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("watch-thinking", anchor: .bottom) } }
                }
            }
        }
        .padding(14)
        .frame(height: 356)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { isAnalysisCardExpanded.toggle() } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("视频画面分析").font(.system(size: 14, weight: .semibold)).foregroundStyle(WatchPalette.plum)
                            Text(isAnalysisConfigured
                                 ? "独立分析模型：\(analysisModel)"
                                 : "还没有配置独立的视频分析模型")
                                .font(.system(size: 11)).foregroundStyle(.black.opacity(0.46))
                        }
                        Image(systemName: isAnalysisCardExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(WatchPalette.plum.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: analyzeCurrentFrame) {
                    HStack(spacing: 6) {
                        if isAnalyzing { ProgressView().tint(WatchPalette.plum) }
                        else { Image(systemName: "sparkle.magnifyingglass") }
                        Text(isAnalyzing ? "正在分析" : "分析当前画面")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchPalette.plum)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(.white.opacity(0.82), in: Capsule())
                }
                .disabled(isAnalyzing || !isAnalysisConfigured)
            }
            if isAnalysisCardExpanded {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                Text("模型配置保存在此设备；聊天仍使用当前聊天模型。")
            }
            .font(.system(size: 10)).foregroundStyle(.black.opacity(0.42))
            Toggle("持续记录剧情记忆", isOn: $continuousAnalysisEnabled)
                .font(.system(size: 11)).tint(WatchPalette.heart)
            if !analysisSummary.isEmpty {
                Text(analysisSummary)
                    .font(.system(size: 13)).foregroundStyle(.black.opacity(0.70))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !analysisMoments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    let currentEpisode = activeWatch?.episodeIndex ?? 1
                    let currentMoments = analysisMoments.filter { ($0.episodeIndex ?? currentEpisode) == currentEpisode }
                    Text("本集剧情记忆 · \(currentMoments.count) 个时间点")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(WatchPalette.plum)
                    ForEach(currentMoments.sorted { $0.playheadSeconds < $1.playheadSeconds }) { moment in
                        Button {
                            guard let player else { return }
                            Task { await player.seek(to: CMTime(seconds: moment.playheadSeconds, preferredTimescale: 600)) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(moment.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WatchPalette.heart).frame(width: 42, alignment: .leading)
                                Text(moment.isRisk ? "需保护 · \(moment.summary)" : moment.summary)
                                    .font(.system(size: 11)).foregroundStyle(.black.opacity(0.64))
                                    .multilineTextAlignment(.leading).lineLimit(3)
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle.fill").font(.system(size: 15)).foregroundStyle(WatchPalette.heart)
                            }
                            .padding(9)
                            .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            }
        }
        .padding(14)
        .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var isAnalysisConfigured: Bool {
        !analysisBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !analysisModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !analysisAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentSubtitle: String {
        _ = playheadRefresh
        guard let player else { return "" }
        let now = player.currentTime().seconds
        return subtitleLines.first(where: { now >= $0.startSeconds && now <= $0.endSeconds })?.text ?? ""
    }

    private var currentDanmaku: WatchDanmakuItem? {
        _ = playheadRefresh
        guard let player else { return nil }
        let now = player.currentTime().seconds
        return danmakuItems.first(where: { now >= $0.playheadSeconds && now < $0.playheadSeconds + 5 })
    }

    private var activeRiskMoment: WatchAnalysisMoment? {
        _ = playheadRefresh
        guard riskProtectionEnabled, let player else { return nil }
        let now = player.currentTime().seconds
        let episodeIndex = activeWatch?.episodeIndex ?? 1
        return analysisMoments.first(where: { $0.isRisk && ($0.episodeIndex ?? episodeIndex) == episodeIndex && $0.id != riskAcknowledgedMomentID && now >= $0.playheadSeconds && now < $0.playheadSeconds + 12 })
    }

    private var watchToolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { isWatchToolsCardExpanded.toggle() } label: {
                    HStack(spacing: 8) {
                        Text("观看工具").font(.system(size: 14, weight: .semibold)).foregroundStyle(WatchPalette.plum)
                        Image(systemName: isWatchToolsCardExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(WatchPalette.plum.opacity(0.65))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { saveTicket() } label: { Label("加入票夹", systemImage: "ticket.fill") }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(WatchPalette.plum)
            }
            if isWatchToolsCardExpanded {
            Toggle("高强度片段保护", isOn: $riskProtectionEnabled)
                .font(.system(size: 12)).tint(WatchPalette.heart)
            HStack {
                Button { markCurrentMomentForProtection() } label: {
                    Label("标记当前片段", systemImage: "hand.raised.fill")
                }
                Spacer()
                Button { subtitlePickerPresented = true } label: {
                    Label(subtitleLines.isEmpty ? "导入字幕" : "已载入字幕", systemImage: "captions.bubble")
                }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(WatchPalette.heart)
            HStack(spacing: 7) {
                TextField("此刻的弹幕", text: $danmakuDraft)
                    .font(.system(size: 12)).padding(9)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                Button("发送") { addDanmaku() }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(WatchPalette.heart)
                    .disabled(danmakuDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Toggle("分集观看", isOn: $isEpisodeMode)
                .font(.system(size: 12)).tint(WatchPalette.heart)
            if isEpisodeMode {
                Text("分集进度与对话会单独保存在这段观看记录里。每次选入新视频都会创建一个分集条目。")
                    .font(.system(size: 11)).foregroundStyle(.black.opacity(0.48))
            }
            }
        }
        .padding(14)
        .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .fileImporter(isPresented: $subtitlePickerPresented, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                subtitleLines = Self.parseSubtitles(try String(contentsOf: url, encoding: .utf8))
                persistWatchRecord()
            } catch { errorMessage = "字幕读取失败：\(error.localizedDescription)"; showError = true }
        }
        .onChange(of: riskProtectionEnabled) { _, _ in persistWatchRecord() }
        .onChange(of: isEpisodeMode) { _, _ in persistWatchRecord() }
    }

    private func saveTicket() {
        guard let player, let item = player.currentItem else { return }
        let at = max(0, player.currentTime().seconds)
        let image = try? captureFrame(from: item.asset, seconds: at)
        ticketItems.insert(WatchTicketItem(
            playheadSeconds: at,
            title: "\(videoTitle) · \(String(format: "%02d:%02d", Int(at) / 60, Int(at) % 60))",
            imageData: image,
            note: analysisMoments.last(where: { ($0.episodeIndex ?? activeWatch?.episodeIndex ?? 1) == (activeWatch?.episodeIndex ?? 1) && $0.playheadSeconds <= at })?.summary ?? "",
            episodeIndex: activeWatch?.episodeIndex
        ), at: 0)
        persistWatchRecord()
        syncRuntimeTickets()
    }

    private func markCurrentMomentForProtection() {
        guard let player else { return }
        let at = max(0, player.currentTime().seconds)
        let clock = String(format: "%02d:%02d", Int(at) / 60, Int(at) % 60)
        analysisMoments.append(WatchAnalysisMoment(
            playheadSeconds: at,
            title: clock,
            summary: "用户标记的需保护片段",
            isRisk: true,
            episodeIndex: activeWatch?.episodeIndex ?? 1
        ))
        riskProtectionEnabled = true
        persistWatchRecord()
        player.pause()
    }

    private func addDanmaku() {
        let text = danmakuDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let player else { return }
        danmakuItems.append(WatchDanmakuItem(playheadSeconds: max(0, player.currentTime().seconds), text: text))
        danmakuDraft = ""
        persistWatchRecord()
    }

    private static func parseSubtitles(_ source: String) -> [WatchSubtitleLine] {
        source.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n\n")
            .compactMap { block in
            let rows = block.split(separator: "\n").map(String.init)
            if rows.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") == true ||
                rows.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("NOTE") == true ||
                rows.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("STYLE") == true ||
                rows.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("REGION") == true {
                return nil
            }
            guard let index = rows.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = rows[index].components(separatedBy: "-->")
            guard times.count == 2, let start = parseSubtitleClock(times[0]), let end = parseSubtitleClock(times[1]) else { return nil }
            let text = rows.dropFirst(index + 1)
                .joined(separator: "\n")
                .replacingOccurrences(of: #"</?(?:v|i|b|u|c(?:\.[A-Za-z0-9_-]+)*|ruby|rt)(?:\s+[^>]*)?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return WatchSubtitleLine(startSeconds: start, endSeconds: end, text: text)
        }.sorted { $0.startSeconds < $1.startSeconds }
    }

    private static func parseSubtitleClock(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? raw
        let parts = cleaned.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]), m < 60, s < 60 {
            return h * 3600 + m * 60 + s
        }
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]), s < 60 {
            return m * 60 + s
        }
        return nil
    }

    @ViewBuilder private var playerCard: some View {
        if let player {
            VStack(alignment: .leading, spacing: 9) {
                VideoPlayer(player: player)
                    .frame(height: 238)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if let moment = activeRiskMoment, riskAcknowledgedMomentID != moment.id {
                            VStack(spacing: 12) {
                                Image(systemName: "hand.raised.fill").font(.system(size: 28))
                                Text("高强度片段保护").font(.system(size: 16, weight: .semibold))
                                Text("你标记的片段 · \(moment.title)").font(.system(size: 12)).opacity(0.82)
                                Button("继续播放") {
                                    riskAcknowledgedMomentID = moment.id
                                    player.play()
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(.white.opacity(0.18), in: Capsule())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.96))
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !currentSubtitle.isEmpty {
                            Text(currentSubtitle)
                                .font(.system(size: 15, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white).padding(.bottom, 18)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let item = currentDanmaku {
                            Text(item.text)
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .shadow(color: .black, radius: 3)
                                .padding(.top, 44).padding(.trailing, 14)
                        }
                    }
                HStack {
                    Button {
                        editedVideoTitle = videoTitle
                        showingRenameVideo = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(videoTitle.isEmpty ? "正在播放" : videoTitle)
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(WatchPalette.plum)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WatchPalette.plum.opacity(0.55))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("修改视频名称")
                    Spacer()
                    Text(timestampText(for: player))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .padding(12)
            .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Button { isPickingVideo = true } label: {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 33, weight: .light)).foregroundStyle(WatchPalette.heart)
                    Text("从文件中选择视频").font(.system(size: 15, weight: .semibold)).foregroundStyle(WatchPalette.plum)
                    Text("视频在 Lumi 内原生播放，不会整段上传。")
                        .font(.system(size: 12)).foregroundStyle(.black.opacity(0.46))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 238)
                .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(WatchPalette.heart.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        }
    }

    private func importVideo(_ result: Result<[URL], Error>) {
        guard !isSendingQuestion && !isAnalyzing else {
            errorMessage = "当前视频分析或回复完成后，再切换视频会更安全。"
            showError = true
            return
        }
        do {
            guard let sourceURL = try result.get().first else { return }
            let sourceHasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if sourceHasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            let videosDirectory = WatchHistoryStore.videoDirectory
            try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
            let fileExtension = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
            let storedURL = videosDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: sourceURL, to: storedURL)
            let bookmark = try storedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            persistWatchRecord()
            let addingEpisode = isEpisodeMode
            let previousEpisode = activeWatch
            if let previousEpisode { closeRuntimeSession(previousEpisode, action: "save_progress") }
            player?.pause()
            if holdsVideoAccess, let localVideoURL { localVideoURL.stopAccessingSecurityScopedResource() }
            localVideoURL = storedURL
            holdsVideoAccess = false
            player = AVPlayer(url: storedURL)
            videoTitle = sourceURL.deletingPathExtension().lastPathComponent
            conversation = []
            analysisSummary = ""
            analysisMoments = []
            subtitleLines = []
            danmakuItems = []
            ticketItems = []
            isEpisodeMode = addingEpisode
            if addingEpisode, let previousEpisode {
                conversation = previousEpisode.conversation
                analysisSummary = previousEpisode.analysisSummary ?? ""
                analysisMoments = previousEpisode.analysisMoments
                for index in analysisMoments.indices where analysisMoments[index].episodeIndex == nil {
                    analysisMoments[index].episodeIndex = previousEpisode.episodeIndex ?? 1
                }
                ticketItems = previousEpisode.tickets
            }
            let nextEpisodeIndex = (previousEpisode?.episodeIndex ?? 1) + 1
            let episodeGroupID = addingEpisode ? (previousEpisode?.episodeGroupID ?? previousEpisode?.id.uuidString ?? UUID().uuidString) : nil
            var newWatch = WatchHistoryRecord(
                id: UUID(), title: videoTitle, videoBookmark: bookmark,
                playheadSeconds: 0, durationSeconds: 0, isCompleted: false,
                coverImageData: nil, conversation: [], analysisSummary: nil, updatedAt: .now
            )
            newWatch.episodeGroupID = episodeGroupID
            newWatch.episodeIndex = addingEpisode ? nextEpisodeIndex : nil
            newWatch.isEpisodeMode = addingEpisode
            newWatch.runtimeSessionID = UUID()
            activeWatch = newWatch
            if let asset = player?.currentItem?.asset, let cover = try? captureFrame(from: asset, seconds: 0) {
                activeWatch?.coverImageData = makeHistoryThumbnail(from: UIImage(data: cover))
            }
            persistWatchRecord()
            beginRuntimeSession(newWatch)
            player?.play()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func restoreWatch(_ record: WatchHistoryRecord) {
        guard !isSendingQuestion && !isAnalyzing else {
            errorMessage = "当前视频分析或回复完成后，再切换历史记录会更安全。"
            showError = true
            return
        }
        do {
            var stale = false
            let sourceURL = try URL(resolvingBookmarkData: record.videoBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let sourceHasAccess = sourceURL.startAccessingSecurityScopedResource()
            var restoredRecord = record
            restoredRecord.runtimeSessionID = UUID()
            let managedPath = WatchHistoryStore.videoDirectory.standardizedFileURL.path + "/"
            let isManagedVideo = sourceURL.standardizedFileURL.path.hasPrefix(managedPath)
            defer {
                if sourceHasAccess && !isManagedVideo { sourceURL.stopAccessingSecurityScopedResource() }
            }
            let playbackURL: URL
            if isManagedVideo {
                playbackURL = sourceURL
            } else {
                let directory = WatchHistoryStore.videoDirectory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
                let copiedURL = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
                playbackURL = copiedURL
                restoredRecord.videoBookmark = try copiedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                WatchHistoryStore.upsert(restoredRecord)
            }
            persistWatchRecord()
            if holdsVideoAccess, let localVideoURL { localVideoURL.stopAccessingSecurityScopedResource() }
            player?.pause()
            localVideoURL = playbackURL
            holdsVideoAccess = isManagedVideo && sourceHasAccess
            videoTitle = restoredRecord.title
            conversation = restoredRecord.conversation
            analysisSummary = restoredRecord.analysisSummary ?? ""
            analysisMoments = restoredRecord.analysisMoments
            danmakuItems = restoredRecord.danmakuItems
            ticketItems = restoredRecord.tickets
            riskProtectionEnabled = restoredRecord.riskProtectionEnabled
            isEpisodeMode = restoredRecord.isEpisodeMode || restoredRecord.episodeGroupID != nil
            subtitleLines = restoredRecord.subtitles
            activeWatch = restoredRecord
            beginRuntimeSession(restoredRecord)
            if stale {
                activeWatch?.videoBookmark = try playbackURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            player = AVPlayer(url: playbackURL)
            guard let player, let item = player.currentItem else { return }
            Task {
                _ = try? await item.asset.load(.duration)
                await player.seek(to: CMTime(seconds: max(0, restoredRecord.playheadSeconds), preferredTimescale: 600))
                player.play()
                persistWatchRecord()
            }
            showingHistory = false
        } catch {
            errorMessage = "找不到这段视频，可能已被移动或删除。请重新选择视频。"
            showError = true
        }
    }

    private func renameCurrentVideo() {
        let renamed = editedVideoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !renamed.isEmpty else { return }
        videoTitle = renamed
        activeWatch?.title = renamed
        persistWatchRecord()
    }

    private func exitWatch() {
        persistWatchRecord(isCompleted: false)
        if let activeWatch { closeRuntimeSession(activeWatch, action: "save_progress") }
        player?.pause()
        dismiss()
    }

    private func beginRuntimeSession(_ record: WatchHistoryRecord) {
        guard let runtimeID = record.runtimeSessionID else { return }
        let rawDuration = record.durationSeconds
        let durationMS = rawDuration.isFinite ? Int(max(0, rawDuration) * 1000) : 0
        runtimeSetupTask = Task {
            do {
                let retainedTickets = try await api.createWatchRuntimeSession(
                    clientID: WatchHistoryStore.clientID,
                    sessionID: runtimeID.uuidString,
                    viewingID: record.episodeGroupID ?? record.id.uuidString,
                    mediaID: record.id.uuidString,
                    title: record.title,
                    durationMS: durationMS,
                    playheadMS: Int(max(0, record.playheadSeconds) * 1000)
                )
                var mergedByID = Dictionary(uniqueKeysWithValues: retainedTickets.compactMap { ticket -> (UUID, WatchTicketItem)? in
                    guard let id = UUID(uuidString: ticket.id) else { return nil }
                    return (id, WatchTicketItem(
                        id: id,
                        playheadSeconds: Double(ticket.playheadMS) / 1000,
                        title: ticket.title,
                        imageData: nil,
                        note: ticket.note,
                        episodeIndex: ticket.episodeIndex
                    ))
                })
                for ticket in record.tickets { mergedByID[ticket.id] = ticket }
                let mergedTickets = mergedByID.values.sorted { $0.playheadSeconds > $1.playheadSeconds }
                if !retainedTickets.isEmpty {
                    ticketItems = mergedTickets
                    activeWatch?.tickets = mergedTickets
                    persistWatchRecord()
                }
                let runtimeTickets = mergedTickets.map { item in
                    WatchRuntimeTicket(
                        id: item.id.uuidString,
                        playheadMS: Int(max(0, item.playheadSeconds) * 1000),
                        title: item.title,
                        note: item.note,
                        episodeIndex: item.episodeIndex
                    )
                }
                if !runtimeTickets.isEmpty {
                    try? await api.replaceWatchRuntimeTickets(
                        clientID: WatchHistoryStore.clientID,
                        sessionID: runtimeID.uuidString,
                        tickets: runtimeTickets
                    )
                }
                runtimeAPIAvailable = true
            } catch { runtimeAPIAvailable = false }
        }
    }

    private func closeRuntimeSession(_ record: WatchHistoryRecord, action: String) {
        guard let runtimeID = record.runtimeSessionID, !endingRuntimeSessions.contains(runtimeID) else { return }
        endingRuntimeSessions.insert(runtimeID)
        let setupTask = runtimeSetupTask
        Task {
            await setupTask?.value
            let runtimeTickets = record.tickets.map { item in
                WatchRuntimeTicket(
                    id: item.id.uuidString,
                    playheadMS: Int(max(0, item.playheadSeconds) * 1000),
                    title: item.title,
                    note: item.note,
                    episodeIndex: item.episodeIndex
                )
            }
            try? await api.replaceWatchRuntimeTickets(
                clientID: WatchHistoryStore.clientID,
                sessionID: runtimeID.uuidString,
                tickets: runtimeTickets
            )
            try? await api.endWatchRuntimeSession(clientID: WatchHistoryStore.clientID, sessionID: runtimeID.uuidString, action: action)
        }
    }

    private func syncRuntimeTickets() {
        guard let record = activeWatch, let runtimeID = record.runtimeSessionID else { return }
        let runtimeTickets = ticketItems.map { item in
            WatchRuntimeTicket(
                id: item.id.uuidString,
                playheadMS: Int(max(0, item.playheadSeconds) * 1000),
                title: item.title,
                note: item.note,
                episodeIndex: item.episodeIndex
            )
        }
        Task {
            try? await api.replaceWatchRuntimeTickets(
                clientID: WatchHistoryStore.clientID,
                sessionID: runtimeID.uuidString,
                tickets: runtimeTickets
            )
        }
    }

    private func persistWatchRecord(isCompleted: Bool? = nil) {
        guard var record = activeWatch else { return }
        if let player {
            let seconds = player.currentTime().seconds
            if seconds.isFinite, seconds >= 0 { record.playheadSeconds = seconds }
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration.isFinite, duration >= 0 { record.durationSeconds = duration }
        }
        record.conversation = conversation
        record.playheadSeconds = max(0, record.playheadSeconds)
        record.analysisSummary = analysisSummary
        record.analysisMoments = analysisMoments
        record.danmakuItems = danmakuItems
        record.tickets = ticketItems
        record.riskProtectionEnabled = riskProtectionEnabled
        record.isEpisodeMode = isEpisodeMode
        record.episodeGroupID = isEpisodeMode ? (record.episodeGroupID ?? record.id.uuidString) : nil
        if isEpisodeMode, record.episodeIndex == nil { record.episodeIndex = 1 }
        record.subtitles = subtitleLines
        record.updatedAt = .now
        if let isCompleted { record.isCompleted = isCompleted }
        activeWatch = record
        WatchHistoryStore.upsert(record)
        historyRecords = WatchHistoryStore.read()
    }

    private func reloadWatchHistory() {
        historyRecords = WatchHistoryStore.read()
    }

    private func deleteWatchRecord(_ record: WatchHistoryRecord) {
        WatchHistoryStore.delete(record)
        let remaining = WatchHistoryStore.read()
        var stale = false
        if let url = try? URL(resolvingBookmarkData: record.videoBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            let managedPath = WatchHistoryStore.videoDirectory.standardizedFileURL.path + "/"
            if url.standardizedFileURL.path.hasPrefix(managedPath) {
                let stillReferenced = remaining.contains { other in
                    var otherStale = false
                    guard let otherURL = try? URL(resolvingBookmarkData: other.videoBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &otherStale) else { return false }
                    return otherURL.standardizedFileURL == url.standardizedFileURL
                }
                if !stillReferenced { try? FileManager.default.removeItem(at: url) }
            }
        }
        historyRecords = remaining
    }

    private func makeHistoryThumbnail(from image: UIImage?) -> Data? {
        guard let image else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 260))
        let thumbnail = renderer.image { _ in
            let bounds = CGRect(x: 0, y: 0, width: 420, height: 260)
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
        return thumbnail.jpegData(compressionQuality: 0.58)
    }

    private func askAboutCurrentFrame() {
        guard let player, let item = player.currentItem else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        let typedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        question = ""
        questionFocused = false
        isSendingQuestion = true
        Task {
            do {
                let jpeg = try captureFrame(from: item.asset, seconds: seconds)
                let minutes = Int(seconds) / 60
                let remainingSeconds = Int(seconds) % 60
                let clock = String(format: "%02d:%02d", minutes, remainingSeconds)
                let snapshotSequence = activeWatch?.snapshotSeq ?? 0
                let timelineEpoch = activeWatch?.timelineEpoch ?? 0
                let episodeLabel = activeWatch?.episodeIndex.map { "｜第 \($0) 集" } ?? ""
                var text = "【一起看｜\(videoTitle)\(episodeLabel)｜当前进度 \(clock)｜时间线 \(timelineEpoch) / \(snapshotSequence)】\n\(typedQuestion.isEmpty ? "看看现在这一帧，和我聊聊此刻的画面。" : typedQuestion)"
                if !currentSubtitle.isEmpty { text += "\n\n【当前字幕】\n\(currentSubtitle)" }
                let timedComments = danmakuItems.filter { $0.playheadSeconds <= seconds }.sorted { $0.playheadSeconds < $1.playheadSeconds }
                if !timedComments.isEmpty {
                    text += "\n\n【本段观看的时间弹幕】\n" + timedComments.map { "[\(String(format: "%02d:%02d", Int($0.playheadSeconds) / 60, Int($0.playheadSeconds) % 60))] \($0.text)" }.joined(separator: "\n")
                }
                let currentEpisodeIndex = activeWatch?.episodeIndex ?? 1
                let watchedMoments = analysisMoments.filter {
                    let episode = $0.episodeIndex ?? currentEpisodeIndex
                    return episode < currentEpisodeIndex || (episode == currentEpisodeIndex && $0.playheadSeconds <= seconds)
                }.sorted {
                    if $0.episodeIndex != $1.episodeIndex { return ($0.episodeIndex ?? currentEpisodeIndex) < ($1.episodeIndex ?? currentEpisodeIndex) }
                    return $0.playheadSeconds < $1.playheadSeconds
                }
                if !watchedMoments.isEmpty {
                    text += "\n\n【本段视频截至当前进度的共看记忆】\n" + watchedMoments.map { "[\(String(format: "%02d:%02d", Int($0.playheadSeconds) / 60, Int($0.playheadSeconds) % 60))] \($0.summary)" }.joined(separator: "\n")
                } else if !analysisSummary.isEmpty {
                    text += "\n\n【独立视频分析模型对当前画面的观察】\n\(analysisSummary)"
                }
                conversation.append(WatchConversationLine(text: typedQuestion.isEmpty ? "看看现在这一帧，和我聊聊此刻的画面。" : typedQuestion, isUser: true))
                persistWatchRecord()
                let watchID = activeWatch?.episodeGroupID ?? activeWatch?.id.uuidString ?? UUID().uuidString
                let reply = await onAskAboutVideo(watchID, text, jpeg.base64EncodedString())
                if let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    conversation.append(WatchConversationLine(text: reply, isUser: false))
                    persistWatchRecord()
                } else {
                    errorMessage = "消息已记入聊天，但暂时没有收到回复。"
                    showError = true
                }
            } catch {
                errorMessage = watchRequestErrorDescription(error)
                showError = true
            }
            isSendingQuestion = false
        }
    }

    private func analyzeCurrentFrame() {
        guard let player, let item = player.currentItem else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        let sourceWatchID = activeWatch?.id
        let sourceEpoch = activeWatch?.timelineEpoch ?? 0
        let sourceSnapshotSeq = activeWatch?.snapshotSeq ?? 0
        isAnalyzing = true
        Task {
            do {
                let jpeg = try captureFrame(from: item.asset, seconds: seconds)
                let result = try await api.analyzeWatchFrame(
                    imageBase64: jpeg.base64EncodedString(),
                    title: videoTitle,
                    playheadMS: Int(seconds * 1000),
                    analysisBaseURL: analysisBaseURL,
                    model: analysisModel,
                    apiKey: analysisAPIKey
                )
                guard activeWatch?.id == sourceWatchID,
                      activeWatch?.timelineEpoch == sourceEpoch else {
                    isAnalyzing = false
                    return
                }
                analysisSummary = result.summary
                let moment = WatchAnalysisMoment(playheadSeconds: seconds, title: String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60), summary: result.summary, isRisk: result.risk, episodeIndex: activeWatch?.episodeIndex ?? 1)
                analysisMoments.removeAll { abs($0.playheadSeconds - seconds) < 3 }
                analysisMoments.append(moment)
                analysisMoments.sort { $0.playheadSeconds < $1.playheadSeconds }
                if result.risk { riskProtectionEnabled = true }
                persistWatchRecord()
                if let runtimeID = activeWatch?.runtimeSessionID {
                    try? await api.recordWatchAnalysis(
                        clientID: WatchHistoryStore.clientID,
                        sessionID: runtimeID.uuidString,
                        momentID: moment.id.uuidString,
                        timelineEpoch: sourceEpoch,
                        snapshotSeq: sourceSnapshotSeq,
                        playheadMS: Int(seconds * 1000),
                        summary: result.summary,
                        risk: result.risk,
                        model: result.model ?? analysisModel
                    )
                }
            } catch {
                errorMessage = watchRequestErrorDescription(error)
                showError = true
            }
            isAnalyzing = false
        }
    }

    private func watchRequestErrorDescription(_ error: Error) -> String {
        let networkError = error as NSError
        if networkError.domain == NSURLErrorDomain, networkError.code == NSURLErrorTimedOut {
            return "请求超时：模型或中转站没有及时返回。请确认分析模型支持图片输入、API 地址可用后再试。"
        }
        return error.localizedDescription
    }

    private func captureFrame(from asset: AVAsset, seconds: Double) throws -> Data {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let frame = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        guard let jpeg = UIImage(cgImage: frame).jpegData(compressionQuality: 0.72) else {
            throw NSError(domain: "LumiWatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前画面暂时无法读取"])
        }
        return jpeg
    }

    private func timestampText(for player: AVPlayer) -> String {
        let value = player.currentTime().seconds
        guard value.isFinite, value >= 0 else { return "00:00" }
        return String(format: "%02d:%02d", Int(value) / 60, Int(value) % 60)
    }
}

private struct WatchConversationLine: Codable, Identifiable {
    let id: UUID
    let text: String
    let isUser: Bool

    init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

private struct WatchHistoryRecord: Codable, Identifiable {
    var id: UUID
    var title: String
    var videoBookmark: Data
    var playheadSeconds: Double
    var durationSeconds: Double
    var isCompleted: Bool
    var coverImageData: Data?
    var conversation: [WatchConversationLine]
    var analysisSummary: String?
    var updatedAt: Date
    var analysisMoments: [WatchAnalysisMoment] = []
    var subtitles: [WatchSubtitleLine] = []
    var danmakuItems: [WatchDanmakuItem] = []
    var tickets: [WatchTicketItem] = []
    var riskProtectionEnabled = false
    var isEpisodeMode = false
    var episodeGroupID: String?
    var episodeIndex: Int?
    var timelineEpoch = 0
    var snapshotSeq = 0
    var runtimeSessionID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id, title, videoBookmark, playheadSeconds, durationSeconds, isCompleted
        case coverImageData, conversation, analysisSummary, updatedAt, analysisMoments, subtitles, danmakuItems, tickets, riskProtectionEnabled, isEpisodeMode, episodeGroupID, episodeIndex, timelineEpoch, snapshotSeq, runtimeSessionID
    }

    init(id: UUID, title: String, videoBookmark: Data, playheadSeconds: Double, durationSeconds: Double,
         isCompleted: Bool, coverImageData: Data?, conversation: [WatchConversationLine],
         analysisSummary: String? = nil, updatedAt: Date) {
        self.id = id
        self.title = title
        self.videoBookmark = videoBookmark
        self.playheadSeconds = playheadSeconds
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
        self.coverImageData = coverImageData
        self.conversation = conversation
        self.analysisSummary = analysisSummary
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        videoBookmark = try values.decode(Data.self, forKey: .videoBookmark)
        playheadSeconds = try values.decode(Double.self, forKey: .playheadSeconds)
        durationSeconds = try values.decode(Double.self, forKey: .durationSeconds)
        isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
        coverImageData = try values.decodeIfPresent(Data.self, forKey: .coverImageData)
        conversation = try values.decode([WatchConversationLine].self, forKey: .conversation)
        analysisSummary = try values.decodeIfPresent(String.self, forKey: .analysisSummary)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        analysisMoments = try values.decodeIfPresent([WatchAnalysisMoment].self, forKey: .analysisMoments) ?? []
        subtitles = try values.decodeIfPresent([WatchSubtitleLine].self, forKey: .subtitles) ?? []
        danmakuItems = try values.decodeIfPresent([WatchDanmakuItem].self, forKey: .danmakuItems) ?? []
        tickets = try values.decodeIfPresent([WatchTicketItem].self, forKey: .tickets) ?? []
        riskProtectionEnabled = try values.decodeIfPresent(Bool.self, forKey: .riskProtectionEnabled) ?? false
        isEpisodeMode = try values.decodeIfPresent(Bool.self, forKey: .isEpisodeMode) ?? false
        episodeGroupID = try values.decodeIfPresent(String.self, forKey: .episodeGroupID)
        episodeIndex = try values.decodeIfPresent(Int.self, forKey: .episodeIndex)
        timelineEpoch = try values.decodeIfPresent(Int.self, forKey: .timelineEpoch) ?? 0
        snapshotSeq = try values.decodeIfPresent(Int.self, forKey: .snapshotSeq) ?? 0
        runtimeSessionID = try values.decodeIfPresent(UUID.self, forKey: .runtimeSessionID)
    }
}

private struct WatchAnalysisMoment: Codable, Identifiable {
    var id = UUID()
    var playheadSeconds: Double
    var title: String
    var summary: String
    var isRisk = false
    var episodeIndex: Int?
}

private struct WatchSubtitleLine: Codable, Identifiable {
    var id = UUID()
    var startSeconds: Double
    var endSeconds: Double
    var text: String
}

private struct WatchDanmakuItem: Codable, Identifiable {
    var id = UUID()
    var playheadSeconds: Double
    var text: String
}

private struct WatchTicketItem: Codable, Identifiable {
    var id = UUID()
    var playheadSeconds: Double
    var title: String
    var imageData: Data?
    var note: String
    var episodeIndex: Int? = nil
}

private enum WatchHistoryStore {
    private static let storageKey = "lumi.togetherWatch.history.v1"

    static var clientID: String {
        let key = "lumi.togetherWatch.clientID.v1"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    static var videoDirectory: URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return supportDirectory
            .appendingPathComponent("Lumi", isDirectory: true)
            .appendingPathComponent("WatchVideos", isDirectory: true)
    }

    private static var storageURL: URL? {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent("Lumi", isDirectory: true)
            .appendingPathComponent("TogetherWatchHistory.json", isDirectory: false)
    }

    static func read() -> [WatchHistoryRecord] {
        let fileRecords: [WatchHistoryRecord]? = storageURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(decodeRecords)
        let defaultsRecords: [WatchHistoryRecord]? = UserDefaults.standard.data(forKey: storageKey)
            .flatMap(decodeRecords)
        let allRecords = (fileRecords ?? []) + (defaultsRecords ?? [])
        var newestByID: [UUID: WatchHistoryRecord] = [:]
        for record in allRecords {
            if let saved = newestByID[record.id], saved.updatedAt >= record.updatedAt { continue }
            newestByID[record.id] = record
        }
        return newestByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func upsert(_ record: WatchHistoryRecord) {
        var records = read().filter { $0.id != record.id }
        records.insert(record, at: 0)
        write(records)
    }

    static func delete(_ record: WatchHistoryRecord) {
        write(read().filter { $0.id != record.id })
    }

    private static func decodeRecords(_ data: Data) -> [WatchHistoryRecord]? {
        try? JSONDecoder().decode(LossyWatchHistoryRecords.self, from: data).records
    }

    private static func write(_ records: [WatchHistoryRecord]) {
        guard let storageURL, let data = try? JSONEncoder().encode(records) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
            if data.count <= 512_000 { UserDefaults.standard.set(data, forKey: storageKey) }
            else { UserDefaults.standard.removeObject(forKey: storageKey) }
        } catch {
            // Preserve a recoverable copy if the app support directory is temporarily unavailable.
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

private struct LossyWatchHistoryRecords: Decodable {
    let records: [WatchHistoryRecord]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [WatchHistoryRecord] = []
        while !container.isAtEnd {
            let recordDecoder = try container.superDecoder()
            do {
                decoded.append(try WatchHistoryRecord(from: recordDecoder))
            } catch { continue }
        }
        records = decoded
    }
}

private struct WatchHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var records: [WatchHistoryRecord]
    let onSelect: (WatchHistoryRecord) -> Void
    let onDelete: (WatchHistoryRecord) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(WatchPalette.plum.opacity(0.62))
                        Text("还没有观看记录")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(WatchPalette.plum)
                        Text("退出共看时会自动保存视频、播放进度和独立对话。")
                            .font(.system(size: 14))
                            .foregroundStyle(WatchPalette.plum.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WatchPalette.background)
                } else {
                    List {
                    ForEach(records) { record in
                        Button { onSelect(record) } label: {
                            HStack(spacing: 13) {
                                Group {
                                    if let data = record.coverImageData, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.system(size: 22)).foregroundStyle(WatchPalette.heart)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(WatchPalette.background)
                                    }
                                }
                                .frame(width: 88, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(WatchPalette.plum)
                                        .lineLimit(1)
                                    Text("\(record.episodeIndex.map { "第 \($0) 集 · " } ?? "")继续观看 · \(Self.clock(record.playheadSeconds)) · \(record.conversation.count) 条对话")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.black.opacity(0.48))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.black.opacity(0.30))
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(WatchPalette.background)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete(record) } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(WatchPalette.background)
                }
            }
            .background(WatchPalette.background)
            .onAppear {
                // Re-read when the sheet becomes visible so it always reflects the
                // durable file, including when no video is currently selected.
                records = WatchHistoryStore.read()
            }
            .navigationTitle("历史观看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WatchPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.foregroundStyle(WatchPalette.plum)
                }
            }
        }
        .tint(WatchPalette.plum)
    }

    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct WatchTicketShelf: View {
    @Environment(\.dismiss) private var dismiss
    let items: [WatchTicketItem]
    let onSelect: (WatchTicketItem) -> Void
    let onDelete: (WatchTicketItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("票夹还是空的", systemImage: "ticket", description: Text("播放时点“加入票夹”，保存喜欢的画面和时间点。"))
                } else {
                    List(items) { item in
                        Button { onSelect(item) } label: {
                            HStack(spacing: 12) {
                                if let imageData = item.imageData, let image = UIImage(data: imageData) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 88, height: 58).clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Image(systemName: "ticket.fill").frame(width: 88, height: 58)
                                        .background(WatchPalette.panel, in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(WatchPalette.plum).lineLimit(1)
                                    Text(item.note.isEmpty ? "点击跳转到此处" : item.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.padding(.vertical, 3)
                        }
                        .listRowBackground(WatchPalette.card)
                        .swipeActions { Button("删除", role: .destructive) { onDelete(item) } }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background(WatchPalette.background)
            .navigationTitle("票夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .tint(WatchPalette.plum)
    }
}

private struct WatchAnalysisSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var baseURL: String
    @Binding var model: String
    @Binding var apiKey: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.example.com/v1", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("例如：vision-model-name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("模型 API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("独立视频分析模型")
                } footer: {
                    Text("填写 OpenAI 兼容接口的 HTTPS 地址、模型名称和密钥。密钥保存在 iPhone 钥匙串，分析时通过 Lumi 后端发送。")
                }

                Section {
                    Button("保存配置") {
                        baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
                        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        LumiKeychain.write(apiKey, account: "watch-analysis-api-key")
                        dismiss()
                    }
                    .disabled(baseURL.isEmpty || model.isEmpty || apiKey.isEmpty)
                    .foregroundStyle(WatchPalette.heart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(WatchPalette.background)
            .tint(WatchPalette.heart)
            .navigationTitle("分析模型设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.foregroundStyle(WatchPalette.plum)
                }
            }
        }
    }
}

private enum WatchPalette {
    static let background = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let heart = Color(red: 0.73, green: 0.36, blue: 0.45)
    static let pulse = Color(red: 0.95, green: 0.56, blue: 0.67)
    static let plum = Color(red: 0.40, green: 0.24, blue: 0.27)
    static let card = Color.white.opacity(0.72)
    static let panel = Color(red: 0.948, green: 0.882, blue: 0.895).opacity(0.60)
}
