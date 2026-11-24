//
//  DetectedSubscription.swift
//  DuelyProject
//
//  A subscription found in an email, waiting for the user to confirm it. Also the pure rules
//  that turn model output into candidates: parsing, merging several emails about the same
//  service, and matching against subscriptions already in the app.
//

import Foundation

struct DetectedSubscription: Identifiable, Equatable {
    /// Normalized service name, so two emails from the same service become one candidate.
    var id: String { DetectedSubscription.matchKey(name) }

    var name: String
    /// `nil` when the email didn't state a price; the subscription is then added as "Needs Setup".
    var price: Decimal?
    /// ISO code as written in the email. Shown when it differs from the app's currency.
    var currencyCode: String?
    var cycle: BillingCycle
    /// False when the email didn't say how often it's charged (then `cycle` is monthly, the most common).
    var cycleIsKnown: Bool
    var category: SubscriptionCategory
    /// A known payment date: the next renewal if stated, else the charge date, else the email's date.
    var paymentDate: Date
    var emailSubject: String
    var emailDate: Date
    /// The connected account the email was found in.
    var sourceAccount: String? = nil

    func differsFromCurrency(_ code: String) -> Bool {
        guard let currencyCode else { return false }
        return currencyCode.caseInsensitiveCompare(code) != .orderedSame
    }
}

// MARK: - Building candidates

extension DetectedSubscription {
    init?(analysis: EmailSubscriptionAnalysis, email: EmailMessage, account: String? = nil, calendar: Calendar = .current) {
        let name = analysis.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard analysis.isRecurringSubscription, !name.isEmpty, name.count <= 60 else { return nil }

        self.name = name
        self.price = Self.price(from: analysis.price)
        let code = analysis.currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        self.currencyCode = code.count == 3 && code.allSatisfy(\.isLetter) ? code : nil
        self.cycle = BillingCycle(analysis.billingCycle)
        self.cycleIsKnown = analysis.billingCycle != .unknown
        self.category = SubscriptionCategory(analysis.category)
        self.paymentDate = Self.date(from: analysis.paymentDate, near: email.date, calendar: calendar)
            ?? calendar.startOfDay(for: email.date)
        self.emailSubject = email.subject
        self.emailDate = email.date
        self.sourceAccount = account
    }

    /// Positive, plausible amounts only, rounded to cents.
    static func price(from value: Double) -> Decimal? {
        guard value.isFinite, value > 0, value < 100_000 else { return nil }
        var decimal = Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 2, .plain)
        return rounded
    }

    /// Parses "yyyy-MM-dd". Dates more than two years away from the email are treated as mistakes.
    static func date(from string: String, near reference: Date, calendar: Calendar = .current) -> Date? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              calendar.component(.month, from: date) == parts[1],   // Rejects 2026-02-31.
              abs(date.timeIntervalSince(reference)) < 2 * 366 * 86_400 else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Lowercased, without accents, spaces, punctuation or trailing plan words, so
    /// "Spotify Premium", "spotify" and "SPOTIFY AB" all match, and so do "Disney+" and "Disney Plus".
    static func matchKey(_ name: String) -> String {
        var key = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        for suffix in [" premium", " plus", " subscription", " membership", " ab", " inc", " llc", " ltd", " gmbh", " s.r.l.", " srl", " s.l."] {
            if key.hasSuffix(suffix) { key = String(key.dropLast(suffix.count)) }
        }
        return key.filter { $0.isLetter || $0.isNumber }
    }

    /// One candidate per service. The most recent email wins, but a missing price or cycle is
    /// filled in from an older email about the same service.
    static func merged(_ candidates: [DetectedSubscription]) -> [DetectedSubscription] {
        var byKey: [String: DetectedSubscription] = [:]
        var order: [String] = []
        for candidate in candidates.sorted(by: { $0.emailDate > $1.emailDate }) {
            let key = candidate.id
            guard !key.isEmpty else { continue }
            guard var existing = byKey[key] else {
                byKey[key] = candidate
                order.append(key)
                continue
            }
            if existing.price == nil {
                existing.price = candidate.price
                existing.currencyCode = candidate.currencyCode
            }
            if !existing.cycleIsKnown, candidate.cycleIsKnown {
                existing.cycle = candidate.cycle
                existing.cycleIsKnown = true
            }
            if existing.category == .other { existing.category = candidate.category }
            byKey[key] = existing
        }
        return order.compactMap { byKey[$0] }
    }
}

// MARK: - Mapping model enums

extension BillingCycle {
    init(_ detected: DetectedCycle) {
        switch detected {
        case .weekly: self = .weekly
        case .monthly, .unknown: self = .monthly
        case .bimonthly: self = .bimonthly
        case .quarterly: self = .quarterly
        case .semiannual: self = .semiannual
        case .yearly: self = .yearly
        }
    }
}

extension SubscriptionCategory {
    init(_ detected: DetectedCategory) {
        switch detected {
        case .filmTV: self = .filmTV
        case .music: self = .music
        case .gaming: self = .leisure
        case .social: self = .social
        case .work: self = .work
        case .utilities: self = .utilities
        case .home: self = .home
        case .taxes: self = .taxes
        case .education: self = .education
        case .insurance: self = .insurance
        case .other: self = .other
        }
    }
}
