//
//  GmailAPI.swift
//  DuelyProject
//
//  The read-only Gmail REST calls the import needs: the account address, a search for
//  likely billing emails, a lightweight metadata pre-filter, and full message fetching.
//  Messages are kept in memory only for the duration of a scan; nothing is written to disk.
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
    /// taxes and tuition notices, in English, Spanish and Italian. Excludes promotions and social
    /// tabs so marketing blasts with words like "payment" or "scadenza" never enter the pipeline.
    static let searchQuery = """
    newer_than:13m -in:chats -in:spam -in:trash -category:promotions -category:social (category:purchases OR subject:(\
    subscription OR subscribed OR renewal OR renews OR renewed OR "auto-renew" OR "free trial" OR trial OR \
    receipt OR invoice OR membership OR "your plan" OR billing OR payment OR "direct debit" OR sepa OR \
    bill OR statement OR "amount due" OR tax OR tuition OR rent OR insurance OR \
    suscripción OR renovación OR recibo OR factura OR membresía OR pago OR impuesto OR matrícula OR \
    abbonamento OR rinnovo OR ricevuta OR fattura OR pagamento OR addebito OR domiciliazione OR \
    "prova gratuita" OR bolletta OR bollette OR utenza OR utenze OR "avviso di pagamento" OR pagopa OR \
    tari OR imu OR tassa OR tasse OR tributo OR tributi OR "bollo auto" OR rata OR scadenza OR \
    condominio OR affitto OR canone OR polizza OR assicurazione OR "contribuzione studentesca" OR iscrizione))
    """

    // MARK: Calls

    func emailAddress() async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        let profile: Profile = try await get("profile")
        return profile.emailAddress
    }

    /// Newest first, as Gmail returns them.
    func searchMessageIDs(query: String = Self.searchQuery, limit: Int) async throws -> [String] {
        guard limit > 0 else { return [] }

        struct ListResponse: Decodable {
            struct Ref: Decodable { let id: String }
            let messages: [Ref]?
            let nextPageToken: String?
        }

        var ids: [String] = []
        var pageToken: String?
        repeat {
            var params = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: String(min(100, limit - ids.count))),
            ]
            if let pageToken { params.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: ListResponse = try await get("messages", query: params)
            ids += page.messages?.map(\.id) ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < limit
        return Array(ids.prefix(limit))
    }

    /// Fetches only `From`, `Subject`, and `List-Unsubscribe` (`format=metadata`) in parallel
    /// to drop promotional newsletters before downloading full bodies or running the on-device model.
    func filterCandidateIDs(_ ids: [String], maxConcurrent: Int = 10) async throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let concurrency = max(1, maxConcurrent)
        var kept = Set<String>()

        try await withThrowingTaskGroup(of: (String, Bool).self) { group in
            var iterator = ids.makeIterator()
            for _ in 0..<min(concurrency, ids.count) {
                if let nextID = iterator.next() {
                    group.addTask { (nextID, try await self.isLikelyBillingMetadata(id: nextID)) }
                }
            }

            while let (id, keep) = try await group.next() {
                if keep { kept.insert(id) }
                if let nextID = iterator.next() {
                    group.addTask { (nextID, try await self.isLikelyBillingMetadata(id: nextID)) }
                }
            }
        }

        // Preserve Gmail's newest-first ordering.
        return ids.filter { kept.contains($0) }
    }

    /// End-to-end convenience pipeline: searches IDs, filters via lightweight metadata headers,
    /// and fetches full message bodies only for surviving candidates.
    func candidateMessages(
        query: String = Self.searchQuery,
        limit: Int,
        maxConcurrent: Int = 8
    ) async throws -> [EmailMessage] {
        let rawIDs = try await searchMessageIDs(query: query, limit: limit)
        let candidateIDs = try await filterCandidateIDs(rawIDs, maxConcurrent: maxConcurrent)
        guard !candidateIDs.isEmpty else { return [] }

        let concurrency = max(1, maxConcurrent)
        var fetched: [String: EmailMessage] = [:]

        try await withThrowingTaskGroup(of: EmailMessage.self) { group in
            var iterator = candidateIDs.makeIterator()
            for _ in 0..<min(concurrency, candidateIDs.count) {
                if let nextID = iterator.next() {
                    group.addTask { try await self.message(id: nextID) }
                }
            }

            while let msg = try await group.next() {
                fetched[msg.id] = msg
                if let nextID = iterator.next() {
                    group.addTask { try await self.message(id: nextID) }
                }
            }
        }

        return candidateIDs.compactMap { fetched[$0] }
    }

    func message(id: String) async throws -> EmailMessage {
        let raw: GmailMessagePayload.Message = try await get(
            "messages/\(id)",
            query: [URLQueryItem(name: "format", value: "full")]
        )
        return GmailMessagePayload.emailMessage(from: raw)
    }

    private func isLikelyBillingMetadata(id: String) async throws -> Bool {
        let raw: GmailMessagePayload.Message = try await get(
            "messages/\(id)",
            query: [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Subject"),
                URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe"),
            ]
        )
        let headers = raw.payload?.headers ?? []
        return GmailHeaderFilter.isLikelyBilling(headers: headers)
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

// MARK: - Header pre-filter

/// Pure header heuristic used on `format=metadata` responses before fetching full bodies.
nonisolated enum GmailHeaderFilter {
    private static let highConfidenceSubjectTokens = [
        // Italian
        "ricevuta", "fattura", "abbonamento", "rinnovo", "addebito", "domiciliazione",
        "bolletta", "bollette", "pagopa", "scadenza", "polizza", "rata", "canone",
        "prova gratuita", "quietanza", "estratto conto",
        // English
        "receipt", "invoice", "subscription", "renewal", "renews", "renewed", "billing",
        "statement", "amount due", "payment", "direct debit", "auto-renew", "free trial",
        // Spanish
        "recibo", "factura", "suscripción", "suscripcion", "renovación", "renovacion", "pago"
    ]

    private static let shippingOnlyTokens = [
        "in consegna", "è stato spedito", "pacco spedito", "traccia il tuo pacco",
        "has shipped", "out for delivery", "track your package", "tracking number"
    ]

    static func isLikelyBilling(headers: [GmailMessagePayload.Header]) -> Bool {
        func value(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }

        let subject = value("Subject").lowercased()
        let hasListUnsubscribe = !value("List-Unsubscribe").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let hasStrongSubject = highConfidenceSubjectTokens.contains { subject.contains($0) }

        // Marketing emails almost always include List-Unsubscribe; keep them only if the
        // subject explicitly looks like a receipt/invoice/renewal (e.g. Spotify, Apple, Netflix).
        if hasListUnsubscribe && !hasStrongSubject {
            return false
        }

        // Pure parcel tracking notifications without billing terms are one-off e-commerce noise.
        if shippingOnlyTokens.contains(where: { subject.contains($0) }) && !hasStrongSubject {
            return false
        }

        return true
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

    /// Prefers the plain-text alternative unless it's a tiny stub; falls back to HTML stripped.
    /// Prefers the plain-text alternative unless it's a tiny stub; falls back to HTML stripped.
        static func bestText(in part: Part) -> String {
            var plain = ""
            if let rawPlain = firstBody(in: part, mimeType: "text/plain") {
                plain = EmailText.normalized(rawPlain).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if plain.count >= 80 {
                return plain
            }

            if let rawHTML = firstBody(in: part, mimeType: "text/html") {
                let stripped = EmailText.normalized(EmailText.plainText(fromHTML: rawHTML))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty {
                    return stripped
                }
            }

            return plain
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
