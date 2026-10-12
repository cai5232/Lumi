import SwiftUI


private enum FoodColors {
    static let background = Color(red: 0.984, green: 0.949, blue: 0.957)
    static let pink = Color(red: 0.91, green: 0.56, blue: 0.67)
    static let primary = Color(red: 0.20, green: 0.17, blue: 0.19)
    static let secondary = Color(red: 0.36, green: 0.31, blue: 0.34)
}

private enum FoodTab: String, CaseIterable, Identifiable {
    case today = "今天", shops = "店铺", taste = "口味"
    var id: String { rawValue }
}

struct FoodNotebookNativeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = FoodNotebookStore()
    @State private var tab: FoodTab = .today
    @State private var showEntry = false
    @State private var showTasteEntry = false
    @State private var mealToEdit: [String: Any]?
    @State private var mealToDelete: [String: Any]?

    var body: some View {
        NavigationStack {
            ZStack {
                FoodColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    tabs.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 9)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            switch tab {
                            case .today: todayContent
                            case .shops: shopsContent
                            case .taste: tasteContent
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .tint(FoodColors.primary)
                        .accessibilityLabel("返回")
                }
                ToolbarItem(placement: .principal) {
                    Text("吃了么").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(FoodColors.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { tab == .taste ? (showTasteEntry = true) : (showEntry = true) } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .tint(FoodColors.pink)
                        .accessibilityLabel(tab == .taste ? "添加口味" : "记一笔")
                }
            }
            .toolbarBackground(FoodColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await store.refresh() }
        .sheet(isPresented: $showEntry) { FoodEntrySheet(store: store).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $showTasteEntry) { FoodTasteSheet(store: store).presentationDetents([.medium]).presentationDragIndicator(.visible) }
        .sheet(isPresented: Binding(get: { mealToEdit != nil }, set: { if !$0 { mealToEdit = nil } })) {
            if let mealToEdit { FoodMealEditSheet(store: store, meal: mealToEdit).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        }
        .confirmationDialog("删除这条饮食记录？", isPresented: Binding(get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }), titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                if let mealToDelete { Task { await store.deleteMeal(mealToDelete) } }
                mealToDelete = nil
            }
            Button("取消", role: .cancel) { mealToDelete = nil }
        }
        .preferredColorScheme(.light)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(FoodTab.allCases) { item in
                Button { withAnimation(.easeInOut(duration: 0.18)) { tab = item } } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: tab == item ? .semibold : .medium))
                        .foregroundStyle(tab == item ? FoodColors.primary : FoodColors.secondary.opacity(0.68))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(tab == item ? Color.white.opacity(0.92) : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(4).background(Color.black.opacity(0.035), in: Capsule())
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.month(.wide).day().locale(Locale(identifier: "zh_CN"))))
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(FoodColors.primary)
                Spacer()
                Label(store.city.isEmpty ? "未设置城市" : store.city, systemImage: "location")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(FoodColors.pink)
            }
            HStack(spacing: 0) {
                summary("\(store.todayMeals.count)", "今天记录")
                divider
                summary("\(store.weekMeals.count)", "本周几餐")
                divider
                summary("\(store.tastes.count)", "口味偏好")
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                Text("今天吃了什么").font(.system(size: 17, weight: .semibold)).foregroundStyle(FoodColors.primary)
                Spacer()
                Button("记一笔") { showEntry = true }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 7).background(FoodColors.pink, in: Capsule())
                    .buttonStyle(.plain)
            }
            if store.isLoading && store.meals.isEmpty {
                ProgressView().tint(FoodColors.pink).frame(maxWidth: .infinity).padding(24)
            } else if store.todayMeals.isEmpty {
                emptyState("今天还没有记录", note: "吃了什么，随手记下来吧", symbol: "fork.knife")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.todayMeals.indices, id: \.self) { index in
                        let meal = store.todayMeals[index]
                        FoodSwipeMealRow(meal: meal, store: store, onEdit: { mealToEdit = meal }, onDelete: { mealToDelete = meal })
                    }
                }
            }
            Button { Task { await store.roll() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "die.face.5")
                    Text(store.recommendation.isEmpty ? "帮我想想吃什么" : store.recommendation)
                    Spacer()
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(FoodColors.pink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white.opacity(0.68), in: Capsule())
            }.buttonStyle(.plain)
            if let message = store.errorMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private var shopsContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("吃过的店").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(FoodColors.primary)
            if store.shops.isEmpty { emptyState("还没有店铺记录", note: "记下第一顿饭后会显示在这里", symbol: "storefront") }
            ForEach(store.shops.indices, id: \.self) { index in
                let shop = store.shops[index]
                HStack(spacing: 11) {
                    Image(systemName: "fork.knife.circle.fill").font(.system(size: 25)).foregroundStyle(FoodColors.pink.opacity(0.86))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.value(shop, "name", fallback: "店铺")).font(.system(size: 14, weight: .semibold)).foregroundStyle(FoodColors.primary)
                        Text(store.value(shop, "cuisine", fallback: "还没有记录菜系")).font(.system(size: 12)).foregroundStyle(FoodColors.secondary.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary.opacity(0.55))
                }
                .padding(13).background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private var tasteContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("我的口味").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(FoodColors.primary)
            tasteGroup("love", title: "爱吃", symbol: "heart.fill")
            tasteGroup("hate", title: "不爱吃", symbol: "hand.thumbsdown.fill")
            tasteGroup("never", title: "不能吃", symbol: "exclamationmark.circle.fill")
        }
    }

    private var divider: some View { Rectangle().fill(FoodColors.secondary.opacity(0.12)).frame(width: 1, height: 28) }
    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(FoodColors.primary)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(FoodColors.secondary.opacity(0.65))
        }.frame(maxWidth: .infinity)
    }
    private func tasteGroup(_ kind: String, title: String, symbol: String) -> some View {
        let items = store.tastes.filter { store.value($0, "kind") == kind }.map { store.value($0, "item") }
        return VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(FoodColors.pink)
            if items.isEmpty { Text("还没有记录").font(.system(size: 12)).foregroundStyle(FoodColors.secondary.opacity(0.6)) }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)], alignment: .leading, spacing: 7) {
                    ForEach(items, id: \.self) { item in
                        Text(item).font(.system(size: 12, weight: .medium)).foregroundStyle(FoodColors.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(FoodColors.pink.opacity(0.14), in: Capsule())
                    }
                }
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
    private func emptyState(_ title: String, note: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(FoodColors.pink.opacity(0.8))
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(FoodColors.primary.opacity(0.8))
            Text(note).font(.system(size: 12)).foregroundStyle(FoodColors.secondary.opacity(0.62))
        }.frame(maxWidth: .infinity).padding(.vertical, 22).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FoodSwipeMealRow: View {
    let meal: [String: Any]
    @ObservedObject var store: FoodNotebookStore
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var isDragging = false
    private let actionWidth: CGFloat = 120

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    onEdit()
                } label: {
                    actionLabel("编辑", symbol: "pencil", color: FoodColors.secondary)
                        .frame(width: actionWidth / 2).frame(maxHeight: .infinity)
                        .background(Color.white.opacity(0.92))
                }.buttonStyle(.plain)
                Button(action: onDelete) {
                    actionLabel("删除", symbol: "trash", color: FoodColors.pink)
                        .frame(width: actionWidth / 2).frame(maxHeight: .infinity)
                        .background(FoodColors.pink.opacity(0.14))
                }.buttonStyle(.plain)
            }
            .opacity(offset == 0 ? 0 : 1)
            
            HStack(spacing: 10) {
                Text(store.value(meal, "slot", fallback: "记录"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(FoodColors.pink)
                    .frame(width: 54, alignment: .leading)
                Text(displayText)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(FoodColors.primary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color.white)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if !isDragging { dragStart = offset; isDragging = true }
                        offset = min(0, max(-actionWidth, dragStart + value.translation.width))
                    }
                    .onEnded { value in
                        guard isDragging else { return }
                        isDragging = false
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            offset = abs(value.translation.width) > abs(value.translation.height) && dragStart + value.translation.width < -actionWidth * 0.42 ? -actionWidth : 0
                        }
                    }
            )
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var displayText: String {
        let food = store.dishes(meal)
        guard !food.isEmpty else { return store.value(meal, "note", fallback: store.mealName(meal)) }
        let place = store.mealName(meal)
        return place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ["自己做", "一顿饭"].contains(place) ? food : "\(place) · \(food)"
    }

    private func actionLabel(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
            Text(title).font(.system(size: 10, weight: .medium))
        }.foregroundStyle(color)
    }
}

