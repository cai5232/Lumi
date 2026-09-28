import SwiftUI
import PhotosUI
import UIKit

private enum TogetherTab: String, CaseIterable, Identifiable {
    case gallery = "相册"
    case diary = "日记"
    case achievements = "成就"
    var id: String { rawValue }
}

struct TogetherView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lumi.together.startAt") private var storedStartAt: Double = 0
    @AppStorage("lumi.together.didApplyAnniversary20260723") private var didApplyAnniversary = false
    @State private var tab: TogetherTab = .gallery
    let onUseInChat: (RemoteGalleryItem) -> Void
    @State private var gallery: [RemoteGalleryItem] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedItem: RemoteGalleryItem?
    @State private var pendingImageData: Data?
    @State private var showingAddDetails = false
    @State private var showingStartDate = false
    @State private var galleryError: String?
    @State private var isLoadingGallery = false
    private let api = LumiAPIClient()

    private static let anniversaryStartDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 23))!

    init(onUseInChat: @escaping (RemoteGalleryItem) -> Void = { _ in }) {
        self.onUseInChat = onUseInChat
    }

    private var startDate: Date { storedStartAt > 0 ? Date(timeIntervalSince1970: storedStartAt) : Self.anniversaryStartDate }

    private func daysTogether(at date: Date) -> Int {
        max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: startDate),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0)
    }

    private var anniversaryLabel: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
        return "\(components.year ?? 2026).\(components.month ?? 7).\(components.day ?? 23)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    relationshipCard
                    tabPicker
                    tabContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(TogetherColors.background.ignoresSafeArea())
            .navigationTitle("我们")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)) }
                }
            }
        }
        .tint(.black.opacity(0.72))
        .onAppear {
            if !didApplyAnniversary {
                storedStartAt = Self.anniversaryStartDate.timeIntervalSince1970
                didApplyAnniversary = true
            }
            Task { await loadGallery() }
        }
        .onChange(of: pickerItem) { _, item in importPhoto(item) }
        .sheet(item: $selectedItem) { item in
            RemoteGalleryDetailView(
                item: item,
                imageURL: api.galleryImageURL(for: item, in: "default"),
                onSave: { title, visualDescription, firstImpression in
                    Task { await update(item, title: title, visualDescription: visualDescription, firstImpression: firstImpression) }
                },
                onDelete: {
                    Task { await delete(item) }
                    selectedItem = nil
                },
                onUse: {
                    onUseInChat(item)
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingAddDetails) {
            if let pendingImageData, let image = UIImage(data: pendingImageData) {
                GalleryAddDetailsView(image: image) { title, visualDescription, firstImpression in
                    Task { await uploadPendingImage(title: title, visualDescription: visualDescription, firstImpression: firstImpression) }
                }
            }
        }
        .sheet(isPresented: $showingStartDate) {
            NavigationStack {
                DatePicker("开始日期", selection: Binding(get: { startDate }, set: { storedStartAt = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("在一起的开始")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingStartDate = false } } }
            }
            .presentationDetents([.medium])
            .presentationBackground(TogetherColors.background)
        }
    }

    private var relationshipCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(spacing: 15) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("在一起已经").font(.system(size: 16, weight: .medium))
                    Text("\(daysTogether(at: timeline.date))")
                        .font(.system(size: 39, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("天").font(.system(size: 16, weight: .medium))
                }
                HStack(spacing: 6) {
                    avatar(named: "AssistantAvatar")
                    HeartbeatDivider()
                        .frame(width: 84, height: 42)
                    avatar(named: "UserAvatar")
                }
                Button { showingStartDate = true } label: {
                    Text(anniversaryLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.85), lineWidth: 1))
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(TogetherTab.allCases) { item in
                Button { withAnimation(.easeOut(duration: 0.2)) { tab = item } } label: {
                    Text(item.rawValue).font(.system(size: 15, weight: tab == item ? .semibold : .regular)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(tab == item ? .black.opacity(0.82) : .black.opacity(0.38))
                        .background(tab == item ? .white.opacity(0.76) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.black.opacity(0.045), in: Capsule())
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .gallery: galleryContent
        case .diary: placeholder(icon: "book.closed", text: "把想记下的日子留在这里。")
        case .achievements: placeholder(icon: "sparkles", text: "我们的每个小瞬间都会慢慢点亮。")
        }
    }

    private var galleryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我们的相册").font(.system(size: 18, weight: .bold))
                    Text("\(gallery.count) 张照片").font(.system(size: 12)).foregroundStyle(.black.opacity(0.42))
                }
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.black.opacity(0.64))
            }
            if let galleryError { Text(galleryError).font(.system(size: 12)).foregroundStyle(.red.opacity(0.72)) }
            if gallery.isEmpty {
                VStack(spacing: 9) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26)).foregroundStyle(.black.opacity(0.34)); Text(isLoadingGallery ? "正在打开我们的相册…" : "第一张照片，留给我们。\n聊天里发出的图片也会自动收藏在这里。").multilineTextAlignment(.center).font(.system(size: 14)).foregroundStyle(.black.opacity(0.48)) }
                    .frame(maxWidth: .infinity).padding(.vertical, 62).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(maximum: 190), spacing: 10), GridItem(.flexible(maximum: 190), spacing: 10)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(gallery) { item in
                        Button { selectedItem = item } label: {
                            RemoteGalleryTile(item: item, imageURL: api.galleryImageURL(for: item, in: "default"))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func placeholder(icon: String, text: String) -> some View { VStack(spacing: 11) { Image(systemName: icon).font(.system(size: 25)).foregroundStyle(TogetherColors.heart); Text(text).font(.system(size: 14)).foregroundStyle(.black.opacity(0.48)) }.frame(maxWidth: .infinity).padding(.vertical, 74).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }

    private func avatar(named name: String) -> some View {
        Group {
            if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: name == "AssistantAvatar" ? "sparkles" : "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(name == "AssistantAvatar" ? TogetherColors.heart : .black.opacity(0.55))
                    .background(name == "AssistantAvatar" ? Color(red: 1.0, green: 0.86, blue: 0.90) : Color.white.opacity(0.72))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.84) else { return }
            pendingImageData = jpeg
            pickerItem = nil
            showingAddDetails = true
        }
    }

    private func uploadPendingImage(title: String, visualDescription: String, firstImpression: String) async {
        guard let pendingImageData else { return }
        do {
            _ = try await api.uploadGallery(
                images: ["data:image/jpeg;base64,\(pendingImageData.base64EncodedString())"],
                title: title,
                visualDescription: visualDescription,
                firstImpression: firstImpression,
                to: "default"
            )
            await loadGallery()
            self.pendingImageData = nil
        } catch {
            galleryError = error.localizedDescription
        }
    }

    private func loadGallery() async {
        isLoadingGallery = true
        defer { isLoadingGallery = false }
        do { gallery = try await api.fetchGallery(for: "default"); galleryError = nil }
        catch { galleryError = error.localizedDescription }
    }

    private func update(_ item: RemoteGalleryItem, title: String, visualDescription: String, firstImpression: String) async {
        do {
            let updated = try await api.updateGallery(item, title: title, visualDescription: visualDescription, firstImpression: firstImpression, in: "default")
            if let index = gallery.firstIndex(where: { $0.id == updated.id }) { gallery[index] = updated }
        } catch { galleryError = error.localizedDescription }
    }

    private func delete(_ item: RemoteGalleryItem) async {
        do {
            try await api.deleteGallery(item, in: "default")
            gallery.removeAll { $0.id == item.id }
        } catch { galleryError = error.localizedDescription }
    }
}

