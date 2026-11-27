//
//  SettingsView.swift
//  MyDues
//
//  Profile, budget, weekly check-in, notifications, iCloud, email import, support and privacy.
//

import SwiftUI
import UIKit
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    @AppStorage(OnboardingKeys.userName) private var userName = ""
    @AppStorage(OnboardingKeys.monthlyBudget) private var budgetString = ""
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @AppStorage(CheckInKeys.enabled) private var checkInEnabled = true
    @AppStorage(CheckInKeys.weekday) private var checkInWeekday = CheckInSchedule.defaultWeekday
    @AppStorage(CheckInKeys.minutes) private var checkInMinutes = CheckInSchedule.defaultMinutes
    @AppStorage(CheckInKeys.paymentRemindersEnabled) private var paymentRemindersEnabled = true

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var isEditingBudget = false
    @State private var isPickingCurrency = false
    @State private var emailImport = EmailImportModel.shared
    @State private var isConfirmingReset = false
    @State private var isResetting = false
    @State private var cloudStatus: CloudSyncStatus = .checking
    @State private var languageController = LanguageController.shared
    @State private var webPage: WebPage?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                languageSection
                budgetSection
                checkInSection
                remindersSection
                if notificationStatus == .denied {
                    notificationsDeniedSection
                }
                iCloudSection
                if FeatureFlags.emailImport {
                    emailImportSection
                }
                supportSection
                resetSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditingBudget) {
                BudgetEditorView()
            }
            .sheet(isPresented: $isPickingCurrency) {
                CurrencyPickerView(selection: currency)
            }
            .safariSheet($webPage)
            .task(id: scenePhase) {
                // Refresh when coming back from the Settings app.
                notificationStatus = await NotificationService.authorizationStatus()
                cloudStatus = await CloudSyncStatus.current()
            }
            .onChange(of: userName) { _, newValue in
                let limited = OnboardingViewModel.limitedName(newValue)
                if limited != newValue { userName = limited }
            }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $userName)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding {
                languageController.language
            } set: { newValue in
                // Rebuilds the whole app in the new language, closing this screen.
                withAnimation(.smooth(duration: 0.35)) {
                    languageController.change(to: newValue)
                }
            }) {
                ForEach(AppLanguage.allCases) { option in
                    if let name = option.nativeName {
                        Text(verbatim: name).tag(option)
                    } else {
                        Text("Device Language").tag(option)
                    }
                }
            } label: {
                Label("Language", systemImage: "globe")
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text("\(AppInfo.name) restarts in the new language.")
        }
    }

    private var budgetSection: some View {
        Section {
            Button {
                isEditingBudget = true
            } label: {
                LabeledContent("Monthly Budget") {
                    if let budget = BillingMath.storedAmount(budgetString) {
                        Text(budget, format: .currency(code: currencyCode))
                    } else {
                        Text("Not Set")
                    }
                }
                .foregroundStyle(.primary)
            }

            Button {
                isPickingCurrency = true
            } label: {
                LabeledContent("Currency") {
                    Text(currency.wrappedValue.name)
                }
                .foregroundStyle(.primary)
            }
        } footer: {
            Text("Used for every price in the app. Changing it doesn't convert prices you've already entered.")
        }
    }

    private var checkInSection: some View {
        Section {
            Toggle("Weekly Check-In", isOn: $checkInEnabled)
                .onChange(of: checkInEnabled) { _, isOn in
                    if isOn { requestPermissionIfNeeded() }
                }

            if checkInEnabled {
                Picker("Day", selection: $checkInWeekday) {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        Text(calendar.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
                DatePicker("Time", selection: checkInTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Check-In")
        } footer: {
            Text("One quick question a week about which subscriptions you used. It makes your spending profile and usage insights more accurate.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Payment Reminders", isOn: $paymentRemindersEnabled)
                .onChange(of: paymentRemindersEnabled) { _, isOn in
                    if isOn { requestPermissionIfNeeded() }
                }
        } footer: {
            Text("Sent at \(Text(reminderTime, format: .dateTime.hour().minute())) before each payment, using the reminder chosen for each subscription.")
        }
    }

    private var notificationsDeniedSection: some View {
        Section {
            Label("Notifications Are Off", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
            Button("Open Notification Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        } footer: {
            Text("Allow notifications for \(AppInfo.name) in the Settings app to receive check-in and payment reminders.")
        }
    }

    private var emailImportSection: some View {
        Section {
            NavigationLink {
                EmailImportView()
            } label: {
                LabeledContent {
                    switch emailImport.connectedEmails.count {
                    case 0: Text("Off")
                    case 1: Text("Connected")
                    case let count: Text("^[\(count) account](inflect: true)")
                    }
                } label: {
                    Label("Import from Email", systemImage: "envelope.badge")
                }
            }
        } footer: {
            Text("Find subscriptions, bills, taxes and tuition in one or more Gmail accounts with Apple Intelligence, on this device.")
        }
    }

    private var iCloudSection: some View {
        Section {
            LabeledContent {
                if cloudStatus == .checking {
                    ProgressView()
                } else {
                    Text(cloudStatus.title)
                }
            } label: {
                Label("iCloud Sync", systemImage: cloudStatus == .on ? "checkmark.icloud" : "icloud.slash")
            }
        } footer: {
            Text(cloudStatus.message)
        }
    }

    private var supportSection: some View {
        Section {
            Button {
                webPage = WebPage(url: AppInfo.supportURL)
            } label: {
                Label("Help & Support", systemImage: "questionmark.circle")
            }
            if let url = AppInfo.supportEmailURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Contact Us", systemImage: "envelope")
                }
            }
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        } header: {
            Text("Support")
        } footer: {
            Text("Questions or problems? Write to \(AppInfo.supportEmail). Version \(AppInfo.version).")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                if isResetting {
                    HStack {
                        Text("Resetting…")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("Reset \(AppInfo.name)")
                }
            }
            .disabled(isResetting)
            .confirmationDialog(
                "Reset \(AppInfo.name)?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Erase All and Start Over", role: .destructive) {
                    resetApp()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if FeatureFlags.emailImport {
                    Text("All your subscriptions, check-ins and settings will be deleted from this device, from iCloud and from your other devices, and every Gmail account will be disconnected. This can't be undone.")
                } else {
                    Text("All your subscriptions, check-ins and settings will be deleted from this device, from iCloud and from your other devices. This can't be undone.")
                }
            }
        } footer: {
            Text("Deletes everything and takes you back to the welcome screen to set up \(AppInfo.name) again.")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Button("Show Onboarding Again") {
                UserDefaults.standard.set(false, forKey: OnboardingKeys.hasCompleted)
                dismiss()
            }
        }
    }
    #endif

    // MARK: Helpers

    /// Weekdays in the region's order (Monday first in Italy, Sunday first in the US).
    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private var currency: Binding<CurrencyOption> {
        Binding {
            CurrencyOption(code: currencyCode)
        } set: { option in
            currencyCode = option.code
        }
    }

    /// Payment reminders' delivery time, formatted for the user's locale ("9:00 AM", "09:00").
    private var reminderTime: Date {
        calendar.date(bySettingHour: ReminderPlanner.reminderHour, minute: 0, second: 0, of: .now) ?? .now
    }

    private var checkInTime: Binding<Date> {
        Binding {
            calendar.date(bySettingHour: checkInMinutes / 60, minute: checkInMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            checkInMinutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
        }
    }

    private func resetApp() {
        isResetting = true
        Task {
            await AppReset.eraseAll(context: modelContext)
            // ContentView switches to onboarding; close the sheet in case it's still on screen.
            dismiss()
        }
    }

    private func requestPermissionIfNeeded() {
        Task {
            await NotificationService.requestAuthorizationIfNeeded()
            notificationStatus = await NotificationService.authorizationStatus()
        }
    }
}

#Preview {
    SettingsView()
}