@MainActor
private final class FoodNotebookStore: ObservableObject {
    @Published var meals: [[String: Any]] = []
    @Published var shops: [[String: Any]] = []
    @Published var branches: [[String: Any]] = []
    @Published var logs: [[String: Any]] = []
    @Published var tastes: [[String: Any]] = []
    @Published var city = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var recommendation = ""
    private let base = URL(string: "https://lumi-tokyo-api.zeabur.app")!
    private var token: String {
        let saved = LumiKeychain.read(account: "push-api-token")
        if !saved.isEmpty { return saved }
        return Bundle.main.object(forInfoDictionaryKey: "LUMI_PUSH_API_TOKEN") as? String ?? ""
    }
    var todayMeals: [[String: Any]] { meals.filter { value($0, "eaten_on") == Self.todayString() }.sorted { value($0, "created_at") < value($1, "created_at") } }
    var weekMeals: [[String: Any]] {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let boundary = formatter.string(from: start)
        return meals.filter { value($0, "eaten_on") >= boundary }
    }
    func value(_ row: [String: Any], _ key: String, fallback: String = "") -> String { row[key] as? String ?? fallback }
    func mealName(_ meal: [String: Any]) -> String {
        guard let branchID = meal["branch_id"], let branch = branches.first(where: { id($0["id"]) == id(branchID) }),
              let shopID = branch["shop_id"], let shop = shops.first(where: { id($0["id"]) == id(shopID) }) else { return value(meal, "place", fallback: "自己做") }
        return value(shop, "name", fallback: "一顿饭")
    }
    func dishes(_ meal: [String: Any]) -> String {
        guard let mealID = meal["id"] else { return "" }
        return logs.filter { id($0["meal_id"]) == id(mealID) }.map { value($0, "name") }.filter { !$0.isEmpty }.joined(separator: "、")
    }
    func mealLogs(_ meal: [String: Any]) -> [[String: Any]] {
        guard let mealID = meal["id"] else { return [] }
        return logs.filter { id($0["meal_id"]) == id(mealID) }
    }
    func refresh() async {
        isLoading = true; defer { isLoading = false }
        do {
            let json = try await request("/v1/food/api/food")
            meals = json["meals"] as? [[String: Any]] ?? []
            shops = json["shops"] as? [[String: Any]] ?? []
            branches = json["branches"] as? [[String: Any]] ?? []
            logs = json["logs"] as? [[String: Any]] ?? []
            tastes = json["taste"] as? [[String: Any]] ?? []
            city = (json["here"] as? [String: Any])?["city"] as? String ?? ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func addMeal(shop: String, slot: String, dish: String, note: String) async {
        var body: [String: Any] = ["meal": ["date": Self.todayString(), "slot": slot, "note": note, "src": "app"]]
        if !shop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["shop"] = ["name": shop] }
        if !dish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["dishes"] = [["name": dish]] }
        do { _ = try await request("/v1/food/api/food/log", method: "POST", body: body); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    func updateMeal(_ meal: [String: Any], slot: String, dishes: String, note: String) async {
        guard let mealID = meal["id"] else { return }
        do {
            _ = try await request("/v1/food/api/food/edit", method: "POST", body: ["kind": "meal", "id": mealID, "fields": ["slot": slot, "note": note]])
            let oldLogs = mealLogs(meal)
            let newDishes = dishes.split(whereSeparator: { "、，,\n".contains($0) }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            for index in oldLogs.indices {
                let log = oldLogs[index]
                guard let logID = log["id"] else { continue }
                if index < newDishes.count {
                    _ = try await request("/v1/food/api/food/edit", method: "POST", body: ["kind": "log", "id": logID, "fields": ["name": newDishes[index]]])
                } else {
                    _ = try await request("/v1/food/api/food/del", method: "POST", body: ["kind": "log", "id": logID])
                }
            }
            if newDishes.count > oldLogs.count {
                for name in newDishes.dropFirst(oldLogs.count) {
                    _ = try await request("/v1/food/api/food/addlog", method: "POST", body: ["meal_id": mealID, "dish": ["name": name]])
                }
            }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func deleteMeal(_ meal: [String: Any]) async {
        guard let mealID = meal["id"] else { return }
        do { _ = try await request("/v1/food/api/food/del", method: "POST", body: ["kind": "meal", "id": mealID]); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    func addTaste(item: String, kind: String) async {
        do { _ = try await request("/v1/food/api/food/taste", method: "POST", body: ["item": item, "kind": kind, "src": "app"]); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    func roll() async {
        do { let json = try await request("/v1/food/api/food/dice", method: "POST", body: ["mode": "dish"]); recommendation = json["text"] as? String ?? json["name"] as? String ?? "再试一次" }
        catch { errorMessage = error.localizedDescription }
    }
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path)); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["ok"] as? Bool != false else { throw URLError(.badServerResponse) }
        return json
    }
    private func id(_ value: Any?) -> String { (value as? NSNumber)?.stringValue ?? value as? String ?? "" }
    private static func todayString() -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}

private struct FoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FoodNotebookStore
    @State private var shop = ""
    @State private var dish = ""
    @State private var note = ""
    @State private var slot = "午饭"
    private let slots = ["早饭", "午饭", "晚饭", "夜宵", "纯记录"]
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                entryField("店名", placeholder: "可不填", text: $shop)
                entryField("吃了什么", placeholder: "菜名", text: $dish)
                entryField("备注", placeholder: "想记下的细节", text: $note)
                Text("餐别").font(.system(size: 13, weight: .medium)).foregroundStyle(FoodColors.secondary)
                HStack(spacing: 7) {
                    ForEach(slots, id: \.self) { item in
                        Button(item) { slot = item }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(slot == item ? .white : FoodColors.secondary)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(slot == item ? FoodColors.pink : Color.black.opacity(0.04), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20).background(FoodColors.background.ignoresSafeArea())
            .navigationTitle("记一笔").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(FoodColors.secondary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { Task { await store.addMeal(shop: shop, slot: slot, dish: dish, note: note); dismiss() } }
                        .fontWeight(.semibold).foregroundStyle(FoodColors.pink)
                        .disabled([shop, dish, note].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }.tint(FoodColors.pink)
    }
    private func entryField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(FoodColors.secondary)
            TextField(placeholder, text: text).font(.system(size: 15)).padding(.horizontal, 13).padding(.vertical, 11)
                .background(Color.white.opacity(0.86), in: Capsule())
        }
    }
}

private struct FoodTasteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FoodNotebookStore
    @State private var item = ""
    @State private var kind = "love"
    private let kinds = [("love", "爱吃"), ("hate", "不爱吃"), ("never", "不能吃")]
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 13) {
                TextField("食物或菜系", text: $item).font(.system(size: 15)).padding(13).background(Color.white.opacity(0.86), in: Capsule())
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.0) { value, title in
                        Button(title) { kind = value }.font(.system(size: 13, weight: .medium))
                            .foregroundStyle(kind == value ? .white : FoodColors.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(kind == value ? FoodColors.pink : Color.black.opacity(0.04), in: Capsule())
                    }
                }
                Spacer()
            }
            .padding(20).background(FoodColors.background.ignoresSafeArea())
            .navigationTitle("口味偏好").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(FoodColors.secondary) }
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { Task { await store.addTaste(item: item, kind: kind); dismiss() } }.fontWeight(.semibold).foregroundStyle(FoodColors.pink).disabled(item.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }.tint(FoodColors.pink)
    }
}

