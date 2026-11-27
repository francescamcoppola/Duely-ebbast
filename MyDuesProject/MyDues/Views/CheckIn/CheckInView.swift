//
//  CheckInView.swift
//  MyDues
//
//  Weekly check-in: tap what you used, then see what went unused and what it costs.
//  Answers update in place, so reopening the same week edits it instead of duplicating.
//

import SwiftUI
import SwiftData
import UserNotifications

struct CheckInView: View {
    /// Start of the 7 days being asked about.
    let week: Date

    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @AppStorage(CheckInKeys.skippedWeek) private var skippedWeek: Double = 0
    @AppStorage(CheckInKeys.weekday) private var weekday = CheckInSchedule.defaultWeekday
    @AppStorage(CheckInKeys.enabled) private var checkInEnabled = true
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @State private var selected: Set<PersistentIdentifier> = []
    @State private var didLoad = false
    @State private var result: Summary?
    @State private var notificationStatus: UNAuthorizationStatus?
    /// Bumped only on taps, so loading previous answers doesn't trigger a haptic.
    @State private var tileTaps = 0
    @ScaledMetric(relativeTo: .largeTitle) private var resultSymbolSize: CGFloat = 56

    struct Summary {
        let used: Int
        let total: Int
        let unused: [Subscription]
        let unusedMonthly: Decimal
    }

    private var weekEnd: Date { calendar.date(byAdding: .day, value: 6, to: week) ?? week }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultView(result)
                } else {
                    picker
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { dismiss() }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Picker

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Which subscriptions did you use this week?")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text((week..<weekEnd).formatted(.interval.day().month(.abbreviated).locale(LocalizedBundle.locale)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(subscriptions) { subscription in
                        CheckInTile(subscription: subscription,
                                    isSelected: selected.contains(subscription.id)) {
                            toggle(subscription)
                        }
                    }
                }

                Button("Skip This Week") {
                    skippedWeek = week.timeIntervalSince1970
                    dismiss()
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .onboardingActionBar {
            OnboardingPrimaryButton(selected.isEmpty ? "I Didn't Use Any" : "Done", action: save)
        }
        .sensoryFeedback(.selection, trigger: tileTaps)
    }

    // MARK: Result

    private func resultView(_ result: Summary) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: resultSymbolSize))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: result.used)
                        .accessibilityHidden(true)
                    Text("Check-In Complete")
                        .font(.title2.bold())
                    Text("You used \(result.used) of ^[\(result.total) subscription](inflect: true) this week.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                if !result.unused.isEmpty {
                    unusedCard(result)
                }

                if notificationStatus == .notDetermined {
                    reminderOffer
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .onboardingActionBar {
            OnboardingPrimaryButton("Done") { dismiss() }
        }
        .task { notificationStatus = await NotificationService.authorizationStatus() }
    }

    private func unusedCard(_ result: Summary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Not Used This Week")
                .font(.headline)
            ForEach(result.unused) { subscription in
                HStack(spacing: 12) {
                    MonogramTile(subscription: subscription, size: 32)
                    Text(subscription.name)
                    Spacer(minLength: 8)
                    if !subscription.needsSetup {
                        Text("\(Text(subscription.monthlyCost, format: .currency(code: currencyCode)))/mo")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if result.unusedMonthly > 0 {
                Divider()
                Text("That's \(Text(result.unusedMonthly, format: .currency(code: currencyCode))) a month. If this keeps happening, it may be worth canceling.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    /// Asked here because the value is obvious right after a check-in (HIG: request in context).
    private var reminderOffer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Get a reminder each week", systemImage: "bell.badge")
                .font(.headline)
            Text("We'll send one notification on \(weekdayName) so you don't forget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Turn On Reminders") {
                // The weekly reminder is the check-in reminder, so make sure it's on.
                checkInEnabled = true
                Task {
                    await NotificationService.requestAuthorization()
                    notificationStatus = await NotificationService.authorizationStatus()
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .cardStyle()
    }

    private var weekdayName: String {
        let symbols = calendar.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    // MARK: Data

    private func entry(for subscription: Subscription) -> UsageEntry? {
        subscription.usageEntries?.first { calendar.isDate($0.weekStart, inSameDayAs: week) }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        // Reopening an answered week shows the previous answers; otherwise Screen Time's data,
        // for subscriptions linked to an app, is already filled in.
        selected = Set(subscriptions.filter { subscription in
            if let answer = entry(for: subscription) { return answer.used }
            return ScreenTimeService.shared.usage(of: subscription, inWeekStarting: week) == true
        }.map(\.id))
    }

    private func toggle(_ subscription: Subscription) {
        tileTaps += 1
        if selected.contains(subscription.id) {
            selected.remove(subscription.id)
        } else {
            selected.insert(subscription.id)
        }
    }

    private func save() {
        for subscription in subscriptions {
            let used = selected.contains(subscription.id)
            if let existing = entry(for: subscription) {
                existing.used = used
            } else {
                context.insert(UsageEntry(weekStart: week, used: used, subscription: subscription))
            }
        }
        do {
            try context.save()
        } catch {
            assertionFailure("Check-in save failed: \(error)")
        }

        let unused = subscriptions.filter { !selected.contains($0.id) }
        withAnimation(.smooth) {
            result = Summary(
                used: subscriptions.count - unused.count,
                total: subscriptions.count,
                unused: unused,
                unusedMonthly: unused.filter { !$0.needsSetup }.reduce(Decimal.zero) { $0 + $1.monthlyCost }
            )
        }
    }
}

// MARK: - Tile

private struct CheckInTile: View {
    let subscription: Subscription
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                MonogramTile(subscription: subscription, size: 48)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, subscription.displayColor)
                                .background(Circle().fill(Color(.systemBackground)).padding(2))
                                .offset(x: 8, y: -8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(subscription.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(subscription.displayColor.opacity(0.15))
                          : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(subscription.displayColor, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(Text(subscription.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CheckInView(week: CheckInSchedule.reviewedWeekStart(for: .now))
        .modelContainer(PreviewData.container)
}
