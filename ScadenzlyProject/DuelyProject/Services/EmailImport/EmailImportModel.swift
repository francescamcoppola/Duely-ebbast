//
//  EmailImportModel.swift
//  DuelyProject
//
//  Connects one or more Gmail accounts, scans their recent billing emails (subscriptions, bills,
//  taxes, tuition) with Apple Intelligence on the device, and adds the ones the user confirms.
//  Email content only ever lives in memory during a scan: it isn't saved, logged or sent anywhere.
//  What gets saved is just the subscriptions the user chooses to add, like any other subscription in the app.
//

import Foundation
import SwiftData
import SwiftUI
import AuthenticationServices
import Observation

enum EmailImportKeys {
    /// Date of the last finished scan, shown in Settings.
    static let lastScan = "emailImportLastScan"
    /// `ScanSummary` of the last finished scan.
    static let lastSummary = "emailImportLastSummary"
}

/// Where a scan is, for the progress UI.
struct ScanProgress: Equatable {
    enum Stage: Equatable {
        /// Asking Gmail for billing-like emails.
        case searching
        /// Checking senders and subjects to skip ads, newsletters and repeats.
        case filtering
        /// Apple Intelligence is reading the emails that matter.
        case reading
    }

    /// The mailbox being scanned.
    var account: String?
    var stage: Stage
    var done = 0
    var total = 0
}

/// What a scan looked at, shown after it finishes so it's clear it went beyond a few emails.
struct ScanSummary: Equatable {
    /// Billing-like emails found by the search in the last 13 months.
    var checked = 0
    /// Ads, newsletters, shipping and security notices, recognized from sender and subject.
    var skippedNotBilling = 0
    /// Older copies of the same receipt or bill (only the newest are read).
    var skippedRepeats = 0
    /// Emails Apple Intelligence actually read.
    var read = 0

    static func + (lhs: ScanSummary, rhs: ScanSummary) -> ScanSummary {
        ScanSummary(checked: lhs.checked + rhs.checked,
                    skippedNotBilling: lhs.skippedNotBilling + rhs.skippedNotBilling,
                    skippedRepeats: lhs.skippedRepeats + rhs.skippedRepeats,
                    read: lhs.read + rhs.read)
    }

    var dictionary: [String: Int] {
        ["checked": checked, "notBilling": skippedNotBilling, "repeats": skippedRepeats, "read": read]
    }

    init(checked: Int = 0, skippedNotBilling: Int = 0, skippedRepeats: Int = 0, read: Int = 0) {
        self.checked = checked
        self.skippedNotBilling = skippedNotBilling
        self.skippedRepeats = skippedRepeats
        self.read = read
    }

    init?(dictionary: [String: Int]?) {
        guard let dictionary, let checked = dictionary["checked"] else { return nil }
        self.init(checked: checked,
                  skippedNotBilling: dictionary["notBilling"] ?? 0,
                  skippedRepeats: dictionary["repeats"] ?? 0,
                  read: dictionary["read"] ?? 0)
    }
}

