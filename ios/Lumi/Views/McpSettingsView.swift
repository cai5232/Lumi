import SwiftUI

private enum McpStyle {
    static let page = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let surface = Color.white
    static let tint = Color(red: 0.66, green: 0.35, blue: 0.47)
    static let ink = Color(red: 0.23, green: 0.19, blue: 0.21)
    static let muted = Color(red: 0.56, green: 0.51, blue: 0.54)
    static let line = Color(red: 0.93, green: 0.88, blue: 0.90)
}

struct McpSettingsView: View {
    @State private var settings = McpServerSettings(servers: [], revision: 0)
    @State private var isLoading = true
    @State private var notice: String?
    private let api = LumiAPIClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView().tint(McpStyle.tint).frame(maxWidth: .infinity).padding(.vertical, 48)
                } else if settings.servers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(McpStyle.tint)
                        Text("後端尚未設定 MCP 伺服器").font(.system(size: 16, weight: .semibold)).foregroundStyle(McpStyle.ink)
                        Text("將伺服器加入 Lumi 後端後，就能在這裡控制開關。")
                            .font(.system(size: 13)).foregroundStyle(McpStyle.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 38).padding(.horizontal, 22)
                    .background(McpStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    VStack(spacing: 11) {
                        ForEach(settings.servers) { server in
                            McpServerCard(server: server) { enabled in await setEnabled(server, enabled: enabled) }
                        }
                    }
                }
                if let notice {
                    Text(notice).font(.system(size: 12)).foregroundStyle(McpStyle.muted).padding(.horizontal, 3)
                }
                Text("伺服器憑證安全保存在 Lumi 後端。已連線的工具可供聊天使用。")
                    .font(.system(size: 12)).foregroundStyle(McpStyle.muted).padding(.horizontal, 3)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 30)
        }
        .background(McpStyle.page.ignoresSafeArea())
        .navigationTitle("MCP 伺服器").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .preferredColorScheme(.light)
    }

    private func load() async {
        isLoading = true
        do { settings = try await api.fetchMcpServers(); notice = nil }
        catch { notice = "目前無法載入伺服器：\(error.localizedDescription)" }
        isLoading = false
    }
    private func setEnabled(_ server: McpRemoteServer, enabled: Bool) async {
        guard let index = settings.servers.firstIndex(where: { $0.id == server.id }) else { return }
        settings.servers[index].enabled = enabled
        do { settings = try await api.setMcpServerEnabled(server.id, enabled: enabled); notice = nil }
        catch {
            settings.servers[index].enabled = server.enabled
            notice = "開關更新失敗：\(error.localizedDescription)"
        }
    }
}

private struct McpServerCard: View {
    let server: McpRemoteServer
    let onToggle: (Bool) async -> Void
    @State private var isUpdating = false
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(McpStyle.tint)
                .frame(width: 44, height: 44).background(McpStyle.page, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(server.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(McpStyle.ink).lineLimit(1)
                    Text(transportLabel)
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(McpStyle.tint).padding(.horizontal, 7).padding(.vertical, 3).background(McpStyle.page, in: Capsule())
                }
                Text("\(server.tools.count) 個工具 · 由後端管理").font(.system(size: 11)).foregroundStyle(McpStyle.muted)
            }
            Spacer(minLength: 0)
            Toggle("啟用 \(server.name)", isOn: Binding(get: { server.enabled }, set: { value in
                isUpdating = true
                Task { await onToggle(value); isUpdating = false }
            })).labelsHidden().tint(McpStyle.tint).disabled(isUpdating)
        }
        .padding(14).background(McpStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var transportLabel: String {
        switch server.transport?.lowercased() {
        case .some("sse"): "SSE"
        case .some("streamable-http"): "HTTP 流式"
        default: "HTTP"
        }
    }
}
