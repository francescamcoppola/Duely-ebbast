//
//  DeadlineRules.swift
//  DuelyProject
//
//  The rules behind the Deadlines tab: when an order can no longer be returned, when its legal
//  warranty ends, and how a pagoPA notice is identified (from its QR code or its printed codes).
//  Pure functions, no I/O: unit-tested in DeadlineRulesTests and PagoPACodeTests.
//

import Foundation

// MARK: - Returns

nonisolated enum ReturnPolicy {
    /// Amazon's standard return window, from delivery.
    static let amazonDays = 30
    /// The EU right of withdrawal for anything bought online, from delivery.
    static let defaultDays = 14
    /// Assumed delivery time when the email doesn't say when the order arrives.
    static let estimatedDeliveryDays = 3

    struct Deadline: Equatable, Sendable {
        let date: Date
        /// True when the delivery date was guessed, so the deadline is approximate.
        let isEstimated: Bool
    }

    static func isAmazon(_ store: String) -> Bool {
        store.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains("amazon")
    }

    /// The last day the order can be returned. A date stated in the email always wins.
    static func returnBy(
        store: String,
        orderDate: Date,
        deliveryDate: Date?,
        stated: Date? = nil,
        calendar: Calendar = .current
    ) -> Deadline {
        if let stated {
            return Deadline(date: calendar.startOfDay(for: stated), isEstimated: false)
        }
        let orderDay = calendar.startOfDay(for: orderDate)
        let delivered = deliveryDate.map(calendar.startOfDay(for:))
            ?? calendar.date(byAdding: .day, value: estimatedDeliveryDays, to: orderDay) ?? orderDay
        let amazon = isAmazon(store)
        var deadline = calendar.date(byAdding: .day, value: amazon ? amazonDays : defaultDays, to: delivered) ?? delivered
        if amazon, let holiday = amazonHolidayDeadline(orderDate: orderDay, calendar: calendar), holiday > deadline {
            deadline = holiday
        }
        return Deadline(date: deadline, isEstimated: deliveryDate == nil)
    }

    /// Amazon's holiday returns: items ordered from 1 November to 31 December can be returned
    /// until 31 January.
    static func amazonHolidayDeadline(orderDate: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: orderDate)
        guard let year = components.year, let month = components.month, month >= 11 else { return nil }
        return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 31))
    }
}

// MARK: - Warranty

nonisolated enum WarrantyPolicy {
    /// The legal guarantee on goods in the EU (garanzia legale, Codice del Consumo).
    static let legalMonths = 24
    /// Purchases from this price up get a warranty reminder unless the user turns it off, so
    /// cables and small things don't send notifications two years later.
    static let reminderThreshold: Decimal = 50

    static func until(orderDate: Date, deliveryDate: Date?, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: deliveryDate ?? orderDate)
        return calendar.date(byAdding: .month, value: legalMonths, to: start) ?? start
    }

    static func remindsByDefault(price: Decimal) -> Bool {
        price >= reminderThreshold
    }
}

// MARK: - pagoPA

/// What identifies a pagoPA payment notice: its 18-digit notice code and the 11-digit tax code
/// of the body that issued it. Enough to pay it at checkout.pagopa.it, in IO or at a bank.
nonisolated struct PagoPACode: Equatable, Hashable, Sendable {
    let noticeNumber: String
    let fiscalCode: String
    /// From the QR code, in euro cents.
    var amountCents: Int?

    init?(noticeNumber: String, fiscalCode: String, amountCents: Int? = nil) {
        let notice = noticeNumber.filter(\.isNumber)
        let fiscal = fiscalCode.filter(\.isNumber)
        guard notice.count == 18, fiscal.count == 11,
              notice.allSatisfy(\.isASCII), fiscal.allSatisfy(\.isASCII) else { return nil }
        self.noticeNumber = notice
        self.fiscalCode = fiscal
        self.amountCents = amountCents.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The notice page on pagoPA's own checkout, with both codes already filled in
    /// (`/<tax code><notice code>`, 29 digits).
    var checkoutURL: URL {
        URL(string: "https://checkout.pagopa.it/\(fiscalCode)\(noticeNumber)")!
    }

    /// The string a notice's QR code holds: `PAGOPA|002|<notice code>|<tax code>|<cents>`.
    func qrPayload(amountCents cents: Int? = nil) -> String {
        "PAGOPA|002|\(noticeNumber)|\(fiscalCode)|\(cents ?? amountCents ?? 0)"
    }

    /// "301234567890123456" → "3012 3456 7890 1234 56", as printed on notices.
    var groupedNoticeNumber: String {
        stride(from: 0, to: noticeNumber.count, by: 4).map { offset in
            let start = noticeNumber.index(noticeNumber.startIndex, offsetBy: offset)
            let end = noticeNumber.index(start, offsetBy: 4, limitedBy: noticeNumber.endIndex) ?? noticeNumber.endIndex
            return String(noticeNumber[start..<end])
        }
        .joined(separator: " ")
    }

    // MARK: Parsing

    /// Reads a notice's QR code. Only the pagoPA format, version 002.
    static func parse(qrPayload payload: String) -> PagoPACode? {
        let parts = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 5, parts[0].uppercased() == "PAGOPA", parts[1] == "002" else { return nil }
        return PagoPACode(noticeNumber: parts[2], fiscalCode: parts[3], amountCents: Int(parts[4]))
    }

    /// Finds the codes in a notice's text (the PDF, or the email itself): the QR string if it's
    /// written out, otherwise the 18 digits after "Codice avviso" and the 11 after
    /// "Codice fiscale ente". Digits may be grouped with spaces, as notices print them.
    static func parse(text: String) -> PagoPACode? {
        if let range = text.range(of: #"PAGOPA\|002\|[0-9 ]+\|[0-9 ]+\|[0-9]*"#, options: [.regularExpression, .caseInsensitive]),
           let code = parse(qrPayload: String(text[range])) {
            return code
        }
        let notice = firstMatch(in: text, label: noticeLabels, digits: 18)
        let fiscal = firstMatch(in: text, label: fiscalLabels, digits: 11)
        guard let notice, let fiscal else { return nil }
        return PagoPACode(noticeNumber: notice, fiscalCode: fiscal)
    }

    private static let noticeLabels =
        #"codice\s+(?:di\s+)?avviso|cod\.?\s*avviso|numero\s+(?:di\s+)?avviso|notice\s+(?:code|number)|c[oó]digo\s+de\s+aviso"#
    private static let fiscalLabels =
        #"codice\s+fiscale\s+(?:dell['’]\s*)?ente(?:\s+creditore)?|c\.?\s*f\.?\s+(?:dell['’]\s*)?ente(?:\s+creditore)?|cf\s+ente|ente\s+creditore\s*[-–:]?\s*(?:c\.?\s*f\.?|codice\s+fiscale)|creditor(?:'s)?\s+(?:entity\s+)?(?:tax|fiscal)\s+code"#

    /// The first `digits`-long number (spaces allowed between digits) within a short distance
    /// after one of the labels.
    private static func firstMatch(in text: String, label: String, digits: Int) -> String? {
        let pattern = "(?i)(?:\(label))[^0-9]{0,40}((?:[0-9][ \\u00A0]?){\(digits - 1)}[0-9])(?![0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let found = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[found].filter(\.isNumber)
        return value.count == digits ? String(value) : nil
    }
}

extension Decimal {
    /// Euro cents, rounded: 12.345 → 1235.
    nonisolated var cents: Int {
        var value = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    nonisolated init(cents: Int) {
        self = Decimal(cents) / 100
    }
}
