//
//  DetectedSubscription.swift
//  MyDues
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
    /// False when `paymentDate` fell back to `emailDate` because the email stated no date.
    var paymentDateIsKnown: Bool = true
    var emailSubject: String
    var emailDate: Date
    /// The connected account the email was found in.
    var sourceAccount: String? = nil
    /// The sender's website, e.g. "dazn.com" for "noreply@mail.dazn.com". `nil` for stores and
    /// mail providers, which aren't the service itself.
    var senderDomain: String? = nil
    /// Set for a free trial: the day it ends, which is also the first charge (`paymentDate`).
    var trialEndDate: Date? = nil

    func differsFromCurrency(_ code: String) -> Bool {
        guard let currencyCode else { return false }
        return currencyCode.caseInsensitiveCompare(code) != .orderedSame
    }

    /// True when this candidate refers to the same service as an existing subscription name in the app.
    func matches(serviceName existingName: String) -> Bool {
        Self.sameService(name, existingName)
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

        let parsedDate = Self.date(from: analysis.paymentDate, near: email.date, calendar: calendar)
        self.paymentDate = parsedDate ?? calendar.startOfDay(for: email.date)
        self.paymentDateIsKnown = parsedDate != nil

        // A trial's first charge is the day it ends.
        if let trialEnd = Self.date(from: analysis.trialEndDate, near: email.date, calendar: calendar),
           trialEnd >= calendar.startOfDay(for: .now) {
            self.trialEndDate = trialEnd
            self.paymentDate = trialEnd
            self.paymentDateIsKnown = true
        }

        self.emailSubject = email.subject
        self.emailDate = email.date
        self.sourceAccount = account
        self.senderDomain = Self.serviceDomain(fromSender: email.from)
    }

    /// Stores (Apple, Google, PayPal) and personal mail providers send emails about other
    /// services, so their domain says nothing about the service's website.
    static func serviceDomain(fromSender from: String) -> String? {
        let address = BillingEmailFilter.senderAddress(from)
        guard let at = address.lastIndex(of: "@") else { return nil }
        let root = PageLinks.rootDomain(String(address[address.index(after: at)...]))
        let notTheService = ["apple.com", "icloud.com", "me.com", "google.com", "gmail.com", "googlemail.com",
                             "paypal.com", "paypal.it", "outlook.com", "hotmail.com", "hotmail.it", "live.com",
                             "live.it", "yahoo.com", "yahoo.it", "libero.it", "virgilio.it", "tiscali.it",
                             "stripe.com", "pec.it"]
        guard root.contains("."), !notTheService.contains(root) else { return nil }
        return root
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
        var key = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let suffixes = [
            " premium", " plus", " subscription", " membership",
            " abbonamento", " mensile", " annuale", " italia",
            // Plan names: "Spotify Premium Family" is still Spotify.
            " family", " famiglia", " duo", " individual", " individuale", " student", " studenti",
            " studente", " standard", " basic", " base", " essential", " con pubblicita",
            " with ads", " monthly", " yearly", " annual", " plan", " piano", " free trial",
            " prova gratuita", " trial",
            " ab", " inc", " llc", " ltd", " gmbh", " s.r.l.", " srl", " s.l.", " s.p.a.", " spa"
        ]

        var removedSuffix = true
        while removedSuffix {
            removedSuffix = false
            for suffix in suffixes where key.hasSuffix(suffix) {
                key = String(key.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                removedSuffix = true
            }
        }

        return key.filter { $0.isLetter || $0.isNumber }
    }

    /// Brands that sell several different services: "Apple" alone mustn't swallow "Apple TV+".
    private static let umbrellaBrands: Set<String> = [
        "apple", "google", "amazon", "microsoft", "paypal", "adobe", "samsung", "sky", "tim",
    ]

    /// True when two names are the same service: same catalog entry (with its aliases, e.g.
    /// "Disney Plus" and "Disney+"), same key, or one is the other plus plan words
    /// ("Spotify" and "Spotify Premium Family", "NOW" and "NOW Entertainment").
    static func sameService(_ first: String, _ second: String, catalog: PlanCatalogStore = .shared) -> Bool {
        let a = matchKey(first)
        let b = matchKey(second)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if let one = catalog.service(matching: first), let other = catalog.service(matching: second) {
            return one.id == other.id
        }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        return short.count >= 4 && !umbrellaBrands.contains(short) && long.hasPrefix(short)
    }

    /// One candidate per service. The most recent email wins, but missing price, cycle,
    /// payment date or category are filled in from an older email about the same service.
    static func merged(_ candidates: [DetectedSubscription]) -> [DetectedSubscription] {
        var byKey: [String: DetectedSubscription] = [:]
        var order: [String] = []
        for candidate in candidates.sorted(by: { $0.emailDate > $1.emailDate }) {
            guard !candidate.id.isEmpty else { continue }
            // The group of an earlier candidate for the same service, if any.
            let key = order.first { sameService(byKey[$0]?.name ?? "", candidate.name) } ?? candidate.id
            guard var existing = byKey[key] else {
                byKey[key] = candidate
                order.append(key)
                continue
            }
            if existing.price == nil {
                existing.price = candidate.price
                existing.currencyCode = candidate.currencyCode
            } else if existing.currencyCode == nil {
                existing.currencyCode = candidate.currencyCode
            }
            if !existing.cycleIsKnown, candidate.cycleIsKnown {
                existing.cycle = candidate.cycle
                existing.cycleIsKnown = true
            }
            if !existing.paymentDateIsKnown, candidate.paymentDateIsKnown {
                existing.paymentDate = candidate.paymentDate
                existing.paymentDateIsKnown = true
            }
            if existing.category == .other { existing.category = candidate.category }
            if existing.sourceAccount == nil { existing.sourceAccount = candidate.sourceAccount }
            if existing.senderDomain == nil { existing.senderDomain = candidate.senderDomain }
            if existing.trialEndDate == nil, let trialEnd = candidate.trialEndDate, !existing.paymentDateIsKnown {
                existing.trialEndDate = trialEnd
                existing.paymentDate = trialEnd
                existing.paymentDateIsKnown = true
            }
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
