//
//  GmailAPI.swift
//  MyDues
//
//  The read-only Gmail REST calls the import needs: the account address, a search for
//  likely billing emails, their headers (to pick which to read), and full messages.
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
    /// PDF attachments (pagoPA notices come as PDFs). Only their references: the files are
    /// downloaded one at a time, and only for notices.
    var attachments: [EmailAttachment] = []
}

nonisolated struct EmailAttachment: Equatable, Sendable {
    let filename: String
    /// Gmail's id, to download it with `GmailAPI.attachment(messageID:id:)`.
    let attachmentID: String?
    /// Small attachments come inline, already base64url-encoded in the message.
    let inlineData: String?
    let size: Int
}

nonisolated struct GmailAPI: Sendable {
    let accessToken: String

    /// Recent emails that look like receipts, renewals, plan confirmations, household bills,
    /// taxes and tuition notices, in English, Spanish and Italian. Excludes promotions and social
    /// tabs, and mail the user sent, so marketing blasts with words like "payment" or "scadenza"
    /// never enter the pipeline. `BillingEmailFilter` then sorts the results by their headers.
    static let searchQuery = """
    newer_than:13m -in:chats -in:spam -in:trash -in:sent -in:drafts -category:promotions -category:social (category:purchases OR subject:(\
    subscription OR subscribed OR renewal OR renews OR renewed OR "auto-renew" OR "free trial" OR trial OR \
    receipt OR invoice OR membership OR "your plan" OR billing OR payment OR "direct debit" OR sepa OR \
    bill OR statement OR "amount due" OR tax OR tuition OR rent OR insurance OR \
    suscripción OR renovación OR recibo OR factura OR membresía OR pago OR impuesto OR matrícula OR \
    abbonamento OR rinnovo OR ricevuta OR fattura OR pagamento OR addebito OR domiciliazione OR \
    "prova gratuita" OR bolletta OR bollette OR utenza OR utenze OR "avviso di pagamento" OR pagopa OR \
    tari OR imu OR tassa OR tasse OR tributo OR tributi OR "bollo auto" OR rata OR scadenza OR \
    condominio OR affitto OR canone OR polizza OR assicurazione OR "contribuzione studentesca" OR iscrizione))
    """

    /// Online orders, shipping and deliveries (Amazon and other stores), for return windows and
    /// warranties. Same exclusions as `searchQuery`.
    static let ordersQuery = """
    newer_than:13m -in:chats -in:spam -in:trash -in:sent -in:drafts -category:promotions -category:social (\
    from:amazon.it OR from:amazon.com OR from:amazon.de OR from:amazon.fr OR from:amazon.es OR from:amazon.co.uk OR \
    subject:(ordinato OR spedito OR consegnato OR "il tuo ordine" OR "conferma d'ordine" OR "conferma ordine" OR \
    "ordine confermato" OR "ordine n" OR "your order" OR "order confirmation" OR "has been delivered" OR \
    shipped OR delivered OR "tu pedido" OR "pedido confirmado" OR entregado OR enviado))
    """

    /// pagoPA payment notices (avvisi di pagamento): often a PDF with the QR code.
    static let pagoPAQuery = """
    newer_than:13m -in:chats -in:spam -in:trash -in:sent -in:drafts (\
    pagopa OR "avviso di pagamento" OR "avviso pagopa" OR "codice avviso" OR "avviso di scadenza")
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

    /// Headers only (`format=metadata`: sender, subject, List-Unsubscribe and date), a few at a
    /// time. Much lighter than full messages: used to decide which emails are worth reading.
    /// Newest first, like `ids`. `onProgress` gets how many have been fetched so far.
    func metadata(
        for ids: [String],
        maxConcurrent: Int = 4,
        onProgress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws -> [EmailMetadata] {
        guard !ids.isEmpty else { return [] }
        var fetched: [String: EmailMetadata] = [:]
        var done = 0

        // One email that can't be fetched (deleted meanwhile, a hiccup) is skipped, never the
        // whole scan. Only a sign-out or a cancel stop it.
        try await withThrowingTaskGroup(of: EmailMetadata?.self) { group in
            var iterator = ids.makeIterator()
            func addNext() {
                guard let id = iterator.next() else { return }
                group.addTask {
                    do {
                        return try await self.metadata(id: id)
                    } catch let error as GmailAuthError where error == .signedOut {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return nil
                    }
                }
            }
            for _ in 0..<min(max(1, maxConcurrent), ids.count) { addNext() }
            while let item = try await group.next() {
                if let item { fetched[item.id] = item }
                done += 1
                await onProgress(done)
                addNext()
            }
        }
        return ids.compactMap { fetched[$0] }
    }

    private func metadata(id: String) async throws -> EmailMetadata {
        let raw: GmailMessagePayload.Message = try await get(
            "messages/\(id)",
            query: [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Subject"),
                URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe"),
            ]
        )
        return GmailMessagePayload.metadata(from: raw)
    }

    func message(id: String) async throws -> EmailMessage {
        let raw: GmailMessagePayload.Message = try await get(
            "messages/\(id)",
            query: [URLQueryItem(name: "format", value: "full")]
        )
        return GmailMessagePayload.emailMessage(from: raw)
    }

    /// One attachment's bytes, kept in memory only.
    func attachment(messageID: String, id: String) async throws -> Data {
        struct Attachment: Decodable { let data: String? }
        let raw: Attachment = try await get("messages/\(messageID)/attachments/\(id)")
        guard let data = raw.data.flatMap(EmailText.base64URLData) else { throw GmailAuthError.server("attachment") }
        return data
    }

    /// The PDFs of an email that could be a notice, skipping oversized files.
    func pdfs(of email: EmailMessage, maxBytes: Int, limit: Int = 3) async -> [Data] {
        var files: [Data] = []
        for attachment in email.attachments.prefix(limit) where attachment.size <= maxBytes {
            if let inline = attachment.inlineData, let data = EmailText.base64URLData(inline) {
                files.append(data)
            } else if let id = attachment.attachmentID,
                      let data = try? await self.attachment(messageID: email.id, id: id) {
                files.append(data)
            }
        }
        return files
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: GmailConfiguration.apiBase.appending(path: path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Gmail limits requests per user per second, and mobile connections drop now and then:
        // back off and retry on rate limits, server errors and transient network errors.
        var attempt = 0
        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where Self.isTransient(error) && attempt < Self.maxRetries {
                attempt += 1
                try await Task.sleep(for: Self.backoff(attempt))
                continue
            }
            let http = response as? HTTPURLResponse
            switch http?.statusCode ?? 0 {
            case 200..<300:
                return try JSONDecoder().decode(T.self, from: data)
            case 401:
                throw GmailAuthError.signedOut
            case 403 where Self.isRateLimit(data):
                fallthrough
            case 429, 500, 502, 503, 504:
                guard attempt < Self.maxRetries else { throw GmailAuthError.server("rate limited") }
                attempt += 1
                // Gmail may say how long to wait.
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                try await Task.sleep(for: retryAfter.map { .seconds(min($0, 30)) } ?? Self.backoff(attempt))
            case 403:
                throw GmailAuthError.scopeNotGranted
            case let status:
                throw GmailAuthError.server("HTTP \(status)")
            }
        }
    }

    private static let maxRetries = 5

    /// 1, 2, 4, 8, 16 seconds, plus a little jitter so parallel requests don't retry together.
    private static func backoff(_ attempt: Int) -> Duration {
        .milliseconds(1000 * (1 << (attempt - 1)) + Int.random(in: 0...400))
    }

    private static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
         .dnsLookupFailed, .secureConnectionFailed].contains(error.code)
    }

    /// Gmail reports some rate limits as 403 with a `rateLimitExceeded` reason.
    private static func isRateLimit(_ data: Data) -> Bool {
        let text = String(decoding: data.prefix(2000), as: UTF8.self)
        return text.contains("rateLimitExceeded") || text.contains("userRateLimitExceeded")
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
        var attachmentId: String? = nil
        var size: Int? = nil
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

        return EmailMessage(id: message.id, from: header("From"), subject: header("Subject"), date: date, body: body,
                            attachments: message.payload.map(pdfAttachments) ?? [])
    }

    static func metadata(from message: Message) -> EmailMetadata {
        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }
        let date = message.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
        return EmailMetadata(
            id: message.id,
            from: header("From"),
            subject: header("Subject"),
            date: date,
            hasListUnsubscribe: !header("List-Unsubscribe").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

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

    /// Every PDF in the message, however deeply nested.
    static func pdfAttachments(in part: Part) -> [EmailAttachment] {
        var found: [EmailAttachment] = []
        if let name = part.filename, !name.isEmpty,
           part.mimeType?.lowercased() == "application/pdf" || name.lowercased().hasSuffix(".pdf") {
            found.append(EmailAttachment(filename: name, attachmentID: part.body?.attachmentId,
                                         inlineData: part.body?.data, size: part.body?.size ?? 0))
        }
        for child in part.parts ?? [] { found += pdfAttachments(in: child) }
        return found
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
