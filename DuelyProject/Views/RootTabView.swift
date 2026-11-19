//
//  RootTabView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 18/11/2026.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, calendar, subscriptions
    
    
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared

    @Query private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @AppStorage(CheckInKeys.enabled) private var checkInEnabled = true
    @AppStorage(CheckInKeys.weekday) private var checkInWeekday = CheckInSchedule.defaultWeekday
    @AppStorage(CheckInKeys.minutes) private var checkInMinutes = CheckInSchedule.defaultMinutes
    @AppStorage(CheckInKeys.paymentRemindersEnabled) private var paymentRemindersEnabled = true

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeView(onShowCalendar: { router.selectedTab = .calendar })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)

            SubscriptionsView()
                .tabItem { Label("Subscriptions", systemImage: "rectangle.stack") }
                .tag(AppTab.subscriptions)
        }
        // Runs on appear and whenever anything that affects notifications changes.
        .task(id: notificationSignature) {
            await rescheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            // Picks up a permission change made in the Settings app, and tops up reminders.
            if phase == .active {
                Task { await rescheduleNotifications() }
            }
        }
    }

    /// Changes whenever a value that affects the notification plan changes.
    private var notificationSignature: String {
        let settings = "\(checkInEnabled)|\(checkInWeekday)|\(checkInMinutes)|\(paymentRemindersEnabled)|\(currencyCode)"
        let data = subscriptions
            .map { "\($0.name)|\($0.price)|\($0.cycleRaw)|\($0.anchorDate?.timeIntervalSince1970 ?? 0)|\($0.reminderDaysBefore)" }
            .sorted()
            .joined(separator: ";")
        return settings + "#" + data
    }

    private func rescheduleNotifications() async {
        let checkIn = checkInEnabled && !subscriptions.isEmpty
            ? CheckInSchedule(weekday: checkInWeekday, minutes: checkInMinutes)
            : nil
        let payments = paymentRemindersEnabled
            ? ReminderPlanner.plan(subscriptions: subscriptions, currencyCode: currencyCode)
            : []
        await NotificationService.reschedule(checkIn: checkIn, payments: payments)
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
