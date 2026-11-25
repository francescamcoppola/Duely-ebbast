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
        } else if identifier.hasPrefix(NotificationIDs.deadlinePrefix) {
            selectedTab = .deadlines
        }
    }
}

/// Receives notification taps (also on a cold launch) and shows banners while the app is open.
/// `nonisolated` + stateless, so it's safely `Sendable` and its conformance isn't tied to the main actor.
nonisolated final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationCoordinator()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            AppRouter.shared.handleNotification(identifier: identifier)
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
