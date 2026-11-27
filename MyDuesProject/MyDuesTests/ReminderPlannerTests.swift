//
//  ReminderPlannerTests.swift
//  MyDuesTests
//
//  "Now" is Wed 18 Nov 2026, 12:00 UTC throughout.
//

import Foundation
import Testing
@testable import MyDues

@MainActor
@Suite("ReminderPlanner")
struct ReminderPlannerTests {
    private let calendar = TestCalendar.utc
    private let now = date(2026, 11, 18, 12)
    private let store: TestStore

    init() throws {
        store = try TestStore()
    }

    private func plan(_ subscriptions: [Subscription]) -> [PlannedReminder] {
        ReminderPlanner.plan(subscriptions: subscriptions, currencyCode: "USD", now: now, calendar: calendar)
    }

    // MARK: Fire date

    @Test("Reminders fire in the morning, the chosen number of days before")
    func fireDate() {
        let fire = ReminderPlanner.fireDate(payment: date(2026, 11, 25, 15), daysBefore: 3, calendar: calendar)
        #expect(fire == date(2026, 11, 22, ReminderPlanner.reminderHour))
    }

    // MARK: Plan

    @Test("Each subscription gets a few upcoming reminders, soonest first")
    func perSubscription() throws {
        let netflix = store.subscription("Netflix", price: 15, anchor: date(2026, 11, 25))
        let reminders = plan([netflix])

        #expect(reminders.count == ReminderPlanner.perSubscription)
        #expect(reminders.map(\.fireDate) == [
            date(2026, 11, 24, 9), date(2026, 12, 24, 9), date(2027, 1, 24, 9),
        ])
    }

    @Test("A reminder whose time has already passed is skipped, not sent late")
    func pastFireDateSkipped() throws {
        // Payment tomorrow, reminder 1 day before = today at 9:00, which is before noon.
        let spotify = store.subscription("Spotify", price: 11, anchor: date(2026, 11, 19))
        let reminders = plan([spotify])

        #expect(reminders.first?.fireDate == date(2026, 12, 18, 9))
        #expect(reminders.allSatisfy { $0.fireDate > now })
    }

    @Test("Subscriptions without a price or with reminders off get none")
    func skipsUnconfiguredAndDisabled() {
        let noPrice = store.subscription("HBO Max", price: 0)
        let noAnchor = store.subscription("Disney+", price: 10, anchor: nil)
        let off = store.subscription("iCloud", price: 3, reminderDays: 0)
        #expect(plan([noPrice, noAnchor, off]).isEmpty)
    }

    @Test("Never more than iOS allows, leaving room for the check-in")
    func respectsPendingNotificationLimit() {
        let subscriptions = (0..<30).map {
            store.subscription("Weekly \($0)", price: 1, cycle: .weekly, anchor: date(2026, 11, 20))
        }
        let reminders = plan(subscriptions)

        #expect(subscriptions.count * ReminderPlanner.perSubscription > ReminderPlanner.maxTotal)
        #expect(reminders.count == ReminderPlanner.maxTotal)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
    }

    @Test("Identifiers are unique and use the payment prefix the service clears")
    func identifiers() {
        let reminders = plan([
            store.subscription("A", price: 5, anchor: date(2026, 11, 25)),
            store.subscription("B", price: 6, anchor: date(2026, 11, 28)),
        ])
        #expect(Set(reminders.map(\.id)).count == reminders.count)
        #expect(reminders.allSatisfy { $0.id.hasPrefix(NotificationIDs.paymentPrefix) })
    }

    @Test("Titles read naturally for the common reminder choices", arguments: [
        (1, "Netflix renews tomorrow"),
        (7, "Netflix renews in a week"),
        (3, "Netflix renews in 3 days"),
    ])
    func titles(daysBefore: Int, expected: String) {
        #expect(ReminderPlanner.title(name: "Netflix", daysBefore: daysBefore) == expected)
    }
}
