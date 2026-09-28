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
    @State private var tab: TogetherTab = .gallery
    @State private var gallery = TogetherGalleryStore.load()
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedItem: TogetherGalleryItem?
    @State private var showingStartDate = false

    private var startDate: Date { storedStartAt > 0 ? Date(timeIntervalSince1970: storedStartAt) : .now }
    private var daysTogether: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: .now)).day ?? 0) }

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
            if storedStartAt == 0 { storedStartAt = Date.now.timeIntervalSince1970 }
            gallery = TogetherGalleryStore.load()
        }
        .onChange(of: pickerItem) { _, item in importPhoto(item) }
        .sheet(item: $selectedItem) { item in GalleryDetailView(item: item) { updated in
            TogetherGalleryStore.rename(updated.item, to: updated.title)
            gallery = TogetherGalleryStore.load()
        } }
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
        VStack(spacing: 15) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("在一起已经").font(.system(size: 16, weight: .medium))
                Text("\(daysTogether)").font(.system(size: 39, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text("天").font(.system(size: 16, weight: .medium))
            }
            HStack(spacing: 12) {
                avatar(named: "AssistantAvatar")
                HStack(spacing: 0) {
                    Rectangle().fill(TogetherColors.line).frame(height: 1)
                    Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(TogetherColors.heart).padding(.horizontal, 8)
                    Rectangle().fill(TogetherColors.line).frame(height: 1)
                }
                .frame(maxWidth: 112)
                avatar(named: "UserAvatar")
            }
            Button { showingStartDate = true } label: {
                Text(startDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: "."))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.48))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.85), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("相册").font(.system(size: 20, weight: .bold)); Spacer(); PhotosPicker(selection: $pickerItem, matching: .images) { Label("添加", systemImage: "plus").font(.system(size: 14, weight: .medium)) }.buttonStyle(.bordered).tint(.black.opacity(0.7)) }
            if gallery.isEmpty {
                VStack(spacing: 9) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26)).foregroundStyle(.black.opacity(0.34)); Text("第一张照片，留给我们。\n聊天里发出的图片也会自动收藏在这里。").multilineTextAlignment(.center).font(.system(size: 14)).foregroundStyle(.black.opacity(0.48)) }
                    .frame(maxWidth: .infinity).padding(.vertical, 62).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(gallery) { item in
                        Button { selectedItem = item } label: { GalleryTile(item: item) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func placeholder(icon: String, text: String) -> some View { VStack(spacing: 11) { Image(systemName: icon).font(.system(size: 25)).foregroundStyle(TogetherColors.heart); Text(text).font(.system(size: 14)).foregroundStyle(.black.opacity(0.48)) }.frame(maxWidth: .infinity).padding(.vertical, 74).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }
    private func avatar(named name: String) -> some View { Group { if let image = UIImage(named: name) { Image(uiImage: image).resizable().scaledToFill() } else { Color.white } }.frame(width: 58, height: 58).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.08), radius: 5, y: 2) }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.84) else { return }
            let fileName = "together-\(UUID().uuidString).jpg"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return }
            await MainActor.run { TogetherGalleryStore.addLocalImage(fileName: fileName); gallery = TogetherGalleryStore.load(); pickerItem = nil }
        }
    }
}

private enum TogetherColors { static let background = Color(red: 0.984, green: 0.949, blue: 0.957); static let heart = Color(red: 0.73, green: 0.36, blue: 0.45); static let line = Color.black.opacity(0.14) }

private struct GalleryTile: View {
    let item: TogetherGalleryItem
    var body: some View { VStack(alignment: .leading, spacing: 7) { if let image = UIImage(contentsOfFile: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(item.fileName).path) { Image(uiImage: image).resizable().scaledToFill().frame(height: 155).frame(maxWidth: .infinity).clipped() } else { Color.white.opacity(0.55).frame(height: 155).overlay(Image(systemName: "photo").foregroundStyle(.black.opacity(0.25))) }; Text(item.title).lineLimit(1).font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.68)).padding(.horizontal, 9).padding(.bottom, 9) }.background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 17, style: .continuous)).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous)) }
}

private struct GalleryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: TogetherGalleryItem
    let onSave: ((item: TogetherGalleryItem, title: String)) -> Void
    @State private var title: String
    init(item: TogetherGalleryItem, onSave: @escaping ((item: TogetherGalleryItem, title: String)) -> Void) { self.item = item; self.onSave = onSave; _title = State(initialValue: item.title) }
    var body: some View { NavigationStack { VStack(spacing: 20) { if let image = UIImage(contentsOfFile: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(item.fileName).path) { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }; TextField("给这张照片起个名字", text: $title).textFieldStyle(.roundedBorder); Spacer() }.padding(20).background(TogetherColors.background.ignoresSafeArea()).navigationTitle("相册") .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { onSave((item, title)); dismiss() } } } } }
}
