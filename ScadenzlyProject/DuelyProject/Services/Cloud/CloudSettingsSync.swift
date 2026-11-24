//
//  CloudSettingsSync.swift
//  DuelyProject
//
//  Mirrors the user's preferences (name, budget, currency, check-in and reminders, and whether
//  onboarding is done) to iCloud Key-Value Storage, so a reinstall or a new device skips
//  onboarding and keeps the same settings. `@AppStorage` keeps reading `UserDefaults`; this only
//  copies values in both directions. Gmail sign-ins are not synced: they stay in this device's
//  Keychain.
//

import Foundation

@MainActor
final class CloudSettingsSync {
    static let shared = CloudSettingsSync()

    /// Only preferences that make sense on every device. Per-device state (last scan, skipped
    /// check-in week, list sort) stays local.
    static let syncedKeys: [String] = [
        OnboardingKeys.hasCompleted,
        OnboardingKeys.userName,
        OnboardingKeys.monthlyBudget,
        OnboardingKeys.currencyCode,
        CheckInKeys.enabled,
        CheckInKeys.weekday,
        CheckInKeys.minutes,
        CheckInKeys.paymentRemindersEnabled,
    ]

    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var isApplyingCloudChange = false
    private var observers: [NSObjectProtocol] = []

    /// Call once at launch.
    func start() {
        guard observers.isEmpty else { return }
        cloud.synchronize()

        // iCloud already has a value (another device, or before a reinstall): it wins.
        // Values only this device has are uploaded.
        for key in Self.syncedKeys {
            if let value = cloud.object(forKey: key) {
                apply(value, forKey: key)
            } else if let value = defaults.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.pullFromCloud(keys: keys) }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushToCloud() }
        })
    }

    /// Removes the synced preferences from iCloud too (used by Reset).
    func eraseCloud() {
        for key in Self.syncedKeys { cloud.removeObject(forKey: key) }
        cloud.synchronize()
    }

    // MARK: Private

    private func pullFromCloud(keys: [String]?) {
        for key in keys ?? Self.syncedKeys where Self.syncedKeys.contains(key) {
            if let value = cloud.object(forKey: key) {
                apply(value, forKey: key)
            } else {
                isApplyingCloudChange = true
                defaults.removeObject(forKey: key)
                isApplyingCloudChange = false
            }
        }
    }

    private func pushToCloud() {
        guard !isApplyingCloudChange else { return }
        var changed = false
        for key in Self.syncedKeys {
            let local = defaults.object(forKey: key)
            let remote = cloud.object(forKey: key)
            guard !Self.isEqual(local, remote) else { continue }
            if let local { cloud.set(local, forKey: key) } else { cloud.removeObject(forKey: key) }
            changed = true
        }
        if changed { cloud.synchronize() }
    }

    private func apply(_ value: Any, forKey key: String) {
        guard !Self.isEqual(defaults.object(forKey: key), value) else { return }
        isApplyingCloudChange = true
        defaults.set(value, forKey: key)
        isApplyingCloudChange = false
    }

    private static func isEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a as NSObject, b as NSObject): a.isEqual(b)
        default: false
        }
    }
}
