//
//  StarterSeeder.swift
//  DuelyProject
//
//  Turns the services picked in onboarding into real (not yet configured) subscriptions.
//

import Foundation
import SwiftData

enum StarterSeeder {
    /// Inserts one unconfigured subscription per picked service, in the order they were picked.
    @MainActor
    static func insert(serviceIDs: [String], into context: ModelContext) {
        guard !serviceIDs.isEmpty else { return }

        var lookup: [String: (StarterService, SubscriptionCategory)] = [:]
        for category in StarterCatalog.categories {
            for service in category.services {
                lookup[service.id] = (service, SubscriptionCategory(starterCategoryID: category.id))
            }
        }

        for id in serviceIDs {
            guard let entry = lookup[id] else { continue }
            context.insert(Subscription(name: entry.0.name, category: entry.1))
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Seeding failed: \(error)")
        }
    }
}
