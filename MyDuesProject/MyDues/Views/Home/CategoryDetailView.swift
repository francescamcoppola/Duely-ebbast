//
//  CategoryDetailView.swift
//  DuelyProject
//
//  "Which ones?" for a row in Home's By Category card: the subscriptions in one category,
//  most expensive first, each with its share of the category.
//

import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let category: SubscriptionCategory

    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    /// Configured subscriptions in this category, most expensive first.
    private var members: [Subscription] {
        subscriptions
            .filter { $0.category == category && !$0.needsSetup }
            .sorted { $0.monthlyCost > $1.monthlyCost }
    }

    /// Same category, but without a price yet, so not part of the total.
    private var unconfiguredCount: Int {
        subscriptions.filter { $0.category == category && $0.needsSetup }.count
    }

    private var categoryTotal: Decimal { members.reduce(Decimal.zero) { $0 + $1.monthlyCost } }

    private var allTotal: Decimal {
        subscriptions.filter { !$0.needsSetup }.reduce(Decimal.zero) { $0 + $1.monthlyCost }
    }

    var body: some View {
        List {
            header
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            if members.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: category.symbol,
                    description: Text("Nothing in this category counts toward your total right now.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(members) { subscription in
                        NavigationLink {
                            SubscriptionDetailView(subscription: subscription)
                        } label: {
                            CategoryMemberRow(
                                subscription: subscription,
                                share: share(of: subscription.monthlyCost, in: categoryTotal),
                                currencyCode: currencyCode
                            )
                        }
                    }
                } footer: {
                    if unconfiguredCount > 0 {
                        Text("^[\(unconfiguredCount) more subscription](inflect: true) in this category isn't counted until it has a price and payment date.")
                    } else {
                        Text("Yearly plans are shown as their monthly average.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: category.symbol)
                .font(.title)
                .foregroundStyle(category.color)
                .padding(14)
                .background(category.color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(categoryTotal, format: .currency(code: currencyCode))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text("per month · \(Text(share(of: categoryTotal, in: allTotal), format: .percent.precision(.fractionLength(0)))) of your subscriptions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func share(of part: Decimal, in whole: Decimal) -> Double {
        let wholeValue = BillingMath.double(whole)
        return wholeValue > 0 ? BillingMath.double(part) / wholeValue : 0
    }
}

// MARK: - Row

private struct CategoryMemberRow: View {
    let subscription: Subscription
    let share: Double
    let currencyCode: String

    var body: some View {
        AdaptiveStack(spacing: 14) {
            HStack(spacing: 14) {
                MonogramTile(subscription: subscription, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(subscription.cycle.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(subscription.monthlyCost, format: .currency(code: currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("\(Text(share, format: .percent.precision(.fractionLength(0)))) of category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(category: .filmTV)
    }
    .modelContainer(PreviewData.container)
}
