//
//  BillingMathTests.swift
//  MyDuesTests
//

import Foundation
import Testing
@testable import MyDues

@MainActor
@Suite("BillingMath")
struct BillingMathTests {
    private let calendar = TestCalendar.utc

    // MARK: Equivalents

    @Test("Monthly equivalent spreads every cycle over 12 months", arguments: [
        (BillingCycle.weekly, Decimal(10), Decimal(520) / 12),
        (.monthly, 10, 10),
        (.quarterly, 30, 10),
        (.yearly, 120, 10),
    ])
    func monthlyEquivalent(cycle: BillingCycle, price: Decimal, expected: Decimal) {
        #expect(BillingMath.monthlyEquivalent(price: price, cycle: cycle) == expected)
    }

    @Test("Yearly equivalent multiplies by payments per year")
    func yearlyEquivalent() {
        #expect(BillingMath.yearlyEquivalent(price: 10, cycle: .weekly) == 520)
        #expect(BillingMath.yearlyEquivalent(price: 10, cycle: .monthly) == 120)
        #expect(BillingMath.yearlyEquivalent(price: 30, cycle: .quarterly) == 120)
        #expect(BillingMath.yearlyEquivalent(price: 99, cycle: .yearly) == 99)
    }

    // MARK: Next payment

    @Test("An anchor in the future is the next payment")
    func futureAnchor() {
        let next = BillingMath.nextPayment(anchor: date(2026, 12, 5, 15), cycle: .monthly,
                                           onOrAfter: date(2026, 11, 18), calendar: calendar)
        #expect(next == date(2026, 12, 5))
    }

    @Test("A payment due today counts as the next payment, whatever the time")
    func paymentToday() {
        let next = BillingMath.nextPayment(anchor: date(2026, 1, 18), cycle: .monthly,
                                           onOrAfter: date(2026, 11, 18, 23, 59), calendar: calendar)
        #expect(next == date(2026, 11, 18))
    }

    @Test("Billing on the 31st clamps in short months, then returns to the 31st", arguments: [
        (date(2027, 2, 1), date(2027, 2, 28)),    // February, non-leap year
        (date(2028, 2, 1), date(2028, 2, 29)),    // February, leap year
        (date(2027, 3, 1), date(2027, 3, 31)),    // Back to the 31st, not the 28th
        (date(2027, 4, 1), date(2027, 4, 30)),    // 30-day month
    ])
    func monthEndClamping(reference: Date, expected: Date) {
        let next = BillingMath.nextPayment(anchor: date(2027, 1, 31), cycle: .monthly,
                                           onOrAfter: reference, calendar: calendar)
        #expect(next == expected)
    }

    @Test("A yearly plan started on 29 February renews on 28 February in common years")
    func leapDayYearly() {
        let next = BillingMath.nextPayment(anchor: date(2028, 2, 29), cycle: .yearly,
                                           onOrAfter: date(2028, 3, 1), calendar: calendar)
        #expect(next == date(2029, 2, 28))
    }

    @Test("Quarterly plans step three months from the anchor")
    func quarterly() {
        let next = BillingMath.nextPayment(anchor: date(2026, 1, 15), cycle: .quarterly,
                                           onOrAfter: date(2026, 11, 18), calendar: calendar)
        #expect(next == date(2027, 1, 15))
    }

    @Test("Weekly plans land on the same weekday as the anchor")
    func weekly() {
        // 2 Nov 2026 is a Monday; 18 Nov is a Wednesday, so the next Monday is the 23rd.
        let next = BillingMath.nextPayment(anchor: date(2026, 11, 2), cycle: .weekly,
                                           onOrAfter: date(2026, 11, 18), calendar: calendar)
        #expect(next == date(2026, 11, 23))
    }

    // MARK: Occurrences

    @Test("Occurrences never drift after a short month")
    func occurrencesAcrossMonthEnds() {
        let dates = BillingMath.occurrences(anchor: date(2027, 1, 31), cycle: .monthly,
                                            from: date(2027, 1, 1), to: date(2027, 6, 1), calendar: calendar)
        #expect(dates == [
            date(2027, 1, 31), date(2027, 2, 28), date(2027, 3, 31), date(2027, 4, 30), date(2027, 5, 31),
        ])
    }

    @Test("The range is half-open: the start is included, the end is not")
    func occurrencesRangeBounds() {
        let dates = BillingMath.occurrences(anchor: date(2026, 1, 1), cycle: .monthly,
                                            from: date(2026, 3, 1), to: date(2026, 5, 1), calendar: calendar)
        #expect(dates == [date(2026, 3, 1), date(2026, 4, 1)])
    }

    @Test("A month holds four or five weekly payments")
    func weeklyOccurrencesInAMonth() {
        // Mondays in November 2026: 2, 9, 16, 23, 30.
        let november = BillingMath.occurrences(anchor: date(2026, 11, 2), cycle: .weekly,
                                               from: date(2026, 11, 1), to: date(2026, 12, 1), calendar: calendar)
        #expect(november.count == 5)

        // Mondays in February 2027: 1, 8, 15, 22.
        let february = BillingMath.occurrences(anchor: date(2026, 11, 2), cycle: .weekly,
                                               from: date(2027, 2, 1), to: date(2027, 3, 1), calendar: calendar)
        #expect(february.count == 4)
    }

    @Test("An empty or inverted range has no occurrences")
    func emptyRange() {
        let empty = BillingMath.occurrences(anchor: date(2026, 1, 1), cycle: .monthly,
                                            from: date(2026, 5, 1), to: date(2026, 5, 1), calendar: calendar)
        let inverted = BillingMath.occurrences(anchor: date(2026, 1, 1), cycle: .monthly,
                                               from: date(2026, 6, 1), to: date(2026, 5, 1), calendar: calendar)
        #expect(empty.isEmpty)
        #expect(inverted.isEmpty)
    }

    // MARK: Days between

    @Test("Days between counts calendar days, not 24-hour periods")
    func daysBetween() {
        #expect(BillingMath.daysBetween(date(2026, 11, 18, 23), date(2026, 11, 19, 1), calendar: calendar) == 1)
        #expect(BillingMath.daysBetween(date(2026, 11, 18, 1), date(2026, 11, 18, 23), calendar: calendar) == 0)
        #expect(BillingMath.daysBetween(date(2026, 12, 31), date(2027, 1, 7), calendar: calendar) == 7)
    }

    // MARK: Stored amounts

    @Test("Stored budgets always use a dot, whatever the user's locale")
    func storedAmountParsing() {
        #expect(BillingMath.storedAmount("1500.5") == Decimal(string: "1500.5"))
        #expect(BillingMath.storedAmount("1500,5") == 1500)   // A comma isn't a valid stored separator.
    }

    @Test("Empty, zero and negative budgets count as no budget", arguments: ["", "0", "-20", "abc"])
    func storedAmountRejects(input: String) {
        #expect(BillingMath.storedAmount(input) == nil)
    }

    @Test("Stored amounts survive a round trip without losing cents")
    func storedAmountRoundTrip() throws {
        let value = try #require(Decimal(string: "1234.56"))
        #expect(BillingMath.storedAmount(BillingMath.storedString(value)) == value)
    }
}
