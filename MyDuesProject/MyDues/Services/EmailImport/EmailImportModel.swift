//
//  EmailImportModel.swift
//  MyDues
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
import UIKit
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
        /// Downloading the emails that matter (and reading pagoPA QR codes). Works in the background.
        case downloading
        /// Apple Intelligence is reading them. Only while the app is open.
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

/// Everything a scan found that isn't in the app yet, for the review screen.
struct ScanResults: Equatable {
    var subscriptions: [DetectedSubscription] = []
    var purchases: [DetectedPurchase] = []
    var notices: [DetectedNotice] = []
    /// Why fewer emails than usual were read (iOS paused Apple Intelligence), if that happened.
    var warning: String? = nil

    var isEmpty: Bool { subscriptions.isEmpty && purchases.isEmpty && notices.isEmpty }
    var count: Int { subscriptions.count + purchases.count + notices.count }
}

@MainActor
@Observable
final class EmailImportModel {
    /// Shared so Settings and the import screen show the same connection and scan state.
    static let shared = EmailImportModel()

    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case review(ScanResults)
        case failed(String)
    }

    /// Billing-like emails checked per account (by sender and subject only), newest first.
    /// Covers the 13-month search window for almost any inbox.
    static let searchLimit = 500
    /// Emails from `KnownBillingSenders` checked per account, on top of `searchLimit`.
    static let knownSendersSearchLimit = 200
    /// Most emails Apple Intelligence reads per account, after ads, newsletters and repeats are
    /// skipped. Keeps a scan to a few minutes.
    static let readLimit = 150
    /// Order and delivery emails read per account, for returns and warranties.
    static let ordersReadLimit = 100
    /// pagoPA emails read per account (each may mean downloading a PDF).
    static let noticesReadLimit = 40
    /// Keeps a scan to a reasonable length.
    static let maxAccounts = 5

    /// Connected addresses, in the order they were added.
    private(set) var connectedEmails: [String] = []
    private(set) var isConnecting = false
    private(set) var phase: Phase = .idle
    /// Set for the scan started at the end of onboarding: Home shows its progress and results,
    /// instead of Settings › Import from Email.
    private(set) var presentsResultsOnHome = false
    private(set) var connectionError: String?
    /// Accounts that couldn't be read during the last scan, with the reason.
    private(set) var accountErrors: [String: String] = [:]
    var aiStatus: AppleIntelligenceStatus = .current

    private var scanTask: Task<Void, Never>?
    /// The emails are downloaded and wait for the app to be opened, since Apple Intelligence
    /// can't read them in the background.
    private(set) var isWaitingForForeground = false
    /// The "ready to read" notification is sent once per scan.
    private var didNotifyReadyToRead = false
    /// Settings › Import from Email is on screen (it shows the results itself).
    var isImportScreenVisible = false
    /// For the Live Activity: which account of how many, and how much was found so far.
    private var accountIndex = 0
    private var accountCount = 1
    private var foundSoFar = 0
    /// Extra time iOS grants if the user leaves the app mid-scan.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

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

    /// Home shows the onboarding scan while it runs or after it failed.
    var showsScanOnHome: Bool {
        guard presentsResultsOnHome else { return false }
        switch phase {
        case .scanning, .failed: return true
        default: return false
        }
    }

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
                connectionError = String(appLocalized: "You can connect up to \(Self.maxAccounts) accounts. Disconnect one to add another.")
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
    func startScan(existing: [Subscription], accounts: [String]? = nil, presentResultsOnHome: Bool = false) {
        guard !isScanning else { return }
        presentsResultsOnHome = presentResultsOnHome
        refreshAvailability()
        guard aiStatus == .available else {
            phase = .failed(aiStatus.message.map { String(appLocalizedResource: $0) } ?? "")
            return
        }
        let targets = accounts ?? connectedEmails
        guard !targets.isEmpty else { return }
        // Services already set up are skipped; ones still in "Needs Setup" can be completed.
        let existingKeys = existing.filter { !$0.needsSetup }.map(\.name)
        let known = KnownItems(context: Persistence.container.mainContext)
        isWaitingForForeground = false
        didNotifyReadyToRead = false
        ScanPacing.reset()
        // Keeps going if the user switches app, with a Live Activity showing the progress.
        ScanBackgroundActivity.shared.begin(subtitle: String(appLocalized: "Searching the last 13 months…"))
        // The notification when it's done is the natural moment to ask (first time only).
        Task { await NotificationService.requestAuthorizationIfNeeded() }
        scanTask = Task { await scan(accounts: targets, skipping: existingKeys, known: known) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        ScanBackgroundActivity.shared.end(success: false)
        if isScanning { phase = .idle }
        presentsResultsOnHome = false
    }

    /// A tap on the "finished" notification: shows the results on Home unless the import screen
    /// that started the scan is open and shows them itself.
    func revealResults() {
        guard case .review = phase, !isImportScreenVisible else { return }
        presentsResultsOnHome = true
    }

    func setWaitingForForeground(_ waiting: Bool) {
        guard waiting != isWaitingForForeground else { return }
        isWaitingForForeground = waiting
        if waiting, !didNotifyReadyToRead {
            didNotifyReadyToRead = true
            ScanBackgroundActivity.shared.notifyReadyToRead()
        }
        if case .scanning(let progress) = phase { report(progress) }
    }

    /// Updates the screen and the Live Activity.
    private func report(_ progress: ScanProgress) {
        phase = .scanning(progress)
        let ratio = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
        // First half: every account's search and download. Second half: reading them all.
        let fraction: Double = switch progress.stage {
        case .searching: (Double(accountIndex) + 0.02) / Double(max(accountCount, 1)) * 0.5
        case .filtering: (Double(accountIndex) + 0.05 + 0.15 * ratio) / Double(max(accountCount, 1)) * 0.5
        case .downloading: (Double(accountIndex) + 0.2 + 0.8 * ratio) / Double(max(accountCount, 1)) * 0.5
        case .reading: 0.5 + 0.5 * ratio
        }
        let subtitle: String
        if isWaitingForForeground {
            subtitle = String(appLocalized: "Emails downloaded: open \(AppInfo.name) to read them")
        } else {
            switch progress.stage {
            case .searching:
                subtitle = String(appLocalized: "Searching the last 13 months…")
            case .filtering:
                subtitle = String(appLocalized: "Checking senders: \(progress.done) of \(progress.total)")
            case .downloading:
                subtitle = String(appLocalized: "Downloading \(progress.done) of \(progress.total)")
            case .reading:
                subtitle = String(appLocalized: "Reading \(progress.done) of \(progress.total) · found: \(foundSoFar)")
            }
        }
        ScanBackgroundActivity.shared.update(fraction: fraction, subtitle: subtitle)
    }

    func dismissReview() {
        presentsResultsOnHome = false
        phase = .idle
    }

    /// Orders and notices already in the app, so a new scan doesn't suggest them again.
    struct KnownItems {
        var orderKeys: Set<String> = []
        var noticeNumbers: Set<String> = []

        init(context: ModelContext) {
            for purchase in (try? context.fetch(FetchDescriptor<Purchase>())) ?? [] {
                if let number = purchase.orderNumber, !number.isEmpty {
                    orderKeys.insert("order:" + number.filter { $0.isLetter || $0.isNumber })
                }
                orderKeys.insert("item:" + DetectedSubscription.matchKey(purchase.store) + "|" + DetectedSubscription.matchKey(purchase.title))
            }
            noticeNumbers = Set(((try? context.fetch(FetchDescriptor<PaymentNotice>())) ?? []).map(\.noticeNumber))
        }
    }

    /// An email downloaded during the first part of a scan, waiting to be read.
    private struct PreparedEmail {
        let account: String
        let route: Route
        let email: EmailMessage
        /// For pagoPA emails: the codes and PDF text, found without Apple Intelligence.
        var notice: PaymentNoticeScanner.Prepared?
    }

    private struct Download {
        var emails: [PreparedEmail] = []
        var summary = ScanSummary()
    }

    private func scan(accounts: [String], skipping existingKeys: [String], known: KnownItems) async {
        accountIndex = 0
        accountCount = accounts.count
        foundSoFar = 0
        report(ScanProgress(account: accounts.first, stage: .searching))
        accountErrors = [:]
        beginKeepingAlive()
        defer { endKeepingAlive() }

        // 1. Search and download every account. Network only, so it carries on in the background.
        var prepared: [PreparedEmail] = []
        var summary = ScanSummary()
        var scannedAny = false
        for (index, account) in accounts.enumerated() {
            accountIndex = index
            do {
                let download = try await downloadAccount(account)
                prepared += download.emails
                summary = summary + download.summary
                scannedAny = true
            } catch is CancellationError {
                finishCancelled()
                return
            } catch GmailAuthError.signedOut {
                // Refresh token expired or was revoked: drop this account, keep scanning the others.
                GmailAuth.deleteStoredTokens(for: account)
                reloadAccounts()
                accountErrors[account] = GmailAuthError.signedOut.errorDescription ?? ""
            } catch {
                accountErrors[account] = Self.message(for: error)
            }
        }

        // 2. Apple Intelligence reads them, only while the app is open.
        var found: [DetectedSubscription] = []
        var foundPurchases: [DetectedPurchase] = []
        var foundNotices: [DetectedNotice] = []
        let subscriptionExtractor = SubscriptionExtractor()
        let purchaseExtractor = PurchaseExtractor()
        var read = 0
        report(ScanProgress(account: nil, stage: .reading, done: 0, total: prepared.count))
        await ScanPacing.waitUntilActive()
        subscriptionExtractor.prewarm()

        for item in prepared {
            if Task.isCancelled {
                finishCancelled()
                return
            }
            if ScanPacing.isRateLimited { break }
            var readAsBilling = false
            switch item.route {
            case .notice(let alsoBilling):
                let notices = await PaymentNoticeScanner.notices(in: item.email, prepared: item.notice ?? .init(codes: [], text: ""),
                                                                 account: item.account)
                foundNotices += notices
                readAsBilling = notices.isEmpty && alsoBilling
            case .order(let alsoBilling):
                if let analysis = await purchaseExtractor.analyze(item.email),
                   let candidate = DetectedPurchase(analysis: analysis, email: item.email, account: item.account) {
                    foundPurchases.append(candidate)
                } else {
                    readAsBilling = alsoBilling
                }
            case .billing:
                readAsBilling = true
            }
            if readAsBilling, !ScanPacing.isRateLimited,
               let analysis = await subscriptionExtractor.analyze(item.email),
               let candidate = DetectedSubscription(analysis: analysis, email: item.email, account: item.account) {
                found.append(candidate)
            }
            if !ScanPacing.isRateLimited { read += 1 }
            foundSoFar = found.count + foundPurchases.count + foundNotices.count
            report(ScanProgress(account: item.account, stage: .reading, done: read, total: prepared.count))
        }
        summary.read = read
        // Shown with the results when iOS stopped Apple Intelligence before every email was read.
        let warning = ScanPacing.isRateLimited
            ? Self.rateLimitMessage(read: read, total: prepared.count, until: ScanPacing.rateLimitResetDate)
            : nil

        if scannedAny {
            let results = ScanResults(
                subscriptions: DetectedSubscription.merged(found).filter { candidate in
                    !existingKeys.contains { candidate.matches(serviceName: $0) }
                },
                // Only orders that can still be returned or are still under warranty.
                purchases: DetectedPurchase.merged(foundPurchases).filter {
                    !known.orderKeys.contains($0.id)
                        && WarrantyPolicy.until(orderDate: $0.orderDate, deliveryDate: $0.deliveryDate) >= Calendar.current.startOfDay(for: .now)
                },
                notices: DetectedNotice.merged(foundNotices).filter { !known.noticeNumbers.contains($0.id) },
                warning: warning
            )
            UserDefaults.standard.set(Date.now, forKey: EmailImportKeys.lastScan)
            UserDefaults.standard.set(summary.dictionary, forKey: EmailImportKeys.lastSummary)
            lastSummary = summary
            phase = .review(results)
            ScanBackgroundActivity.shared.end(success: true, subtitle: results.isEmpty
                ? String(appLocalized: "Nothing new was found.")
                : String(appLocalized: "Found: \(results.count). Open \(AppInfo.name) to review."))
            ScanBackgroundActivity.shared.notifyFinished(results)
        } else {
            phase = .failed(accountErrors.values.first ?? String(appLocalized: "Something went wrong. Try again."))
            ScanBackgroundActivity.shared.end(success: false)
        }
        isWaitingForForeground = false
        scanTask = nil
    }

    private func finishCancelled() {
        phase = .idle
        scanTask = nil
        isWaitingForForeground = false
        ScanBackgroundActivity.shared.end(success: false)
    }

    private static func rateLimitMessage(read: Int, total: Int, until: Date?) -> String {
        if let until, until > .now {
            let time = until.formatted(.dateTime.hour().minute().locale(LocalizedBundle.locale))
            return String(appLocalized: "iOS has paused Apple Intelligence for \(AppInfo.name) until \(time). \(read) of \(total) emails were read: scan again later to read the rest.")
        }
        return String(appLocalized: "iOS has paused Apple Intelligence for \(AppInfo.name) for a while. \(read) of \(total) emails were read: scan again later to read the rest.")
    }

    /// What an email is read as. pagoPA first (a notice beats a recurring tax), then orders,
    /// then recurring payments; each falls back to the next if it finds nothing.
    private enum Route {
        case notice(alsoBilling: Bool)
        case order(alsoBilling: Bool)
        case billing
    }

    /// 1. Search: billing-like, known-subscription-sender, order and pagoPA emails of the last
    ///    13 months (IDs only).
    /// 2. Filter: fetch just sender and subject, skip ads, newsletters, security notices, review
    ///    requests and older repeats of the same receipt or order.
    /// 3. Download: only what's left, in full; the PDFs of pagoPA emails are scanned for their
    ///    QR code. Apple Intelligence reads them afterwards (`scan`).
    /// Every step is network or Vision only, so it keeps going in the background.
    private func downloadAccount(_ account: String) async throws -> Download {
        func api(forceRefresh: Bool = false) async throws -> GmailAPI {
            // A long scan can outlast Google's one-hour access token: refresh it when needed.
            GmailAPI(accessToken: try await validAccessToken(for: account, forceRefresh: forceRefresh).token)
        }
        /// One Gmail call: a fresh token after a 401, another try after the app comes back to the
        /// foreground if iOS suspended it mid-request.
        func call<T>(_ request: (GmailAPI) async throws -> T) async throws -> T {
            try await ScanPacing.retryingInForeground {
                do {
                    return try await request(try await api())
                } catch GmailAuthError.signedOut {
                    return try await request(try await api(forceRefresh: true))
                }
            }
        }

        report(ScanProgress(account: account, stage: .searching))
        let billingIDs = try await call { try await $0.searchMessageIDs(limit: Self.searchLimit) }
        try Task.checkCancellation()
        let knownIDs = try await call { try await $0.searchMessageIDs(query: GmailAPI.knownSendersQuery, limit: Self.knownSendersSearchLimit) }
        try Task.checkCancellation()
        let orderIDs = try await call { try await $0.searchMessageIDs(query: GmailAPI.ordersQuery, limit: Self.searchLimit) }
        try Task.checkCancellation()
        let noticeIDs = try await call { try await $0.searchMessageIDs(query: GmailAPI.pagoPAQuery, limit: Self.noticesReadLimit * 2) }
        try Task.checkCancellation()

        // Newest first, each email once.
        var seen = Set<String>()
        let ids = (billingIDs + knownIDs + orderIDs + noticeIDs).filter { seen.insert($0).inserted }

        report(ScanProgress(account: account, stage: .filtering, done: 0, total: ids.count))
        let headers = try await call { api in
            try await api.metadata(for: ids) { [weak self] done in
                await self?.updateFiltering(account: account, done: done, total: ids.count)
            }
        }
        try Task.checkCancellation()

        let orderSet = Set(orderIDs)
        let noticeSet = Set(noticeIDs)
        let billing = headers.filter { BillingEmailFilter.verdict(for: $0) == .billing }
        let selection = BillingEmailFilter.selectForReading(billing, limit: Self.readLimit)
        let billingSelected = Set(selection.selected.map(\.id))
        let orders = PurchaseEmailFilter.selectForReading(headers.filter { orderSet.contains($0.id) && !noticeSet.contains($0.id) },
                                                          limit: Self.ordersReadLimit)
        let notices = headers.filter { noticeSet.contains($0.id) }
            .sorted { $0.date > $1.date }
            .prefix(Self.noticesReadLimit)

        var routes: [(id: String, route: Route)] = []
        var routed = Set<String>()
        for item in notices where routed.insert(item.id).inserted {
            routes.append((item.id, .notice(alsoBilling: billingSelected.contains(item.id))))
        }
        for item in orders where routed.insert(item.id).inserted {
            routes.append((item.id, .order(alsoBilling: billingSelected.contains(item.id))))
        }
        for item in selection.selected where routed.insert(item.id).inserted {
            routes.append((item.id, .billing))
        }

        var download = Download()
        download.summary = ScanSummary(
            checked: ids.count,
            skippedNotBilling: max(0, headers.count - billing.count - orders.count - notices.count),
            skippedRepeats: selection.repeats,
            read: 0
        )

        report(ScanProgress(account: account, stage: .downloading, done: 0, total: routes.count))
        var unreadable = 0
        var consecutiveFailures = 0
        var processed = 0
        var connectionLost = false

        for (id, route) in routes {
            try Task.checkCancellation()
            do {
                let email = try await call { try await $0.message(id: id) }
                consecutiveFailures = 0
                var item = PreparedEmail(account: account, route: route, email: Self.compact(email))
                if case .notice = route {
                    let pdfs = await (try? api())?.pdfs(of: email, maxBytes: PaymentNoticeScanner.maxAttachmentBytes) ?? []
                    item.notice = await PaymentNoticeScanner.prepare(email, pdfs: pdfs)
                }
                download.emails.append(item)
            } catch is CancellationError {
                throw CancellationError()
            } catch GmailAuthError.signedOut {
                throw GmailAuthError.signedOut
            } catch {
                // One email that can't be fetched is skipped. Several in a row: the connection is gone.
                unreadable += 1
                consecutiveFailures += 1
                if consecutiveFailures >= 5 {
                    connectionLost = true
                    processed += 1
                    break
                }
            }
            processed += 1
            report(ScanProgress(account: account, stage: .downloading, done: processed, total: routes.count))
        }

        // What was downloaded is always read; the account row explains what's missing.
        if connectionLost {
            accountErrors[account] = String(appLocalized: "The connection dropped after \(processed) of \(routes.count) emails. What was found so far is shown; scan again to finish.")
        } else if unreadable > 0 {
            accountErrors[account] = String(appLocalized: "^[\(unreadable) email](inflect: true) couldn't be read and was skipped.")
        }
        return download
    }

    /// Keeps only what the model reads (the start and the end of long emails), so hundreds of
    /// downloaded emails don't weigh on memory while they wait to be read.
    private static func compact(_ email: EmailMessage) -> EmailMessage {
        guard email.body.count > 8000 else { return email }
        let body = "\(email.body.prefix(5600))\n...\n\(email.body.suffix(2400))"
        return EmailMessage(id: email.id, from: email.from, subject: email.subject, date: email.date,
                            body: body, attachments: email.attachments)
    }

    /// Keeps the screen on during a scan (a locked phone drops network connections) and asks
    /// iOS for extra time if the user switches apps.
    private func beginKeepingAlive() {
        UIApplication.shared.isIdleTimerDisabled = true
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Email scan") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
    }

    private func endKeepingAlive() {
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func updateFiltering(account: String, done: Int, total: Int) {
        guard isScanning else { return }
        report(ScanProgress(account: account, stage: .filtering, done: done, total: total))
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

    /// Adds the chosen subscriptions, orders and notices. Returns how many were added or completed.
    @discardableResult
    func add(_ results: ScanResults, existing: [Subscription], into context: ModelContext) -> Int {
        for candidate in results.purchases {
            context.insert(Purchase(
                title: candidate.title,
                store: candidate.store,
                orderNumber: candidate.orderNumber,
                orderDate: candidate.orderDate,
                deliveryDate: candidate.deliveryDate,
                price: candidate.price ?? 0,
                statedReturnBy: candidate.statedReturnBy,
                sourceAccount: candidate.sourceAccount,
                websiteDomain: candidate.websiteDomain
            ))
        }
        for candidate in results.notices {
            context.insert(PaymentNotice(
                code: candidate.code,
                payee: candidate.payee,
                amount: candidate.amount ?? 0,
                dueDate: candidate.dueDate,
                reason: candidate.reason,
                sourceAccount: candidate.sourceAccount
            ))
        }
        let added = add(results.subscriptions, existing: existing, into: context)
        if !results.purchases.isEmpty || !results.notices.isEmpty {
            // Return, warranty and notice reminders are on by default.
            Task { await NotificationService.requestAuthorizationIfNeeded() }
        }
        return added + results.purchases.count + results.notices.count
    }

    /// Adds the chosen candidates. A matching subscription still in "Needs Setup" is completed
    /// instead of duplicated. Returns how many were added or completed.
    @discardableResult
    func add(_ candidates: [DetectedSubscription], existing: [Subscription], into context: ModelContext) -> Int {
        // Still in "Needs Setup", or added since the scan started (another device, a double tap).
        let pendingOrNew = existing.filter(\.needsSetup)
        let configured = existing.filter { !$0.needsSetup }
        var addedNow: [Subscription] = []

        for candidate in candidates {
            if configured.contains(where: { candidate.matches(serviceName: $0.name) })
                || addedNow.contains(where: { candidate.matches(serviceName: $0.name) }) {
                continue
            }
            if let pending = pendingOrNew.first(where: { candidate.matches(serviceName: $0.name) }) {
                if let price = candidate.price { pending.price = price }
                pending.cycle = candidate.cycle
                pending.anchorDate = candidate.paymentDate
                if let trialEnd = candidate.trialEndDate { pending.trialEndDate = trialEnd }
                if pending.category == .other { pending.category = candidate.category }
                if pending.sourceAccount == nil { pending.sourceAccount = candidate.sourceAccount }
                if pending.websiteDomain == nil { pending.websiteDomain = candidate.senderDomain }
            } else {
                let subscription = Subscription(
                    name: candidate.name,
                    price: candidate.price ?? 0,
                    cycle: candidate.cycle,
                    category: candidate.category,
                    anchorDate: candidate.paymentDate,
                    sourceAccount: candidate.sourceAccount
                )
                subscription.websiteDomain = candidate.senderDomain
                subscription.trialEndDate = candidate.trialEndDate
                context.insert(subscription)
                addedNow.append(subscription)
            }
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Import failed: \(error)")
        }
        phase = .idle
        presentsResultsOnHome = false
        return candidates.count
    }

    // MARK: Errors

    private static func message(for error: Error) -> String {
        if let error = error as? GmailAuthError { return error.errorDescription ?? "" }
        if error is URLError { return GmailAuthError.server("").errorDescription ?? "" }
        return String(appLocalized: "Something went wrong. Try again.")
    }
}
