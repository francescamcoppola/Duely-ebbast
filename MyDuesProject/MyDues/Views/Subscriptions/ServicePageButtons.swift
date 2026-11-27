//
//  ServicePageButtons.swift
//  MyDues
//
//  "Cancel Subscription" and "See Plans" buttons. They open the service's own page, found by
//  `ServicePageFinder`, and show progress while it's looked for. A cancellation page found for a
//  service outside the catalog is remembered on the subscription (and synced with iCloud).
//

import SwiftUI
import SwiftData

struct CancelSubscriptionButton: View {
    let subscription: Subscription

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var catalog = PlanCatalogStore.shared
    @State private var isFinding = false
    @State private var fallback: ServicePageFinder.Result?

    var body: some View {
        Button(role: .destructive) {
            Task { await open() }
        } label: {
            HStack {
                Label(isFinding ? "Finding the Cancellation Page…" : "Cancel Subscription", systemImage: "xmark.circle")
                Spacer()
                if isFinding { ProgressView() }
            }
        }
        .disabled(isFinding)
        .contextMenu {
            if subscription.cancelURL != nil {
                Button("Find the Page Again", systemImage: "arrow.clockwise") {
                    subscription.cancelURL = nil
                    try? context.save()
                    Task { await open() }
                }
            }
        }
        .alert(
            Text("Couldn't Find the Cancellation Page"),
            isPresented: Binding(get: { fallback != nil }, set: { if !$0 { fallback = nil } }),
            presenting: fallback
        ) { result in
            if let url = result.url {
                Button("Open \(url.host() ?? "Website")") { openURL(url) }
            }
            Button("App Store Subscriptions") { openURL(ServiceLinks.appleSubscriptions) }
            Button("Cancel", role: .cancel) {}
        } message: { result in
            if result.url != nil {
                Text("\(subscription.name)'s website doesn't link to it directly. Sign in there and look for your account or subscription settings. If you subscribed through the App Store, cancel it from App Store Subscriptions.")
            } else {
                Text("\(subscription.name)'s website couldn't be found. If you subscribed through the App Store, cancel it from App Store Subscriptions.")
            }
        }
    }

    private func open() async {
        let service = catalog.service(matching: subscription.name)
        // Catalog links are always read fresh, so catalog updates apply.
        if service == nil, let saved = subscription.cancelURL.flatMap(URL.init(string:)) {
            openURL(saved)
            return
        }

        isFinding = true
        let found = await ServicePageFinder.find(.cancel, name: subscription.name, service: service,
                                                 knownDomain: subscription.websiteDomain)
        isFinding = false
        guard !subscription.isDeleted else { return }

        if service == nil, subscription.websiteDomain == nil { subscription.websiteDomain = found.domain }
        switch found.result {
        case .page(let url), .nearby(let url):
            if service == nil { subscription.cancelURL = url.absoluteString }
            try? context.save()
            // In Safari (or the Apple Account), where the user is signed in to the service.
            openURL(url)
        case .website, .notFound:
            try? context.save()
            fallback = found.result
        }
    }
}

/// Finds the plans page of a service outside the catalog and hands it to `onFound`.
struct FindPlansButton: View {
    let name: String
    var knownDomain: String? = nil
    let onFound: (URL) -> Void

    @State private var catalog = PlanCatalogStore.shared
    @State private var isFinding = false
    @State private var notFound = false

    var body: some View {
        Button {
            Task { await find() }
        } label: {
            HStack {
                Label(isFinding ? "Looking for \(name)'s Website…" : "Find \(name)'s Plans and Prices",
                      systemImage: "safari")
                Spacer()
                if isFinding { ProgressView() }
            }
        }
        .disabled(isFinding)
        .alert("Couldn't Find \(name)'s Website", isPresented: $notFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check the name, or enter the price and billing cycle yourself.")
        }
    }

    private func find() async {
        isFinding = true
        let found = await ServicePageFinder.find(.plans, name: name, service: catalog.service(matching: name),
                                                 knownDomain: knownDomain)
        isFinding = false
        if let url = found.result.url {
            onFound(url)
        } else {
            notFound = true
        }
    }
}
