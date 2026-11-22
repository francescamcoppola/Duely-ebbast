//
//  DuelyProjectApp.swift
//  DuelyProject
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
struct DuelyProjectApp: App {
    /// Registers the notification delegate at launch so taps on notifications are handled.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Subscription.self, UsageEntry.self])
    }
}

