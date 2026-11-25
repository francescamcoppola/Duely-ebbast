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
        for subscription in configured where subscription.hasCharges {
            // Weekly plans can be charged several times in a month. Paid ones are done with.
            for date in subscription.paymentDates(from: calendar.startOfDay(for: now), to: horizon, calendar: calendar)
            where !subscription.isMarkedPaid(on: date, calendar: calendar) {
                upcoming.append(.init(name: subscription.name, date: date, amount: subscription.price,
                                      color: subscription.displayColorName))
            }
        }
        upcoming.sort { $0.date < $1.date }

        var inDays: [Int: String] = [:]
        for days in 2...31 { inDays[days] = String(appLocalized: "In \(days) days") }

        let snapshot = WidgetSnapshot(
            currencyCode: currencyCode,
            localeIdentifier: LanguageController.shared.locale.identifier,
            monthlyTotal: configured.reduce(0) { $0 + $1.monthlyCost },
            budget: budget,
            upcoming: Array(upcoming.prefix(20)),
            hasSubscriptions: !subscriptions.isEmpty,
            labels: .init(
                nextPayment: String(appLocalized: "Next Payment"),
                upcoming: String(appLocalized: "Up Next"),
                perMonth: String(appLocalized: "a month"),
                today: String(appLocalized: "Today"),
                tomorrow: String(appLocalized: "Tomorrow"),
                inDays: inDays,
                nothingDue: String(appLocalized: "Nothing due soon."),
                noSubscriptions: String(appLocalized: "No Subscriptions"),
                ofBudget: String(appLocalized: "%@ of %@")
            ),
            updated: now
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
