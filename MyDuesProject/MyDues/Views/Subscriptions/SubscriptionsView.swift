//
//  SubscriptionsView.swift
//  MyDues
//
//  Plan management: every subscription once, searchable and sortable, drilling into a detail screen.
//  Payments (dates) live in Calendar; totals live in Home.
//

import SwiftUI
import SwiftData

enum SubscriptionSort: String, CaseIterable, Identifiable {
    case name, cost, nextPayment

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .name: "Name"
        case .cost: "Monthly Cost"
        case .nextPayment: "Next Payment"
        }
    }

    var symbol: String {
        switch self {
        case .name: "textformat"
        case .cost: "banknote"
        case .nextPayment: "calendar"
        }
    }
}

struct SubscriptionsView: View {
    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @AppStorage("subscriptionsSort") private var sort: SubscriptionSort = .name

    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var isAdding = false
    @State private var editingSubscription: Subscription?
    @State private var pendingSetup: PendingSetup?
    @State private var pendingDelete: Subscription?

    // MARK: Data

    private var filtered: [Subscription] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return subscriptions }
        return subscriptions.filter { $0.name.localizedStandardContains(term) }
    }

    private var needsSetup: [Subscription] { filtered.filter(\.needsSetup) }

    private var active: [Subscription] {
        let configured = filtered.filter { !$0.needsSetup }
        switch sort {
        case .name:
            return configured.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .cost:
            return configured.sorted { $0.monthlyCost > $1.monthlyCost }
        case .nextPayment:
            return configured.sorted {
                ($0.nextPayment() ?? .distantFuture) < ($1.nextPayment() ?? .distantFuture)
            }
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Subscriptions")
            .navigationDestination(for: Subscription.self) { subscription in
                SubscriptionDetailView(subscription: subscription)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sort) {
                            ForEach(SubscriptionSort.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(subscriptions.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Subscription", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                SubscriptionEditorView(subscription: nil)
            }
            .sheet(item: $editingSubscription) { subscription in
                SubscriptionEditorView(subscription: subscription)
            }
            .sheet(item: $pendingSetup) { setup in
                PendingSetupFlow(setup)
            }
            .confirmationDialog(
                Text("Delete \(pendingDelete?.name ?? "")?"),
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { subscription in
                Button("Delete Subscription", role: .destructive) {
                    delete(subscription)
                }
            } message: { _ in
                Text("Its check-in history will be deleted too.")
            }
        }
    }

    private var list: some View {
        List {
            if !needsSetup.isEmpty {
                Section {
                    ForEach(needsSetup) { subscription in
                        Button {
                            // Continues through the rest of "Needs Setup" after this one.
                            pendingSetup = PendingSetup(starting: subscription, in: needsSetup)
                        } label: {
                            SubscriptionRow(subscription: subscription, currencyCode: currencyCode)
                        }
                        .foregroundStyle(.primary)
                        .rowActions(for: subscription, edit: { editingSubscription = $0 }, delete: { pendingDelete = $0 })
                    }
                } header: {
                    Text("Needs Setup")
                } footer: {
                    Text("Add a price and payment date to include these in your totals.")
                }
            }

            if !active.isEmpty {
                Section {
                    ForEach(active) { subscription in
                        NavigationLink(value: subscription) {
                            SubscriptionRow(subscription: subscription, currencyCode: currencyCode)
                        }
                        .rowActions(for: subscription, edit: { editingSubscription = $0 }, delete: { pendingDelete = $0 })
                    }
                } header: {
                    if !needsSetup.isEmpty { Text("Active") }
                } footer: {
                    Text("^[\(active.count) active subscription](inflect: true)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: Text("Search"))
        .overlay {
            if !query.isEmpty && filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .animation(.smooth, value: sort)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Subscriptions Yet", systemImage: "rectangle.stack")
        } description: {
            Text("Add the services you pay for to keep track of their cost and renewal dates.")
        } actions: {
            Button("Add Subscription") { isAdding = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }

    private func delete(_ subscription: Subscription) {
        context.delete(subscription)
        try? context.save()
        pendingDelete = nil
    }
}

// MARK: - Row actions

private extension View {
    /// Same actions by swipe and by long press, so they're discoverable either way.
    func rowActions(
        for subscription: Subscription,
        edit: @escaping (Subscription) -> Void,
        delete: @escaping (Subscription) -> Void
    ) -> some View {
        self
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // No `.destructive` role: that role removes the row before the user confirms.
                Button("Delete", systemImage: "trash") { delete(subscription) }
                    .tint(.red)
                Button("Edit", systemImage: "pencil") { edit(subscription) }
                    .tint(.gray)
            }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { edit(subscription) }
                Button("Delete", systemImage: "trash", role: .destructive) { delete(subscription) }
            }
    }
}

// MARK: - Row

struct SubscriptionRow: View {
    let subscription: Subscription
    let currencyCode: String

    var body: some View {
        AdaptiveStack(spacing: 14) {
            MonogramTile(subscription: subscription, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subscription.category.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if subscription.needsSetup {
                Text("Add Details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Group {
                        if subscription.isFree {
                            Text("Free")
                        } else {
                            Text(subscription.price, format: .currency(code: currencyCode))
                        }
                    }
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Group {
                        if subscription.isInTrial() {
                            Text("Free Trial")
                                .foregroundStyle(DeadlineItem.Kind.trial.color)
                        } else if subscription.hasEnded() {
                            Text("Ended")
                        } else if let left = subscription.remainingPayments() {
                            Text("^[\(left) payment](inflect: true) left")
                        } else {
                            Text(subscription.cycle.title)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("With data") {
    SubscriptionsView()
        .modelContainer(PreviewData.container)
}

#Preview("Empty") {
    SubscriptionsView()
        .modelContainer(PreviewData.emptyContainer)
}