private enum TogetherColors {
    static let background = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let heart = Color(red: 0.73, green: 0.36, blue: 0.45)
    static let pulse = Color(red: 0.95, green: 0.56, blue: 0.67)
    static let card = Color.white.opacity(0.72)
    static let line = Color.black.opacity(0.14)
}

private struct HeartbeatDivider: View {
    var body: some View {
        ZStack {
            HeartbeatLine()
                .stroke(TogetherColors.pulse, style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TogetherColors.pulse)
        }
        .accessibilityHidden(true)
    }
}

private struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        let middleY = rect.midY
        let peak = rect.height * 0.36
        let low = rect.height * 0.66
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: middleY))
        path.addLine(to: CGPoint(x: rect.width * 0.14, y: middleY))
        path.addLine(to: CGPoint(x: rect.width * 0.24, y: peak))
        path.addLine(to: CGPoint(x: rect.width * 0.35, y: low))
        path.addLine(to: CGPoint(x: rect.width * 0.40, y: middleY))
        path.addLine(to: CGPoint(x: rect.width * 0.50, y: middleY))

        path.move(to: CGPoint(x: rect.width * 0.50, y: middleY))
        path.addLine(to: CGPoint(x: rect.width * 0.60, y: middleY))
        path.addLine(to: CGPoint(x: rect.width * 0.65, y: low))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: peak))
        path.addLine(to: CGPoint(x: rect.width * 0.86, y: middleY))
        path.addLine(to: CGPoint(x: rect.maxX, y: middleY))
        return path
    }
}

