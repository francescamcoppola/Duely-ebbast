//
//  EmailStepView.swift
//  DuelyProject
//
//  Offers to find subscriptions in Gmail before asking for them by hand. Connecting finishes
//  onboarding straight away: the scan runs on Home and its results are shown for review, so the
//  manual pick is skipped. "Add Them Myself" goes on to the manual pick.
//

import SwiftUI
import AuthenticationServices

struct EmailStepView: View {
    /// Called after an account is connected.
    let onConnected: () -> Void
    /// Called to pick subscriptions by hand instead.
    let onManual: () -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var emailImport = EmailImportModel.shared

    /// Always offered when Gmail import is set up in this build. Without Apple Intelligence the
    /// account is connected anyway and Home explains how to start the scan.
    static var isAvailable: Bool { GmailConfiguration.isConfigured }

    var body: some View {
        OnboardingStepLayout(
            step: .email,
            symbol: "envelope.badge",
            title: "Find your subscriptions automatically",
            subtitle: "Connect Gmail and Apple Intelligence will find your subscriptions and free trials, bills and taxes, orders you can return, warranties and pagoPA notices, on this device. You choose what to add.",
            onSkip: onManual
        ) {
            VStack(alignment: .leading, spacing: 18) {
                PrivacyPoint(
                    title: "Processed on this device",
                    detail: "Emails are read by Apple Intelligence on your device. Their content is never sent to \(AppInfo.name), to Apple or to anyone else.",
                    systemImage: "iphone"
                )
                PrivacyPoint(
                    title: "Read-only",
                    detail: "\(AppInfo.name) can only read email. It can't send, delete or change anything in your mailbox.",
                    systemImage: "eye"
                )
                if let message = AppleIntelligenceStatus.current.message {
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: "apple.intelligence")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                if let error = emailImport.connectionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Button {
                    Task {
                        if await emailImport.connect(using: webAuthenticationSession) != nil {
                            onConnected()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if emailImport.isConnecting { ProgressView() }
                        Text("Connect Gmail")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(emailImport.isConnecting)

                Button("Add Them Myself", action: onManual)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: AppMetrics.minimumHitTarget)
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailStepView(onConnected: {}, onManual: {})
    }
}
