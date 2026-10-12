import SwiftUI
import MapKit
import CoreLocation

private enum LettersPalette {
    static let background = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let paper = Color.white
    static let ink = Color(red: 0.20, green: 0.17, blue: 0.19)
    static let muted = Color(red: 0.57, green: 0.50, blue: 0.54)
    static let accent = Color(red: 0.91, green: 0.56, blue: 0.67)
    static let gold = Color(red: 0.77, green: 0.53, blue: 0.61)
}

private struct LettersMapResponse: Decodable {
    var names: LettersNames
    var stops: [LettersStop]
    var letters: [LettersLetter]
    var badges: [LettersBadge]
    var marks: [LettersMark]
    var seen: LettersSeen?
    var track: [LettersTrackPoint]
}

private struct LettersNames: Decodable { var hider: String; var finder: String }
private struct LettersPoint: Decodable { var lat: Double; var lon: Double }
private struct LettersStop: Decodable, Identifiable {
    var id: String; var trip: String; var date: String; var name: String; var lat: Double; var lon: Double; var note: String
}
private struct LettersHintArea: Decodable { var lat: Double; var lon: Double; var r: Double }
private struct LettersVoice: Decodable { var url: String; var text: String }
private struct LettersBadge: Decodable, Identifiable {
    var id: String; var name: String; var emoji: String; var note: String?; var awardedAt: String?; var place: String?
    enum CodingKeys: String, CodingKey { case id, name, emoji, note, awardedAt, place }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decode(String.self, forKey: .name)
        emoji = try values.decode(String.self, forKey: .emoji)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        awardedAt = try values.decodeIfPresent(String.self, forKey: .awardedAt)
        place = try values.decodeIfPresent(String.self, forKey: .place)
    }
}
private struct LettersLetter: Decodable, Identifiable {
    var id: String
    var status: String
    var hint: String
    var area: LettersHintArea
    var contents: [String]
    var createdAt: String?
    var visits: Int?
    var visitsNeeded: Int?
    var place: String?
    var lat: Double?
    var lon: Double?
    var foundAt: String?
    var body: String?
    var voice: LettersVoice?
    var badge: LettersBadge?
    var streetView: LettersStreetView?
    var openedAt: String?
}
private struct LettersStreetView: Decodable { var url: String; var date: String? }
private struct LettersMark: Decodable, Identifiable { var id: String; var lat: Double; var lon: Double; var note: String; var createdAt: String }
private struct LettersSeen: Decodable { var lat: Double; var lon: Double; var acc: Double; var at: String }
private struct LettersTrackPoint: Decodable { var t: String; var lat: Double; var lon: Double }
private struct LettersOpenResponse: Decodable { var ok: Bool; var awayM: Int?; var counted: Bool?; var visits: Int?; var visitsNeeded: Int?; var letter: LettersLetter? }
private struct LettersMarkBody: Encodable { var lat: Double; var lon: Double; var acc: Double; var note: String }
private struct LettersOpenBody: Encodable { var lat: Double; var lon: Double; var acc: Double }
private struct LettersLocationBody: Encodable { var lat: Double; var lon: Double; var acc: Double }

private enum LettersMapError: LocalizedError {
    case unauthorized
    case server(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Lumi 授权未配置，请在设置里完成服务器连接。"
        case .server(let message): return message
        }
    }
}

