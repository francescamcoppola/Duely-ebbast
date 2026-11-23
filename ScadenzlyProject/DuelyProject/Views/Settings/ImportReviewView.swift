//
//  ImportReviewView.swift
//  DuelyProject
//
//  The subscriptions found in email, all selected by default. Nothing is added until the user
//  taps Add; every detail can still be edited afterwards like any other subscription.
//

import SwiftUI

struct ImportReviewView: View {
    let candidates: [DetectedSubscription]
    let onAdd: ([DetectedSubscription]) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @State private var selection: Set<String>

    init(candidates: [DetectedSubscription], onAdd: @escaping ([DetectedSubscription]) -> Void) {
        self.candidates = candidates
        self.onAdd = onAdd
        _selection = State(initialValue: Set(candidates.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("No New Subscriptions", systemImage: "envelope.open")
                    } description: {
                        Text("No receipts or renewals were found for subscriptions that aren't in \(AppInfo.name) yet.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Found in Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                if !candidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(title: "Add", isEnabled: !selection.isEmpty) {
                            onAdd(candidates.filter { selection.contains($0.id) })
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        toggle(candidate)
                    } label: {
                        CandidateRow(candidate: candidate,
                                     currencyCode: currencyCode,
                                     isSelected: selection.contains(candidate.id))
                    }
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(selection.contains(candidate.id) ? .isSelected : [])
                }
            } header: {
                Text("\(selection.count) of \(candidates.count) selected")
            } footer: {
                Text("Found on this device by Apple Intelligence, which can make mistakes. Check the details: you can edit any subscription after adding it.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggle(_ candidate: DetectedSubscription) {
        if selection.contains(candidate.id) {
            selection.remove(candidate.id)
        } else {
            selection.insert(candidate.id)
        }
    }
}

// MARK: - Row

private struct CandidateRow: View {
    let candidate: DetectedSubscription
    let currencyCode: String
    let isSelected: Bool

    private var nextPayment: Date? {
        BillingMath.nextPayment(anchor: candidate.paymentDate, cycle: candidate.cycle, onOrAfter: .now)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            MonogramTile(name: candidate.name, color: candidate.category.color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                priceLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let nextPayment {
                    Text("Next payment \(Text(nextPayment, format: .dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if candidate.differsFromCurrency(currencyCode), let code = candidate.currencyCode {
                    Label("Billed in \(code), saved without conversion", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var priceLine: some View {
        if let price = candidate.price {
            Text("\(Text(price, format: .currency(code: candidate.currencyCode ?? currencyCode))) · \(Text(candidate.cycle.title))")
        } else {
            Text("No price found · Needs setup")
        }
    }
}

#Preview {
    ImportReviewView(candidates: [
        DetectedSubscription(name: "Netflix", price: 13.99, currencyCode: "EUR", cycle: .monthly, cycleIsKnown: true,
                             category: .filmTV, paymentDate: .now, emailSubject: "Your receipt", emailDate: .now),
        DetectedSubscription(name: "iCloud+", price: nil, currencyCode: nil, cycle: .monthly, cycleIsKnown: false,
                             category: .utilities, paymentDate: .now, emailSubject: "Renewal", emailDate: .now),
    ]) { _ in }
}
