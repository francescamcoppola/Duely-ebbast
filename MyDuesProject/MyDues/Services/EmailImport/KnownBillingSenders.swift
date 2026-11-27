//
//  KnownBillingSenders.swift
//  MyDues
//
//  Services that are paid mostly by subscription or recurring pass, whose receipts don't always
//  use billing words a search can find ("Conferma acquisto", "Welcome to Claude Pro", a Stripe
//  receipt with only the plan name). Every email they send that isn't an ad is searched for and
//  read; the model then keeps only recurring payments (a monthly pass, not a single ticket).
//  Matched on the sender's domain, so "noreply@mail.anthropic.com" is Anthropic.
//

import Foundation

nonisolated enum KnownBillingSenders {
    /// Root domains, lowercased. Add a service here when its receipts aren't found by the search.
    /// Not services that send many notifications or newsletters (GitHub, LinkedIn, Twitch,
    /// newspapers): with no billing words to go by, every one of them would be read.
    static let domains: [String] = [
        // AI and software
        "anthropic.com", "claude.ai", "claude.com", "openai.com", "perplexity.ai", "midjourney.com",
        "cursor.com", "cursor.sh", "mistral.ai", "notion.so", "canva.com", "adobe.com",
        "figma.com", "grammarly.com", "1password.com", "bitwarden.com", "nordvpn.com",
        "expressvpn.com", "surfshark.com", "proton.me", "setapp.com",
        // Merchants of record that send the receipts of other apps
        "paddle.com", "paddle.net", "lemonsqueezy.com", "fastspring.com",
        // Trains, public transport and mobility
        "trenitalia.it", "trenitalia.com", "italotreno.it", "italotreno.com", "trenord.it",
        "atm.it", "atac.roma.it", "gtt.to.it", "tper.it", "anm.it", "eavsrl.it", "unicocampania.it",
        "amt.genova.it", "actv.it", "mycicero.it", "telepass.com", "telepass.it", "unipolmove.it",
        // TV, audiobooks and reading
        "nowtv.it", "sky.it", "timvision.it", "dazn.com", "audible.it", "audible.com",
        "storytel.com", "kobo.com",
        // Gyms and wellbeing
        "virginactive.it", "mcfit.com", "headspace.com", "calm.com",
    ]

    /// True when the sender's address belongs to one of `domains` or a subdomain of it.
    static func contains(_ from: String) -> Bool {
        let address = BillingEmailFilter.senderAddress(from)
        guard let at = address.lastIndex(of: "@") else { return false }
        let host = address[address.index(after: at)...]
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Gmail `from:` terms for every known domain, for `GmailAPI.knownSendersQuery`.
    static var gmailFromTerms: String {
        domains.map { "from:\($0)" }.joined(separator: " OR ")
    }
}
