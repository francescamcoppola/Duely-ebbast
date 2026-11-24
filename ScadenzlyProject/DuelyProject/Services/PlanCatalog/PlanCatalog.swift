//
//  PlanCatalog.swift
//  DuelyProject
//
//  A catalog of popular services and their plans (name, price, billing cycle). It powers:
//  • plan suggestions when a subscription is added by hand (pick "Netflix › Premium" and the
//    price and cycle fill themselves in);
//  • cheaper alternatives: cheaper plans of the same service, or similar services that cost less.
//
//  There's no public API with up-to-date subscription prices, so the catalog is a JSON file:
//  a copy ships in the app (Resources/PlanCatalog.json) and, if `PlanCatalogConfiguration.remoteURL`
//  is set, a newer copy is downloaded from there, so prices can be updated without a release.
//

import Foundation
import Observation

// MARK: - Data

nonisolated struct PlanCatalog: Codable, Sendable {
    var version: Int
    /// "yyyy-MM-dd". The newest of the bundled, cached and downloaded copies wins.
    var updated: String
    /// Market the prices refer to, e.g. "IT".
    var region: String?
    var note: String?
    var services: [CatalogService]

    static let empty = PlanCatalog(version: 0, updated: "", region: nil, note: nil, services: [])
}

nonisolated struct CatalogService: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var aliases: [String]?
    /// A `SubscriptionCategory` raw value.
    var category: String
    /// Services that share a group offer the same kind of thing ("video", "music", "cloud-storage"…)
    /// and are suggested as alternatives to each other.
    var groups: [String]
    var plans: [CatalogPlan]
}

nonisolated struct CatalogPlan: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// A `BillingCycle` raw value.
    var cycle: String
    /// Price per billing period by ISO currency code, as a decimal string ("13.99") so no
    /// precision is lost.
    var prices: [String: String]
    /// Short summary: quality, screens, people…
    var details: String?
    /// Who can get it, when not everyone can ("students"). Such plans are offered in the editor
    /// but never suggested as a cheaper alternative.
    var eligibility: String?
}

extension CatalogService {
    var subscriptionCategory: SubscriptionCategory {
        SubscriptionCategory(rawValue: category) ?? .other
    }

    /// Plans with a price in `currencyCode`, cheapest per month first.
    func plans(in currencyCode: String) -> [PricedPlan] {
        plans.compactMap { PricedPlan(service: self, plan: $0, currencyCode: currencyCode) }
            .sorted { $0.monthlyCost < $1.monthlyCost }
    }
}

/// A plan with its price resolved in the app's currency.
struct PricedPlan: Identifiable, Hashable {
    let service: CatalogService
    let plan: CatalogPlan
    let price: Decimal
    let cycle: BillingCycle

    var id: String { service.id + "/" + plan.id }
    var monthlyCost: Decimal { BillingMath.monthlyEquivalent(price: price, cycle: cycle) }

    init?(service: CatalogService, plan: CatalogPlan, currencyCode: String) {
        let match = plan.prices.first { $0.key.caseInsensitiveCompare(currencyCode) == .orderedSame }
        guard let text = match?.value,
              let price = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              price > 0 else { return nil }
        self.service = service
        self.plan = plan
        self.price = price
        self.cycle = BillingCycle(rawValue: plan.cycle) ?? .monthly
    }
}

/// A cheaper option than what the user pays now.
struct PlanAlternative: Identifiable, Hashable {
    let option: PricedPlan
    /// What the user would save per month by switching.
    let monthlySaving: Decimal
    /// A cheaper plan of the service the user already has, rather than another service.
    let isSameService: Bool

    var id: String { option.id }
}

// MARK: - Configuration

enum PlanCatalogConfiguration {
    /// Where an up-to-date copy of PlanCatalog.json is published, for example a public GitHub
    /// repository's raw URL or a GitHub Gist. `nil` uses only the copy bundled with the app.
    /// The file is fetched with a plain GET: no account, no identifiers, nothing about the user.
    static let remoteURL: URL? = nil

    /// How often the remote copy is checked.
    static let refreshInterval: TimeInterval = 24 * 60 * 60
}

// MARK: - Store

@MainActor
@Observable
final class PlanCatalogStore {
    static let shared = PlanCatalogStore()

    private(set) var catalog: PlanCatalog
    @ObservationIgnored private var byKey: [String: CatalogService] = [:]

    private static let lastFetchKey = "planCatalogLastFetch"

