//
//  WidgetSync.swift
//  DuelyProject
//
//  Writes the widgets' snapshot (upcoming payments, monthly total, texts in the app's language)
//  to the App Group and asks WidgetKit to redraw. Called whenever subscriptions, the budget,
//  the currency or the language change.
//

import Foundation
import WidgetKit

@MainActor
enum WidgetSync {
    static func update(subscriptions: [Subscription], currencyCode: String, budget: Decimal?,
                       now: Date = .now, calendar: Calendar = .current) {
        let configured = subscriptions.filter { !$0.needsSetup }
        let horizon = calendar.date(byAdding: .day, value: 31, to: calendar.startOfDay(for: now)) ?? now

        var upcoming: [WidgetSnapshot.Payment] = []
        for subscription in configured {
            guard let anchor = subscription.anchorDate else { continue }
            var date = BillingMath.nextPayment(anchor: anchor, cycle: subscription.cycle,
                                               onOrAfter: calendar.startOfDay(for: now), calendar: calendar)
            // Weekly plans can be charged several times in a month.
            while let current = date, current < horizon {
                upcoming.append(.init(name: subscription.name, date: current, amount: subscription.price,
                                      color: subscription.displayColorName))
                date = calendar.date(byAdding: .day, value: 1, to: current).flatMap {
                    BillingMath.nextPayment(anchor: anchor, cycle: subscription.cycle, onOrAfter: $0, calendar: calendar)
                }
            }
        }
        upcoming.sort { $0.date < $1.date }

        var inDays: [Int: String] = [:]
        for days in 2...31 { inDays[days] = String(localized: "In \(days) days") }

        let snapshot = WidgetSnapshot(
            currencyCode: currencyCode,
            localeIdentifier: LanguageController.shared.locale.identifier,
            monthlyTotal: configured.reduce(0) { $0 + $1.monthlyCost },
            budget: budget,
            upcoming: Array(upcoming.prefix(20)),
            hasSubscriptions: !subscriptions.isEmpty,
            labels: .init(
                nextPayment: String(localized: "Next Payment"),
                upcoming: String(localized: "Up Next"),
                perMonth: String(localized: "a month"),
                today: String(localized: "Today"),
                tomorrow: String(localized: "Tomorrow"),
                inDays: inDays,
                nothingDue: String(localized: "Nothing due soon."),
                noSubscriptions: String(localized: "No Subscriptions"),
                ofBudget: String(localized: "%@ of %@")
            ),
            updated: now
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
