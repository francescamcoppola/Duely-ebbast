//
//  HomeCards.swift
//  DuelyProject
//
//  Each card answers one question, and no other screen repeats it:
//  • Overview — "How much do my subscriptions cost, and am I within budget?"
//  • Setup    — "What's missing?" (only while something is)
//  • Up Next  — "What's charged in the next two weeks?" (the Calendar tab owns the full schedule)
//  • Profile  — "What kind of spender am I?"
//  • Category — "Where does the money go?"
//  • Savings  — "Could I pay less for the same thing?" (SavingsCard.swift, only when I could)
//

import SwiftUI
import SwiftData

// MARK: - Overview

struct MonthlyOverviewCard: View {
    let summary: HomeSummary
    let currencyCode: String
    let onEditBudget: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusColor: Color {
        switch summary.budgetStatus {
        case .over: .red
        case .gettingClose: .orange
        case .onTrack, nil: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                // "Average": yearly plans are spread across 12 months, unlike Calendar's actual charges.
                Text("Average per month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                InlineTextButton(summary.budget == nil ? "Set Budget" : "Edit Budget", action: onEditBudget)
            }

            Text(summary.monthlyTotal, format: .currency(code: currencyCode))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let ratio = summary.budgetRatio, let budget = summary.budget, let remaining = summary.remaining {
                VStack(alignment: .leading, spacing: 8) {
                    BudgetBar(ratio: ratio, tint: statusColor)
                    AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
                        statusLabel
                        Spacer(minLength: 4)
                        Group {
                            if remaining >= 0 {
                                Text("\(Text(remaining, format: .currency(code: currencyCode))) left of \(Text(budget, format: .currency(code: currencyCode)))")
                            } else {
                                Text("\(Text(abs(remaining), format: .currency(code: currencyCode))) over budget")
                            }
                        }
                        .foregroundStyle(.secondary)
                        // Right-aligned beside the status; left-aligned once stacked below it.
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    }
                    .font(.footnote)
                }
                .accessibilityElement(children: .combine)
            }

            Divider()

            stat(title: "Per year", value: summary.yearlyTotal)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch summary.budgetStatus {
        case .over:
            Label("Over budget", systemImage: "exclamationmark.circle.fill").foregroundStyle(statusColor)
        case .gettingClose:
            Label("Getting close", systemImage: "exclamationmark.triangle.fill").foregroundStyle(statusColor)
        case .onTrack, nil:
            Label("On track", systemImage: "checkmark.circle.fill").foregroundStyle(statusColor)
        }
    }

    private func stat(title: LocalizedStringKey, value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetBar: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: 10)
        .animation(.smooth, value: ratio)
        .accessibilityHidden(true)   // The status label next to it says the same in words.
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard ratio > 0 else { return 0 }
        return max(width * min(ratio, 1), 10)   // Never thinner than its own height.
    }
}

// MARK: - Setup

struct SetupCard: View {
    let subscriptions: [Subscription]
    let onSelect: (Subscription) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish Setting Up")
                        .font(.headline)
                    Text("Add a price and payment date so ^[\(subscriptions.count) subscription](inflect: true) can count toward your budget.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(subscriptions) { subscription in
                    Button {
                        onSelect(subscription)
                    } label: {
                        HStack(spacing: 8) {
                            MonogramTile(subscription: subscription, size: 22)
                            Text(subscription.name)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint(Text("Add price and payment date"))
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Up Next

struct UpNextList: View {
    let items: [HomeSummary.Upcoming]
    let currencyCode: String
    let onSelect: (Subscription) -> Void

    var body: some View {
        if items.isEmpty {
            Label("Nothing due in the next two weeks.", systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .cardStyle()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item.subscription)
                    } label: {
                        UpcomingRow(item: item, currencyCode: currencyCode)
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider().padding(.leading, 74)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

private struct UpcomingRow: View {
    let item: HomeSummary.Upcoming
    let currencyCode: String

    private var isSoon: Bool { item.daysAway <= 1 }

    var body: some View {
        AdaptiveStack(spacing: 14) {
            DateTile(date: item.date, highlighted: isSoon)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.subscription.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(HomeSummary.relativeDay(item.daysAway))
                    .font(.subheadline)
                    .foregroundStyle(isSoon ? Color.red : Color.secondary)
            }

            Spacer(minLength: 8)

            Text(item.subscription.price, format: .currency(code: currencyCode))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows subscription details"))
    }
}

/// Calendar-style date chip, so a payment reads as "when", not as another subscription row.
private struct DateTile: View {
    let date: Date
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(highlighted ? Color.red : Color.secondary)
            Text(date, format: .dateTime.day())
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(minWidth: 44, minHeight: 48)   // Minimums, so larger text grows the tile instead of clipping.
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Spending profile

struct SpendingProfileCard: View {
    let profile: SpendingProfile
    let checkInWeeks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: profile.symbol)
                    .font(.title2)
                    .foregroundStyle(profile.tint)
                    .frame(width: 52, height: 52)
                    .background(profile.tint.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Spending profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.title)
                        .font(.title2.bold())
                }

                Spacer(minLength: 8)

                // Signals that the card opens the profile detail.
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(profile.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Label {
                if checkInWeeks == 0 {
                    Text("Based on your budget. Weekly check-ins will make it more accurate.")
                } else {
                    Text("Based on your budget and ^[\(checkInWeeks) week](inflect: true) of check-ins.")
                }
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows why you have this profile"))
    }
}

// MARK: - Spending by category

struct CategoryBreakdownCard: View {
    let shares: [HomeSummary.CategoryShare]
    let total: Decimal
    let currencyCode: String

    /// Minimum width of the amount column, so percentages line up across rows.
    @ScaledMetric(relativeTo: .subheadline) private var amountColumnWidth: CGFloat = 88

    private func fraction(_ share: HomeSummary.CategoryShare) -> Double {
        let totalValue = BillingMath.double(total)
        return totalValue > 0 ? BillingMath.double(share.amount) / totalValue : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("By Category")
                .font(.headline)

            StackedBar(segments: shares.map { (fraction: fraction($0), color: $0.category.color) })

            VStack(spacing: 0) {
                ForEach(shares) { share in
                    // Each row opens the subscriptions in that category ("which ones?").
                    NavigationLink {
                        CategoryDetailView(category: share.category)
                    } label: {
                        AdaptiveStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(share.category.color)
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(share.category.title)
                            }
                            Spacer(minLength: 0)
                            HStack(spacing: 10) {
                                Text(fraction(share), format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(share.amount, format: .currency(code: currencyCode))
                                    .monospacedDigit()
                                    .frame(minWidth: amountColumnWidth, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            // Numbers keep their natural width; the category name gives way instead.
                            .fixedSize()
                        }
                        .font(.subheadline)
                        .frame(minHeight: AppMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(Text("Shows the subscriptions in this category"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }
}

private struct StackedBar: View {
    let segments: [(fraction: Double, color: Color)]
    private let gap: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - gap * CGFloat(max(segments.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color.gradient)
                        .frame(width: max(usable * segment.fraction, 2))
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityHidden(true)   // The legend below carries the same data.
    }
}
