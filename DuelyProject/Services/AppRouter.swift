//
//  AppRouter.swift
//  DuelyProject
//
//  App-wide navigation state that outside events (notification taps) can change.
//

import SwiftUI
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
