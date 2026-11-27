//
//  HomeSummary.swift
//  MyDues
//
//  Everything the Home screen shows, computed once per render from the store.
//  Keeping it here (not in the views) makes each card a dumb, previewable view.
//


import Foundation
import SwiftData

struct HomeSummary {
    struct Upcoming: Identifiable {
        let subscription: Subscription
        let date: Date
        let daysAway: Int
        var id: Subscription.ID { subscription.id }
        var isPaid: Bool { subscription.isMarkedPaid(on: date) }
    }

    struct CategoryShare: Identifiable {
        let category: SubscriptionCategory
        let amount: Decimal
        var id: SubscriptionCategory { category }
    }

    enum BudgetStatus {
        case onTrack, gettingClose, over
    }

    let monthlyTotal: Decimal
    let yearlyTotal: Decimal
    let budget: Decimal?
    let configuredCount: Int
    let upcoming: [Upcoming]
    let categories: [CategoryShare]
    let needsSetup: [Subscription]
    let profile: SpendingProfile
    let checkInWeeks: Int

    static let upcomingWindowDays = 14
    static let maxUpcoming = 3

    init(subscriptions: [Subscription], budget: Decimal?, now: Date = .now, calendar: Calendar = .current) {
        let configured = subscriptions.filter { !$0.needsSetup }
        self.configuredCount = configured.count
        self.budget = budget
        self.needsSetup = subscriptions.filter(\.needsSetup)

        self.monthlyTotal = configured.reduce(Decimal.zero) { $0 + $1.monthlyCost }
        self.yearlyTotal = configured.reduce(Decimal.zero) { $0 + $1.yearlyCost }

        // Up next: payments in the coming two weeks, soonest first.
        self.upcoming = Array(
            configured
                .filter(\.hasCharges)
                .compactMap { subscription -> Upcoming? in
                    guard let date = subscription.nextPayment(after: now, calendar: calendar) else { return nil }
                    let days = BillingMath.daysBetween(now, date, calendar: calendar)
                    guard days <= Self.upcomingWindowDays else { return nil }
                    return Upcoming(subscription: subscription, date: date, daysAway: days)
                }
                .sorted { ($0.date, $0.subscription.name) < ($1.date, $1.subscription.name) }
                .prefix(Self.maxUpcoming)
        )

        // Spending by category, largest first.
        var totals: [SubscriptionCategory: Decimal] = [:]
        for subscription in configured {
            totals[subscription.category, default: 0] += subscription.monthlyCost
        }
        self.categories = totals
            .map { CategoryShare(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        // Profile and usage come from the same model the profile detail screen uses.
        let insights = ProfileInsights(subscriptions: configured, budget: budget, now: now, calendar: calendar)
        self.checkInWeeks = insights.checkInWeeks
        self.profile = insights.profile
    }

    // MARK: Budget

    var remaining: Decimal? { budget.map { $0 - monthlyTotal } }

    /// 0…∞ (1 = exactly on budget).
    var budgetRatio: Double? {
        guard let budget, budget > 0 else { return nil }
        return BillingMath.double(monthlyTotal) / BillingMath.double(budget)
    }

    var budgetStatus: BudgetStatus? {
        guard let budgetRatio else { return nil }
        if budgetRatio > 1 { return .over }
        if budgetRatio >= SpendingProfile.Threshold.balanced { return .gettingClose }
        return .onTrack
    }

    // MARK: Relative day labels

    /// "Today", "Tomorrow", "In 5 days". Day-based, so 23:00 → tomorrow 00:00 is still "Tomorrow".
    static func relativeDay(_ daysAway: Int) -> String {
        switch daysAway {
        case ...0: String(appLocalized: "Today")
        case 1: String(appLocalized: "Tomorrow")
        default: String(appLocalized: "In \(daysAway) days")
        }
    }
}
