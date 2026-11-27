//
//  ProfileInsightsTests.swift
//  MyDuesTests
//
//  "Now" is Wed 18 Nov 2026; the last three check-in weeks start on 26 Oct, 2 Nov and 9 Nov.
//

import Foundation
import Testing
@testable import MyDues

@MainActor
@Suite("ProfileInsights")
struct ProfileInsightsTests {
    private let calendar = TestCalendar.utc
    private let now = date(2026, 11, 18, 12)
    private let weeks = [date(2026, 10, 26), date(2026, 11, 2), date(2026, 11, 9)]
    private let store: TestStore

    init() throws {
        store = try TestStore()
    }

    private func answers(_ used: Bool...) -> [(week: Date, used: Bool)] {
        zip(weeks, used).map { (week: $0, used: $1) }
    }

    private func insights(_ subscriptions: [Subscription], budget: Decimal?) -> ProfileInsights {
        ProfileInsights(subscriptions: subscriptions, budget: budget, now: now, calendar: calendar)
    }

    /// Netflix used every week, Spotify once, Disney+ and LinkedIn never: 4 of 12 answers used (33 %).
    private func collectorSubscriptions() -> [Subscription] {
        [
            store.subscription("Netflix", price: 15, answers: answers(true, true, true)),
            store.subscription("Disney+", price: 10, answers: answers(false, false, false)),
            store.subscription("LinkedIn", price: 30, answers: answers(false, false, false)),
            store.subscription("Spotify", price: 11, answers: answers(true, false, false)),
        ]
    }

    // MARK: Signals

    @Test("Without subscriptions, the profile is Getting Started")
    func empty() {
        let result = insights([], budget: 100)
        #expect(result.profile == .newcomer)
        #expect(result.usageRate == nil)
        #expect(result.suggestion == nil)
    }

    @Test("Subscriptions without a price don't count toward the total or the profile")
    func ignoresUnconfigured() {
        let result = insights([
            store.subscription("Netflix", price: 15),
            store.subscription("HBO Max", price: 0),
        ], budget: 100)
        #expect(result.subscriptionCount == 1)
        #expect(result.monthlyTotal == 15)
    }

    @Test("Only the last four weeks of check-ins count")
    func lookbackWindow() {
        let old = date(2026, 9, 28)   // Seven weeks ago.
        let netflix = store.subscription("Netflix", price: 15,
                                         answers: [(old, false)] + answers(true, true))
        let result = insights([netflix], budget: 100)

        #expect(result.checkInWeeks == 2)
        #expect(result.usageRate == 1)
    }

    @Test("Usage needs two check-in weeks before it affects the profile")
    func needsTwoWeeks() {
        let netflix = store.subscription("Netflix", price: 15, answers: answers(true))
        #expect(insights([netflix], budget: 100).hasEnoughCheckIns == false)
    }

    @Test("Budget ratio compares the monthly total with the budget")
    func budgetRatio() {
        let result = insights([store.subscription("Netflix", price: 30)], budget: 120)
        #expect(result.budgetRatio == 0.25)
        #expect(insights([], budget: nil).budgetRatio == nil)
    }

    // MARK: Ranking

    @Test("Least used first; among equally unused, the most expensive first")
    func rankingOrder() {
        let result = insights(collectorSubscriptions(), budget: 100)
        #expect(result.usage.map(\.subscription.name) == ["LinkedIn", "Disney+", "Spotify", "Netflix"])
    }

    @Test("Cost per week used spreads the weekly cost over the weeks actually used")
    func costPerUsedWeek() throws {
        // 52 a year = 1 a week; used 1 of 3 weeks → 3 per week used.
        let magazine = store.subscription("Magazine", price: 52, cycle: .yearly, answers: answers(true, false, false))
        let usage = try #require(insights([magazine], budget: nil).usage.first)
        #expect(usage.costPerUsedWeek == 3)
    }

    @Test("A subscription never used has no cost per week used")
    func neverUsed() throws {
        let unused = store.subscription("Gym", price: 40, answers: answers(false, false))
        let usage = try #require(insights([unused], budget: nil).usage.first)
        #expect(usage.costPerUsedWeek == nil)
    }

    // MARK: Suggestion

    @Test("A collector is shown which cancellation would make them a saver")
    func collectorSuggestion() throws {
        let result = insights(collectorSubscriptions(), budget: 100)
        #expect(result.profile == .collector)

        let suggestion = try #require(result.suggestion)
        #expect(suggestion.cancel.map(\.name) == ["LinkedIn"])
        #expect(suggestion.monthlySavings == 30)
        #expect(suggestion.newProfile == .saver)
    }

    @Test("Someone over budget is shown which cancellation brings them back under")
    func overBudgetSuggestion() throws {
        let result = insights(collectorSubscriptions(), budget: 60)
        #expect(result.profile == .overBudget)

        let suggestion = try #require(result.suggestion)
        #expect(suggestion.cancel.map(\.name) == ["LinkedIn"])
        #expect(suggestion.newProfile != .overBudget)
    }

    @Test("No suggestion without check-ins: cancelling would be a guess")
    func noSuggestionWithoutUsage() {
        let result = insights([
            store.subscription("Netflix", price: 50),
            store.subscription("LinkedIn", price: 50),
        ], budget: 60)
        #expect(result.profile == .overBudget)
        #expect(result.suggestion == nil)
    }

    @Test("No suggestion when the profile is already healthy")
    func noSuggestionWhenHealthy() {
        let result = insights([
            store.subscription("Netflix", price: 15, answers: answers(true, true, true)),
            store.subscription("Spotify", price: 11, answers: answers(true, true, true)),
        ], budget: 100)
        #expect(result.profile == .optimizer)
        #expect(result.suggestion == nil)
    }
}