@MainActor
@Observable
final class EmailImportModel {
    /// Shared so Settings and the import screen show the same connection and scan state.
    static let shared = EmailImportModel()

    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case review([DetectedSubscription])
        case failed(String)
    }

    /// Billing-like emails checked per account (by sender and subject only), newest first.
    /// Covers the 13-month search window for almost any inbox.
    static let searchLimit = 500
    /// Most emails Apple Intelligence reads per account, after ads, newsletters and repeats are
    /// skipped. Keeps a scan to a few minutes.
    static let readLimit = 150
    /// Keeps a scan to a reasonable length.
    static let maxAccounts = 5

    /// Connected addresses, in the order they were added.
    private(set) var connectedEmails: [String] = []
    private(set) var isConnecting = false
    private(set) var phase: Phase = .idle
    private(set) var connectionError: String?
    /// Accounts that couldn't be read during the last scan, with the reason.
    private(set) var accountErrors: [String: String] = [:]
    var aiStatus: AppleIntelligenceStatus = .current

    private var scanTask: Task<Void, Never>?

    init() {
        reloadAccounts()
    }

    var isConnected: Bool { !connectedEmails.isEmpty }
    var canAddAccount: Bool { connectedEmails.count < Self.maxAccounts }

    var isScanning: Bool {
        if case .scanning = phase { true } else { false }
    }

    var lastScan: Date? {
        UserDefaults.standard.object(forKey: EmailImportKeys.lastScan) as? Date
    }

    /// What the last finished scan looked at.
    private(set) var lastSummary: ScanSummary? =
        ScanSummary(dictionary: UserDefaults.standard.dictionary(forKey: EmailImportKeys.lastSummary) as? [String: Int])

    /// The account being scanned right now, if any.
    var scanningAccount: String? {
        if case .scanning(let progress) = phase { progress.account } else { nil }
    }

    func refreshAvailability() {
        aiStatus = .current
    }

    private func reloadAccounts() {
        connectedEmails = GmailAuth.storedAccounts().compactMap(\.email)
    }

    // MARK: Connect

    /// Opens Google's sign-in in a private browser session, then saves the tokens to the Keychain.
    /// Connecting an address that's already connected just refreshes its sign-in.
    /// Returns the connected address.
    @discardableResult
    func connect(using session: WebAuthenticationSession) async -> String? {
        guard !isConnecting else { return nil }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            let request = try GmailAuth.makeAuthorizationRequest()
            let callback = try await session.authenticate(
                using: request.url,
                callbackURLScheme: GmailConfiguration.redirectScheme,
                preferredBrowserSession: .ephemeral
            )
            let code = try GmailAuth.authorizationCode(from: callback, expectedState: request.state)
            var tokens = try await GmailAuth.exchange(code: code, codeVerifier: request.codeVerifier)
            let email = try await GmailAPI(accessToken: tokens.accessToken).emailAddress()
            tokens.email = email

            let isNew = !connectedEmails.contains { $0.caseInsensitiveCompare(email) == .orderedSame }
            guard !isNew || canAddAccount else {
                await GmailAuth.revoke(token: tokens.refreshToken ?? tokens.accessToken)
                connectionError = String(localized: "You can connect up to \(Self.maxAccounts) accounts. Disconnect one to add another.")
                return nil
            }
            try GmailAuth.store(tokens)
            accountErrors[email] = nil
            reloadAccounts()
            return email
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return nil
        } catch {
            connectionError = Self.message(for: error)
            return nil
        }
    }

    /// Revokes the app's access to one account on Google's side and deletes its tokens from this device.
    func disconnect(email: String) async {
        if isScanning { cancelScan() }
        let tokens = GmailAuth.storedTokens(for: email)
        GmailAuth.deleteStoredTokens(for: email)
        accountErrors[email] = nil
        reloadAccounts()
        if !isConnected {
            UserDefaults.standard.removeObject(forKey: EmailImportKeys.lastScan)
            UserDefaults.standard.removeObject(forKey: EmailImportKeys.lastSummary)
            lastSummary = nil
            phase = .idle
        }
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            await GmailAuth.revoke(token: token)
        }
    }

    /// Disconnects every account (used by Reset).
    func disconnectAll() async {
        cancelScan()
        let accounts = GmailAuth.storedAccounts()
        GmailAuth.deleteAllStoredTokens()
        UserDefaults.standard.removeObject(forKey: EmailImportKeys.lastScan)
        UserDefaults.standard.removeObject(forKey: EmailImportKeys.lastSummary)
        lastSummary = nil
        accountErrors = [:]
        connectedEmails = []
        phase = .idle
        for tokens in accounts {
            await GmailAuth.revoke(token: tokens.refreshToken ?? tokens.accessToken)
        }
    }

    // MARK: Scan

    /// Scans every connected account, or only `accounts` when given.
    func startScan(existing: [Subscription], accounts: [String]? = nil) {
        guard !isScanning else { return }
        refreshAvailability()
        guard aiStatus == .available else {
            phase = .failed(aiStatus.message.map { String(localized: $0) } ?? "")
            return
        }
        let targets = accounts ?? connectedEmails
        guard !targets.isEmpty else { return }
        // Services already set up are skipped; ones still in "Needs Setup" can be completed.
        let existingKeys = Set(existing.filter { !$0.needsSetup }.map { DetectedSubscription.matchKey($0.name) })
        scanTask = Task { await scan(accounts: targets, skipping: existingKeys) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { phase = .idle }
    }

    func dismissReview() {
        phase = .idle
    }

    private func scan(accounts: [String], skipping existingKeys: Set<String>) async {
        phase = .scanning(ScanProgress(account: accounts.first, stage: .searching))
        accountErrors = [:]
        let extractor = SubscriptionExtractor()
        // Loads the on-device model while the first network requests run.
        extractor.prewarm()
        var found: [DetectedSubscription] = []
        var summary = ScanSummary()
        var scannedAny = false

        for account in accounts {
            var didRefresh = false
            do {
                phase = .scanning(ScanProgress(account: account, stage: .searching))
                let auth = try await validAccessToken(for: account)
                didRefresh = auth.refreshed
                let result = try await scanAccount(account, accessToken: auth.token, extractor: extractor)
                found += result.found
                summary = summary + result.summary
                scannedAny = true
            } catch is CancellationError {
                phase = .idle
                scanTask = nil
                return
            } catch GmailAuthError.signedOut where !didRefresh {
                // Access token may have been invalidated early (HTTP 401); try refreshing once before signing out.
                do {
                    let auth = try await validAccessToken(for: account, forceRefresh: true)
                    let result = try await scanAccount(account, accessToken: auth.token, extractor: extractor)
                    found += result.found
                    summary = summary + result.summary
                    scannedAny = true
                } catch is CancellationError {
                    phase = .idle
                    scanTask = nil
                    return
                } catch GmailAuthError.signedOut {
                    GmailAuth.deleteStoredTokens(for: account)
                    reloadAccounts()
                    accountErrors[account] = GmailAuthError.signedOut.errorDescription ?? ""
                } catch {
                    accountErrors[account] = Self.message(for: error)
                }
            } catch GmailAuthError.signedOut {
                // Refresh token expired or was revoked: drop this account, keep scanning the others.
                GmailAuth.deleteStoredTokens(for: account)
                reloadAccounts()
                accountErrors[account] = GmailAuthError.signedOut.errorDescription ?? ""
            } catch {
                accountErrors[account] = Self.message(for: error)
            }
        }

        if scannedAny {
            let candidates = DetectedSubscription.merged(found).filter { !existingKeys.contains($0.id) }
            UserDefaults.standard.set(Date.now, forKey: EmailImportKeys.lastScan)
            UserDefaults.standard.set(summary.dictionary, forKey: EmailImportKeys.lastSummary)
            lastSummary = summary
            phase = .review(candidates)
        } else {
            phase = .failed(accountErrors.values.first ?? String(localized: "Something went wrong. Try again."))
        }
        scanTask = nil
    }

    /// 1. Search: every billing-like email of the last 13 months (IDs only).
    /// 2. Filter: fetch just sender and subject, skip ads, newsletters, shipping, security notices
    ///    and older repeats of the same receipt.
    /// 3. Read: only what's left is downloaded in full and read by Apple Intelligence.
    private func scanAccount(
        _ account: String,
        accessToken: String,
        extractor: SubscriptionExtractor
    ) async throws -> (found: [DetectedSubscription], summary: ScanSummary) {
        let api = GmailAPI(accessToken: accessToken)

        let ids = try await api.searchMessageIDs(limit: Self.searchLimit)
        try Task.checkCancellation()

        phase = .scanning(ScanProgress(account: account, stage: .filtering, done: 0, total: ids.count))
        let headers = try await api.metadata(for: ids) { [weak self] done in
            await self?.updateFiltering(account: account, done: done, total: ids.count)
        }
        try Task.checkCancellation()

        let billing = headers.filter { BillingEmailFilter.verdict(for: $0) == .billing }
        let selection = BillingEmailFilter.selectForReading(billing, limit: Self.readLimit)
        var summary = ScanSummary(
            checked: ids.count,
            skippedNotBilling: headers.count - billing.count,
            skippedRepeats: selection.repeats,
            read: 0
        )

        let toRead = selection.selected
        phase = .scanning(ScanProgress(account: account, stage: .reading, done: 0, total: toRead.count))
        var accountFound: [DetectedSubscription] = []
        for (index, item) in toRead.enumerated() {
            try Task.checkCancellation()
            // Each email is fetched, read and dropped before the next one.
            let email = try await api.message(id: item.id)
            if let analysis = await extractor.analyze(email),
               let candidate = DetectedSubscription(analysis: analysis, email: email, account: account) {
                accountFound.append(candidate)
            }
            summary.read = index + 1
            phase = .scanning(ScanProgress(account: account, stage: .reading, done: index + 1, total: toRead.count))
        }
        return (accountFound, summary)
    }

    private func updateFiltering(account: String, done: Int, total: Int) {
        guard isScanning else { return }
        phase = .scanning(ScanProgress(account: account, stage: .filtering, done: done, total: total))
    }

    private func validAccessToken(for account: String, forceRefresh: Bool = false) async throws -> (token: String, refreshed: Bool) {
        guard var tokens = GmailAuth.storedTokens(for: account) else { throw GmailAuthError.signedOut }
        if forceRefresh || tokens.isExpired {
            tokens = try await GmailAuth.refreshed(tokens)
            try GmailAuth.store(tokens)
            return (tokens.accessToken, true)
        }
        return (tokens.accessToken, false)
    }

    // MARK: Add

    /// Adds the chosen candidates. A matching subscription still in "Needs Setup" is completed
    /// instead of duplicated. Returns how many were added or completed.
    @discardableResult
    func add(_ candidates: [DetectedSubscription], existing: [Subscription], into context: ModelContext) -> Int {
        var pendingByKey: [String: Subscription] = [:]
        for subscription in existing where subscription.needsSetup {
            pendingByKey[DetectedSubscription.matchKey(subscription.name)] = subscription
        }

        for candidate in candidates {
            if let pending = pendingByKey[candidate.id] {
                if let price = candidate.price { pending.price = price }
                pending.cycle = candidate.cycle
                pending.anchorDate = candidate.paymentDate
                if pending.category == .other { pending.category = candidate.category }
                if pending.sourceAccount == nil { pending.sourceAccount = candidate.sourceAccount }
            } else {
                context.insert(Subscription(
                    name: candidate.name,
                    price: candidate.price ?? 0,
                    cycle: candidate.cycle,
                    category: candidate.category,
                    anchorDate: candidate.paymentDate,
                    sourceAccount: candidate.sourceAccount
                ))
            }
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Import failed: \(error)")
        }
        phase = .idle
        return candidates.count
    }

    // MARK: Errors

    private static func message(for error: Error) -> String {
        if let error = error as? GmailAuthError { return error.errorDescription ?? "" }
        if error is URLError { return GmailAuthError.server("").errorDescription ?? "" }
        return String(localized: "Something went wrong. Try again.")
    }
}
