//
//  MonthScheduleTests.swift
//  DuelyProjectTests
//
//  November 2026, with "today" on Wed 18 Nov.
//

import Foundation
import Testing
@testable import DuelyProject

@MainActor
@Suite("MonthSchedule")
struct MonthScheduleTests {
    private let calendar = TestCalendar.utc
    private let today = date(2026, 11, 18, 12)
    private let store: TestStore

    init() throws {
        store = try TestStore()
    }

    private func november(_ subscriptions: [Subscription]) -> MonthSchedule {
        MonthSchedule(subscriptions: subscriptions,
                      month: CalendarMonth(containing: date(2026, 11, 1), calendar: calendar),
                      today: today, calendar: calendar)
    }

    @Test("Charges before today count as charged, the rest as still to come")
    func chargedAndUpcoming() {
        let schedule = november([
            store.subscription("Spotify", price: 11, anchor: date(2026, 11, 5)),
            store.subscription("Netflix", price: 15, anchor: date(2026, 11, 25)),
        ])
        #expect(schedule.paymentCount == 2)
        #expect(schedule.total == 26)
        #expect(schedule.chargedTotal == 11)
        #expect(schedule.upcomingTotal == 15)
    }

    @Test("A yearly renewal this month explains why it's higher than the average")
    func higherBecauseOfRenewals() {
        let netflix = store.subscription("Netflix", price: 15, anchor: date(2026, 11, 25))
        let linkedIn = store.subscription("LinkedIn", price: 240, cycle: .yearly, anchor: date(2026, 11, 20))
        let disney = store.subscription("Disney+", price: 90, cycle: .yearly, anchor: date(2026, 11, 27))
        let schedule = november([netflix, linkedIn, disney])

        // Average: 15 + 20 + 7.50 = 42.50; November charges 345.
        let average = netflix.monthlyCost + linkedIn.monthlyCost + disney.monthlyCost
        #expect(schedule.comparison(toMonthlyAverage: average) == .higher(renewals: ["LinkedIn", "Disney+"]))
    }

    @Test("A month without the yearly renewal is lower than the average")
    func lowerWhenRenewalIsElsewhere() {
        let netflix = store.subscription("Netflix", price: 15, anchor: date(2026, 11, 25))
        let linkedIn = store.subscription("LinkedIn", price: 240, cycle: .yearly, anchor: date(2027, 3, 20))
        let schedule = november([netflix, linkedIn])

        #expect(schedule.comparison(toMonthlyAverage: netflix.monthlyCost + linkedIn.monthlyCost) == .lower)
    }

    @Test("Only monthly plans: the month matches the average")
    func typicalWithMonthlyPlans() {
        let netflix = store.subscription("Netflix", price: 15, anchor: date(2026, 11, 25))
        let spotify = store.subscription("Spotify", price: 11, anchor: date(2026, 11, 5))
        let schedule = november([netflix, spotify])

        #expect(schedule.comparison(toMonthlyAverage: 26) == .typical)
    }

    @Test("Five weekly payments in a month are higher, with the weekly plan named")
    func higherBecauseOfWeeklyPayments() {
        // Mondays in November 2026: 2, 9, 16, 23, 30. Average: 10 × 52 / 12 ≈ 43.33.
        let gym = store.subscription("Gym", price: 10, cycle: .weekly, anchor: date(2026, 11, 2))
        let schedule = november([gym])

        #expect(schedule.total == 50)
        #expect(schedule.comparison(toMonthlyAverage: gym.monthlyCost) == .higher(renewals: ["Gym"]))   // +15.4 %
    }

    @Test("No average yet: nothing to compare with")
    func noAverage() {
        #expect(november([]).comparison(toMonthlyAverage: 0) == .typical)
    }
}
