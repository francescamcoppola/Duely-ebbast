//
//  AppReset.swift
//  MyDues
//
//  Erases everything the app stored, on this device and in iCloud, and sends the user back to onboarding.
//

import Foundation
import SwiftData
import UserNotifications
import WidgetKit

@MainActor
enum AppReset {
    /// Deletes subscriptions, usage history, purchases and pagoPA notices, removes notifications, disconnects Gmail and
    /// clears every preference. Setting `hasCompleted` to false last makes `ContentView` swap to onboarding.
    static func eraseAll(context: ModelContext, defaults: UserDefaults = .standard) async {
        // Data. Deleted one by one rather than in a batch, so CloudKit mirrors the deletions
        // and the data is erased from iCloud and the user's other devices too.
        do {
            for entry in try context.fetch(FetchDescriptor<UsageEntry>()) { context.delete(entry) }
            for subscription in try context.fetch(FetchDescriptor<Subscription>()) { context.delete(subscription) }
            for purchase in try context.fetch(FetchDescriptor<Purchase>()) { context.delete(purchase) }
            for notice in try context.fetch(FetchDescriptor<PaymentNotice>()) { context.delete(notice) }
            try context.save()
        } catch {
            assertionFailure("Reset failed: \(error)")
        }

        // Notifications
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // Gmail tokens (Keychain) and the app's access on Google's side, for every account
        await EmailImportModel.shared.disconnectAll()

        // Screen Time links and the widgets' data, in the App Group
        UsageLinks.all = [:]
        UsageLinks.usedDays = [:]
        UsageLinks.lastNotified = [:]
        ScreenTimeService.shared.restartMonitoring()
        SharedStore.defaults?.removeObject(forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadAllTimelines()

        // Navigation state
        AppRouter.shared.selectedTab = .home
        AppRouter.shared.isCheckInPresented = false

        // Preferences: name, budget, currency, check-in, sort… (in iCloud too)
        CloudSettingsSync.shared.eraseCloud()
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.set(false, forKey: OnboardingKeys.hasCompleted)
        // Back to the device's language, chosen again on the first onboarding screen.
        LanguageController.shared.change(to: .system)
    }
}
