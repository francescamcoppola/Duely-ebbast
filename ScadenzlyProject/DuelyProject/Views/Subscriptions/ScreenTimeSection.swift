//
//  ScreenTimeSection.swift
//  DuelyProject
//
//  Links a subscription to the app it's used in, with Apple's Screen Time picker, so usage is
//  tracked without the weekly question.
//

import SwiftUI
import SwiftData
import FamilyControls

struct ScreenTimeSection: View {
    let subscription: Subscription

    @Environment(\.modelContext) private var context
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @State private var screenTime = ScreenTimeService.shared
    @State private var isPicking = false
    @State private var selection = FamilyActivitySelection()

    private var isLinked: Bool { screenTime.isLinked(subscription) }

    var body: some View {
        Section {
            switch screenTime.status {
            case .unavailable:
                Label("Screen Time isn't available in this version of the app.", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .denied:
                Label("Screen Time access is off. Allow it in Settings › Screen Time.", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .notDetermined:
                Button {
                    Task {
                        await screenTime.requestAuthorization()
                        if screenTime.status == .approved { openPicker() }
                    }
                } label: {
                    HStack {
                        Label("Track Usage with Screen Time", systemImage: "hourglass")
                        Spacer()
                        if screenTime.isRequesting { ProgressView() }
                    }
                }
            case .approved:
                if isLinked {
                    LabeledContent {
                        Text(lastUseText)
                    } label: {
                        Label("Linked to Screen Time", systemImage: "checkmark.circle.fill")
                    }
                    Button("Change App") { openPicker() }
                    Button("Stop Tracking", role: .destructive) {
                        screenTime.unlink(subscription, context: context)
                    }
                } else {
                    Button {
                        openPicker()
                    } label: {
                        Label("Choose the App for \(subscription.name)", systemImage: "apps.iphone")
                    }
                }
            }
        } header: {
            Text("Screen Time")
        } footer: {
            Text("Pick the app you use for \(subscription.name). Screen Time only tells \(AppInfo.name) on which days it was used for a few minutes, never what you did, and you'll be reminded if you stop opening it.")
        }
        .familyActivityPicker(isPresented: $isPicking, selection: $selection)
        .onChange(of: isPicking) { _, isOpen in
            // Saved when the picker closes.
            guard !isOpen else { return }
            screenTime.link(subscription, selection: selection, currencyCode: currencyCode, context: context)
        }
    }

    private var lastUseText: String {
        guard let key = subscription.usageKey, let last = UsageLinks.lastUse(key: key) else {
            return String(localized: "Not used yet")
        }
        if Calendar.current.isDateInToday(last) { return String(localized: "Used today") }
        return String(localized: "Last used \(last.formatted(.dateTime.day().month(.abbreviated).locale(LanguageController.shared.locale)))")
    }

    private func openPicker() {
        selection = screenTime.selection(for: subscription)
        isPicking = true
    }
}
