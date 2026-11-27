//
//  EmailImportTests.swift
//  DuelyProjectTests
//
//  Email text cleanup, OAuth callback checks and the rules that turn model output into
//  subscription candidates. No network and no language model involved.
//

import Foundation
import SwiftData
import Testing
@testable import DuelyProject

@MainActor
@Suite("Email text")
struct EmailTextTests {
    @Test("Gmail's base64url bodies decode, with or without padding")
    func base64URL() {
        // "Total: 9,99 €" in base64url, padding removed.
        #expect(EmailText.base64URLDecoded("VG90YWw6IDksOTkg4oKs") == "Total: 9,99 €")
        #expect(EmailText.base64URLDecoded("SGk_") == "Hi?")
    }

    @Test("HTML becomes readable text, without styles, scripts or tags")
    func html() {
        let html = """
        <html><head><style>.a{color:red}</style></head><body>
        <table><tr><td>Plan</td><td>Premium</td></tr><tr><td>Total</td><td>&euro;10&#44;99</td></tr></table>
        <script>track()</script><p>Renews on&nbsp;Dec 1</p></body></html>
        """
        let text = EmailText.normalized(EmailText.plainText(fromHTML: html))
        #expect(text.contains("Plan Premium"))
        #expect(text.contains("Total €10,99"))
        #expect(text.contains("Renews on Dec 1"))
        #expect(!text.contains("color"))
        #expect(!text.contains("track"))
        #expect(!text.contains("<"))
    }

    @Test("Links and extra blank lines are removed, and the text is capped")
    func normalize() {
        let text = EmailText.normalized("Hello\n\n\n\nManage: https://example.com/a?b=c\u{200B}\n  World  ", limit: 100)
        #expect(text == "Hello\n\nManage:\nWorld")
        #expect(EmailText.normalized(String(repeating: "a", count: 50), limit: 10).count == 10)
    }

    @Test("Plain text is preferred over HTML, and attachments are ignored")
    func bestPart() {
        typealias P = GmailMessagePayload.Part
        let plain = P(mimeType: "text/plain", filename: "", headers: nil,
                      body: .init(data: GmailAuth.base64URL(Data("Plain body".utf8))), parts: nil)
        let html = P(mimeType: "text/html", filename: "", headers: nil,
                     body: .init(data: GmailAuth.base64URL(Data("<b>HTML body</b>".utf8))), parts: nil)
        let attachment = P(mimeType: "text/plain", filename: "invoice.txt", headers: nil,
                           body: .init(data: GmailAuth.base64URL(Data("Attachment".utf8))), parts: nil)

        let both = P(mimeType: "multipart/alternative", filename: nil, headers: nil, body: nil, parts: [attachment, html, plain])
        #expect(GmailMessagePayload.bestText(in: both) == "Plain body")

        let htmlOnly = P(mimeType: "multipart/mixed", filename: nil, headers: nil, body: nil, parts: [attachment, html])
        #expect(GmailMessagePayload.bestText(in: htmlOnly) == "HTML body")
    }
}

