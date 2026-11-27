//
//  ServiceLinks.swift
//  MyDues
//
//  Fixed links shared by the plans and cancellation features. Finding a service's own pages
//  is done by `ServicePageFinder`; no search engine is ever used.
//

import Foundation

nonisolated enum ServiceLinks {
    /// Every subscription billed through the App Store or Apple, in the user's Apple Account.
    static let appleSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// True when cancelling happens in the user's Apple Account rather than on a website.
    static func isBilledByApple(_ service: CatalogService?) -> Bool {
        service?.billedByApple == true
    }
}

/// A URL that can drive `.sheet(item:)`.
struct WebPage: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}
