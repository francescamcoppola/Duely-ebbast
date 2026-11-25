//
//  ImportReviewView.swift
//  DuelyProject
//
//  What a scan found in email: subscriptions, online orders (returns and warranties) and pagoPA
//  notices, all selected by default. Nothing is added until the user taps Add; every detail can
//  still be edited afterwards.
//

import SwiftUI

struct ImportReviewView: View {
    let results: ScanResults
    let onAdd: (ScanResults) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @State private var selection: Set<String>

    init(results: ScanResults, onAdd: @escaping (ScanResults) -> Void) {
        self.results = results
        self.onAdd = onAdd
        _selection = State(initialValue: Set(
            results.subscriptions.map { Self.key(subscription: $0) }
                + results.purchases.map { Self.key(purchase: $0) }
                + results.notices.map { Self.key(notice: $0) }
        ))
    }

    private static func key(subscription: DetectedSubscription) -> String { "s:" + subscription.id }
    private static func key(purchase: DetectedPurchase) -> String { "p:" + purchase.id }
    private static func key(notice: DetectedNotice) -> String { "n:" + notice.id }

    private var chosen: ScanResults {
        ScanResults(
            subscriptions: results.subscriptions.filter { selection.contains(Self.key(subscription: $0)) },
            purchases: results.purchases.filter { selection.contains(Self.key(purchase: $0)) },
            notices: results.notices.filter { selection.contains(Self.key(notice: $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing New Found", systemImage: "envelope.open")
                    } description: {
                        Text("No receipts, renewals, orders or pagoPA notices were found that aren't in \(AppInfo.name) yet.")
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
                if !results.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(title: "Add", isEnabled: !selection.isEmpty) {
                            onAdd(chosen)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            if !results.subscriptions.isEmpty {
                Section {
                    ForEach(results.subscriptions) { candidate in
                        selectable(Self.key(subscription: candidate)) { isSelected in
                            CandidateRow(candidate: candidate, currencyCode: currencyCode, isSelected: isSelected)
                        }
                    }
                } header: {
                    Text("Subscriptions")
                }
            }

            if !results.purchases.isEmpty {
                Section {
                    ForEach(results.purchases) { candidate in
                        selectable(Self.key(purchase: candidate)) { isSelected in
                            PurchaseCandidateRow(candidate: candidate, currencyCode: currencyCode, isSelected: isSelected)
                        }
                    }
                } header: {
                    Text("Orders")
                } footer: {
                    Text("You'll be reminded before the return window closes. Purchases from \(Text(WarrantyPolicy.reminderThreshold, format: .currency(code: currencyCode))) also get a reminder before the 2-year warranty ends.")
                }
            }

            if !results.notices.isEmpty {
                Section {
                    ForEach(results.notices) { candidate in
                        selectable(Self.key(notice: candidate)) { isSelected in
                            NoticeCandidateRow(candidate: candidate, isSelected: isSelected)
                        }
                    }
                } header: {
                    Text("pagoPA Notices")
                } footer: {
                    Text("Pay them from the Deadlines tab, on pagoPA's official site.")
                }
            }

            Section {
            } footer: {
                Text("\(selection.count) of \(results.count) selected. Found on this device by Apple Intelligence, which can make mistakes. Check the details: you can edit anything after adding it.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func selectable(_ key: String, @ViewBuilder row: (Bool) -> some View) -> some View {
        let isSelected = selection.contains(key)
        return Button {
            if isSelected { selection.remove(key) } else { selection.insert(key) }
        } label: {
            row(isSelected)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Rows

private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

private struct CandidateRow: View {
    let candidate: DetectedSubscription
    let currencyCode: String
    let isSelected: Bool

    private var nextPayment: Date? {
        BillingMath.nextPayment(anchor: candidate.paymentDate, cycle: candidate.cycle, onOrAfter: .now)
    }

    var body: some View {
        HStack(spacing: 14) {
            SelectionMark(isSelected: isSelected)

            MonogramTile(name: candidate.name, color: candidate.category.color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                priceLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let trialEnd = candidate.trialEndDate {
                    Text("Free trial until \(Text(trialEnd, format: .dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(DeadlineItem.Kind.trial.color)
                } else if let nextPayment {
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

private struct PurchaseCandidateRow: View {
    let candidate: DetectedPurchase
    let currencyCode: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            SelectionMark(isSelected: isSelected)

            DeadlineIcon(kind: .returnWindow, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Group {
                    if let price = candidate.price {
                        Text("\(candidate.store) · \(Text(price, format: .currency(code: candidate.currencyCode ?? currencyCode)))")
                    } else {
                        Text(candidate.store)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                returnLine
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var returnLine: some View {
        let deadline = candidate.returnBy
        if deadline.date >= Calendar.current.startOfDay(for: .now) {
            Text("Returnable until \(Text(deadline.date, format: .dateTime.day().month().year()))")
                .foregroundStyle(DeadlineItem.Kind.returnWindow.color)
        } else {
            Text("Under warranty until \(Text(WarrantyPolicy.until(orderDate: candidate.orderDate, deliveryDate: candidate.deliveryDate), format: .dateTime.day().month().year()))")
                .foregroundStyle(.secondary)
        }
    }
}

private struct NoticeCandidateRow: View {
    let candidate: DetectedNotice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            SelectionMark(isSelected: isSelected)

            DeadlineIcon(kind: .notice, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Group {
                    if let amount = candidate.amount {
                        if candidate.reason.isEmpty || candidate.payee.isEmpty {
                            Text(amount, format: .currency(code: "EUR"))
                        } else {
                            Text("\(candidate.reason) · \(Text(amount, format: .currency(code: "EUR")))")
                        }
                    } else if !candidate.payee.isEmpty {
                        Text(candidate.reason)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let due = candidate.dueDate {
                    Text("Due \(Text(due, format: .dateTime.day().month().year()))")
                        .font(.caption)
                        .foregroundStyle(DeadlineItem.Kind.notice.color)
                }
                Text("Notice code \(candidate.code.groupedNoticeNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ImportReviewView(results: ScanResults(subscriptions: [
        DetectedSubscription(name: "Netflix", price: 13.99, currencyCode: "EUR", cycle: .monthly, cycleIsKnown: true,
                             category: .filmTV, paymentDate: .now, emailSubject: "Your receipt", emailDate: .now),
        DetectedSubscription(name: "iCloud+", price: nil, currencyCode: nil, cycle: .monthly, cycleIsKnown: false,
                             category: .utilities, paymentDate: .now, emailSubject: "Renewal", emailDate: .now),
    ])) { _ in }
}
