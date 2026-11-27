//
//  PagoPACodeTests.swift
//  DuelyProjectTests
//

import Foundation
import Testing
@testable import DuelyProject

@Suite("pagoPA codes")
struct PagoPACodeTests {
    @Test("Reads the QR code of a notice")
    func qrPayload() throws {
        let code = try #require(PagoPACode.parse(qrPayload: "PAGOPA|002|301000000000123456|80014890638|12850"))
        #expect(code.noticeNumber == "301000000000123456")
        #expect(code.fiscalCode == "80014890638")
        #expect(code.amountCents == 12850)
        #expect(code.qrPayload() == "PAGOPA|002|301000000000123456|80014890638|12850")
        #expect(code.groupedNoticeNumber == "3010 0000 0000 1234 56")
    }

    @Test("Rejects other versions and wrong lengths", arguments: [
        "PAGOPA|001|301000000000123456|80014890638|12850",
        "PAGOPA|002|30100000000012345|80014890638|12850",
        "PAGOPA|002|301000000000123456|8001489063|12850",
        "PAGOPA|002|301000000000123456",
        "https://example.com",
    ])
    func rejects(payload: String) {
        #expect(PagoPACode.parse(qrPayload: payload) == nil)
    }

    @Test("The checkout link holds the tax code then the notice code (29 digits)")
    func checkoutURL() throws {
        let code = try #require(PagoPACode(noticeNumber: "301000000000123456", fiscalCode: "80014890638"))
        #expect(code.checkoutURL.absoluteString == "https://checkout.pagopa.it/80014890638301000000000123456")
    }

    @Test("Finds the printed codes, grouped with spaces")
    func printedCodes() throws {
        let text = """
        AVVISO DI PAGAMENTO
        Ente Creditore: Comune di Napoli
        Codice Fiscale Ente Creditore: 80014890638
        Codice Avviso: 3010 0000 0000 1234 56
        """
        let code = try #require(PagoPACode.parse(text: text))
        #expect(code.noticeNumber == "301000000000123456")
        #expect(code.fiscalCode == "80014890638")
    }

    @Test("Short labels and a QR string written in the text")
    func otherFormats() {
        #expect(PagoPACode.parse(text: "CF Ente: 80014890638 - Cod. avviso 301000000000123456") != nil)
        #expect(PagoPACode.parse(text: "Paga: PAGOPA|002|301000000000123456|80014890638|9999")?.amountCents == 9999)
        #expect(PagoPACode.parse(text: "Codice avviso: 3010 0000 0000 1234 56") == nil)
    }

    @Test("Cents")
    func cents() {
        #expect(Decimal(string: "12.345")!.cents == 1235)
        #expect(Decimal(cents: 12850) == Decimal(string: "128.5")!)
    }
}
