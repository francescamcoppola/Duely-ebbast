//
//  EmailImportView.swift
//  DuelyProject
//
//  Connect Gmail and scan it for subscriptions. Explains up front what is read, where it's
//  processed and what is kept, before the user connects anything.
//

import SwiftUI
import SwiftData
import AuthenticationServices

struct EmailImportView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var subscriptions: [Subscription]

    @State private var model = EmailImportModel.shared
    /// The account waiting for the user to confirm it should be disconnected.
    @State private var accountToDisconnect: String?
    @State private var addedCount: Int?

    var body: some View {
        Form {
            introSection
            accountSection
            if model.isConnected {
                scanSection
            }
            privacySection
        }
        .navigationTitle("Import from Email")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text("Disconnect \(accountToDisconnect ?? "")?"),
            isPresented: isConfirmingDisconnect,
            titleVisibility: .visible,
            presenting: accountToDisconnect
        ) { account in
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect(email: account) }
            }
        } message: { _ in
            Text("Removes \(AppInfo.name)'s access in this Google Account and deletes the sign-in from this device. Subscriptions you've added stay.")
        }
        .sheet(isPresented: isReviewing) {
            if case .review(let candidates) = model.phase {
                ImportReviewView(candidates: candidates) { chosen in
                    addedCount = model.add(chosen, existing: subscriptions, into: context)
                }
            }
        }
        .task(id: scenePhase) {
            // Picks up Apple Intelligence being turned on in the Settings app.
            model.refreshAvailability()
        }
        .task(id: model.aiStatus) {
            // The model finishes downloading in the background: check again until it's ready,
            // so the Scan button enables itself without leaving the screen.
            while model.aiStatus == .modelNotReady, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                model.refreshAvailability()
            }
        }
    }

    // MARK: Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Find Recurring Payments in Your Email", systemImage: "envelope.badge")
                    .font(.headline)
                Text("Apple Intelligence reads your recent receipts, renewals, bills, tax notices and tuition emails on this device and suggests what it finds. Connect several accounts to find them all. You choose what to add.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if !GmailConfiguration.isConfigured {
                Label("Gmail import isn't available in this version of the app.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.connectedEmails, id: \.self) { email in
                    accountRow(email)
                }

                if model.canAddAccount {
                    Button {
                        Task {
                            if let email = await model.connect(using: webAuthenticationSession) {
                                addedCount = nil
                                model.startScan(existing: subscriptions, accounts: [email])
                            }
                        }
                    } label: {
                        HStack {
                            Label(model.isConnected ? "Add Another Gmail Account" : "Connect Gmail",
                                  systemImage: model.isConnected ? "plus.circle" : "envelope")
                            Spacer()
                            if model.isConnecting { ProgressView() }
                        }
                    }
                    .disabled(model.isConnecting || model.isScanning)
                }
            }
        } header: {
            Text(model.connectedEmails.count > 1 ? "Accounts" : "Account")
        } footer: {
            if let error = model.connectionError {
                Text(error).foregroundStyle(.red)
            } else if GmailConfiguration.isConfigured {
                if model.isConnected {
                    Text("Swipe an account to disconnect it. You can connect up to \(EmailImportModel.maxAccounts) accounts.")
                } else {
                    Text("You'll sign in on Google's page. \(AppInfo.name) never sees your password.")
                }
            }
        }
    }

    private func accountRow(_ email: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(email)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = model.accountErrors[email] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if case .scanning(_, _, let account) = model.phase, account == email {
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .swipeActions {
            Button("Disconnect", role: .destructive) {
                accountToDisconnect = email
            }
        }
        .contextMenu {
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                accountToDisconnect = email
            }
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        Section {
            switch model.phase {
            case .scanning(let done, let total, let account):
                VStack(alignment: .leading, spacing: 8) {
                    if total > 0 {
                        ProgressView(value: Double(done), total: Double(total)) {
                            Text("Reading emails…")
                        } currentValueLabel: {
                            if let account, model.connectedEmails.count > 1 {
                                Text("\(done) of \(total) · \(account)")
                            } else {
                                Text("\(done) of \(total)")
                            }
                        }
                    } else {
                        ProgressView { Text("Searching your inbox…") }
                    }
                }
                .padding(.vertical, 4)
                Button("Stop Scanning", role: .cancel) { model.cancelScan() }

            default:
                Button {
                    addedCount = nil
                    model.startScan(existing: subscriptions)
                } label: {
                    Label(model.connectedEmails.count > 1 ? "Scan All Accounts" : "Scan Emails",
                          systemImage: "sparkle.magnifyingglass")
                }
                .disabled(model.aiStatus != .available)
            }
        } header: {
            Text("Scan")
        } footer: {
            scanFooter
        }
    }

    @ViewBuilder
    private var scanFooter: some View {
        if let message = model.aiStatus.message {
            Text(message)
        } else if case .failed(let message) = model.phase {
            Text(message).foregroundStyle(.red)
        } else if let addedCount, addedCount > 0 {
            Text("^[\(addedCount) payment](inflect: true) added.")
        } else if let lastScan = model.lastScan {
            Text("Last scanned \(Text(lastScan, format: .relative(presentation: .named))). Reads up to \(EmailImportModel.scanLimit) recent billing emails per account.")
        } else {
            Text("Reads up to \(EmailImportModel.scanLimit) recent billing emails per account. Keep the app open while it runs.")
        }
    }

    private var privacySection: some View {
        Section("Your Privacy") {
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
            PrivacyPoint(
                title: "Nothing is kept",
                detail: "Emails are held in memory only during a scan. Only the payments you choose to add are saved.",
                systemImage: "tray"
            )
            PrivacyPoint(
                title: "Your choice",
                detail: "Each account's sign-in is stored in this device's Keychain and is never synced to iCloud. Disconnect at any time here or in your Google Account.",
                systemImage: "hand.raised"
            )
        }
    }

    private var isConfirmingDisconnect: Binding<Bool> {
        Binding {
            accountToDisconnect != nil
        } set: { isPresented in
            if !isPresented { accountToDisconnect = nil }
        }
    }

    private var isReviewing: Binding<Bool> {
        Binding {
            if case .review = model.phase { true } else { false }
        } set: { isPresented in
            if !isPresented, case .review = model.phase { model.dismissReview() }
        }
    }
}

// MARK: - Privacy point

struct PrivacyPoint: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        EmailImportView()
    }
    .modelContainer(PreviewData.container)
}
