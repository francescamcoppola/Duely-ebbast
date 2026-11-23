//
//  EmailImportModel.swift
//  DuelyProject
//
//  Connects Gmail, scans recent billing emails with Apple Intelligence on the device, and adds
//  the subscriptions the user confirms. Email content only ever lives in memory during a scan:
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
        case scanning(done: Int, total: Int)
        case review([DetectedSubscription])
        case failed(String)
    }

    /// Emails read per scan, newest first. Enough for a year of receipts without a long wait.
    static let scanLimit = 60

    private(set) var connectedEmail: String?
    private(set) var isConnecting = false
    private(set) var phase: Phase = .idle
    private(set) var connectionError: String?
    var aiStatus: AppleIntelligenceStatus = .current

    private var scanTask: Task<Void, Never>?

    init() {
        connectedEmail = GmailAuth.storedTokens()?.email
    }

    var isConnected: Bool { connectedEmail != nil }

    var isScanning: Bool {
        if case .scanning = phase { true } else { false }
    }

    var lastScan: Date? {
        UserDefaults.standard.object(forKey: EmailImportKeys.lastScan) as? Date
    }

    func refreshAvailability() {
        aiStatus = .current
    }

    // MARK: Connect

    /// Opens Google's sign-in in a private browser session, then saves the tokens to the Keychain.
    /// Returns true when the account was connected.
    @discardableResult
    func connect(using session: WebAuthenticationSession) async -> Bool {
        guard !isConnecting else { return false }
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
            tokens.email = try await GmailAPI(accessToken: tokens.accessToken).emailAddress()
            try GmailAuth.store(tokens)
            connectedEmail = tokens.email
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            connectionError = Self.message(for: error)
            return false
        }
    }

    /// Revokes the app's access on Google's side and deletes the tokens from this device.
    func disconnect() async {
        cancelScan()
        let tokens = GmailAuth.storedTokens()
        GmailAuth.deleteStoredTokens()
        UserDefaults.standard.removeObject(forKey: EmailImportKeys.lastScan)
        connectedEmail = nil
        phase = .idle
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            await GmailAuth.revoke(token: token)
        }
    }

    // MARK: Scan

    func startScan(existing: [Subscription]) {
        guard !isScanning else { return }
        refreshAvailability()
        guard aiStatus == .available else {
            phase = .failed(aiStatus.message.map { String(localized: $0) } ?? "")
            return
        }
        // Services already set up are skipped; ones still in "Needs Setup" can be completed.
        let existingKeys = Set(existing.filter { !$0.needsSetup }.map { DetectedSubscription.matchKey($0.name) })
        scanTask = Task { await scan(skipping: existingKeys) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { phase = .idle }
    }

    func dismissReview() {
        phase = .idle
    }

    private func scan(skipping existingKeys: Set<String>) async {
        phase = .scanning(done: 0, total: 0)
        do {
            let api = GmailAPI(accessToken: try await validAccessToken())
            let ids = try await api.searchMessageIDs(limit: Self.scanLimit)
            phase = .scanning(done: 0, total: ids.count)

            let extractor = SubscriptionExtractor()
            var found: [DetectedSubscription] = []
            for (index, id) in ids.enumerated() {
                try Task.checkCancellation()
                // Each email is fetched, read and dropped before the next one.
                let email = try await api.message(id: id)
                if let analysis = await extractor.analyze(email),
                   let candidate = DetectedSubscription(analysis: analysis, email: email) {
                    found.append(candidate)
                }
                phase = .scanning(done: index + 1, total: ids.count)
            }

            let candidates = DetectedSubscription.merged(found).filter { !existingKeys.contains($0.id) }
            UserDefaults.standard.set(Date.now, forKey: EmailImportKeys.lastScan)
            phase = .review(candidates)
        } catch is CancellationError {
            phase = .idle
        } catch GmailAuthError.signedOut {
            GmailAuth.deleteStoredTokens()
            connectedEmail = nil
            phase = .failed(GmailAuthError.signedOut.errorDescription ?? "")
        } catch {
            phase = .failed(Self.message(for: error))
        }
        scanTask = nil
    }

    private func validAccessToken() async throws -> String {
        guard var tokens = GmailAuth.storedTokens() else { throw GmailAuthError.signedOut }
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
            } else {
                context.insert(Subscription(
                    name: candidate.name,
                    price: candidate.price ?? 0,
                    cycle: candidate.cycle,
                    category: candidate.category,
                    anchorDate: candidate.paymentDate
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
