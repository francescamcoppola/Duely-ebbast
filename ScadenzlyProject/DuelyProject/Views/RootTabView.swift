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
    @State private var emailImport = EmailImportModel.shared
    @Environment(\.modelContext) private var context

    @Query private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @AppStorage(CheckInKeys.enabled) private var checkInEnabled = true
    @AppStorage(CheckInKeys.weekday) private var checkInWeekday = CheckInSchedule.defaultWeekday
    @AppStorage(CheckInKeys.minutes) private var checkInMinutes = CheckInSchedule.defaultMinutes
    @AppStorage(CheckInKeys.paymentRemindersEnabled) private var paymentRemindersEnabled = true
    @AppStorage(OnboardingKeys.monthlyBudget) private var budgetString = ""
    @State private var screenTime = ScreenTimeService.shared

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
        // Results of the Gmail scan started at the end of onboarding.
        .sheet(isPresented: isReviewingOnboardingScan) {
            if case .review(let candidates) = emailImport.phase {
                ImportReviewView(candidates: candidates) { chosen in
                    emailImport.add(chosen, existing: subscriptions, into: context)
                }
            }
        }
        // Runs on appear and whenever anything that affects notifications changes.
        .task(id: notificationSignature) {
            await rescheduleNotifications()
            WidgetSync.update(subscriptions: subscriptions, currencyCode: currencyCode,
                              budget: BillingMath.storedAmount(budgetString))
        }
        .onChange(of: scenePhase) { _, phase in
            // Picks up a permission change made in the Settings app, and tops up reminders.
            if phase == .active {
                Task { await rescheduleNotifications() }
                syncScreenTime()
            }
        }
        .task { syncScreenTime() }
    }

    private var isReviewingOnboardingScan: Binding<Bool> {
        Binding {
            if case .review = emailImport.phase, emailImport.presentsResultsOnHome { true } else { false }
        } set: { isPresented in
            if !isPresented, case .review = emailImport.phase { emailImport.dismissReview() }
        }
    }

    /// Screen Time: refreshes permission, forgets deleted subscriptions, answers the finished
    /// week when every subscription is tracked.
    private func syncScreenTime() {
        screenTime.refreshStatus()
        screenTime.pruneLinks(keeping: subscriptions)
        guard checkInEnabled else { return }
        screenTime.recordFinishedWeek(subscriptions: subscriptions,
                                      schedule: CheckInSchedule(weekday: checkInWeekday, minutes: checkInMinutes),
                                      context: context)
    }

    /// Changes whenever a value that affects the notification plan (or the widgets) changes.
    private var notificationSignature: String {
        let settings = "\(checkInEnabled)|\(checkInWeekday)|\(checkInMinutes)|\(paymentRemindersEnabled)|\(currencyCode)|\(budgetString)|\(LanguageController.shared.generation)"
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