private struct RemoteGalleryTile: View {
    let item: RemoteGalleryItem
    let imageURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedGalleryImage(url: imageURL)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(item.title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.68))
                .padding(.horizontal, 9)
                .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private final class GalleryImageLoader: ObservableObject {
    private static let cache = NSCache<NSURL, UIImage>()
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false
    private let url: URL

    init(url: URL) { self.url = url }

    func load() async {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let loaded = UIImage(data: data) else {
                failed = true
                return
            }
            Self.cache.setObject(loaded, forKey: url as NSURL)
            image = loaded
        } catch { failed = true }
    }
}

private struct CachedGalleryImage: View {
    @StateObject private var loader: GalleryImageLoader
    let placeholderHeight: CGFloat

    init(url: URL, placeholderHeight: CGFloat = 124) {
        _loader = StateObject(wrappedValue: GalleryImageLoader(url: url))
        self.placeholderHeight = placeholderHeight
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else if loader.failed {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight)
                    .overlay(Image(systemName: "photo").foregroundStyle(.black.opacity(0.25)))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight)
                    .overlay(ProgressView().tint(.black.opacity(0.35)))
            }
        }
        .task { await loader.load() }
    }
}

private struct RemoteGalleryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: RemoteGalleryItem
    let imageURL: URL
    let onSave: (String, String, String) -> Void
    let onDelete: () -> Void
    let onUse: () -> Void
    @State private var title: String
    @State private var visualDescription: String
    @State private var firstImpression: String
    @State private var isEditing = false
    @State private var confirmingDeletion = false

    init(item: RemoteGalleryItem, imageURL: URL, onSave: @escaping (String, String, String) -> Void, onDelete: @escaping () -> Void, onUse: @escaping () -> Void) {
        self.item = item
        self.imageURL = imageURL
        self.onSave = onSave
        self.onDelete = onDelete
        self.onUse = onUse
        _title = State(initialValue: item.title)
        _visualDescription = State(initialValue: item.visualDescription)
        _firstImpression = State(initialValue: item.firstImpression)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CachedGalleryImage(url: imageURL, placeholderHeight: 240)
                    .frame(maxHeight: 310)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if isEditing {
                        editorField(title: "标题", text: $title, lines: 1)
                        editorField(title: "第一次看见", text: $visualDescription, lines: 3)
                        editorField(title: "当时留下的印象", text: $firstImpression, lines: 3)
                    } else {
                        detailSection(title: "第一次看见", text: visualDescription, hasBackground: true)
                        detailSection(title: "当时留下的印象", text: firstImpression, hasBackground: false, italic: true)
                    }
                    Button(action: onUse) {
                        Label("带去聊天", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.black.opacity(0.72))
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .tint(.black.opacity(0.5))
                }
                .padding(20)
            }
            .background(TogetherColors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "完成" : "编辑") {
                        if isEditing { onSave(title, visualDescription, firstImpression) }
                        withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        Label("删除照片", systemImage: "trash")
                    }
                }
            }
            .alert("删除这张照片？", isPresented: $confirmingDeletion) {
                Button("删除", role: .destructive) { onDelete(); dismiss() }
                Button("取消", role: .cancel) { }
            } message: { Text("照片和它的相册文字都会删除。") }
        }
    }

    private func detailSection(title: String, text: String, hasBackground: Bool, italic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.black.opacity(0.52))
            Text(text)
                .font(.system(size: 13.5, weight: .regular))
                .italic(italic)
                .foregroundStyle(.black.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(hasBackground ? 14 : 0)
        .background(hasBackground ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func editorField(title: String, text: Binding<String>, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.42))
            TextField("", text: text, axis: lines == 1 ? .horizontal : .vertical)
                .lineLimit(lines, reservesSpace: lines > 1)
                .padding(10)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct GalleryAddDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onAdd: (String, String, String) -> Void
    @State private var title = ""
    @State private var visualDescription = ""
    @State private var firstImpression = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    field(title: "标题", placeholder: "给这一刻起个名字", text: $title, lines: 1)
                    field(title: "第一次看见", placeholder: "你第一眼看见了什么？", text: $visualDescription, lines: 3)
                    field(title: "当时留下的印象", placeholder: "想留下怎样的感觉？", text: $firstImpression, lines: 3)
                    Text("这些文字会和照片一起留在我们的相册里。")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.42))
                }
                .padding(20)
            }
            .background(TogetherColors.background.ignoresSafeArea())
            .navigationTitle("添加照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onAdd(title, visualDescription, firstImpression)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.48))
            TextField(placeholder, text: text, axis: lines == 1 ? .horizontal : .vertical)
                .lineLimit(lines, reservesSpace: lines > 1)
                .font(.system(size: 15))
                .padding(11)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }
}
