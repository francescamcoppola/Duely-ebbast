//
//  GmailAPI.swift
//  DuelyProject
//
//  The three read-only Gmail REST calls the import needs: the account address, a search for
//  likely billing emails, and one message at a time. Messages are kept in memory only for the
//  duration of a scan; nothing is written to disk.
//

import Foundation

/// One email, reduced to what the on-device model needs.
nonisolated struct EmailMessage: Identifiable, Equatable, Sendable {
    let id: String
    let from: String
    let subject: String
    let date: Date
    let body: String
}

nonisolated struct GmailAPI: Sendable {
    let accessToken: String

    /// Recent emails that look like receipts, renewals, plan confirmations, household bills,
    /// taxes and tuition notices, in English, Spanish and Italian. A broad net: the model decides
    /// what is really a recurring payment.
    static let searchQuery = """
    newer_than:13m -in:chats -in:spam -in:trash (category:purchases OR subject:(subscription OR \
    subscribed OR renewal OR renews OR renewed OR receipt OR invoice OR membership OR "your plan" OR \
    billing OR payment OR bill OR statement OR "amount due" OR tax OR tuition OR rent OR insurance OR \
    suscripción OR renovación OR recibo OR factura OR membresía OR pago OR impuesto OR matrícula OR \
    abbonamento OR rinnovo OR ricevuta OR fattura OR pagamento OR bolletta OR bollette OR \
    "avviso di pagamento" OR pagopa OR tari OR imu OR tassa OR tasse OR tributo OR tributi OR \
    "bollo auto" OR rata OR scadenza OR condominio OR affitto OR canone OR polizza OR assicurazione OR \
    "contribuzione studentesca" OR iscrizione))
    """

    // MARK: Calls

    func emailAddress() async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        let profile: Profile = try await get("profile")
        return profile.emailAddress
    }

    /// Newest first, as Gmail returns them.
    func searchMessageIDs(query: String = Self.searchQuery, limit: Int) async throws -> [String] {
        struct ListResponse: Decodable {
            struct Ref: Decodable { let id: String }
            let messages: [Ref]?
            let nextPageToken: String?
        }

        var ids: [String] = []
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: String(min(100, limit - ids.count))),
            ]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: ListResponse = try await get("messages", query: query)
            ids += page.messages?.map(\.id) ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < limit
        return Array(ids.prefix(limit))
    }

    func message(id: String) async throws -> EmailMessage {
        let raw: GmailMessagePayload.Message = try await get(
            "messages/\(id)",
            query: [URLQueryItem(name: "format", value: "full")]
        )
        return GmailMessagePayload.emailMessage(from: raw)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: GmailConfiguration.apiBase.appending(path: path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw GmailAuthError.signedOut
        case 403:
            throw GmailAuthError.scopeNotGranted
        case let status:
            throw GmailAuthError.server("HTTP \(status)")
        }
    }
}

// MARK: - Message payload

/// Gmail's `format=full` message, and the conversion to plain text. Pure, so it's unit-testable.
nonisolated enum GmailMessagePayload {
    struct Message: Decodable, Sendable {
        let id: String
        let internalDate: String?
        let snippet: String?
        let payload: Part?
    }

    struct Part: Decodable, Sendable {
        let mimeType: String?
        let filename: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?
    }

    struct Header: Decodable, Sendable {
        let name: String
        let value: String
    }

    struct Body: Decodable, Sendable {
        let data: String?
    }

    static func emailMessage(from message: Message) -> EmailMessage {
        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }

        // internalDate is when Gmail received it, in milliseconds; more reliable than the Date header.
        let date = message.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now

        var body = message.payload.map(bestText) ?? ""
        if body.isEmpty { body = EmailText.decodeEntities(message.snippet ?? "") }

        return EmailMessage(id: message.id, from: header("From"), subject: header("Subject"), date: date, body: body)
    }

    /// Prefers the plain-text alternative; falls back to the HTML one, stripped. Attachments are skipped.
    static func bestText(in part: Part) -> String {
        if let plain = firstBody(in: part, mimeType: "text/plain"), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return EmailText.normalized(plain)
        }
        if let html = firstBody(in: part, mimeType: "text/html") {
            return EmailText.normalized(EmailText.plainText(fromHTML: html))
        }
        return ""
    }

    private static func firstBody(in part: Part, mimeType: String) -> String? {
        if let name = part.filename, !name.isEmpty { return nil }
        if part.mimeType?.lowercased() == mimeType,
           let data = part.body?.data,
           let decoded = EmailText.base64URLDecoded(data) {
            return decoded
        }
        for child in part.parts ?? [] {
            if let found = firstBody(in: child, mimeType: mimeType) { return found }
        }
        return nil
    }
}
