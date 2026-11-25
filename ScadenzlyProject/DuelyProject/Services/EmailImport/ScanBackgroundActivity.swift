//
//  ScanBackgroundActivity.swift
//  DuelyProject
//
//  Keeps an email scan running when the user switches to another app, with iOS 26's continued
//  processing tasks: the system shows the scan's progress in a Live Activity (Dynamic Island and
//  Lock Screen), where it can also be stopped. When it finishes in the background, a notification
//  says what was found. Also paces Apple Intelligence, which iOS may limit for apps in the background.
//

import BackgroundTasks
import Foundation
import FoundationModels
import UIKit
import UserNotifications

@MainActor
final class ScanBackgroundActivity {
    static let shared = ScanBackgroundActivity()

    /// Listed in Info.plist › BGTaskSchedulerPermittedIdentifiers as `<prefix>.*`.
    static var identifierPrefix: String { (Bundle.main.bundleIdentifier ?? "MyDues") + ".emailScan" }

    private var task: BGContinuedProcessingTask?
    private var onStop: (() -> Void)?
    /// Last state sent, re-applied when the task starts a moment after being submitted.
    private var fraction: Double = 0
    private var subtitle = ""

    private static let units: Int64 = 1000

    /// Asks iOS to keep the scan running in the background. Must be called right after the user
    /// starts a scan, while the app is in front. `onStop` runs if the user stops it from the Live
    /// Activity or iOS ends it.
    func begin(subtitle: String, onStop: @escaping () -> Void) {
        end(success: false)
        guard UIApplication.shared.applicationState == .active else { return }
        self.onStop = onStop
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
        try? BGTaskScheduler.shared.submit(request)
    }

    /// `fraction` from 0 to 1, across every account and stage.
    func update(fraction: Double, subtitle: String) {
        self.fraction = max(self.fraction, min(fraction, 1))
        self.subtitle = subtitle
        apply()
    }

    /// Ends the Live Activity. `subtitle` is shown for a moment before it goes away.
    func end(success: Bool, subtitle: String? = nil) {
        onStop = nil
        guard let task else { return }
        self.task = nil
        if let subtitle { task.updateTitle(Self.title, subtitle: subtitle) }
        task.progress.completedUnitCount = Self.units
        task.setTaskCompleted(success: success)
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = Self.units
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let stop = self.onStop
                self.onStop = nil
                self.task = nil
                stop?()
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

    func notifyPaused() {
        guard UIApplication.shared.applicationState != .active else { return }
        post(id: Self.pausedNotificationID,
             title: String(appLocalized: "Email Search Paused"),
             body: String(appLocalized: "iOS is limiting Apple Intelligence while \(AppInfo.name) is in the background. Open the app to finish the search."))
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

/// One on-device model request, robust to the background: a shorter prompt after a context
/// overflow, and waiting (then retrying) when iOS rate-limits the app instead of skipping the email.
nonisolated enum OnDeviceModel {
    /// Rate-limited retries for one email before it's skipped.
    static let maxWaits = 12

    static func respond<Content: Generable>(
        instructions: String,
        prompts: [String],
        generating type: Content.Type
    ) async -> Content? {
        var index = 0
        var waits = 0
        while index < prompts.count, !Task.isCancelled {
            let session = LanguageModelSession(model: .default, instructions: instructions)
            do {
                return try await session.respond(to: prompts[index], generating: type,
                                                 options: GenerationOptions(samplingMode: .greedy)).content
            } catch {
                if SubscriptionExtractor.isContextOverflow(error) {
                    index += 1
                } else if isRateLimited(error), waits < maxWaits {
                    waits += 1
                    await ScanPacing.wait(attempt: waits)
                } else {
                    return nil
                }
            }
        }
        return nil
    }

    static func isRateLimited(_ error: Error) -> Bool {
        if #available(iOS 27.0, *), let error = error as? LanguageModelError, case .rateLimited = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .rateLimited, .concurrentRequests: return true
            default: return false
            }
        }
        return false
    }
}

@MainActor
enum ScanPacing {
    /// A short backoff first; if iOS still says no, the app is likely in the background: wait
    /// until the user opens it again (or stops the scan).
    static func wait(attempt: Int) async {
        if attempt <= 4 {
            try? await Task.sleep(for: .seconds(2 << attempt))   // 4, 8, 16, 32 s
            return
        }
        guard UIApplication.shared.applicationState != .active else {
            try? await Task.sleep(for: .seconds(5))
            return
        }
        let model = EmailImportModel.shared
        model.setWaitingForForeground(true)
        while UIApplication.shared.applicationState != .active, !Task.isCancelled, !model.isStopRequested {
            try? await Task.sleep(for: .seconds(2))
        }
        model.setWaitingForForeground(false)
    }
}
