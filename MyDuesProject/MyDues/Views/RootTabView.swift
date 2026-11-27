//
//  RootTabView.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 18/11/2026.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, calendar, deadlines, subscriptions
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared
    @State private var emailImport = EmailImportModel.shared
    @Environment(\.modelContext) private var context

    @Query private var subscriptions: [Subscription]
    @Query private var purchases: [Purchase]
    @Query private var notices: [PaymentNotice]
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

            DeadlinesView()
                .tabItem { Label("Deadlines", systemImage: "calendar.badge.clock") }
                .tag(AppTab.deadlines)

            SubscriptionsView()
                .tabItem { Label("Subscriptions", systemImage: "rectangle.stack") }
                .tag(AppTab.subscriptions)
        }
        // Results of the Gmail scan started at the end of onboarding.
        .sheet(isPresented: isReviewingOnboardingScan) {
            if case .review(let results) = emailImport.phase {
                ImportReviewView(results: results) { chosen in
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
        guard FeatureFlags.screenTime else { return }
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
            .map {
                "\($0.name)|\($0.price)|\($0.cycleRaw)|\($0.anchorDate?.timeIntervalSince1970 ?? 0)|\($0.reminderDaysBefore)"
                    + "|\($0.lastPaymentDate?.timeIntervalSince1970 ?? 0)|\($0.paidDates.map(\.timeIntervalSince1970).sorted())"
                    + "|\($0.trialEndDate?.timeIntervalSince1970 ?? 0)"
            }
            .sorted()
            .joined(separator: ";")
        let orders = purchases
            .map {
                "\($0.title)|\($0.store)|\($0.price)|\($0.returnBy?.timeIntervalSince1970 ?? 0)|\($0.warrantyUntil?.timeIntervalSince1970 ?? 0)"
                    + "|\($0.returnReminderEnabled)|\($0.warrantyReminderEnabled)|\($0.returnedAt != nil)"
            }
            .sorted()
            .joined(separator: ";")
        let pagoPA = notices
            .map { "\($0.noticeNumber)|\($0.payee)|\($0.amount)|\($0.dueDate?.timeIntervalSince1970 ?? 0)|\($0.reminderDaysBefore)|\($0.paidAt != nil)" }
            .sorted()
            .joined(separator: ";")
        return settings + "#" + data + "#" + orders + "#" + pagoPA
    }

    private func rescheduleNotifications() async {
        let checkIn = checkInEnabled && !subscriptions.isEmpty
            ? CheckInSchedule(weekday: checkInWeekday, minutes: checkInMinutes)
            : nil
        // Deadline reminders (returns, warranties, trials, pagoPA) have their own switches per
        // item, so they're planned even when payment reminders are off.
        let payments = ReminderPlanner.plan(subscriptions: subscriptions,
                                            currencyCode: currencyCode,
                                            includePayments: paymentRemindersEnabled,
                                            purchases: purchases,
                                            notices: notices)
        await NotificationService.reschedule(checkIn: checkIn, payments: payments)
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
