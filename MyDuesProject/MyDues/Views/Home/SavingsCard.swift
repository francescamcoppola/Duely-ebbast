//
//  SavingsCard.swift
//  MyDues
//
//  "Could I pay less for the same thing?" Shown on Home only while a cheaper plan or a similar,
//  cheaper service exists for something the user pays for. Each row opens that subscription,
//  where all its alternatives are listed.
//

import SwiftUI
import SwiftData

struct SavingsCard: View {
    struct Item: Identifiable {
        let subscription: Subscription
        let best: PlanAlternative
        var id: PersistentIdentifier { subscription.persistentModelID }
    }

    let items: [Item]
    let currencyCode: String
    let onSelect: (Subscription) -> Void

    static let rowsShown = 3

    private var total: Decimal { items.reduce(0) { $0 + $1.best.monthlySaving } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.forward.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ways to Save")
                        .font(.headline)
                    Text("You could pay up to \(Text(total, format: .currency(code: currencyCode))) less a month with cheaper plans or similar services.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(items.prefix(Self.rowsShown).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    Button {
                        onSelect(item.subscription)
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private func row(_ item: Item) -> some View {
        let option = item.best.option
        return HStack(spacing: 12) {
            MonogramTile(subscription: item.subscription, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.subscription.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if item.best.isSameService {
                        Text("Switch to \(option.plan.name)")
                    } else {
                        Text("Try \(option.service.name) \(option.plan.name)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("−\(Text(item.best.monthlySaving, format: .currency(code: currencyCode)))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.green)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
