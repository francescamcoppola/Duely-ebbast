//
//  SpendingProfileDetailView.swift
//  DuelyProject
//
//  Why the user has their spending profile, and what would change it:
//  • Why     — the two signals (budget share, usage) against the profile thresholds
//  • Change  — which cancellations would move them to a better profile
//  • Ranking — subscriptions least worth their cost, each opening its detail screen
//

import SwiftUI
import SwiftData

struct SpendingProfileDetailView: View {
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.monthlyBudget) private var budgetString = ""
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @State private var isEditingBudget = false

    /// Rows shown in "Least Worth It"; the full list lives in the Subscriptions tab.
    private let maxRankedRows = 5

    var body: some View {
        let insights = ProfileInsights(subscriptions: subscriptions, budget: BillingMath.storedAmount(budgetString))

        List {
            header(insights.profile)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            whySection(insights)

            if let suggestion = insights.suggestion {
                suggestionSection(suggestion)
            }

            if !insights.usage.isEmpty {
                rankingSection(insights.usage)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Spending Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingBudget) {
            BudgetEditorView()
        }
    }

    // MARK: Header

    private func header(_ profile: SpendingProfile) -> some View {
        VStack(spacing: 10) {
            Image(systemName: profile.symbol)
                .font(.largeTitle)
                .foregroundStyle(profile.tint)
                .padding(18)
                .background(profile.tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(profile.title)
                .font(.title2.bold())
            Text(profile.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Why

    private func whySection(_ insights: ProfileInsights) -> some View {
        Section {
            budgetRow(insights)
            usageRow(insights)
        } header: {
            Text("Why")
        } footer: {
            Text("Your profile combines how much of your budget subscriptions take with how often you use them, over the last \(ProfileInsights.lookbackWeeks) weeks.")
        }
    }

    @ViewBuilder
    private func budgetRow(_ insights: ProfileInsights) -> some View {
        if let ratio = insights.budgetRatio {
            SignalRow(
                title: "Budget",
                summary: ratio > 0 && ratio < 0.01
                    ? Text("Subscriptions use less than 1% of your monthly budget.")
                    : Text("Subscriptions use \(Text(ratio, format: .percent.precision(.fractionLength(0)))) of your monthly budget."),
                value: ratio,
                marks: [SpendingProfile.Threshold.saver, SpendingProfile.Threshold.balanced],
                tint: ratio > 1 ? .red : ratio >= SpendingProfile.Threshold.balanced ? .orange : .green,
                legend: Text("Saver under \(percent(SpendingProfile.Threshold.saver)) · Balanced under \(percent(SpendingProfile.Threshold.balanced)) · Over budget above 100%")
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Budget")
                    .font(.headline)
                Text("No budget set, so your profile can only use how often you use your subscriptions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Set Budget") { isEditingBudget = true }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func usageRow(_ insights: ProfileInsights) -> some View {
        if insights.hasEnoughCheckIns, let rate = insights.usageRate {
            SignalRow(
                title: "Usage",
                summary: Text("You used your subscriptions in \(Text(rate, format: .percent.precision(.fractionLength(0)))) of check-in answers."),
                value: rate,
                marks: [SpendingProfile.Threshold.lowUsage, SpendingProfile.Threshold.highUsage],
                tint: rate < SpendingProfile.Threshold.lowUsage ? .orange : .green,
                legend: Text("Collector under \(percent(SpendingProfile.Threshold.lowUsage)) · Optimizer at \(percent(SpendingProfile.Threshold.highUsage)) or more")
            )
        } else {
            // Not enough data yet: show progress instead of an empty insight.
            let needed = SpendingProfile.Threshold.minimumCheckInWeeks
            let done = min(insights.checkInWeeks, needed)
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage")
                    .font(.headline)
                Text("\(done) of \(needed) weekly check-ins done")
                    .font(.subheadline)
                ProgressView(value: Double(done), total: Double(needed))
                    .accessibilityHidden(true)   // The text above says the same.
                Text("Usage starts counting toward your profile after \(needed) weekly check-ins.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: What would change it

    private func suggestionSection(_ suggestion: ProfileInsights.Suggestion) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.newProfile.symbol)
                    .font(.title3)
                    .foregroundStyle(suggestion.newProfile.tint)
                    .accessibilityHidden(true)
                Text("Canceling \(suggestion.cancel.map(\.name).formatted(.list(type: .and).locale(LocalizedBundle.locale))) would save \(Text(suggestion.monthlySavings, format: .currency(code: currencyCode))) a month and make you \(Text(suggestion.newProfile.title).bold()).")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("What Would Change It")
        } footer: {
            Text("Based on your recent check-ins. Only you know what's worth keeping.")
        }
    }

    // MARK: Least worth it

    private func rankingSection(_ usage: [ProfileInsights.Usage]) -> some View {
        Section {
            ForEach(usage.prefix(maxRankedRows)) { item in
                NavigationLink {
                    SubscriptionDetailView(subscription: item.subscription)
                } label: {
                    UsageRankRow(item: item, currencyCode: currencyCode)
                }
            }
        } header: {
            Text("Least Worth It")
        } footer: {
            Text("Cost per week used is what each week you actually used it really cost.")
        }
    }

    // MARK: Helpers

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(LocalizedBundle.locale))
    }
}

// MARK: - Signal row

/// One input to the profile: a sentence, a bar with the profile thresholds marked, and a legend.
private struct SignalRow: View {
    let title: LocalizedStringKey
    let summary: Text
    let value: Double
    let marks: [Double]
    let tint: Color
    let legend: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            summary
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            ThresholdBar(value: value, marks: marks, tint: tint)
            legend
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// 0…100 % bar with tick marks at the thresholds. Purely visual; the row's text carries the meaning.
private struct ThresholdBar: View {
    let value: Double
    let marks: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: value > 0 ? max(width * min(value, 1), 10) : 0)
                ForEach(marks, id: \.self) { mark in
                    Rectangle()
                        .fill(Color(.label).opacity(0.35))
                        .frame(width: 2, height: 16)
                        .offset(x: width * mark - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .animation(.smooth, value: value)
        .accessibilityHidden(true)
    }
}

// MARK: - Ranking row

private struct UsageRankRow: View {
    let item: ProfileInsights.Usage
    let currencyCode: String

    var body: some View {
        AdaptiveStack(spacing: 14) {
            HStack(spacing: 14) {
                MonogramTile(subscription: item.subscription, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.subscription.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text("Used \(item.usedWeeks) of ^[\(item.answeredWeeks) week](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let cost = item.costPerUsedWeek {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cost, format: .currency(code: currencyCode))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Text("per week used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not used")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        SpendingProfileDetailView()
    }
    .modelContainer(PreviewData.container)
}
