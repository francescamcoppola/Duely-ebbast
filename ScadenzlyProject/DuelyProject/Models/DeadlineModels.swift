//
//  DeadlineModels.swift
//  DuelyProject
//
//  SwiftData models for the Deadlines tab: online orders (return window and warranty) and
//  pagoPA payment notices. Like `Subscription`, every stored property has a default, as CloudKit
//  requires: they sync to the user's private iCloud database too (see Persistence.swift).
//

import Foundation
import SwiftData

// MARK: - Purchase

@Model
final class Purchase {
    /// What was bought, short: "AirPods Pro", "Scarpe Nike Air Max".
    var title: String = ""
    var store: String = ""
    var orderNumber: String?
    var orderDate: Date = Date.now
    /// `nil` while it hasn't arrived and the email gave no expected date.
    var deliveryDate: Date?
    var price: Decimal = 0
    /// Last day it can be returned.
    var returnBy: Date?
    /// True when `returnBy` was worked out from a guessed delivery date.
    var returnByIsEstimated: Bool = false
    /// End of the legal warranty.
    var warrantyUntil: Date?
    var returnReminderEnabled: Bool = true
    var warrantyReminderEnabled: Bool = false
    /// Set when the user marks it as returned: no more return or warranty reminders.
    var returnedAt: Date?
    var sourceAccount: String?
    /// The store's website, e.g. "amazon.it", for its orders page.
    var websiteDomain: String?
    var createdAt: Date = Date.now

    init(
        title: String,
        store: String,
        orderNumber: String? = nil,
        orderDate: Date,
        deliveryDate: Date? = nil,
        price: Decimal = 0,
        statedReturnBy: Date? = nil,
        sourceAccount: String? = nil,
        websiteDomain: String? = nil,
        calendar: Calendar = .current
    ) {
        self.title = title
        self.store = store
        self.orderNumber = orderNumber
        self.orderDate = calendar.startOfDay(for: orderDate)
        self.deliveryDate = deliveryDate.map(calendar.startOfDay(for:))
        self.price = price
        self.sourceAccount = sourceAccount
        self.websiteDomain = websiteDomain
        self.createdAt = .now
        self.warrantyReminderEnabled = WarrantyPolicy.remindsByDefault(price: price)
        recomputeDeadlines(statedReturnBy: statedReturnBy, calendar: calendar)
    }

    /// Recomputes the return deadline and the warranty from the store and the dates. Call after
    /// editing the store, order or delivery date.
    func recomputeDeadlines(statedReturnBy: Date? = nil, calendar: Calendar = .current) {
        let deadline = ReturnPolicy.returnBy(store: store, orderDate: orderDate, deliveryDate: deliveryDate,
                                             stated: statedReturnBy, calendar: calendar)
        returnBy = deadline.date
        returnByIsEstimated = deadline.isEstimated
        warrantyUntil = WarrantyPolicy.until(orderDate: orderDate, deliveryDate: deliveryDate, calendar: calendar)
    }

    var isReturned: Bool { returnedAt != nil }

    /// Can still be returned today.
    func isReturnOpen(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isReturned, let returnBy else { return false }
        return calendar.startOfDay(for: returnBy) >= calendar.startOfDay(for: now)
    }

    /// Still covered by the warranty today.
    func isWarrantyActive(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isReturned, let warrantyUntil else { return false }
        return calendar.startOfDay(for: warrantyUntil) >= calendar.startOfDay(for: now)
    }

    var isAmazon: Bool { ReturnPolicy.isAmazon(store) || (websiteDomain.map(ReturnPolicy.isAmazon) ?? false) }

    /// Where returns start: Amazon's order history, or the store's website.
    var ordersPageURL: URL? {
        if isAmazon {
            let domain = websiteDomain.flatMap { ReturnPolicy.isAmazon($0) ? $0 : nil } ?? "amazon.it"
            return URL(string: "https://www.\(domain)/gp/css/order-history")
        }
        return websiteDomain.flatMap { URL(string: "https://\($0)") }
    }
}

// MARK: - pagoPA notice

@Model
final class PaymentNotice {
    /// Who asked for the payment: "Comune di Napoli", "Università di Bologna".
    var payee: String = ""
    /// The issuing body's 11-digit tax code.
    var payeeFiscalCode: String = ""
    /// 18 digits.
    var noticeNumber: String = ""
    var amount: Decimal = 0
    var dueDate: Date?
    /// What it's for: "TARI 2026 – rata 1".
    var reason: String = ""
    var paidAt: Date?
    /// 0 = only on the due day.
    var reminderDaysBefore: Int = 3
    var sourceAccount: String?
    var createdAt: Date = Date.now

    init(
        code: PagoPACode,
        payee: String,
        amount: Decimal,
        dueDate: Date? = nil,
        reason: String = "",
        sourceAccount: String? = nil,
        calendar: Calendar = .current
    ) {
        self.payee = payee
        self.payeeFiscalCode = code.fiscalCode
        self.noticeNumber = code.noticeNumber
        self.amount = amount
        self.dueDate = dueDate.map(calendar.startOfDay(for:))
        self.reason = reason
        self.sourceAccount = sourceAccount
        self.createdAt = .now
    }

    var isPaid: Bool { paidAt != nil }

    var code: PagoPACode? {
        PagoPACode(noticeNumber: noticeNumber, fiscalCode: payeeFiscalCode, amountCents: amount.cents)
    }

    /// Display name: the payee, or the reason when the payee is unknown.
    var displayName: String {
        let name = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? reason : name
    }

    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isPaid, let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}

// MARK: - Free trial

extension Subscription {
    /// True while a free trial is running: the first charge is on `trialEndDate`.
    func isInTrial(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let trialEndDate else { return false }
        return calendar.startOfDay(for: trialEndDate) >= calendar.startOfDay(for: now)
    }
}
