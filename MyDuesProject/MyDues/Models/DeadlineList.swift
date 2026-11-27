//
//  DeadlineList.swift
//  MyDues
//
//  Everything with a deadline, in one list: return windows, warranties, free trials and pagoPA
//  notices. Shared by the Deadlines tab, Home's "Due Soon" card and the calendar.
//

import Foundation
import SwiftData
import SwiftUI

struct DeadlineItem: Identifiable {
    enum Kind: String, CaseIterable, Hashable {
        case returnWindow, trial, notice, warranty

        var title: LocalizedStringKey {
            switch self {
            case .returnWindow: "Return"
            case .trial: "Free Trial"
            case .notice: "pagoPA"
            case .warranty: "Warranty"
            }
        }

        var symbol: String {
            switch self {
            case .returnWindow: "shippingbox.and.arrow.backward"
            case .trial: "gift"
            case .notice: "building.columns"
            case .warranty: "checkmark.seal"
            }
        }

        var color: Color {
            switch self {
            case .returnWindow: .orange
            case .trial: .purple
            case .notice: .teal
            case .warranty: .blue
            }
        }
    }

    enum Target {
        case purchase(Purchase)
        case notice(PaymentNotice)
        case subscription(Subscription)

        var modelID: PersistentIdentifier {
            switch self {
            case .purchase(let purchase): purchase.persistentModelID
            case .notice(let notice): notice.persistentModelID
            case .subscription(let subscription): subscription.persistentModelID
            }
        }
    }

    struct ID: Hashable {
        let kind: Kind
        let model: PersistentIdentifier
    }

    let kind: Kind
    /// The deadline's day. `nil` for a pagoPA notice without a due date.
    let date: Date?
    let target: Target

    var id: ID { ID(kind: kind, model: target.modelID) }

    var title: String {
        switch target {
        case .purchase(let purchase): purchase.title
        case .notice(let notice): notice.displayName
        case .subscription(let subscription): subscription.name
        }
    }

    /// Money involved: the order's price, the notice's amount, the first charge after the trial.
    var amount: Decimal? {
        let value: Decimal = switch target {
        case .purchase(let purchase): purchase.price
        case .notice(let notice): notice.amount
        case .subscription(let subscription): subscription.price
        }
        return value > 0 ? value : nil
    }
}

enum DeadlineList {
    /// Open deadlines, soonest first: returns still possible, active warranties, running trials,
    /// unpaid notices (overdue ones first, ones without a due date last).
    static func items(
        purchases: [Purchase],
        notices: [PaymentNotice],
        subscriptions: [Subscription],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DeadlineItem] {
        var items: [DeadlineItem] = []
        for purchase in purchases {
            if purchase.isReturnOpen(now: now, calendar: calendar), let returnBy = purchase.returnBy {
                items.append(DeadlineItem(kind: .returnWindow, date: returnBy, target: .purchase(purchase)))
            }
            if purchase.isWarrantyActive(now: now, calendar: calendar), let until = purchase.warrantyUntil {
                items.append(DeadlineItem(kind: .warranty, date: until, target: .purchase(purchase)))
            }
        }
        for notice in notices where !notice.isPaid {
            items.append(DeadlineItem(kind: .notice, date: notice.dueDate, target: .notice(notice)))
        }
        for subscription in subscriptions where subscription.isInTrial(now: now, calendar: calendar) {
            items.append(DeadlineItem(kind: .trial, date: subscription.trialEndDate, target: .subscription(subscription)))
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Deadlines within `days` from today (overdue notices included), for Home.
    static func upcoming(
        within days: Int,
        purchases: [Purchase],
        notices: [PaymentNotice],
        subscriptions: [Subscription],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DeadlineItem] {
        let limit = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return items(purchases: purchases, notices: notices, subscriptions: subscriptions, now: now, calendar: calendar)
            .filter { item in item.date.map { $0 <= limit } ?? false }
    }

    /// Deadlines falling on `day`, for the calendar.
    static func on(
        _ day: Date,
        purchases: [Purchase],
        notices: [PaymentNotice],
        subscriptions: [Subscription],
        calendar: Calendar = .current
    ) -> [DeadlineItem] {
        // Seen from the start of `day`, so that day's deadlines still count as open.
        items(purchases: purchases, notices: notices, subscriptions: subscriptions,
              now: calendar.startOfDay(for: day), calendar: calendar)
            .filter { item in item.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }
}
