import Foundation

struct TogetherGalleryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    var title: String
}

enum TogetherGalleryStore {
    private static let storageKey = "lumi.together.gallery.v1"

    static func load() -> [TogetherGalleryItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([TogetherGalleryItem].self, from: data) else { return [] }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    static func recordSentImage(fileName: String, date: Date = .now) {
        var items = load()
        guard !items.contains(where: { $0.fileName == fileName }) else { return }
        items.append(TogetherGalleryItem(id: UUID(), fileName: fileName, createdAt: date, title: "我们收藏的一张照片"))
        save(items)
    }

    static func addLocalImage(fileName: String, title: String = "我们收藏的一张照片") {
        var items = load()
        guard !items.contains(where: { $0.fileName == fileName }) else { return }
        items.append(TogetherGalleryItem(id: UUID(), fileName: fileName, createdAt: .now, title: title))
        save(items)
    }

    static func rename(_ item: TogetherGalleryItem, to title: String) {
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我们收藏的一张照片" : title
        save(items)
    }

    private static func save(_ items: [TogetherGalleryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
