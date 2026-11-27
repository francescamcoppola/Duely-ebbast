//
//  SpendingProfile.swift
//  DuelyProject
//
//  Classifies the user from two signals:
//  1. How much of the monthly budget their subscriptions take.
//  2. How often they actually use them (weekly check-ins).
//

import SwiftUI

enum SpendingProfile: String, CaseIterable, Sendable {
    case newcomer, saver, balanced, spender, overBudget, collector, optimizer

    // MARK: Thresholds (one place to tune them)

    enum Threshold {
        static let saver = 0.5            // < 50 % of budget
        static let balanced = 0.85        // < 85 % of budget
        static let lowUsage = 0.4         // used in < 40 % of check-in answers
        static let highUsage = 0.75       // used in ≥ 75 % of check-in answers
        static let minimumCheckInWeeks = 2
        static let collectorMinimumSubscriptions = 3
    }

    /// - Parameters:
    ///   - monthlyTotal: monthly-equivalent cost of all configured subscriptions.
    ///   - budget: monthly budget, `nil` if the user skipped it.
    ///   - usageRate: share of check-in answers marked "used" (0…1), `nil` without check-ins.
    ///   - checkInWeeks: distinct weeks with at least one answer.
    ///   - subscriptionCount: configured subscriptions.
    static func evaluate(
        monthlyTotal: Decimal,
        budget: Decimal?,
        usageRate: Double?,
        checkInWeeks: Int,
        subscriptionCount: Int
    ) -> SpendingProfile {
        guard subscriptionCount > 0 else { return .newcomer }

        let ratio: Double? = budget.flatMap { $0 > 0 ? BillingMath.double(monthlyTotal) / BillingMath.double($0) : nil }

        if let ratio, ratio > 1 { return .overBudget }

        if checkInWeeks >= Threshold.minimumCheckInWeeks, let usageRate {
            if usageRate < Threshold.lowUsage, subscriptionCount >= Threshold.collectorMinimumSubscriptions {
                return .collector
            }
            if usageRate >= Threshold.highUsage, (ratio ?? 0) < Threshold.balanced {
                return .optimizer
            }
        }

        guard let ratio else { return .newcomer }
        if ratio < Threshold.saver { return .saver }
        if ratio < Threshold.balanced { return .balanced }
        return .spender
    }

    // MARK: Presentation

    var title: LocalizedStringKey {
        switch self {
        case .newcomer: "Getting Started"
        case .saver: "Saver"
        case .balanced: "Balanced"
        case .spender: "Spender"
        case .overBudget: "Over Budget"
        case .collector: "Collector"
        case .optimizer: "Optimizer"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .newcomer: "Set a budget and complete a weekly check-in to discover your profile."
        case .saver: "Your subscriptions use less than half of your budget."
        case .balanced: "Your subscriptions fit comfortably within your budget."
        case .spender: "You're close to your budget. A check-in can show what to cut."
        case .overBudget: "Your subscriptions cost more than your monthly budget."
        case .collector: "You pay for more than you use. Some subscriptions may be worth canceling."
        case .optimizer: "You use what you pay for and stay within budget."
        }
    }

    var symbol: String {
        switch self {
        case .newcomer: "hand.wave.fill"
        case .saver: "leaf.fill"
        case .balanced: "scale.3d"
        case .spender: "cart.fill"
        case .overBudget: "exclamationmark.triangle.fill"
        case .collector: "square.stack.3d.up.fill"
        case .optimizer: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .newcomer: .blue
        case .saver: .green
        case .balanced: .teal
        case .spender: .orange
        case .overBudget: .red
        case .collector: .purple
        case .optimizer: .indigo
        }
    }
}
