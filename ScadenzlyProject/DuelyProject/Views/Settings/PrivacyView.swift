//
//  PrivacyView.swift
//  DuelyProject
//
//  In-app privacy notice. Keep it in sync with PRIVACY.md at the repository root and with the
//  App Store privacy label.
//

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        Form {
            Section {
                Text("\(AppInfo.name) has no account, no servers and no analytics. Everything you enter stays on your devices and in your own private iCloud.")
                    .padding(.vertical, 4)
            }

            Section("What's Stored") {
                PrivacyPoint(
                    title: "On your devices",
                    detail: "Your name, budget, currency, subscriptions, payments and check-in answers are saved in the app's storage on this device.",
                    systemImage: "iphone"
                )
                PrivacyPoint(
                    title: "In your private iCloud",
                    detail: "If you're signed in to iCloud, the same data is saved in your private iCloud database so it's never lost and stays in sync on your devices. Only you can access it; \(AppInfo.name)'s developers can't.",
                    systemImage: "icloud"
                )
                PrivacyPoint(
                    title: "Local notifications",
                    detail: "Check-in and payment reminders are scheduled on your device. iCloud only uses silent notifications to tell the app your data changed on another device.",
                    systemImage: "bell"
                )
                PrivacyPoint(
                    title: "Plan suggestions",
                    detail: "Plans, prices and cheaper alternatives come from a list in the app, which may be updated by downloading a new copy. When you look for a service's plans or cancellation page, your device reads that service's public web pages, without cookies or anything about you. Comparisons and choices happen on your device.",
                    systemImage: "tag"
                )
                PrivacyPoint(
                    title: "No tracking",
                    detail: "\(AppInfo.name) doesn't track you, show ads or share data with data brokers.",
                    systemImage: "hand.raised"
                )
            }

            Section {
                PrivacyPoint(
                    title: "Optional and read-only",
                    detail: "For each Gmail account you connect, \(AppInfo.name) asks Google for read-only access. It can't send, delete or change email.",
                    systemImage: "envelope"
                )
                PrivacyPoint(
                    title: "Analyzed on this device",
                    detail: "Recent billing emails are downloaded straight from Google to your device and read by Apple Intelligence on the device. Their content is never sent to \(AppInfo.name), to Apple or to anyone else, isn't used to train models, and isn't saved after the scan.",
                    systemImage: "apple.intelligence"
                )
                PrivacyPoint(
                    title: "Stored securely",
                    detail: "Each Gmail sign-in is kept in this device's Keychain and is never synced to iCloud. Disconnecting an account revokes it in your Google Account and deletes it.",
                    systemImage: "key"
                )
            } header: {
                Text("Import from Email")
            } footer: {
                Text("\(AppInfo.name)'s use of information received from Google APIs adheres to the Google API Services User Data Policy, including the Limited Use requirements.")
            }

            Section {
                PrivacyPoint(
                    title: "Delete your data",
                    detail: "Delete subscriptions in the app, disconnect Gmail accounts in Settings, or reset \(AppInfo.name) in Settings to erase everything from this device, iCloud and your other devices.",
                    systemImage: "trash"
                )
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
