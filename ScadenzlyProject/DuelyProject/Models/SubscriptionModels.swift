//
//  SubscriptionModels.swift
//  DuelyProject
//
//  SwiftData models. Every stored property has a default and relationships are optional,
//  as CloudKit requires: the store syncs to the user's private iCloud database (see Persistence.swift).
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Billing cycle

enum BillingCycle: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly, monthly, bimonthly, quarterly, semiannual, yearly

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .bimonthly: "Every 2 Months"
        case .quarterly: "Every 3 Months"
        case .semiannual: "Every 6 Months"
        case .yearly: "Yearly"
        }
    }

    /// Calendar step between two payments.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .bimonthly: (.month, 2)
        case .quarterly: (.month, 3)
        case .semiannual: (.month, 6)
        case .yearly: (.year, 1)
        }
    }

    var paymentsPerYear: Decimal {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .bimonthly: 6
        case .quarterly: 4
        case .semiannual: 2
        case .yearly: 1
        }
    }
}

// MARK: - Category

enum SubscriptionCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case filmTV, music, leisure, social, work, utilities, home, taxes, education, insurance, other

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .filmTV: "Film & TV"
        case .music: "Music"
        case .leisure: "Leisure"
        case .social: "Social"
        case .work: "Work"
        case .utilities: "Utilities"
        case .home: "Home & Bills"
        case .taxes: "Taxes & Fees"
        case .education: "Education"
        case .insurance: "Insurance"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .filmTV: "tv"
        case .music: "music.note"
        case .leisure: "gamecontroller"
        case .social: "bubble.left.and.bubble.right"
        case .work: "briefcase"
        case .utilities: "wrench.and.screwdriver"
        case .home: "house"
        case .taxes: "building.columns"
        case .education: "graduationcap"
        case .insurance: "checkmark.shield"
        case .other: "square.grid.2x2"
        }
    }

    var colorName: String {
        switch self {
        case .filmTV: "red"
        case .music: "green"
        case .leisure: "purple"
        case .social: "indigo"
        case .work: "teal"
        case .utilities: "orange"
        case .home: "brown"
        case .taxes: "blue"
        case .education: "yellow"
        case .insurance: "pink"
        case .other: "gray"
        }
    }

    var color: Color {
        switch self {
        case .filmTV: .red
        case .music: .green
        case .leisure: .purple
        case .social: .indigo
        case .work: .teal
        case .utilities: .orange
        case .home: .brown
        case .taxes: .blue
        case .education: .yellow
        case .insurance: .pink
        case .other: .gray
        }
    }

    /// Maps the onboarding catalog's category ids.
    init(starterCategoryID: String) {
        switch starterCategoryID {
        case "film-tv": self = .filmTV
        case "music": self = .music
        case "leisure": self = .leisure
        default: self = .other
        }
    }
}

// MARK: - Color

/// Curated system colors (like Reminders lists): they adapt to Dark Mode and Increase Contrast,
/// and keep the white monogram letter readable, which a free-form color wheel can't guarantee.
enum SubscriptionTint: String, CaseIterable, Identifiable, Codable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .teal: "Teal"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .brown: "Brown"
        }
    }
}

// MARK: - Reminder options

enum ReminderOption {
    /// Days before a payment. 0 = no reminder.
    static let all = [0, 1, 2, 3, 7]

    static func title(_ days: Int) -> LocalizedStringKey {
        switch days {
        case 0: "None"
        case 1: "1 day before"
        case 7: "1 week before"
        default: "\(days) days before"
        }
    }
}

// MARK: - Subscription

@Model
final class Subscription {
    var name: String = ""
    var price: Decimal = 0
    var cycleRaw: String = BillingCycle.monthly.rawValue
    var categoryRaw: String = SubscriptionCategory.other.rawValue
    /// Any known payment date. Future payments are derived from it, so it never needs updating.
    var anchorDate: Date?
    /// 0 = no reminder.
    var reminderDaysBefore: Int = 1
    var createdAt: Date = Date.now
    /// User-chosen color. `nil` = use the category's color.
    var tintRaw: String?
    /// Plan picked from the catalog, e.g. "Premium". `nil` when entered by hand.
    var planName: String?
    /// The email account this was found in, when it came from an email import.
    var sourceAccount: String?
    /// The service's website, e.g. "dazn.com": from the sender of the imported email, or found
    /// when looking for its pages. Helps find the cancellation page of services not in the catalog.
    var websiteDomain: String?
    /// The cancellation page found for a service not in the catalog, remembered so the next tap
    /// opens it straight away. Cleared when the name changes.
    var cancelURL: String?
    /// Identifies this subscription's Screen Time link (`UsageLinks`) once it's linked to an app.
    var usageKey: String?

    @Relationship(deleteRule: .cascade, inverse: \UsageEntry.subscription)
    var usageEntries: [UsageEntry]? = []

    init(
        name: String,
        price: Decimal = 0,
        cycle: BillingCycle = .monthly,
        category: SubscriptionCategory = .other,
        anchorDate: Date? = nil,
        reminderDaysBefore: Int = 1,
        tint: SubscriptionTint? = nil,
        planName: String? = nil,
        sourceAccount: String? = nil
    ) {
        self.name = name
        self.price = price
        self.cycleRaw = cycle.rawValue
        self.categoryRaw = category.rawValue
        self.anchorDate = anchorDate
        self.reminderDaysBefore = reminderDaysBefore
        self.createdAt = .now
        self.tintRaw = tint?.rawValue
        self.planName = planName
        self.sourceAccount = sourceAccount
    }

    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    var category: SubscriptionCategory {
        get { SubscriptionCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var tint: SubscriptionTint? {
        get { tintRaw.flatMap(SubscriptionTint.init(rawValue:)) }
        set { tintRaw = newValue?.rawValue }
    }

    /// The color shown everywhere for this subscription.
    var displayColor: Color { tint?.color ?? category.color }

    /// `displayColor` by name, for the widgets (`SharedColor`).
    var displayColorName: String { tint?.rawValue ?? category.colorName }

    /// Added from onboarding but still missing a price or a payment date.
    var needsSetup: Bool { price <= 0 || anchorDate == nil }

    var monthlyCost: Decimal { BillingMath.monthlyEquivalent(price: price, cycle: cycle) }

    func nextPayment(after reference: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let anchorDate else { return nil }
        return BillingMath.nextPayment(anchor: anchorDate, cycle: cycle, onOrAfter: reference, calendar: calendar)
    }

    /// Earliest date we show charges from: the month tracking began, or an earlier known payment.
    /// Before that we don't know whether the user was subscribed, so nothing is invented.
    func trackingStart(calendar: Calendar = .current) -> Date {
        let createdMonth = calendar.dateInterval(of: .month, for: createdAt)?.start ?? createdAt
        guard let anchorDate else { return createdMonth }
        return min(createdMonth, calendar.startOfDay(for: anchorDate))
    }
}

// MARK: - Weekly check-in answer

@Model
final class UsageEntry {
    /// Start of the week the answer refers to.
    var weekStart: Date = Date.now
    var used: Bool = false
    var subscription: Subscription?

    init(weekStart: Date, used: Bool, subscription: Subscription?) {
        self.weekStart = weekStart
        self.used = used
        self.subscription = subscription
    }
}