private struct LettersMapAPI {
    let baseURL = URL(string: "https://lumi-tokyo-api.zeabur.app")!
    private var token: String? {
        let stored = LumiKeychain.read(account: "push-api-token")
        if !stored.isEmpty { return stored }
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LUMI_PUSH_API_TOKEN") as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
    func fetch() async throws -> LettersMapResponse {
        try await send(path: "/v1/letters-map", method: "GET", body: Optional<String>.none)
    }
    func open(_ letter: LettersLetter, at location: CLLocation?) async throws -> LettersOpenResponse {
        let body: LettersOpenBody?
        if letter.status == "sealed" {
            guard let location else { throw LettersMapError.server("先点右上角定位，再到附近拆信。") }
            body = LettersOpenBody(lat: location.coordinate.latitude, lon: location.coordinate.longitude, acc: location.horizontalAccuracy)
        } else { body = nil }
        return try await send(path: "/v1/letters-map/letters/\(letter.id)/open", method: "POST", body: body)
    }
    func addMark(at location: CLLocation, note: String) async throws {
        let _: LettersMarkResponse = try await send(path: "/v1/letters-map/marks", method: "POST", body: LettersMarkBody(lat: location.coordinate.latitude, lon: location.coordinate.longitude, acc: location.horizontalAccuracy, note: note))
    }
    func report(_ location: CLLocation) async throws {
        let _: LettersMarkResponse = try await send(path: "/v1/letters-map/location", method: "POST", body: LettersLocationBody(lat: location.coordinate.latitude, lon: location.coordinate.longitude, acc: location.horizontalAccuracy))
    }
    private func send<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        guard let token else { throw LettersMapError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LettersMapError.server("服务器没有响应。") }
        if http.statusCode == 401 { throw LettersMapError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "请求失败（\(http.statusCode)）"
            throw LettersMapError.server(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
private struct LettersMarkResponse: Decodable { var ok: Bool }

@MainActor
private final class LettersLocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus
    @Published var error: String?
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    func locate() {
        error = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: error = "请在系统设置里允许 Lumi 使用定位。"
        default: manager.requestLocation()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { self.error = "没有取得当前位置，请稍后重试。" }
}

private enum LettersTab: String, CaseIterable { case map = "地图", letters = "信笺", badges = "成就" }

@MainActor
struct LettersMapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LettersLocationManager()
    @State private var data: LettersMapResponse?
    @State private var selectedTab: LettersTab = .map
    @State private var selectedLetter: LettersLetter?
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading = false
    @State private var isLoggedIn = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var note = ""
    @State private var showingMarkComposer = false
    private let api = LettersMapAPI()

    var body: some View {
        NavigationStack {
            Group {
                if let data { content(data) }
                else if isLoading { loadingView }
                else { unavailableView }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(LettersPalette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(LettersPalette.ink) }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("藏宝地图").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(LettersPalette.ink)
                        Text("TREASURES ALONG THE WAY").font(.system(size: 8, weight: .medium, design: .rounded)).tracking(1.1).foregroundStyle(LettersPalette.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoggedIn {
                        Button { locationManager.locate() } label: { Image(systemName: "location.north.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(LettersPalette.accent) }
                        .accessibilityLabel("定位我")
                    }
                }
            }
            .toolbarBackground(LettersPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(LettersPalette.accent)
            .task { await loadMap() }
            .onChange(of: locationManager.location?.timestamp) { _, _ in
                guard let location = locationManager.location, isLoggedIn else { return }
                withAnimation { camera = .region(MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))) }
                Task { await reportLocation(location) }
            }
            .onChange(of: locationManager.error) { _, value in if let value { errorMessage = value } }
            .alert("藏宝地图", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(item: $selectedLetter) { letter in letterDetail(letter) }
            .sheet(isPresented: $showingMarkComposer) { markComposer }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) { ProgressView().tint(LettersPalette.accent); Text("正在展开地图…").font(.system(size: 13)).foregroundStyle(LettersPalette.muted) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unavailableView: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .light)).foregroundStyle(LettersPalette.accent)
                .frame(width: 76, height: 76).background(.white, in: Circle())
            Text("藏宝地图暂时没有打开").font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.ink)
            Text("检查网络后再试一次。信件内容只会在找到后显示。")
                .font(.system(size: 13)).foregroundStyle(LettersPalette.muted).multilineTextAlignment(.center)
            Button { Task { await loadMap() } } label: {
                Text("重新加载").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 150, height: 48).background(LettersPalette.accent, in: Capsule())
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func content(_ map: LettersMapResponse) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LettersTab.allCases, id: \.self) { tab in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab == .map ? "map" : tab == .letters ? "envelope" : "rosette")
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? LettersPalette.ink : LettersPalette.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(selectedTab == tab ? LettersPalette.paper : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(4).background(LettersPalette.ink.opacity(0.055), in: Capsule()).padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 10)
            switch selectedTab {
            case .map: mapContent(map)
            case .letters: lettersList(map)
            case .badges: badgesList(map)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if selectedTab == .map {
                Button { if locationManager.location == nil { locationManager.locate() } else { showingMarkComposer = true } } label: {
                    Label("我来过", systemImage: "mappin.and.ellipse").font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 17).padding(.vertical, 13).background(LettersPalette.accent, in: Capsule()).shadow(color: .black.opacity(0.16), radius: 12, y: 4)
                }.padding(20)
            }
        }
    }

    private func mapContent(_ map: LettersMapResponse) -> some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                ForEach(map.stops) { stop in
                    Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon), anchor: .bottom) {
                        mapMarker(icon: "flag.fill", color: LettersPalette.gold, label: stop.name)
                    }
                }
                ForEach(map.letters) { letter in
                    MapCircle(center: CLLocationCoordinate2D(latitude: letter.area.lat, longitude: letter.area.lon), radius: letter.area.r)
                        .foregroundStyle(LettersPalette.accent.opacity(0.10))
                        .stroke(LettersPalette.accent.opacity(0.38), lineWidth: 1)
                    Annotation(letter.status == "opened" ? (letter.place ?? "信") : "未拆封", coordinate: CLLocationCoordinate2D(latitude: letter.area.lat, longitude: letter.area.lon), anchor: .bottom) {
                        Button { selectedLetter = letter } label: {
                            Image(systemName: letter.status == "opened" ? "envelope.open.fill" : "envelope.badge.shield.half.filled")
                                .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 38, height: 38).background(letter.status == "opened" ? LettersPalette.gold : LettersPalette.accent, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2)).shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                        }.buttonStyle(.plain)
                    }
                }
                ForEach(map.marks) { mark in
                    Annotation("我来过", coordinate: CLLocationCoordinate2D(latitude: mark.lat, longitude: mark.lon), anchor: .bottom) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 19)).foregroundStyle(LettersPalette.accent)
                    }
                }
                ForEach(Array(trackSegments(map.track).enumerated()), id: \.offset) { item in
                    MapPolyline(coordinates: item.element.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                        .stroke(LettersPalette.accent.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5]))
                }
                if map.stops.count > 1 {
                    MapPolyline(coordinates: map.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                        .stroke(LettersPalette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Circle().fill(LettersPalette.accent).frame(width: 7, height: 7)
                    Text("\(map.letters.count) 封信 · \(map.stops.count) 个旅程坐标")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(LettersPalette.ink)
                }.padding(.horizontal, 12).padding(.vertical, 9).background(LettersPalette.paper.opacity(0.94), in: Capsule()).padding(12)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("沿途的心意").font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.ink)
                        Text("\(map.names.hider) 为 \(map.names.finder) 留下的线索").font(.system(size: 12)).foregroundStyle(LettersPalette.muted)
                    }
                    Spacer()
                    Button { Task { await loadMap() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).foregroundStyle(LettersPalette.accent).frame(width: 36, height: 36).background(.white.opacity(0.7), in: Circle()) }
                    Button { locationManager.locate() } label: { Image(systemName: "location.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(LettersPalette.accent).frame(width: 36, height: 36).background(.white.opacity(0.7), in: Circle()) }
                }
                if let letter = map.letters.first(where: { $0.status != "opened" }) {
                    Button { selectedLetter = letter } label: { letterRow(letter) }.buttonStyle(.plain)
                } else if map.letters.isEmpty {
                    Text("地图还是空白的，第一份心意正在路上。")
                        .font(.system(size: 13)).foregroundStyle(LettersPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(.horizontal, 20).padding(.top, 17).padding(.bottom, 18)
            .background(LettersPalette.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LettersPalette.background)
    }

    private func mapMarker(icon: String, color: Color, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 27, height: 27).background(color, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 1.5))
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(LettersPalette.ink).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3).background(LettersPalette.paper, in: Capsule())
        }
    }

    private func lettersList(_ map: LettersMapResponse) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("每一片雾里，都有一句谜语。").font(.system(size: 14, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.muted).padding(.bottom, 3)
                ForEach(map.letters) { letter in Button { selectedLetter = letter } label: { letterRow(letter) }.buttonStyle(.plain) }
                if map.letters.isEmpty { emptyCard("还没有信笺", subtitle: "等一份心意，沿着路慢慢寄来。", icon: "envelope") }
            }.padding(.horizontal, 18).padding(.vertical, 8)
        }
        .background(LettersPalette.background)
    }

    private func letterRow(_ letter: LettersLetter) -> some View {
        HStack(spacing: 14) {
            Image(systemName: letter.status == "opened" ? "envelope.open.fill" : letter.status == "found" ? "envelope.badge.fill" : "envelope.badge.shield.half.filled")
                .font(.system(size: 19)).foregroundStyle(letter.status == "opened" ? LettersPalette.gold : LettersPalette.accent)
                .frame(width: 46, height: 46).background(LettersPalette.background, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(letter.place ?? (letter.status == "sealed" ? "一片未拆封的雾" : "找到一封信")).font(.system(size: 14, weight: .semibold)).foregroundStyle(LettersPalette.ink); Spacer(); Text(statusTitle(letter.status)).font(.system(size: 10, weight: .medium)).foregroundStyle(LettersPalette.accent) }
                Text(letter.hint).font(.system(size: 12)).foregroundStyle(LettersPalette.muted).lineLimit(2)
                if let needed = letter.visitsNeeded, needed > 1 { Text("来过 \(letter.visits ?? 0) / \(needed) 天").font(.system(size: 10, weight: .medium)).foregroundStyle(LettersPalette.gold) }
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(LettersPalette.muted.opacity(0.55))
        }
        .padding(14).background(LettersPalette.paper, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.85), lineWidth: 1))
    }

    private func badgesList(_ map: LettersMapResponse) -> some View {
        let foundAtPlaces = map.letters.compactMap { letter -> LettersBadge? in
            guard letter.status == "opened", var badge = letter.badge else { return nil }
            badge.id = letter.id
            badge.place = letter.place
            badge.awardedAt = letter.openedAt
            return badge
        }
        let badges = map.badges + foundAtPlaces
        let lockedBadges = map.letters.filter { $0.status != "opened" && $0.contents.contains("badge") }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("沿途收集的星光").font(.system(size: 22, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.ink)
                    Text("每一枚成就，都是一段走过的路。\(badges.count) 枚已点亮").font(.system(size: 12)).foregroundStyle(LettersPalette.muted)
                }
                if badges.isEmpty && lockedBadges.isEmpty { emptyCard("成就墙还空着", subtitle: "第一枚纪念章，正在等你发现。", icon: "rosette") }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(badges) { badge in
                        VStack(spacing: 8) {
                            Text(badge.emoji).font(.system(size: 37)).frame(width: 72, height: 72).background(LinearGradient(colors: [Color.white, Color(red: 0.93, green: 0.87, blue: 0.73)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle()).overlay(Circle().stroke(LettersPalette.gold.opacity(0.35), lineWidth: 1))
                            Text(badge.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(LettersPalette.ink).lineLimit(1)
                            if let place = badge.place { Text(place).font(.system(size: 10)).foregroundStyle(LettersPalette.muted).lineLimit(1) }
                            if let note = badge.note, !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(LettersPalette.muted).multilineTextAlignment(.center).lineLimit(3) }
                        }
                        .frame(maxWidth: .infinity).padding(15).background(LettersPalette.paper, in: RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(lockedBadges) { _ in
                        VStack(spacing: 8) {
                            Image(systemName: "rosette").font(.system(size: 28, weight: .light)).foregroundStyle(LettersPalette.muted.opacity(0.55)).frame(width: 72, height: 72).background(LettersPalette.background, in: Circle())
                            Text("地图上的成就").font(.system(size: 13, weight: .medium)).foregroundStyle(LettersPalette.ink)
                            Text("走到雾圈附近解锁").font(.system(size: 10)).foregroundStyle(LettersPalette.muted)
                        }.frame(maxWidth: .infinity).padding(15).background(LettersPalette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }.padding(18)
        }.background(LettersPalette.background)
    }

    private func emptyCard(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(LettersPalette.accent.opacity(0.72))
            Text(title).font(.system(size: 15, weight: .medium, design: .serif)).foregroundStyle(LettersPalette.ink)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(LettersPalette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 34).background(LettersPalette.paper, in: RoundedRectangle(cornerRadius: 20))
    }

    private func letterDetail(_ letter: LettersLetter) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        Image(systemName: letter.status == "opened" ? "envelope.open.fill" : "envelope.badge.shield.half.filled")
                            .font(.system(size: 25)).foregroundStyle(LettersPalette.accent).frame(width: 58, height: 58).background(.white.opacity(0.72), in: Circle())
                        Spacer()
                        Text(statusTitle(letter.status)).font(.system(size: 12, weight: .medium)).foregroundStyle(LettersPalette.accent).padding(.horizontal, 12).padding(.vertical, 7).background(LettersPalette.accent.opacity(0.10), in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(letter.place ?? "地图上的一封信").font(.system(size: 25, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.ink)
                        Text(letter.hint).font(.system(size: 15)).foregroundStyle(LettersPalette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if letter.status == "sealed" {
                        HStack(spacing: 9) { Image(systemName: "location.circle"); Text("到雾圈附近，才能拆开这封信。") }.font(.system(size: 12)).foregroundStyle(LettersPalette.muted).padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if letter.status == "opened" {
                        if let body = letter.body, !body.isEmpty {
                            Text(body).font(.system(size: 16, weight: .regular, design: .serif)).lineSpacing(7).foregroundStyle(LettersPalette.ink).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(LettersPalette.paper, in: RoundedRectangle(cornerRadius: 18))
                            Text("—— \(data?.names.hider ?? "TA")").font(.system(size: 12, design: .serif)).foregroundStyle(LettersPalette.muted).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let voice = letter.voice, let url = URL(string: voice.url) {
                            Link(destination: url) { Label("播放语音讲解", systemImage: "play.circle.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(LettersPalette.accent) }
                            if !voice.text.isEmpty { Text(voice.text).font(.system(size: 13)).foregroundStyle(LettersPalette.muted) }
                        }
                        if let badge = letter.badge {
                            HStack(spacing: 12) { Text(badge.emoji).font(.system(size: 36)); VStack(alignment: .leading, spacing: 3) { Text("成就解锁").font(.system(size: 10, weight: .medium)).foregroundStyle(LettersPalette.gold); Text(badge.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(LettersPalette.ink); if let note = badge.note { Text(note).font(.system(size: 12)).foregroundStyle(LettersPalette.muted) } } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                        }
                    } else if letter.contents.contains("badge") {
                        Label("还有一枚成就等你发现", systemImage: "rosette").font(.system(size: 13)).foregroundStyle(LettersPalette.gold)
                    }
                    if let error = locationManager.error { Text(error).font(.system(size: 12)).foregroundStyle(LettersPalette.accent) }
                    Button { Task { await open(letter) } } label: {
                        HStack { if isWorking { ProgressView().tint(.white) } else { Image(systemName: letter.status == "opened" ? "checkmark" : "envelope.open"); Text(letter.status == "opened" ? "已经拆开" : letter.status == "found" ? "拆开这封信" : "定位并试着拆信") } }
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50).background(LettersPalette.accent, in: RoundedRectangle(cornerRadius: 16))
                    }.disabled(isWorking || letter.status == "opened")
                }.padding(20)
            }
            .background(LettersPalette.background.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selectedLetter = nil } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).tint(LettersPalette.accent)
    }

    private var markComposer: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("把此刻留在地图上").font(.system(size: 21, weight: .regular, design: .serif)).foregroundStyle(LettersPalette.ink)
                Text("留下一句短短的话，做个路过的记号。\n位置只会保存在藏宝地图里。") .font(.system(size: 13)).foregroundStyle(LettersPalette.muted)
                TextField("写一句话（可以留空）", text: $note, axis: .vertical).lineLimit(2...4).padding(13).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                Button { Task { await saveMark() } } label: { HStack { if isWorking { ProgressView().tint(.white) } else { Text("钉在地图上") } }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 50).background(LettersPalette.accent, in: RoundedRectangle(cornerRadius: 15)) }.disabled(isWorking || locationManager.location == nil)
                Spacer()
            }.padding(22).padding(.top, 12).background(LettersPalette.background.ignoresSafeArea())
                .navigationTitle("我来过").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { showingMarkComposer = false } } }
        }.presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    private func loadMap() async {
        isLoading = true; defer { isLoading = false }
        do {
            data = try await api.fetch()
            isLoggedIn = true
        } catch { errorMessage = error.localizedDescription; isLoggedIn = false }
    }
    private func reportLocation(_ location: CLLocation) async {
        do { try await api.report(location); await loadMap() }
        catch { errorMessage = error.localizedDescription }
    }
    private func open(_ letter: LettersLetter) async {
        if letter.status == "sealed", locationManager.location == nil { locationManager.locate(); return }
        isWorking = true; defer { isWorking = false }
        do {
            let response = try await api.open(letter, at: locationManager.location)
            if response.ok, let unlocked = response.letter {
                selectedLetter = unlocked
                await loadMap()
            } else if let awayM = response.awayM { errorMessage = "还差 \(awayM >= 1000 ? String(format: "%.1f 公里", Double(awayM) / 1000) : "\(max(10, (awayM / 10) * 10)) 米")，再往前走一点。" }
            else if response.counted == true { errorMessage = "今天的到访已记下，再来 \(max(0, (response.visitsNeeded ?? 1) - (response.visits ?? 0))) 天就能拆开。"; await loadMap() }
        } catch { errorMessage = error.localizedDescription }
    }
    private func saveMark() async {
        guard let location = locationManager.location else { locationManager.locate(); return }
        isWorking = true; defer { isWorking = false }
        do { try await api.addMark(at: location, note: note); showingMarkComposer = false; note = ""; await loadMap() }
        catch { errorMessage = error.localizedDescription }
    }
    private func statusTitle(_ status: String) -> String { status == "opened" ? "已拆开" : status == "found" ? "已找到" : "待发现" }
    private func trackSegments(_ points: [LettersTrackPoint]) -> [[LettersTrackPoint]] {
        var result: [[LettersTrackPoint]] = []
        var current: [LettersTrackPoint] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        for point in points {
            let date = formatter.date(from: point.t) ?? plainFormatter.date(from: point.t)
            if let previous = current.last,
               let previousDate = formatter.date(from: previous.t) ?? plainFormatter.date(from: previous.t),
               let date, date.timeIntervalSince(previousDate) > 6 * 3600 {
                if current.count > 1 { result.append(current) }
                current = []
            }
            current.append(point)
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