    init(catalog: PlanCatalog? = nil) {
        if let catalog {
            self.catalog = catalog
        } else {
            let candidates = [Self.load(from: Self.cacheURL), Self.load(from: Self.bundledURL)].compactMap { $0 }
            self.catalog = candidates.max { $0.updated < $1.updated } ?? .empty
        }
        rebuildIndex()
    }

    // MARK: Lookup

    /// The catalog entry for a subscription's name: "Netflix", "netflix premium", "Disney Plus"…
    func service(matching name: String) -> CatalogService? {
        let key = DetectedSubscription.matchKey(name)
        guard !key.isEmpty else { return nil }
        if let exact = byKey[key] { return exact }
        // "Spotify Premium Family" → Spotify. Longest known name wins, so "Amazon Music…"
        // isn't taken for "Amazon".
        return byKey
            .filter { $0.key.count >= 4 && key.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    /// Services whose name starts with or contains what was typed, for the editor's suggestions.
    func suggestions(for query: String, limit: Int = 5) -> [CatalogService] {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return [] }
        var prefix: [CatalogService] = []
        var contains: [CatalogService] = []
        for service in catalog.services {
            let names = [service.name] + (service.aliases ?? [])
            let foldedNames = names.map(Self.fold)
            if foldedNames.contains(where: { $0.hasPrefix(folded) }) {
                prefix.append(service)
            } else if foldedNames.contains(where: { $0.contains(folded) }) {
                contains.append(service)
            }
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// Cheaper ways to get the same thing, best saving first: cheaper plans of the same service,
    /// then the cheapest plan of each similar service. Services in `excludedNames` (ones the user
    /// already pays for) aren't suggested.
    func alternatives(
        forName name: String,
        monthlyCost: Decimal,
        currencyCode: String,
        excludingNames excludedNames: [String] = [],
        limit: Int = 4
    ) -> [PlanAlternative] {
        guard monthlyCost > 0, let current = service(matching: name) else { return [] }
        let minimumSaving: Decimal = 0.5

        func alternative(_ option: PricedPlan, sameService: Bool) -> PlanAlternative? {
            let saving = monthlyCost - option.monthlyCost
            guard saving >= minimumSaving else { return nil }
            return PlanAlternative(option: option, monthlySaving: saving, isSameService: sameService)
        }

        let samePlans = current.plans(in: currencyCode)
            .filter { $0.plan.eligibility == nil }
            .compactMap { alternative($0, sameService: true) }

        let owned = Set(excludedNames.compactMap { service(matching: $0)?.id })
        let groups = Set(current.groups)
        let peers = catalog.services
            .filter { $0.id != current.id && !owned.contains($0.id) && !groups.isDisjoint(with: $0.groups) }
            .compactMap { $0.plans(in: currencyCode).first { $0.plan.eligibility == nil } }
            .compactMap { alternative($0, sameService: false) }

        let sorted = (samePlans + peers).sorted { $0.monthlySaving > $1.monthlySaving }
        return Array(sorted.prefix(limit))
    }

    // MARK: Remote updates

    /// Downloads the hosted catalog at most once a day and keeps it if it's newer.
    func refreshIfNeeded(force: Bool = false) async {
        guard let url = PlanCatalogConfiguration.remoteURL else { return }
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: Self.lastFetchKey) as? Date,
           Date.now.timeIntervalSince(last) < PlanCatalogConfiguration.refreshInterval {
            return
        }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let downloaded = try JSONDecoder().decode(PlanCatalog.self, from: data)
            defaults.set(Date.now, forKey: Self.lastFetchKey)
            guard !downloaded.services.isEmpty, downloaded.updated >= catalog.updated else { return }
            try data.write(to: Self.cacheURL, options: .atomic)
            catalog = downloaded
            rebuildIndex()
        } catch {
            // Offline or a bad file: keep what we have.
        }
    }

    // MARK: Private

    private func rebuildIndex() {
        var index: [String: CatalogService] = [:]
        for service in catalog.services {
            for name in [service.name] + (service.aliases ?? []) {
                let key = DetectedSubscription.matchKey(name)
                if !key.isEmpty, index[key] == nil { index[key] = service }
            }
        }
        byKey = index
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static var bundledURL: URL? {
        Bundle.main.url(forResource: "PlanCatalog", withExtension: "json")
    }

    private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "PlanCatalog.json")
    }

    private static func load(from url: URL?) -> PlanCatalog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlanCatalog.self, from: data)
    }
}
