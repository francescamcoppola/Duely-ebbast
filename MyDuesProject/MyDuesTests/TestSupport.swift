//
//  TestSupport.swift
//  MyDuesTests
//
//  A fixed calendar and date helper, so results don't depend on the machine's
//  time zone, region or first weekday, plus an in-memory store for model tests.
//

import Foundation
import SwiftData
@testable import MyDues

enum TestCalendar {
    /// Gregorian, UTC, Sunday-first.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()
}

/// `date(2026, 11, 18, 14, 30)` → 18 Nov 2026, 14:30 UTC.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    guard let date = TestCalendar.utc.date(from: components) else {
        preconditionFailure("Invalid test date \(components)")
    }
    return date
}

/// An in-memory SwiftData store. Keep it alive for as long as its models are used.
@MainActor
final class TestStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Subscription.self, UsageEntry.self, Purchase.self, PaymentNotice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Inserts a subscription. `answers` are check-in answers for the weeks starting at
    /// `weeks[i]` (true = used), so tests can control exactly which weeks were answered.
    @discardableResult
    func subscription(
        _ name: String,
        price: Decimal,
        cycle: BillingCycle = .monthly,
        anchor: Date? = date(2026, 11, 25),
        reminderDays: Int = 1,
        answers: [(week: Date, used: Bool)] = []
    ) -> Subscription {
        let subscription = Subscription(name: name, price: price, cycle: cycle,
                                        anchorDate: anchor, reminderDaysBefore: reminderDays)
        context.insert(subscription)
        for answer in answers {
            context.insert(UsageEntry(weekStart: answer.week, used: answer.used, subscription: subscription))
        }
        return subscription
    }
}
