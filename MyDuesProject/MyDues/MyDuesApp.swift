//
//  MyDuesApp.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores,
//             Thomas Zefilippo,
//             Francesca Maria Coppola,
//             Gianluigi Russo,
//             Pietro Sarnataro
//  on 17/11/2026.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct MyDuesApp: App {
    /// Registers the notification delegate at launch so taps on notifications are handled.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before the first view reads @AppStorage, so iCloud settings are already in place.
        CloudSettingsSync.shared.start()
        LanguageController.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await PlanCatalogStore.shared.refreshIfNeeded() }
        }
        // Synced with the user's private iCloud database (see Persistence.swift).
        .modelContainer(Persistence.container)
    }
}
