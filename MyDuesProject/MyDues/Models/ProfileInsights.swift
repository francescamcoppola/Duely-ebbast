//
//  ProfileInsights.swift
//  MyDues
//
//  The numbers behind the spending profile: the two signals it's based on, which subscriptions
//  are least worth their cost, and what canceling them would change.
//  Home and the profile detail screen both read from here, so they always agree.
//

import Foundation
import SwiftData

struct ProfileInsights {
    /// One subscription's recent check-in answers.
    struct Usage: Identifiable {
        let subscription: Subscription
        let usedWeeks: Int
        let answeredWeeks: Int

        var id: Subscription.ID { subscription.id }

        var rate: Double { answeredWeeks > 0 ? Double(usedWeeks) / Double(answeredWeeks) : 0 }

        /// Weekly cost spread over the weeks it was actually used; `nil` if it wasn't used at all.
        var costPerUsedWeek: Decimal? {
            guard usedWeeks > 0 else { return nil }
            let weeklyCost = BillingMath.yearlyEquivalent(price: subscription.price, cycle: subscription.cycle) / 52
            return weeklyCost * Decimal(answeredWeeks) / Decimal(usedWeeks)
        }
    }

    /// Canceling these would move the user to a better profile.
    struct Suggestion {
        let cancel: [Subscription]
        let monthlySavings: Decimal
        let newProfile: SpendingProfile
    }

    /// Only recent answers count, so the profile reflects current habits.
    static let lookbackWeeks = 4
    /// The suggestion never asks to cancel more than this many at once.
    static let maxSuggestedCancellations = 3

    let profile: SpendingProfile
    let monthlyTotal: Decimal
    let budget: Decimal?
    /// Share of check-in answers marked "used" (0…1), `nil` without recent check-ins.
    let usageRate: Double?
    /// Distinct weeks with at least one recent answer.
    let checkInWeeks: Int
    let subscriptionCount: Int
    /// Subscriptions with recent answers, least worth their cost first.
    let usage: [Usage]
    let suggestion: Suggestion?

    init(subscriptions: [Subscription], budget: Decimal?, now: Date = .now, calendar: Calendar = .current) {
        let configured = subscriptions.filter { !$0.needsSetup }
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -Self.lookbackWeeks, to: now) ?? now

        var allWeeks = Set<Date>()
        var usage: [Usage] = []
        for subscription in configured {
            let recent = (subscription.usageEntries ?? []).filter { $0.weekStart >= cutoff }
            allWeeks.formUnion(recent.map { calendar.startOfDay(for: $0.weekStart) })
            if !recent.isEmpty {
                usage.append(Usage(subscription: subscription,
                                   usedWeeks: recent.filter(\.used).count,
                                   answeredWeeks: recent.count))
            }
        }

        // Least used first; among equally used, the most expensive first.
        usage.sort {
            if $0.rate != $1.rate { return $0.rate < $1.rate }
            return $0.subscription.monthlyCost > $1.subscription.monthlyCost
        }

        let monthlyTotal = configured.reduce(Decimal.zero) { $0 + $1.monthlyCost }
        let usageRate = Self.rate(of: usage)

        self.monthlyTotal = monthlyTotal
        self.budget = budget
        self.usageRate = usageRate
        self.checkInWeeks = allWeeks.count
        self.subscriptionCount = configured.count
        self.usage = usage
        self.profile = SpendingProfile.evaluate(
            monthlyTotal: monthlyTotal,
            budget: budget,
            usageRate: usageRate,
            checkInWeeks: allWeeks.count,
            subscriptionCount: configured.count
        )
        self.suggestion = Self.suggestion(
            for: profile, usage: usage, monthlyTotal: monthlyTotal, budget: budget,
            checkInWeeks: allWeeks.count, subscriptionCount: configured.count
        )
    }

    // MARK: Derived

    /// 0…∞ (1 = exactly on budget).
    var budgetRatio: Double? {
        guard let budget, budget > 0 else { return nil }
        return BillingMath.double(monthlyTotal) / BillingMath.double(budget)
    }

    var hasEnoughCheckIns: Bool {
        checkInWeeks >= SpendingProfile.Threshold.minimumCheckInWeeks && usageRate != nil
    }

    // MARK: Helpers

    private static func rate(of usage: [Usage]) -> Double? {
        let answered = usage.reduce(0) { $0 + $1.answeredWeeks }
        guard answered > 0 else { return nil }
        return Double(usage.reduce(0) { $0 + $1.usedWeeks }) / Double(answered)
    }

    /// Cancels the least-worth subscriptions one at a time (up to a few) and returns the first set
    /// that lands on a better profile. Only subscriptions with check-in answers are candidates:
    /// without usage data, suggesting a cancellation would be a guess.
    private static func suggestion(
        for profile: SpendingProfile,
        usage: [Usage],
        monthlyTotal: Decimal,
        budget: Decimal?,
        checkInWeeks: Int,
        subscriptionCount: Int
    ) -> Suggestion? {
        guard [.overBudget, .collector, .spender].contains(profile) else { return nil }

        let candidates = usage
            .filter { $0.rate < SpendingProfile.Threshold.highUsage }
            .prefix(maxSuggestedCancellations)

        var removed: [Usage] = []
        for candidate in candidates {
            removed.append(candidate)
            let remainingCount = subscriptionCount - removed.count
            guard remainingCount > 0 else { return nil }

            let removedIDs = Set(removed.map(\.id))
            let savings = removed.reduce(Decimal.zero) { $0 + $1.subscription.monthlyCost }
            let newProfile = SpendingProfile.evaluate(
                monthlyTotal: monthlyTotal - savings,
                budget: budget,
                usageRate: rate(of: usage.filter { !removedIDs.contains($0.id) }),
                checkInWeeks: checkInWeeks,
                subscriptionCount: remainingCount
            )
            if newProfile.rank > profile.rank {
                return Suggestion(cancel: removed.map(\.subscription), monthlySavings: savings, newProfile: newProfile)
            }
        }
        return nil
    }
}

private extension SpendingProfile {
    /// Higher is healthier. Used only to decide whether a change is an improvement.
    var rank: Int {
        switch self {
        case .newcomer: -1
        case .overBudget: 0
        case .collector: 1
        case .spender: 2
        case .balanced, .saver: 3
        case .optimizer: 4
        }
    }
}
