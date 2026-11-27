//
//  PlanCatalogTests.swift
//  DuelyProjectTests
//

import Foundation
import Testing
@testable import DuelyProject

@MainActor
@Suite("PlanCatalog")
struct PlanCatalogTests {
    private static func plan(_ id: String, _ cycle: BillingCycle, _ eur: String, eligibility: String? = nil) -> CatalogPlan {
        CatalogPlan(id: id, name: id.capitalized, cycle: cycle.rawValue, prices: ["EUR": eur], details: nil, eligibility: eligibility)
    }

    private let store = PlanCatalogStore(catalog: PlanCatalog(
        version: 1, updated: "2026-11-24", region: "IT", note: nil,
        services: [
            CatalogService(id: "netflix", name: "Netflix", aliases: nil, category: "filmTV", groups: ["video"], plans: [
                plan("ads", .monthly, "7.99"), plan("standard", .monthly, "14.99"), plan("premium", .monthly, "21.99"),
            ]),
            CatalogService(id: "disney-plus", name: "Disney+", aliases: ["Disney Plus"], category: "filmTV", groups: ["video"], plans: [
                plan("standard", .monthly, "10.99"), plan("yearly", .yearly, "109.90"),
            ]),
            CatalogService(id: "spotify", name: "Spotify", aliases: nil, category: "music", groups: ["music"], plans: [
                plan("student", .monthly, "6.49", eligibility: "students"), plan("individual", .monthly, "11.99"),
            ]),
            CatalogService(id: "apple-music", name: "Apple Music", aliases: nil, category: "music", groups: ["music"], plans: [
                plan("individual", .monthly, "10.99"),
            ]),
        ]
    ))

    @Test("Names match with plan words, punctuation and aliases", arguments: [
        ("Netflix", "netflix"), ("netflix premium", "netflix"), ("Disney Plus", "disney-plus"),
        ("DISNEY+", "disney-plus"), ("Spotify Premium Family", "spotify"),
    ])
    func matching(name: String, expected: String) {
        #expect(store.service(matching: name)?.id == expected)
    }

    @Test("Unknown names don't match")
    func noMatch() {
        #expect(store.service(matching: "TARI Comune di Napoli") == nil)
        #expect(store.service(matching: "") == nil)
    }

    @Test("Suggestions put prefix matches first")
    func suggestions() {
        #expect(store.suggestions(for: "net").map(\.id) == ["netflix"])
        #expect(store.suggestions(for: "music").map(\.id) == ["apple-music"])
    }

    @Test("Plans are priced in the app's currency, cheapest first")
    func pricedPlans() {
        let netflix = store.service(matching: "Netflix")!
        #expect(netflix.plans(in: "EUR").map(\.plan.id) == ["ads", "standard", "premium"])
        #expect(netflix.plans(in: "USD").isEmpty)
    }

    @Test("Alternatives: cheaper plans of the same service and similar services, biggest saving first")
    func alternatives() {
        let result = store.alternatives(forName: "Netflix", monthlyCost: 21.99, currencyCode: "EUR")
        #expect(result.map(\.option.id) == ["netflix/ads", "disney-plus/yearly", "netflix/standard"])
        #expect(result.first?.monthlySaving == Decimal(string: "14"))
        #expect(result.first?.isSameService == true)
    }

    @Test("Services the user already has and student plans aren't suggested")
    func exclusions() {
        let video = store.alternatives(forName: "Netflix", monthlyCost: 21.99, currencyCode: "EUR", excludingNames: ["Disney+"])
        #expect(!video.contains { $0.option.service.id == "disney-plus" })

        let music = store.alternatives(forName: "Spotify", monthlyCost: 11.99, currencyCode: "EUR")
        #expect(music.map(\.option.id) == ["apple-music/individual"])
    }

    @Test("Nothing is suggested when already on the cheapest option")
    func cheapest() {
        #expect(store.alternatives(forName: "Netflix", monthlyCost: 7.99, currencyCode: "EUR").isEmpty)
    }

    @Test("New billing cycles spread over 12 months")
    func newCycles() {
        #expect(BillingMath.monthlyEquivalent(price: 60, cycle: .bimonthly) == 30)
        #expect(BillingMath.monthlyEquivalent(price: 60, cycle: .semiannual) == 10)
    }
}
