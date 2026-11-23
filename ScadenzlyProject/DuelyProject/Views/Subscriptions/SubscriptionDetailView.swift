//
//  SubscriptionDetailView.swift
//  DuelyProject
//
//  Everything about one plan: billing, what it has cost so far, and how much it's used.
//



import SwiftUI
import SwiftData

struct SubscriptionDetailView: View {
    let subscription: Subscription

    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    /// After a delete the model is detached; reading its properties then is unsafe.
    private var isGone: Bool { subscription.isDeleted || subscription.modelContext == nil }

    var body: some View {
        Group {
            if isGone {
                ContentUnavailableView("Subscription Deleted", systemImage: "trash")
            } else {
                content(stats: SubscriptionStats(subscription: subscription))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isGone {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            SubscriptionEditorView(subscription: subscription, onDeleted: { dismiss() })
        }
    }

    private func content(stats: SubscriptionStats) -> some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            if subscription.needsSetup {
                Section {
                    Button("Add Price and Payment Date") { isEditing = true }
                } footer: {
                    Text("This subscription isn't counted in your totals yet.")
                }
            } else {
                billingSection
                historySection(stats)
            }

            usageSection(stats)

            Section {
                // Plain HStack, not `Label`: inside a List row a Label takes the list's icon-column
                // layout, which stretched this row and pushed its separator to the right.
                LabeledContent("Category") {
                    HStack(spacing: 6) {
                        Image(systemName: subscription.category.symbol)
                            .accessibilityHidden(true)
                        Text(subscription.category.title)
                    }
                }
                LabeledContent("Reminder") {
                    Text(ReminderOption.title(subscription.reminderDaysBefore))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            MonogramTile(subscription: subscription, size: 72)
            Text(subscription.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if !subscription.needsSetup {
                Text("\(Text(subscription.price, format: .currency(code: currencyCode))) · \(Text(subscription.cycle.title))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var billingSection: some View {
        Section("Billing") {
            if let next = subscription.nextPayment() {
                LabeledContent("Next Payment") {
                    Text(next, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                }
            }
            LabeledContent("Billing Cycle") {
                Text(subscription.cycle.title)
            }
            if subscription.cycle != .monthly {
                LabeledContent("Per Month") {
                    Text(subscription.monthlyCost, format: .currency(code: currencyCode))
                }
            }
            LabeledContent("Per Year") {
                Text(BillingMath.yearlyEquivalent(price: subscription.price, cycle: subscription.cycle),
                     format: .currency(code: currencyCode))
            }
        }
    }

    private func historySection(_ stats: SubscriptionStats) -> some View {
        Section {
            LabeledContent("Spent So Far") {
                Text(stats.chargedTotal, format: .currency(code: currencyCode))
            }
            LabeledContent("Payments") {
                Text(stats.chargedCount, format: .number)
            }
        } header: {
            Text("History")
        } footer: {
            Text("Since \(Text(stats.trackingStart, format: .dateTime.month(.wide).year())), based on billing dates.")
        }
    }

    private func usageSection(_ stats: SubscriptionStats) -> some View {
        Section {
            if stats.usageRate != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Used \(stats.usedWeeks) of ^[\(stats.answeredWeeks) week](inflect: true)")
                    UsageStrip(weeks: stats.recentUsage, color: subscription.displayColor)
                }
                .padding(.vertical, 4)

                if let cost = stats.costPerUsedWeek {
                    LabeledContent("Cost per Week Used") {
                        Text(cost, format: .currency(code: currencyCode))
                    }
                }
            } else {
                Text("No check-ins yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Usage")
        } footer: {
            if stats.usageRate == nil {
                Text("Weekly check-ins will show how often you use this subscription and what each use really costs.")
            }
        }
    }
}

// MARK: - Usage strip

/// Always 8 slots, one per weekly check-in, oldest on the left. Answered weeks fill in as they
/// happen (colored = used, gray = not used); dashed slots are weeks still to come. Once all 8 are
/// filled, the oldest drops off, so the strip never grows beyond one row.
private struct UsageStrip: View {
    let weeks: [SubscriptionStats.WeekUsage]
    let color: Color

    private let slots = SubscriptionStats.usageWeeksShown

    @Environment(\.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<slots, id: \.self) { index in
                    slot(index < weeks.count ? weeks[index] : nil)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
            }

            HStack(spacing: 12) {
                legend(fill: AnyShapeStyle(color.gradient), title: "Used")
                legend(fill: AnyShapeStyle(Color(.tertiarySystemFill)), title: "Not used")
                Spacer(minLength: 8)
                Text("Last \(slots) weeks")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last ^[\(weeks.count) check-in](inflect: true): used \(weeks.filter(\.used).count)"))
    }

    @ViewBuilder
    private func slot(_ week: SubscriptionStats.WeekUsage?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if let week {
            // A checkmark on used weeks, so the strip doesn't rely on color alone
            // (a gray or brown tint would look like the gray "not used" fill).
            shape.fill(week.used ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
                .overlay {
                    if week.used {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color.contrastingForeground(in: environment))
                    }
                }
        } else {
            shape.strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func legend(fill: AnyShapeStyle, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }
}

#Preview {
    let container = PreviewData.container
    let subscription = try? container.mainContext.fetch(FetchDescriptor<Subscription>()).first
    return NavigationStack {
        if let subscription {
            SubscriptionDetailView(subscription: subscription)
        }
    }
    .modelContainer(container)
}
