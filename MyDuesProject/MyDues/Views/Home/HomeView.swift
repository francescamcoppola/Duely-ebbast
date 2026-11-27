//
//  HomeView.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    /// Switches to the Calendar tab ("Up Next" → full schedule).
    var onShowCalendar: () -> Void = {}

    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]
    @Query private var purchases: [Purchase]
    @Query private var notices: [PaymentNotice]

    @AppStorage(OnboardingKeys.userName) private var userName = ""
    @AppStorage(OnboardingKeys.monthlyBudget) private var budgetString = ""
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @AppStorage(CheckInKeys.enabled) private var checkInEnabled = true
    @AppStorage(CheckInKeys.weekday) private var checkInWeekday = CheckInSchedule.defaultWeekday
    @AppStorage(CheckInKeys.minutes) private var checkInMinutes = CheckInSchedule.defaultMinutes
    @AppStorage(CheckInKeys.skippedWeek) private var skippedWeek: Double = 0

    /// Re-evaluates "is a check-in due?" whenever the app comes back to the foreground.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @State private var router = AppRouter.shared
    /// "Finish Setting Up" opens every pending subscription in a row, starting with the tapped one.
    @State private var pendingSetup: PendingSetup?
    /// Up Next rows open the same detail screen as the Subscriptions tab.
    @State private var detailSubscription: Subscription?
    @State private var isAddingSubscription = false
    @State private var isEditingBudget = false
    @State private var isShowingSettings = false
    @State private var catalog = PlanCatalogStore.shared
    @State private var emailImport = EmailImportModel.shared

    private var checkInSchedule: CheckInSchedule {
        CheckInSchedule(weekday: checkInWeekday, minutes: checkInMinutes)
    }

    /// Start of the week a check-in is pending for, if any.
    private var dueCheckInWeek: Date? {
        _ = scenePhase
        guard checkInEnabled, !subscriptions.isEmpty else { return nil }
        let answered = Set(subscriptions.flatMap { $0.usageEntries ?? [] }.map { calendar.startOfDay(for: $0.weekStart) })
        return checkInSchedule.dueWeek(
            now: .now,
            answeredWeeks: answered,
            skippedWeek: skippedWeek > 0 ? Date(timeIntervalSince1970: skippedWeek) : nil,
            trackingSince: subscriptions.map(\.createdAt).min(),
            calendar: calendar
        )
    }

    /// A `Text` (not `String(localized:)`), so SwiftUI resolves it with the environment locale
    /// and it follows an in-app language change like every other label.
    private var title: Text {
        let firstName = userName.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? Text("Home") : Text("Hi, \(firstName)")
    }

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty && emailImport.showsScanOnHome {
                    ScrollView {
                        EmailScanCard()
                            .padding(16)
                            .frame(maxWidth: 700)
                            .frame(maxWidth: .infinity)
                    }
                } else if subscriptions.isEmpty {
                    emptyState
                } else {
                    content(HomeSummary(subscriptions: subscriptions,
                                        budget: BillingMath.storedAmount(budgetString)))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Subscription", systemImage: "plus") {
                        isAddingSubscription = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isAddingSubscription) {
                SubscriptionEditorView(subscription: nil)
            }
            .navigationDestination(item: $detailSubscription) { subscription in
                SubscriptionDetailView(subscription: subscription)
            }
            .sheet(item: $pendingSetup) { setup in
                PendingSetupFlow(setup)
            }
            .sheet(isPresented: $isEditingBudget) {
                BudgetEditorView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $router.isCheckInPresented) {
                // Opened from the card or a notification; falls back to the latest week if nothing is due.
                CheckInView(week: dueCheckInWeek ?? checkInSchedule.currentWeek(now: .now, calendar: calendar))
            }
        }
    }

    private func content(_ summary: HomeSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if emailImport.showsScanOnHome {
                    EmailScanCard()
                }

                MonthlyOverviewCard(summary: summary, currencyCode: currencyCode) {
                    isEditingBudget = true
                }

                if !summary.needsSetup.isEmpty {
                    SetupCard(subscriptions: summary.needsSetup) {
                        pendingSetup = PendingSetup(starting: $0, in: summary.needsSetup)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Up Next", actionTitle: "Calendar", action: onShowCalendar)
                    UpNextList(items: summary.upcoming, currencyCode: currencyCode) { detailSubscription = $0 }
                }

                let deadlines = Array(DeadlineList.upcoming(within: 14, purchases: purchases, notices: notices,
                                                            subscriptions: subscriptions, calendar: calendar).prefix(3))
                if !deadlines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Due Soon", actionTitle: "Deadlines") { router.selectedTab = .deadlines }
                        DeadlinesCard(items: deadlines, currencyCode: currencyCode) { router.selectedTab = .deadlines }
                    }
                }

                let dueWeek = dueCheckInWeek
                if summary.configuredCount > 0 || dueWeek != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Insights")
                        if let dueWeek {
                            CheckInCard(week: dueWeek) { router.isCheckInPresented = true }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if summary.configuredCount > 0 {
                            NavigationLink {
                                SpendingProfileDetailView()
                            } label: {
                                SpendingProfileCard(profile: summary.profile, checkInWeeks: summary.checkInWeeks)
                            }
                            .buttonStyle(.plain)
                        }
                        let savings = savingsItems
                        if !savings.isEmpty {
                            SavingsCard(items: savings, currencyCode: currencyCode) { detailSubscription = $0 }
                        }
                        if !summary.categories.isEmpty {
                            CategoryBreakdownCard(shares: summary.categories,
                                                  total: summary.monthlyTotal,
                                                  currencyCode: currencyCode)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 700)              // Readable on iPad and in landscape.
            .frame(maxWidth: .infinity)
        }
        .animation(.smooth, value: subscriptions.count)
        .animation(.smooth, value: dueCheckInWeek)
    }

    /// The best cheaper option for each configured subscription, biggest saving first.
    private var savingsItems: [SavingsCard.Item] {
        let names = subscriptions.map(\.name)
        return subscriptions
            .filter { !$0.needsSetup }
            .compactMap { subscription in
                let others = names.filter { $0 != subscription.name }
                return catalog.alternatives(forName: subscription.name,
                                            monthlyCost: subscription.monthlyCost,
                                            currencyCode: currencyCode,
                                            excludingNames: others,
                                            limit: 1)
                    .first
                    .map { SavingsCard.Item(subscription: subscription, best: $0) }
            }
            .sorted { $0.best.monthlySaving > $1.best.monthlySaving }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Subscriptions Yet", systemImage: "rectangle.stack")
        } description: {
            Text("Add the subscriptions you pay for to see your monthly cost and upcoming payments.")
        } actions: {
            Button("Add Subscription") { isAddingSubscription = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

#Preview("With data") {
    HomeView()
        .modelContainer(PreviewData.container)
}

#Preview("Empty") {
    HomeView()
        .modelContainer(PreviewData.emptyContainer)
}
