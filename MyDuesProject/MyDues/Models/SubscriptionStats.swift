//
//  SubscriptionStats.swift
//  MyDues
//
//  Per-subscription numbers for the detail screen: what it has cost so far and how much it's used.
//

import Foundation
import SwiftData

struct SubscriptionStats {
    struct WeekUsage: Identifiable {
        let weekStart: Date
        let used: Bool
        var id: Date { weekStart }
    }

    static let usageWeeksShown = 8

    /// Charges strictly before today since tracking began, plus upcoming ones marked as paid.
    let chargedCount: Int
    let chargedTotal: Decimal
    let trackingStart: Date
    /// Oldest → newest, one entry per week, at most `usageWeeksShown`.
    let recentUsage: [WeekUsage]
    /// Share of answered weeks marked "used" (0…1), `nil` without check-ins.
    let usageRate: Double?
    /// All-time counts, so the summary reads "Used 3 of 4 weeks" instead of a bare percentage.
    let usedWeeks: Int
    let answeredWeeks: Int
    /// Weekly cost divided by usage rate: what each week you actually used it really cost.
    let costPerUsedWeek: Decimal?

    init(subscription: Subscription, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        trackingStart = subscription.trackingStart(calendar: calendar)

        if !subscription.needsSetup {
            let past = subscription.paymentDates(from: trackingStart, to: today, limit: 10_000, calendar: calendar)
            // Upcoming payments already marked as paid count too.
            let paidAhead = subscription.paidDates.filter { day in
                day >= today && !subscription.paymentDates(
                    from: day, to: calendar.date(byAdding: .day, value: 1, to: day) ?? day, calendar: calendar
                ).isEmpty
            }
            chargedCount = past.count + paidAhead.count
            chargedTotal = subscription.price * Decimal(chargedCount)
        } else {
            chargedCount = 0
            chargedTotal = 0
        }

        // One answer per week (the check-in updates in place, so duplicates are only a safety net).
        var byWeek: [Date: UsageEntry] = [:]
        for entry in subscription.usageEntries ?? [] {
            let week = calendar.startOfDay(for: entry.weekStart)
            byWeek[week] = entry
        }
        let weeks = byWeek
            .map { WeekUsage(weekStart: $0.key, used: $0.value.used) }
            .sorted { $0.weekStart < $1.weekStart }
        recentUsage = Array(weeks.suffix(Self.usageWeeksShown))
        usedWeeks = weeks.filter(\.used).count
        answeredWeeks = weeks.count

        if weeks.isEmpty {
            usageRate = nil
            costPerUsedWeek = nil
        } else {
            let rate = Double(weeks.filter(\.used).count) / Double(weeks.count)
            usageRate = rate
            let weeklyCost = BillingMath.yearlyEquivalent(price: subscription.price, cycle: subscription.cycle) / 52
            costPerUsedWeek = rate > 0 && weeklyCost > 0 ? weeklyCost / Decimal(rate) : nil
        }
    }
}
