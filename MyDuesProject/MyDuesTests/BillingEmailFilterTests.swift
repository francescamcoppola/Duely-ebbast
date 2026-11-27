//
//  BillingEmailFilterTests.swift
//  MyDuesTests
//

import Foundation
import Testing
@testable import MyDues

@Suite("BillingEmailFilter")
struct BillingEmailFilterTests {
    private func email(_ from: String, _ subject: String, unsubscribe: Bool = false, daysAgo: Double = 0) -> EmailMetadata {
        EmailMetadata(id: UUID().uuidString, from: from, subject: subject,
                      date: Date(timeIntervalSinceNow: -daysAgo * 86_400), hasListUnsubscribe: unsubscribe)
    }

    @Test("Receipts, bills, taxes and tuition are read", arguments: [
        ("Netflix <info@account.netflix.com>", "Il tuo abbonamento è stato rinnovato", true),
        ("Spotify <no-reply@spotify.com>", "La tua ricevuta Spotify", true),
        ("Enel Energia <noreply@enel.com>", "Bolletta luce disponibile - scadenza 15/12", false),
        ("Comune di Napoli <tributi@comune.napoli.it>", "Avviso di pagamento TARI 2026", false),
        ("PagoPA <noreply@pagopa.it>", "Hai un nuovo avviso", false),
        ("Università <segreteria@unina.it>", "Contribuzione studentesca: seconda rata", false),
        ("Google Payments <payments-noreply@google.com>", "Your Google One subscription", true),
    ])
    func billing(from: String, subject: String, unsubscribe: Bool) {
        #expect(BillingEmailFilter.verdict(for: email(from, subject, unsubscribe: unsubscribe)) == .billing)
    }

    @Test("Ads and newsletters are skipped, even with billing words", arguments: [
        ("Zalando <news@zalando.it>", "Saldi fino al -70% 🔥"),
        ("Disney+ <disneyplus@mail.disneyplus.com>", "Offerta in scadenza: abbonati ora a 1,99€"),
        ("Viaggi <info@viaggi.it>", "Itinerari imperdibili per il ponte"),
    ])
    func advertising(from: String, subject: String) {
        #expect(BillingEmailFilter.verdict(for: email(from, subject, unsubscribe: true)) == .advertising)
    }

    @Test("Shipping and security notices are skipped")
    func notBilling() {
        #expect(BillingEmailFilter.verdict(for: email("Amazon <shipment-tracking@amazon.it>", "Il tuo ordine è in consegna")) == .notBilling)
        #expect(BillingEmailFilter.verdict(for: email("Google <no-reply@accounts.google.com>", "Avviso di sicurezza: nuovo accesso")) == .notBilling)
    }

    @Test("Short tokens match whole words only")
    func wholeWords() {
        #expect(BillingEmailFilter.containsWord("avviso tari 2026", ["tari"]))
        #expect(!BillingEmailFilter.containsWord("itinerari imperdibili", ["tari"]))
        #expect(!BillingEmailFilter.containsWord("comunicazione", ["imu"]))
    }

    @Test("Only the newest repeats are read; stores keep more")
    func repeats() {
        let months = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
                      "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
        var inbox = months.enumerated().map { index, month in
            email("Spotify <no-reply@spotify.com>", "La tua ricevuta Spotify - \(month) 2026", daysAgo: Double(30 * index))
        }
        inbox += (0..<8).map { email("Apple <no_reply@email.apple.com>", "La tua ricevuta di Apple", daysAgo: Double(10 * $0)) }
        inbox += [0, 60, 120].map { email("Enel <noreply@enel.com>", "Bolletta n. \(100 + Int($0)) del 01/11/2026", daysAgo: $0) }

        let result = BillingEmailFilter.selectForReading(inbox, limit: 150)
        #expect(result.selected.count == 2 + 6 + 2)
        #expect(result.repeats == inbox.count - 10)
        #expect(result.selected.first?.subject.hasPrefix("La tua ricevuta Spotify - gennaio") == true)
    }

    @Test("The reading limit is respected")
    func limit() {
        let inbox = (0..<50).map { email("Sender\($0) <billing@s\($0).com>", "Invoice") }
        #expect(BillingEmailFilter.selectForReading(inbox, limit: 20).selected.count == 20)
    }
}