@MainActor
@Suite("Gmail sign-in")
struct GmailAuthTests {
    @Test("The callback is accepted only with the expected state")
    func callbackState() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.1:/oauth2redirect?state=abc&code=XYZ"))
        #expect(try GmailAuth.authorizationCode(from: url, expectedState: "abc") == "XYZ")
        #expect(throws: GmailAuthError.invalidCallback) {
            try GmailAuth.authorizationCode(from: url, expectedState: "other")
        }
    }

    @Test("A denied consent is reported as such")
    func denied() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.1:/oauth2redirect?state=abc&error=access_denied"))
        #expect(throws: GmailAuthError.accessDenied) {
            try GmailAuth.authorizationCode(from: url, expectedState: "abc")
        }
    }

    @Test("PKCE verifiers are URL-safe and unique")
    func verifier() {
        let first = GmailAuth.randomURLSafeString(byteCount: 32)
        let second = GmailAuth.randomURLSafeString(byteCount: 32)
        #expect(first != second)
        #expect(first.count == 43)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

@MainActor
@Suite("Detected subscriptions")
struct DetectedSubscriptionTests {
    private func email(_ day: Int, subject: String = "Receipt") -> EmailMessage {
        EmailMessage(id: UUID().uuidString, from: "billing@example.com", subject: subject,
                     date: date(2026, 11, day, 12), body: "")
    }

    private func analysis(
        _ name: String,
        price: Double = 9.99,
        currency: String = "EUR",
        cycle: DetectedCycle = .monthly,
        paymentDate: String = "",
        isSubscription: Bool = true
    ) -> EmailSubscriptionAnalysis {
        EmailSubscriptionAnalysis(isRecurringSubscription: isSubscription, serviceName: name, price: price,
                                  currencyCode: currency, billingCycle: cycle, paymentDate: paymentDate,
                                  category: .filmTV)
    }

    @Test("Model output becomes a candidate with the stated details")
    func candidate() throws {
        let candidate = try #require(DetectedSubscription(
            analysis: analysis(" Netflix ", price: 13.989, cycle: .yearly, paymentDate: "2026-12-05"),
            email: email(5), calendar: TestCalendar.utc
        ))
        #expect(candidate.name == "Netflix")
        #expect(candidate.price == Decimal(string: "13.99"))
        #expect(candidate.currencyCode == "EUR")
        #expect(candidate.cycle == .yearly)
        #expect(candidate.category == .filmTV)
        #expect(candidate.paymentDate == date(2026, 12, 5))
    }

    @Test("Missing or invalid values fall back safely")
    func fallbacks() throws {
        let candidate = try #require(DetectedSubscription(
            analysis: analysis("Spotify", price: 0, currency: "euro", cycle: .unknown, paymentDate: "2026-02-31"),
            email: email(10), calendar: TestCalendar.utc
        ))
        #expect(candidate.price == nil)          // Added as "Needs Setup".
        #expect(candidate.currencyCode == nil)
        #expect(candidate.cycle == .monthly)
        #expect(!candidate.cycleIsKnown)
        #expect(candidate.paymentDate == date(2026, 11, 10))   // The email's own date.
    }

    @Test("Non-subscriptions and empty names are dropped")
    func rejected() {
        #expect(DetectedSubscription(analysis: analysis("Amazon", isSubscription: false), email: email(1)) == nil)
        #expect(DetectedSubscription(analysis: analysis("   "), email: email(1)) == nil)
    }

    @Test("Name variants of the same service match", arguments: [
        ("Spotify Premium", "spotify"),
        ("SPOTIFY AB", "Spotify"),
        ("Disney Plus", "Disney+"),
        ("Crunchyroll Inc", "crunchyroll"),
    ])
    func matching(lhs: String, rhs: String) {
        #expect(DetectedSubscription.matchKey(lhs) == DetectedSubscription.matchKey(rhs))
    }

    @Test("Several emails about one service merge into the newest, filling gaps from older ones")
    func merge() throws {
        let newest = try #require(DetectedSubscription(
            analysis: analysis("Netflix", price: 0, cycle: .unknown), email: email(20), calendar: TestCalendar.utc))
        let older = try #require(DetectedSubscription(
            analysis: analysis("Netflix Premium", price: 17.99, cycle: .monthly), email: email(1), calendar: TestCalendar.utc))
        let other = try #require(DetectedSubscription(
            analysis: analysis("Spotify"), email: email(10), calendar: TestCalendar.utc))

        let merged = DetectedSubscription.merged([older, other, newest])
        #expect(merged.map(\.name) == ["Netflix", "Spotify"])
        #expect(merged[0].price == Decimal(string: "17.99"))
        #expect(merged[0].cycleIsKnown)
        #expect(merged[0].paymentDate == date(2026, 11, 20))
    }

    @Test("Adding completes a matching 'Needs Setup' subscription instead of duplicating it")
    func addCompletesPending() throws {
        let store = try TestStore()
        let pending = Subscription(name: "Netflix", category: .filmTV)
        store.context.insert(pending)
        let configured = store.subscription("Spotify", price: 10)

        let netflix = try #require(DetectedSubscription(
            analysis: analysis("Netflix", price: 13.99, paymentDate: "2026-12-01"), email: email(1), calendar: TestCalendar.utc))
        let youtube = try #require(DetectedSubscription(
            analysis: analysis("YouTube Premium", price: 0), email: email(2), calendar: TestCalendar.utc))

        let model = EmailImportModel()
        model.add([netflix, youtube], existing: [pending, configured], into: store.context)

        let all = try store.context.fetch(FetchDescriptor<Subscription>())
        #expect(all.count == 3)
        #expect(pending.price == Decimal(string: "13.99"))
        #expect(pending.anchorDate == date(2026, 12, 1))
        #expect(!pending.needsSetup)
        let added = try #require(all.first { $0.name == "YouTube Premium" })
        #expect(added.needsSetup)
    }
}
