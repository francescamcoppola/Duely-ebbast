//
//  ReminderPlanner.swift
//  MyDues
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
    /// Returns, warranties, free trials and pagoPA notices.
    static let deadlinePrefix = "deadline-"
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

    /// Payment reminders plus deadline reminders (returns, warranties, free trials, pagoPA
    /// notices), soonest first and capped together at `maxTotal`.
    static func plan(
        subscriptions: [Subscription],
        currencyCode: String,
        includePayments: Bool = true,
        purchases: [Purchase] = [],
        notices: [PaymentNotice] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var drafts: [Draft] = []
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now

        for subscription in subscriptions where includePayments && subscription.hasCharges && subscription.reminderDaysBefore > 0 {
            let days = subscription.reminderDaysBefore
            // The trial's own reminder covers its first charge.
            let trialEnd = subscription.isInTrial(now: now, calendar: calendar) ? subscription.trialEndDate : nil
            // Stops after the last installment; payments already marked as paid need no reminder.
            let payments = subscription.paymentDates(from: calendar.startOfDay(for: now), to: horizon, calendar: calendar)
                .filter { !subscription.isMarkedPaid(on: $0, calendar: calendar) }
                .filter { payment in trialEnd.map { !calendar.isDate($0, inSameDayAs: payment) } ?? true }
            var added = 0
            for payment in payments {
                guard added < perSubscription,
                      let fire = fireDate(payment: payment, daysBefore: days, calendar: calendar),
                      fire > now else { continue }
                drafts.append(Draft(date: fire, isDeadline: false,
                                    title: title(name: subscription.name, daysBefore: days),
                                    body: body(price: subscription.price, currencyCode: currencyCode, payment: payment)))
                added += 1
            }
        }

        drafts += deadlineDrafts(subscriptions: subscriptions, purchases: purchases, notices: notices,
                                 currencyCode: currencyCode, now: now, calendar: calendar)

        return drafts
            .sorted { $0.date < $1.date }
            .prefix(maxTotal)
            .enumerated()
            .map { offset, draft in
                let prefix = draft.isDeadline ? NotificationIDs.deadlinePrefix : NotificationIDs.paymentPrefix
                return PlannedReminder(id: "\(prefix)\(offset)", fireDate: draft.date, title: draft.title, body: draft.body)
            }
    }

    private struct Draft {
        let date: Date
        let isDeadline: Bool
        let title: String
        let body: String
    }

    // MARK: Deadlines

    /// Days before the end of a return window: a first warning, then the last day itself.
    static let returnDaysBefore = 3
    static let warrantyDaysBefore = 30
    static let trialDaysBefore = 2

    private static func deadlineDrafts(
        subscriptions: [Subscription],
        purchases: [Purchase],
        notices: [PaymentNotice],
        currencyCode: String,
        now: Date,
        calendar: Calendar
    ) -> [Draft] {
        var drafts: [Draft] = []
        func add(_ day: Date, before days: Int, _ title: String, _ body: String) {
            guard let fire = fireDate(payment: day, daysBefore: days, calendar: calendar), fire > now else { return }
            drafts.append(Draft(date: fire, isDeadline: true, title: title, body: body))
        }

        for purchase in purchases {
            if purchase.returnReminderEnabled, purchase.isReturnOpen(now: now, calendar: calendar),
               let returnBy = purchase.returnBy {
                let date = longDate(returnBy)
                add(returnBy, before: returnDaysBefore,
                    String(appLocalized: "\(purchase.title): \(returnDaysBefore) days left to return it"),
                    String(appLocalized: "You can return it to \(purchase.store) until \(date)."))
                add(returnBy, before: 0,
                    String(appLocalized: "Last day to return \(purchase.title)"),
                    String(appLocalized: "The return window at \(purchase.store) closes today."))
            }
            if purchase.warrantyReminderEnabled, purchase.isWarrantyActive(now: now, calendar: calendar),
               let until = purchase.warrantyUntil {
                let date = longDate(until)
                add(until, before: warrantyDaysBefore,
                    String(appLocalized: "\(purchase.title): warranty ends in a month"),
                    String(appLocalized: "It's covered until \(date). If something isn't working, now is the time to ask for a repair."))
            }
        }

        for notice in notices where !notice.isPaid {
            guard let due = notice.dueDate else { continue }
            let amount = notice.amount.formatted(.currency(code: "EUR").locale(LocalizedBundle.locale))
            let date = longDate(due)
            let name = notice.displayName
            if notice.reminderDaysBefore > 0 {
                add(due, before: notice.reminderDaysBefore,
                    String(appLocalized: "pagoPA notice from \(name) due in \(notice.reminderDaysBefore) days"),
                    String(appLocalized: "\(amount) to pay by \(date). Tap to pay it."))
            }
            add(due, before: 0,
                String(appLocalized: "pagoPA notice from \(name) due today"),
                String(appLocalized: "\(amount) to pay today. Tap to pay it."))
        }

        for subscription in subscriptions where subscription.isInTrial(now: now, calendar: calendar) {
            guard let end = subscription.trialEndDate else { continue }
            let date = longDate(end)
            let body = subscription.price > 0
                ? String(appLocalized: "Then \(subscription.price.formatted(.currency(code: currencyCode).locale(LocalizedBundle.locale))) will be charged on \(date). Cancel before then if you don't want to keep it.")
                : String(appLocalized: "It turns into a paid plan on \(date). Cancel before then if you don't want to keep it.")
            add(end, before: trialDaysBefore,
                String(appLocalized: "\(subscription.name) free trial ends in \(trialDaysBefore) days"),
                body)
        }
        return drafts
    }

    private static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(LocalizedBundle.locale))
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
