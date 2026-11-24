//
//  Persistence.swift
//  DuelyProject
//
//  The app's SwiftData store, mirrored to the user's private iCloud database with CloudKit, so
//  subscriptions and check-ins survive a reinstall or a new device and stay in sync between
//  iPhone and iPad. Without iCloud (signed out, or a build without the capability) the same
//  store keeps working locally and starts syncing once iCloud is available.
//

import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Subscription.self, UsageEntry.self])

    /// Created once at launch and shared by the whole app.
    static let container: ModelContainer = makeContainer()

    /// True when the store was opened with CloudKit mirroring.
    private(set) static var isCloudBacked = false

    private static func makeContainer() -> ModelContainer {
        // `.automatic` uses the first iCloud container in MyDues.entitlements, so the container
        // can be changed in Signing & Capabilities without touching the code.
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: cloud)
            isCloudBacked = true
            return container
        } catch {
            // Missing entitlement or CloudKit unavailable: keep the data on the device.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                fatalError("Couldn't open the data store: \(error)")
            }
        }
    }
}

// MARK: - iCloud account status

enum CloudSyncStatus: Equatable {
    case checking
    case on
    case noAccount
    case restricted
    case unavailable

    static func current() async -> CloudSyncStatus {
        guard Persistence.isCloudBacked else { return .unavailable }
        // Signed in to iCloud with iCloud Drive/data allowed for this app. Doesn't need the
        // container's name, so it can't fall out of sync with the entitlements.
        return FileManager.default.ubiquityIdentityToken == nil ? .noAccount : .on
    }

    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking…"
        case .on: "On"
        case .noAccount, .restricted, .unavailable: "Off"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .checking, .on:
            "Subscriptions, check-ins and settings are saved in your private iCloud and stay in sync on all your devices signed in with the same Apple Account."
        case .noAccount:
            "Sign in to iCloud in the Settings app to back up your data and sync it across your devices. Until then, it's saved only on this device."
        case .restricted:
            "iCloud is restricted on this device, so your data is saved only here."
        case .unavailable:
            "iCloud isn't available right now, so your data is saved only on this device."
        }
    }
}