private struct FoodMealEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FoodNotebookStore
    let meal: [String: Any]
    @State private var slot: String
    @State private var dishes: String
    @State private var note: String
    private let slots = ["早饭", "午饭", "晚饭", "夜宵", "纯记录"]

    init(store: FoodNotebookStore, meal: [String: Any]) {
        self.store = store
        self.meal = meal
        _slot = State(initialValue: store.value(meal, "slot", fallback: "纯记录"))
        _dishes = State(initialValue: store.dishes(meal))
        _note = State(initialValue: store.value(meal, "note"))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("餐别").font(.system(size: 13, weight: .medium)).foregroundStyle(FoodColors.secondary)
                HStack(spacing: 7) {
                    ForEach(slots, id: \.self) { item in
                        Button(item) { slot = item }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(slot == item ? .white : FoodColors.secondary)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(slot == item ? FoodColors.pink : Color.black.opacity(0.04), in: Capsule())
                    }
                }
                editField("吃了什么", placeholder: "多个菜名用顿号分开", text: $dishes)
                editField("备注", placeholder: "想记下的细节", text: $note)
                Spacer(minLength: 0)
            }
            .padding(20).background(FoodColors.background.ignoresSafeArea())
            .navigationTitle("编辑记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() }.foregroundStyle(FoodColors.secondary) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { Task { await store.updateMeal(meal, slot: slot, dishes: dishes, note: note); dismiss() } }
                        .fontWeight(.semibold).foregroundStyle(FoodColors.pink)
                }
            }
        }.tint(FoodColors.pink)
    }

    private func editField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(FoodColors.secondary)
            TextField(placeholder, text: text).font(.system(size: 15)).padding(.horizontal, 13).padding(.vertical, 11)
                .background(Color.white.opacity(0.86), in: Capsule())
        }
    }
}
