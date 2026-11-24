//
//  EmailImportModel.swift
//  DuelyProject
//
//  Connects one or more Gmail accounts, scans their recent billing emails (subscriptions, bills,
//  taxes, tuition) with Apple Intelligence on the device, and adds the ones the user confirms. Email content only ever lives in memory during a scan:
//  it isn't saved, logged or sent anywhere. What gets saved is just the subscriptions the user
//  chooses to add, like any other subscription in the app.
//

import Foundation
import SwiftData
import SwiftUI
import AuthenticationServices
import Observation

enum EmailImportKeys {
    /// Date of the last finished scan, shown in Settings.
    static let lastScan = "emailImportLastScan"
}

@MainActor
@Observable
final class EmailImportModel {
    /// Shared so Settings and the import screen show the same connection and scan state.
    static let shared = EmailImportModel()

    enum Phase: Equatable {
        case idle
        /// `account` is the mailbox being read right now.
        case scanning(done: Int, total: Int, account: String?)
        case review([DetectedSubscription])
        case failed(String)
    }

    /// Emails read per account and scan, newest first. Enough for a year of receipts without a long wait.
    static let scanLimit = 60
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
        phase = .scanning(done: 0, total: 0, account: accounts.first)
        accountErrors = [:]
        let extractor = SubscriptionExtractor()
        var found: [DetectedSubscription] = []
        var scannedAny = false

        for account in accounts {
            do {
                phase = .scanning(done: 0, total: 0, account: account)
                let api = GmailAPI(accessToken: try await validAccessToken(for: account))
                let ids = try await api.searchMessageIDs(limit: Self.scanLimit)
                phase = .scanning(done: 0, total: ids.count, account: account)

                for (index, id) in ids.enumerated() {
                    try Task.checkCancellation()
                    // Each email is fetched, read and dropped before the next one.
                    let email = try await api.message(id: id)
                    if let analysis = await extractor.analyze(email),
                       let candidate = DetectedSubscription(analysis: analysis, email: email, account: account) {
                        found.append(candidate)
                    }
                    phase = .scanning(done: index + 1, total: ids.count, account: account)
                }
                scannedAny = true
            } catch is CancellationError {
                phase = .idle
                scanTask = nil
                return
            } catch GmailAuthError.signedOut {
                // This account's sign-in expired or was revoked: drop it, keep scanning the others.
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
            phase = .review(candidates)
        } else {
            phase = .failed(accountErrors.values.first ?? String(localized: "Something went wrong. Try again."))
        }
        scanTask = nil
    }

    private func validAccessToken(for account: String) async throws -> String {
        guard var tokens = GmailAuth.storedTokens(for: account) else { throw GmailAuthError.signedOut }
        if tokens.isExpired {
            tokens = try await GmailAuth.refreshed(tokens)
            try GmailAuth.store(tokens)
        }
        return tokens.accessToken
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
