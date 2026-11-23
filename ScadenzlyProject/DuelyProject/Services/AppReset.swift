//
//  AppReset.swift
//  DuelyProject
//
//  Erases everything the app stored on this device and sends the user back to onboarding.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum AppReset {
    /// Deletes subscriptions and usage history, removes notifications, disconnects Gmail and
    /// clears every preference. Setting `hasCompleted` to false last makes `ContentView` swap to onboarding.
    static func eraseAll(context: ModelContext, defaults: UserDefaults = .standard) async {
        // Data
        do {
            try context.delete(model: UsageEntry.self)
            try context.delete(model: Subscription.self)
            try context.save()
        } catch {
            assertionFailure("Reset failed: \(error)")
        }

        // Notifications
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // Gmail tokens (Keychain) and the app's access on Google's side
        await EmailImportModel.shared.disconnect()

        // Navigation state
        AppRouter.shared.selectedTab = .home
        AppRouter.shared.isCheckInPresented = false

        // Preferences: name, budget, currency, check-in, sort…
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.set(false, forKey: OnboardingKeys.hasCompleted)
    }
}
