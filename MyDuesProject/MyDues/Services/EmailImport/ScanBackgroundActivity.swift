//
//  ScanBackgroundActivity.swift
//  MyDues
//
//  Keeps an email scan running when the user switches to another app, with iOS 26's continued
//  processing tasks: the system shows the scan's progress in a Live Activity (Dynamic Island and
//  Lock Screen). In the background the scan only searches and downloads: iOS rate-limits Apple
//  Intelligence for background apps (sometimes for hours, and then in the foreground too), so
//  emails are read only while the app is open. Notifications say when the emails are ready to
//  read and when the scan is done.
//

import BackgroundTasks
import Foundation
import FoundationModels
import OSLog
import UIKit
import UserNotifications

@MainActor
final class ScanBackgroundActivity {
    static let shared = ScanBackgroundActivity()

    /// Listed in Info.plist › BGTaskSchedulerPermittedIdentifiers as `<prefix>.*`.
    static var identifierPrefix: String { (Bundle.main.bundleIdentifier ?? "MyDues") + ".emailScan" }

    private var task: BGContinuedProcessingTask?
    /// Last state sent, re-applied when the task starts a moment after being submitted.
    private var fraction: Double = 0
    private var subtitle = ""

    private static let units: Int64 = 1000

    /// Asks iOS to keep the scan running in the background. Must be called right after the user
    /// starts a scan, while the app is in front.
    func begin(subtitle: String) {
        end(success: false)
        guard UIApplication.shared.applicationState == .active else { return }
        self.fraction = 0
        self.subtitle = subtitle

        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString.prefix(8))"
        // Continued processing tasks may be registered after launch, once per identifier.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(task)
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: Self.title, subtitle: subtitle)
        // Starts now or not at all: a scan queued for later would surprise the user.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Not fatal: the scan still runs while the app is open.
            Self.log.error("Continued processing task not submitted: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `fraction` from 0 to 1, across every account and stage.
    func update(fraction: Double, subtitle: String) {
        self.fraction = max(self.fraction, min(fraction, 1))
        self.subtitle = subtitle
        apply()
    }

    /// Ends the Live Activity. `subtitle` is shown for a moment before it goes away.
    func end(success: Bool, subtitle: String? = nil) {
        guard let task else { return }
        self.task = nil
        if let subtitle { task.updateTitle(Self.title, subtitle: subtitle) }
        task.progress.completedUnitCount = Self.units
        task.setTaskCompleted(success: success)
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = Self.units
        // Stopped from the Live Activity, or ended by iOS: the scan isn't lost. It carries on while
        // the app can run, and otherwise picks up where it was when the app is opened again.
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                Self.log.info("Continued processing task expired")
                self?.task = nil
            }
        }
        apply()
    }

    private func apply() {
        guard let task else { return }
        task.progress.completedUnitCount = Int64(fraction * Double(Self.units))
        task.updateTitle(Self.title, subtitle: subtitle)
    }

    private static var title: String { String(appLocalized: "Searching Your Email") }

    nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MyDues", category: "EmailScan")

    // MARK: Notifications

    static let finishedNotificationID = "email-scan-finished"
    static let pausedNotificationID = "email-scan-paused"

    /// Only when the user is in another app: otherwise the results are already on screen.
    func notifyFinished(_ results: ScanResults) {
        guard UIApplication.shared.applicationState != .active else { return }
        let body: String
        if results.isEmpty {
            body = String(appLocalized: "Nothing new was found.")
        } else {
            var parts: [String] = []
            if !results.subscriptions.isEmpty {
                parts.append(String(appLocalized: "^[\(results.subscriptions.count) subscription](inflect: true)"))
            }
            if !results.purchases.isEmpty {
                parts.append(String(appLocalized: "^[\(results.purchases.count) order](inflect: true)"))
            }
            if !results.notices.isEmpty {
                parts.append(String(appLocalized: "^[\(results.notices.count) pagoPA notice](inflect: true)"))
            }
            let list = parts.formatted(.list(type: .and).locale(LocalizedBundle.locale))
            body = String(appLocalized: "Found \(list). Tap to review them.")
        }
        post(id: Self.finishedNotificationID, title: String(appLocalized: "Email Search Finished"), body: body)
    }

    /// The emails are downloaded and wait for the app to be opened to be read.
    func notifyReadyToRead() {
        guard UIApplication.shared.applicationState != .active else { return }
        post(id: Self.pausedNotificationID,
             title: String(appLocalized: "Emails Ready to Read"),
             body: String(appLocalized: "Open \(AppInfo.name) to let Apple Intelligence read them: iOS doesn't allow it while the app is in the background."))
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "email-scan"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Apple Intelligence requests

/// One on-device model request: a shorter prompt after a context overflow; only while the app
/// is open (iOS rate-limits background apps); a few short retries if it's rate-limited anyway,
/// then the scan is told to stop reading instead of skipping every email silently.
nonisolated enum OnDeviceModel {
    static func respond<Content: Generable>(
        instructions: String,
        prompts: [String],
        generating type: Content.Type
    ) async -> Content? {
        var index = 0
        var retries = 0
        while index < prompts.count, !Task.isCancelled {
            await ScanPacing.waitUntilActive()
            if await ScanPacing.isRateLimited { return nil }
            let session = LanguageModelSession(model: .default, instructions: instructions)
            do {
                return try await session.respond(to: prompts[index], generating: type,
                                                 options: GenerationOptions(samplingMode: .greedy)).content
            } catch {
                if SubscriptionExtractor.isContextOverflow(error) {
                    index += 1
                } else if let limit = rateLimit(error) {
                    if retries < 3 {
                        retries += 1
                        try? await Task.sleep(for: .seconds(2 << retries))   // 4, 8, 16 s
                    } else {
                        ScanBackgroundActivity.log.error("Apple Intelligence rate limited")
                        await ScanPacing.markRateLimited(until: limit.resetDate)
                        return nil
                    }
                } else {
                    ScanBackgroundActivity.log.error("Model request failed: \(String(describing: error), privacy: .public)")
                    return nil
                }
            }
        }
        return nil
    }

    struct RateLimit { var resetDate: Date? }

    /// `nil` when `error` isn't a rate limit (or too many requests at once).
    static func rateLimit(_ error: Error) -> RateLimit? {
        if #available(iOS 27.0, *), let error = error as? LanguageModelError, case .rateLimited(let info) = error {
            return RateLimit(resetDate: info.resetDate)
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests: return RateLimit(resetDate: nil)
            default: return nil
            }
        }
        return nil
    }
}

@MainActor
enum ScanPacing {
    /// Set when iOS keeps refusing Apple Intelligence: the scan stops reading.
    private(set) static var isRateLimited = false
    private(set) static var rateLimitResetDate: Date?

    static func reset() {
        isRateLimited = false
        rateLimitResetDate = nil
    }

    static func markRateLimited(until date: Date?) {
        isRateLimited = true
        rateLimitResetDate = date
    }

    /// Returns at once while the app is open; otherwise waits for the user to come back.
    static func waitUntilActive() async {
        guard UIApplication.shared.applicationState != .active else { return }
        let model = EmailImportModel.shared
        model.setWaitingForForeground(true)
        while UIApplication.shared.applicationState != .active, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
        model.setWaitingForForeground(false)
    }

    /// Network calls made in the background can fail when iOS suspends the app: run `operation`,
    /// and if it fails while the app is in the background, try once more after it's opened again.
    static func retryingInForeground<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GmailAuthError where error == .signedOut {
            throw error
        } catch {
            guard UIApplication.shared.applicationState != .active else { throw error }
            await waitUntilActive()
            return try await operation()
        }
    }
}
