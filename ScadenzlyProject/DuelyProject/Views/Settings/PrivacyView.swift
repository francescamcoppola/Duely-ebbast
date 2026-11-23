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
                Text("\(AppInfo.name) has no account, no servers and no analytics. Everything you enter stays on your device.")
                    .padding(.vertical, 4)
            }

            Section("What's Stored") {
                PrivacyPoint(
                    title: "On this device only",
                    detail: "Your name, budget, currency, subscriptions and check-in answers are saved in the app's storage on this device. They're included in your device backup like other app data.",
                    systemImage: "iphone"
                )
                PrivacyPoint(
                    title: "Local notifications",
                    detail: "Check-in and payment reminders are scheduled on your device. No push service is used.",
                    systemImage: "bell"
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
                    detail: "If you connect Gmail, \(AppInfo.name) asks Google for read-only access. It can't send, delete or change email.",
                    systemImage: "envelope"
                )
                PrivacyPoint(
                    title: "Analyzed on this device",
                    detail: "Recent billing emails are downloaded straight from Google to your device and read by Apple Intelligence on the device. Their content is never sent to \(AppInfo.name), to Apple or to anyone else, isn't used to train models, and isn't saved after the scan.",
                    systemImage: "apple.intelligence"
                )
                PrivacyPoint(
                    title: "Stored securely",
                    detail: "The Gmail sign-in is kept in this device's Keychain and isn't synced. Disconnecting revokes it in your Google Account and deletes it.",
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
                    detail: "Delete subscriptions in the app, disconnect Gmail in Settings, or delete the app to remove everything it stored.",
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
