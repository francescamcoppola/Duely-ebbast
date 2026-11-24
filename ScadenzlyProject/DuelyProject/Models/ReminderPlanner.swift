//
//  ReminderPlanner.swift
//  DuelyProject
//
//  Decides which payment reminders to schedule. Pure: returns plain values that the
//  notification service turns into requests.
//

import Foundation
import SwiftData

/// `nonisolated`: read off the main actor by `NotificationService`.
nonisolated struct PlannedReminder: Equatable, Sendable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Identifiers shared by the planner, the service and the router.
nonisolated enum NotificationIDs {
    static let checkIn = "weekly-check-in"
    static let paymentPrefix = "payment-"
}

enum ReminderPlanner {
    /// Reminders arrive in the morning, not at midnight.
    static let reminderHour = 9
    /// A few upcoming payments per subscription, so reminders keep coming even if the app
    /// isn't opened for a while (every launch reschedules).
    static let perSubscription = 3
    /// iOS keeps at most 64 pending notifications per app; leave room for the check-in.
    static let maxTotal = 60
    static let horizonDays = 400

    static func plan(
        subscriptions: [Subscription],
        currencyCode: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var drafts: [(date: Date, title: String, body: String)] = []
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        for subscription in subscriptions where !subscription.needsSetup && subscription.reminderDaysBefore > 0 {
            let days = subscription.reminderDaysBefore
            // Stops after the last installment; payments already marked as paid need no reminder.
            let payments = subscription.paymentDates(from: calendar.startOfDay(for: now), to: horizon, calendar: calendar)
                .filter { !subscription.isMarkedPaid(on: $0, calendar: calendar) }
            var added = 0
            for payment in payments {
                guard added < perSubscription,
                      let fire = fireDate(payment: payment, daysBefore: days, calendar: calendar),
                      fire > now else { continue }
                drafts.append((fire,
                               title(name: subscription.name, daysBefore: days),
                               body(price: subscription.price, currencyCode: currencyCode, payment: payment)))
                added += 1
            }
        }

        return drafts
            .sorted { $0.date < $1.date }
            .prefix(maxTotal)
            .enumerated()
            .map { PlannedReminder(id: "\(NotificationIDs.paymentPrefix)\($0.offset)", fireDate: $0.element.date,
                                   title: $0.element.title, body: $0.element.body) }
    }

    static func fireDate(payment: Date, daysBefore: Int, calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: payment)) else {
            return nil
        }
        return calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day)
    }

    static func title(name: String, daysBefore: Int) -> String {
        switch daysBefore {
        case 1: String(appLocalized: "\(name) renews tomorrow")
        case 7: String(appLocalized: "\(name) renews in a week")
        default: String(appLocalized: "\(name) renews in \(daysBefore) days")
        }
    }

    static func body(price: Decimal, currencyCode: String, payment: Date) -> String {
        let amount = price.formatted(.currency(code: currencyCode).locale(LocalizedBundle.locale))
        let date = payment.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(LocalizedBundle.locale))
        return String(appLocalized: "\(amount) will be charged on \(date).")
    }
}
