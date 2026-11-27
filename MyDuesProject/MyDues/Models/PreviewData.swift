//
//  PreviewData.swift
//  MyDues
//
//  In-memory store with realistic data for SwiftUI previews only.
//

import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Subscription.self, UsageEntry.self, Purchase.self, PaymentNotice.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            insertSamples(into: container.mainContext)
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }()

    static let emptyContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Subscription.self, UsageEntry.self, Purchase.self, PaymentNotice.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }()

    private static func insertSamples(into context: ModelContext) {
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
        }
        // Built from strings: a Double literal like 13.99 is not exact in Decimal.
        func money(_ value: String) -> Decimal { Decimal(string: value) ?? 0 }

        let samples: [Subscription] = [
            Subscription(name: "Netflix", price: money("13.99"), category: .filmTV, anchorDate: day(1)),
            Subscription(name: "Spotify", price: money("10.99"), category: .music, anchorDate: day(4)),
            Subscription(name: "Disney+", price: money("89.99"), cycle: .yearly, category: .filmTV, anchorDate: day(9)),
            Subscription(name: "Discord Nitro", price: money("9.99"), category: .social, anchorDate: day(20)),
            Subscription(name: "LinkedIn Premium", price: money("239.99"), cycle: .yearly, category: .work, anchorDate: day(-40), tint: .blue),
            Subscription(name: "HBO Max", category: .filmTV),   // still needs setup
        ]
        for subscription in samples { context.insert(subscription) }

        let trial = Subscription(name: "Apple TV+", price: money("9.99"), category: .filmTV, anchorDate: day(5))
        trial.trialEndDate = day(5)
        context.insert(trial)

        // Deadlines tab.
        context.insert(Purchase(title: "AirPods Pro", store: "Amazon", orderNumber: "405-1234567-1234567",
                                orderDate: day(-26), deliveryDate: day(-24), price: money("249.00"),
                                websiteDomain: "amazon.it"))
        context.insert(Purchase(title: "Cavo USB-C", store: "Amazon", orderDate: day(-400), deliveryDate: day(-398),
                                price: money("9.99"), websiteDomain: "amazon.it"))
        if let code = PagoPACode(noticeNumber: "301000000000123456", fiscalCode: "80014890638") {
            context.insert(PaymentNotice(code: code, payee: "Comune di Napoli", amount: money("128.50"),
                                         dueDate: day(6), reason: "TARI 2026 – rata 1"))
        }

        // Two weeks of check-ins.
        for weekOffset in [-1, -2] {
            let week = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
            for (index, subscription) in samples.prefix(5).enumerated() {
                context.insert(UsageEntry(weekStart: week, used: index != 3, subscription: subscription))
            }
        }
    }
}
