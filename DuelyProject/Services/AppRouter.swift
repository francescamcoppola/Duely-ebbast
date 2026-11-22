//
//  AppRouter.swift
//  DuelyProject
//
//  App-wide navigation state that outside events (notification taps) can change.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var selectedTab: AppTab = .home
    var isCheckInPresented = false

    func handleNotification(identifier: String) {
        if identifier == NotificationIDs.checkIn {
            selectedTab = .home
            isCheckInPresented = true
        } else if identifier.hasPrefix(NotificationIDs.paymentPrefix) {
            selectedTab = .calendar
        }
    }
}

/// Erases everything the user created and sends them back to the first-launch setup.
@MainActor
enum AppReset {
    /// Every preference the app stores. Removing them brings back the defaults of a fresh install.
    static let storedKeys = [
        OnboardingKeys.userName,
        OnboardingKeys.monthlyBudget,
        OnboardingKeys.currencyCode,
        CheckInKeys.enabled,
        CheckInKeys.weekday,
        CheckInKeys.minutes,
        CheckInKeys.skippedWeek,
        CheckInKeys.paymentRemindersEnabled,
        "subscriptionsSort",
    ]

    static func eraseAll(context: ModelContext, defaults: UserDefaults = .standard) async {
        // Delete one by one (not a batch delete) so open @Query views update right away.
        for entry in (try? context.fetch(FetchDescriptor<UsageEntry>())) ?? [] {
            context.delete(entry)
        }
        for subscription in (try? context.fetch(FetchDescriptor<Subscription>())) ?? [] {
            context.delete(subscription)
        }
        try? context.save()

        await NotificationService.reschedule(checkIn: nil, payments: [])
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        storedKeys.forEach(defaults.removeObject(forKey:))
        AppRouter.shared.isCheckInPresented = false
        AppRouter.shared.selectedTab = .home

        // Last: flipping this swaps the tabs for onboarding.
        defaults.set(false, forKey: OnboardingKeys.hasCompleted)
    }
}

/// Receives notification taps (also on a cold launch) and shows banners while the app is open.
/// `nonisolated` + stateless, so it's safely `Sendable` and its conformance isn't tied to the main actor.
nonisolated final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationCoordinator()

    // Completion-handler variants on purpose: the `async` ones, in a nonisolated class, run off the
    // main thread and call UIKit's completion handler from there, which crashes on notification tap.

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        // UIKit delivers taps on the main thread and expects the handler to be called there too.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                AppRouter.shared.handleNotification(identifier: identifier)
            }
            completionHandler()
        } else {
            nonisolated(unsafe) let completion = completionHandler
            DispatchQueue.main.async {
                AppRouter.shared.handleNotification(identifier: identifier)
                completion()
            }
        }
    }
}

/// Sets the notification delegate before launch finishes, so a tap that launched the app is delivered.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        return true
    }
}
