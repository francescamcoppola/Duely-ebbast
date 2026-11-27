//
//  PageLinksTests.swift
//  MyDuesTests
//

import Foundation
import Testing
@testable import MyDues

@Suite("PageLinks")
struct PageLinksTests {
    private let base = URL(string: "https://www.example.it/")!

    @Test("Root domains drop subdomains but keep country second levels")
    func rootDomain() {
        #expect(PageLinks.rootDomain("mail.dazn.com") == "dazn.com")
        #expect(PageLinks.rootDomain("www.example.it") == "example.it")
        #expect(PageLinks.rootDomain("shop.bbc.co.uk") == "bbc.co.uk")
    }

    @Test("Only same-site links are extracted, relative ones resolved")
    func extract() {
        let html = """
        <a href="/account/cancel">Disdici <b>abbonamento</b></a>
        <a href="https://help.example.it/disdetta">Come disdire</a>
        <a href="https://other.com/cancel">Cancel elsewhere</a>
        <a href="mailto:info@example.it">Scrivici</a>
        """
        let links = PageLinks.extract(from: html, baseURL: base, rootDomain: "example.it")
        #expect(links.map(\.url.absoluteString) == ["https://www.example.it/account/cancel", "https://help.example.it/disdetta"])
        #expect(links.first?.text == "Disdici abbonamento")
    }

    @Test("Cancel links beat account links; sign-up and newsletter links are dropped")
    func rankCancel() {
        let links = [
            PageLinks.Link(url: URL(string: "https://www.example.it/account")!, text: "Area personale"),
            PageLinks.Link(url: URL(string: "https://www.example.it/subscription/confirmation")!, text: "Iscriviti ora"),
            PageLinks.Link(url: URL(string: "https://www.example.it/newsletter")!, text: "Unsubscribe"),
            PageLinks.Link(url: URL(string: "https://help.example.it/a/123")!, text: "Come disdire l'abbonamento"),
        ]
        let ranked = PageLinks.rank(links, for: .cancel)
        #expect(ranked.map(\.url.path()) == ["/a/123", "/account"])
        #expect(ranked[0].score >= PageLinks.strongScore)
        #expect(ranked[1].score < PageLinks.strongScore)
    }

    @Test("The service's name breaks ties")
    func nameBoost() {
        let links = [
            PageLinks.Link(url: URL(string: "https://support.example.it/1")!, text: "How to cancel your server boost"),
            PageLinks.Link(url: URL(string: "https://support.example.it/2")!, text: "How to cancel your Nitro subscription"),
        ]
        #expect(PageLinks.rank(links, for: .cancel, serviceName: "Discord Nitro").first?.url.path() == "/2")
    }

    @Test("Imported emails remember the service's own domain, not stores or mail providers")
    @MainActor
    func senderDomain() {
        #expect(DetectedSubscription.serviceDomain(fromSender: "DAZN <noreply@mail.dazn.com>") == "dazn.com")
        #expect(DetectedSubscription.serviceDomain(fromSender: "Apple <no_reply@email.apple.com>") == nil)
        #expect(DetectedSubscription.serviceDomain(fromSender: "mario@gmail.com") == nil)
    }
}
