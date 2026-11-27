//
//  DeadlineRulesTests.swift
//  MyDuesTests
//

import Foundation
import Testing
@testable import MyDues

@Suite("Return and warranty deadlines")
struct DeadlineRulesTests {
    private let calendar = TestCalendar.utc

    @Test("Amazon: 30 days from delivery")
    func amazonStandard() {
        let deadline = ReturnPolicy.returnBy(store: "Amazon", orderDate: date(2026, 3, 1), deliveryDate: date(2026, 3, 3), calendar: calendar)
        #expect(deadline.date == date(2026, 4, 2))
        #expect(!deadline.isEstimated)
    }

    @Test("Amazon: orders in November and December until 31 January")
    func amazonHoliday() {
        let deadline = ReturnPolicy.returnBy(store: "Amazon.it", orderDate: date(2026, 11, 20), deliveryDate: date(2026, 11, 22), calendar: calendar)
        #expect(deadline.date == date(2027, 1, 31))
    }

    @Test("Amazon: 30 days from a January delivery beat 31 January")
    func amazonHolidayLateDelivery() {
        let deadline = ReturnPolicy.returnBy(store: "amazon", orderDate: date(2026, 12, 28), deliveryDate: date(2027, 1, 5), calendar: calendar)
        #expect(deadline.date == date(2027, 2, 4))
    }

    @Test("Other stores: 14 days, the EU right of withdrawal")
    func otherStore() {
        let deadline = ReturnPolicy.returnBy(store: "Zalando", orderDate: date(2026, 3, 1), deliveryDate: date(2026, 3, 3), calendar: calendar)
        #expect(deadline.date == date(2026, 3, 17))
    }

    @Test("No delivery date: estimated a few days after the order")
    func estimatedDelivery() {
        let deadline = ReturnPolicy.returnBy(store: "Zalando", orderDate: date(2026, 3, 1), deliveryDate: nil, calendar: calendar)
        #expect(deadline.date == date(2026, 3, 18))
        #expect(deadline.isEstimated)
    }

    @Test("A date stated in the email wins")
    func statedDate() {
        let deadline = ReturnPolicy.returnBy(store: "Amazon", orderDate: date(2026, 3, 1), deliveryDate: date(2026, 3, 3),
                                             stated: date(2026, 4, 10), calendar: calendar)
        #expect(deadline.date == date(2026, 4, 10))
    }

    @Test("Legal warranty: 24 months from delivery, reminder from 50")
    func warranty() {
        #expect(WarrantyPolicy.until(orderDate: date(2026, 3, 1), deliveryDate: date(2026, 3, 3), calendar: calendar) == date(2028, 3, 3))
        #expect(WarrantyPolicy.until(orderDate: date(2026, 3, 1), deliveryDate: nil, calendar: calendar) == date(2028, 3, 1))
        #expect(WarrantyPolicy.remindsByDefault(price: 50))
        #expect(!WarrantyPolicy.remindsByDefault(price: Decimal(string: "49.99")!))
    }
}
