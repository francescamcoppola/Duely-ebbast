//
//  BillingEmailFilter.swift
//  DuelyProject
//
//  Decides, from an email's headers only (sender, subject, List-Unsubscribe), whether it's worth
//  downloading and reading with Apple Intelligence. This lets a scan look at every billing-like
//  email of the last 13 months while the model reads only the ones that matter:
//  • ads, newsletters, shipping updates and security notices are skipped;
//  • repeats are skipped: 12 monthly receipts from the same service are one subscription, so only
//    the newest couple are read (an older one can still fill in a missing price).
//  Pure functions, no I/O: unit-tested in BillingEmailFilterTests.
//

import Foundation

/// The headers of one email, fetched with Gmail's lightweight `format=metadata`.
nonisolated struct EmailMetadata: Equatable, Sendable {
    let id: String
    let from: String
    let subject: String
    let date: Date
    let hasListUnsubscribe: Bool
}

nonisolated enum BillingEmailFilter {
    /// Why an email was or wasn't kept. Counted for the scan summary.
    enum Verdict: Equatable {
        case billing
        case advertising
        case notBilling
    }

    // MARK: Classification

    static func verdict(for email: EmailMetadata) -> Verdict {
        let subject = fold(email.subject)
        let sender = fold(email.from)

        let isStrong = containsWord(subject, strongSubjectTokens) || sender.containsAny(billingSenderTokens)
        if isStrong { return .billing }

        if containsWord(subject, securityTokens) || containsWord(subject, shippingTokens) { return .notBilling }
        if containsWord(subject, marketingTokens) || sender.containsAny(marketingSenderTokens) || hasEmoji(email.subject) {
            return .advertising
        }
        if containsWord(subject, weakSubjectTokens) { return .billing }

        // Found only through Gmail's Purchases category, with no billing words: keep it unless it
        // looks like a mailing (one-off orders are then rejected by the model).
        return email.hasListUnsubscribe ? .advertising : .billing
    }

    // MARK: Repeats

    /// Emails about the same thing from the same sender: "Your Spotify receipt – March 2026" and
    /// "Your Spotify receipt – April 2026" share a key.
    static func groupKey(for email: EmailMetadata) -> String {
        let subject = fold(email.subject)
            .replacingOccurrences(of: "[0-9]+", with: " ", options: .regularExpression)
            .split(whereSeparator: { !$0.isLetter })
            .filter { !monthWords.contains(String($0)) }
            .joined(separator: " ")
        return senderAddress(email.from) + "|" + subject
    }

    /// Billing emails worth reading, newest first: at most `perGroup` per sender and subject
    /// (more for stores that send one receipt per app, like Apple), at most `limit` in total.
    static func selectForReading(
        _ emails: [EmailMetadata],
        perGroup: Int = 2,
        storePerGroup: Int = 6,
        limit: Int
    ) -> (selected: [EmailMetadata], repeats: Int) {
        var counts: [String: Int] = [:]
        var selected: [EmailMetadata] = []
        var repeats = 0
        for email in emails.sorted(by: { $0.date > $1.date }) {
            let key = groupKey(for: email)
            let cap = isStoreSender(email.from) ? storePerGroup : perGroup
            guard counts[key, default: 0] < cap else {
                repeats += 1
                continue
            }
            counts[key, default: 0] += 1
            selected.append(email)
        }
        return (Array(selected.prefix(limit)), repeats)
    }

    // MARK: Helpers

    static func senderAddress(_ from: String) -> String {
        let lowered = from.lowercased()
        if let start = lowered.lastIndex(of: "<"), let end = lowered.lastIndex(of: ">"), start < end {
            return String(lowered[lowered.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
        }
        return lowered.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isStoreSender(_ from: String) -> Bool {
        let address = senderAddress(from)
        return storeDomains.contains { address.hasSuffix("@" + $0) || address.hasSuffix("." + $0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whole words or phrases only, so "tari" doesn't match "itinerari" nor "imu" "comunicazione".
    static func containsWord(_ text: String, _ tokens: [String]) -> Bool {
        tokens.contains { token in
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: token, range: searchRange) {
                let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return true }
                searchRange = range.upperBound..<text.endIndex
            }
            return false
        }
    }

    /// Marketing subjects love emoji; receipts and bills practically never use them.
    private static func hasEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isEmojiPresentation && $0.value > 0x2000 }
    }

    // MARK: Vocabulary (folded: lowercase, no accents)

    /// Almost only used for real charges, bills and renewals.
    private static let strongSubjectTokens = [
        // Italian
        "ricevuta", "fattura", "bolletta", "bollette", "pagopa", "avviso di pagamento", "addebito",
        "domiciliazione", "quietanza", "estratto conto", "conferma di pagamento", "pagamento ricevuto",
        "pagamento effettuato", "pagamento riuscito", "pagamento non riuscito", "rinnovo", "rinnovato",
        "il tuo abbonamento", "tasse universitarie", "contribuzione studentesca", "tari", "imu",
        "bollo auto", "polizza", "premio assicurativo",
        // English
        "receipt", "invoice", "renewal", "renews", "renewed", "auto-renew", "payment received",
        "payment confirmation", "payment failed", "your payment", "amount due", "direct debit",
        "billing statement", "your subscription", "your membership", "your bill", "tuition",
        // Spanish
        "recibo", "factura", "renovacion", "tu suscripcion", "tu factura", "matricula",
    ]

    /// Billing words that also show up in ads ("offerta in scadenza", "abbonati ora").
    private static let weakSubjectTokens = [
        "abbonamento", "pagamento", "scadenza", "rata", "canone", "tassa", "tasse", "tributo",
        "iscrizione", "affitto", "condominio", "assicurazione", "utenza", "prova gratuita", "piano",
        "subscription", "payment", "billing", "statement", "membership", "free trial", "trial",
        "plan", "tax", "rent", "insurance", "premium",
        "suscripcion", "pago", "impuesto", "plan",
    ]

    private static let marketingTokens = [
        "offerta", "offerte", "sconto", "sconti", "promo", "coupon", "saldi", "black friday",
        "cyber monday", "newsletter", "webinar", "solo per oggi", "ultimi giorni", "non perdere",
        "regalo", "novita", "scopri", "abbonati ora", "% di sconto",
        "sale", "deal", "discount", "% off", "limited time", "last chance", "don't miss", "save up to",
        "upgrade now", "oferta", "descuento", "rebajas",
    ]

    private static let shippingTokens = [
        "in consegna", "e stato spedito", "pacco spedito", "traccia il tuo pacco", "ordine spedito",
        "has shipped", "out for delivery", "track your package", "tracking number", "delivered",
    ]

    private static let securityTokens = [
        "password", "codice di verifica", "verification code", "codigo de verificacion",
        "security alert", "avviso di sicurezza", "nuovo accesso", "new sign-in", "sign-in attempt",
        "conferma il tuo indirizzo", "verify your email", "two-factor", "2fa",
    ]

    private static let billingSenderTokens = [
        "billing", "invoice", "receipt", "fattur", "bollett", "pagopa", "payments@", "pagamenti@",
        "accounts-payable", "noreply@tax",
    ]

    private static let marketingSenderTokens = [
        "newsletter", "marketing", "promo", "offers@", "offerte@", "deals@", "news@", "info@news",
    ]

    /// Stores that send one receipt per app or service from the same address.
    private static let storeDomains = [
        "apple.com", "google.com", "paypal.com", "paypal.it", "amazon.com", "amazon.it",
        "microsoft.com",
    ]

    private static let monthWords: Set<String> = [
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto",
        "settembre", "ottobre", "novembre", "dicembre",
        "january", "february", "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep",
        "sept", "oct", "nov", "dec",
        "enero", "febrero", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
        "noviembre", "diciembre",
    ]
}

private extension String {
    nonisolated func containsAny(_ tokens: [String]) -> Bool {
        tokens.contains { contains($0) }
    }
}
