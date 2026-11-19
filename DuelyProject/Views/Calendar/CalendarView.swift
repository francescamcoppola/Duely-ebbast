//
//  CalendarView.swift
//  DuelyProject
//
//  The full payment schedule: month grid → selected day's payments → the month's real charges.
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @Environment(\.calendar) private var calendar
    @State private var month = CalendarMonth(containing: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    /// Payment rows open the same detail screen as the Subscriptions tab.
    @State private var detailSubscription: Subscription?
    @State private var isAddingSubscription = false

    private var isShowingToday: Bool {
        month.contains(.now, calendar: calendar) && calendar.isDateInToday(selectedDay)
    }

    var body: some View {
        let schedule = MonthSchedule(subscriptions: subscriptions, month: month, calendar: calendar)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    MonthGridView(month: month, schedule: schedule, selectedDay: $selectedDay) { offset in
                        showMonth(month.adding(months: offset, calendar: calendar))
                    }

                    DayAgendaView(
                        day: selectedDay,
                        payments: schedule.payments(on: selectedDay, calendar: calendar),
                        currencyCode: currencyCode
                    ) { detailSubscription = $0 }

                    if schedule.paymentCount > 0 {
                        MonthSummaryCard(schedule: schedule, currencyCode: currencyCode, today: .now)
                    }

                    if subscriptions.isEmpty {
                        emptyHint
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today", action: goToToday)
                        .disabled(isShowingToday)
                }
            }
            .navigationDestination(item: $detailSubscription) { subscription in
                SubscriptionDetailView(subscription: subscription)
            }
            .sheet(isPresented: $isAddingSubscription) {
                SubscriptionEditorView(subscription: nil)
            }
        }
    }

    /// A card, not a ContentUnavailableView: the month grid above already fills the screen.
    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Payments Yet")
                        .font(.headline)
                    Text("Add a subscription and its billing dates will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }

            Button("Add Subscription") { isAddingSubscription = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .cardStyle()
    }

    // MARK: Navigation

    private func showMonth(_ newMonth: CalendarMonth) {
        month = newMonth
        // Same rule as the Calendar app: today if it's in view, otherwise the 1st.
        selectedDay = newMonth.contains(.now, calendar: calendar)
            ? calendar.startOfDay(for: .now)
            : newMonth.start
    }

    private func goToToday() {
        withAnimation(.smooth) {
            month = CalendarMonth(containing: .now, calendar: calendar)
            selectedDay = calendar.startOfDay(for: .now)
        }
    }
}

#Preview("With data") {
    CalendarView()
        .modelContainer(PreviewData.container)
}

#Preview("Empty") {
    CalendarView()
        .modelContainer(PreviewData.emptyContainer)
}
