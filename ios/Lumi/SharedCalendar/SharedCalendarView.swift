import SwiftUI
import UIKit

@MainActor
final class SharedCalendarDayRouter {
    static let shared = SharedCalendarDayRouter()
    private init() {}
    private var pending: (CalMonth, Int)?
    var onOpenDay: ((CalMonth, Int) -> Void)? {
        didSet {
            if let pending, let onOpenDay {
                self.pending = nil
                onOpenDay(pending.0, pending.1)
            }
        }
    }
    func open(dayKey: String) {
        guard let (month, day) = CalMonth.parseDayKey(dayKey) else { return }
        if let onOpenDay { onOpenDay(month, day) }
        else { pending = (month, day) }
    }
}

struct SharedCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CalendarStore()
    @State private var selectedDay = SharedCalendarView.launchDay
    @State private var showingDay = false

    private static let flip = Animation.spring(response: 0.36, dampingFraction: 0.9)
    private static var launchMonth: CalMonth {
        UserDefaults.standard.string(forKey: "month").flatMap(CalMonth.init(key:)) ?? .current
    }
    private static var launchDay: Int {
        let month = launchMonth
        let day = UserDefaults.standard.integer(forKey: "day")
        return (1...month.daysInMonth).contains(day) ? day : (month.todayInMonth ?? 1)
    }

    var body: some View {
        ZStack {
            if showingDay {
                DayView(day: $selectedDay) {
                    withAnimation(Self.flip) { showingDay = false }
                    PageSync.shared.flush(store: store)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            } else {
                MonthView(selectedDay: $selectedDay, openDay: { _ in
                    withAnimation(Self.flip) { showingDay = true }
                }, onClose: { dismiss() })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(0)
            }
        }
        .environment(store)
        .task(id: store.month) { store.load(store.month) }
        .onAppear {
            PlacedStore.shared.didMutate = { PageSync.shared.markDirty($0) }
            let selected = $selectedDay
            let dayView = $showingDay
            SharedCalendarDayRouter.shared.onOpenDay = { month, day in
                store.month = month
                selected.wrappedValue = min(day, month.daysInMonth)
                withAnimation(Self.flip) { dayView.wrappedValue = true }
            }
        }
        .onDisappear { SharedCalendarDayRouter.shared.onOpenDay = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushPlaced()
                PageSync.shared.flush(store: store)
            } else {
                store.load(store.month, force: true)
            }
        }
        .onChange(of: store.month) { _, month in
            if selectedDay > month.daysInMonth { selectedDay = month.daysInMonth }
        }
        .onOpenURL { url in
            guard url.scheme == "ourcalendar", url.host == "day",
                  let key = url.pathComponents.dropFirst().first,
                  !url.pathComponents.dropFirst().isEmpty else { return }
            SharedCalendarDayRouter.shared.open(dayKey: key)
        }
    }
}
