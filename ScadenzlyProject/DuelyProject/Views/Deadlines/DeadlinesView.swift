//
//  DeadlinesView.swift
//  DuelyProject
//
//  The Deadlines tab: orders that can still be returned, free trials about to turn into a
//  charge, pagoPA notices to pay and warranties, soonest first. Found in email or added by hand.
//

import SwiftUI
import SwiftData

struct DeadlinesView: View {
    @Query private var purchases: [Purchase]
    @Query private var notices: [PaymentNotice]
    @Query private var subscriptions: [Subscription]
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar

    @State private var isAddingPurchase = false
    @State private var isAddingNotice = false
    @State private var isShowingArchive = false

    private var items: [DeadlineItem] {
        DeadlineList.items(purchases: purchases, notices: notices, subscriptions: subscriptions, calendar: calendar)
    }

    private func items(_ kind: DeadlineItem.Kind) -> [DeadlineItem] {
        items.filter { $0.kind == kind }
    }

    /// Returned orders, paid notices and expired warranties, newest first.
    private var archivedPurchases: [Purchase] {
        purchases.filter { !$0.isReturnOpen(calendar: calendar) && !$0.isWarrantyActive(calendar: calendar) }
            .sorted { $0.orderDate > $1.orderDate }
    }

    private var paidNotices: [PaymentNotice] {
        notices.filter(\.isPaid).sorted { ($0.paidAt ?? .distantPast) > ($1.paidAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if purchases.isEmpty && notices.isEmpty && items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Deadlines")
            .navigationDestination(for: PersistentIdentifier.self) { id in
                destination(for: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .sheet(isPresented: $isAddingPurchase) {
                NewPurchaseView()
            }
            .sheet(isPresented: $isAddingNotice) {
                NewPaymentNoticeView()
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add Purchase", systemImage: "shippingbox") { isAddingPurchase = true }
            Button("Add pagoPA Notice", systemImage: "building.columns") { isAddingNotice = true }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private var list: some View {
        List {
            section(.returnWindow, header: "To Return",
                    footer: "Amazon: 30 days from delivery, until 31 January for orders placed in November and December. Other stores: at least 14 days, the EU right of withdrawal.")
            section(.trial, header: "Free Trials",
                    footer: "You get a reminder 2 days before each trial turns into a charge.")
            section(.notice, header: "pagoPA Notices",
                    footer: "Pay on pagoPA's official site, with the notice's codes already filled in.")
            section(.warranty, header: "Under Warranty",
                    footer: "The legal warranty in the EU lasts 2 years from delivery.")

            if !archivedPurchases.isEmpty || !paidNotices.isEmpty {
                Section(isExpanded: $isShowingArchive) {
                    ForEach(paidNotices) { notice in
                        NavigationLink(value: notice.persistentModelID) {
                            ArchiveRow(kind: .notice, title: notice.displayName,
                                       detail: Text("Paid"))
                        }
                    }
                    ForEach(archivedPurchases) { purchase in
                        NavigationLink(value: purchase.persistentModelID) {
                            ArchiveRow(kind: purchase.isReturned ? .returnWindow : .warranty, title: purchase.title,
                                       detail: purchase.isReturned ? Text("Returned") : Text("Warranty ended"))
                        }
                    }
                } header: {
                    Text("Archive")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func section(_ kind: DeadlineItem.Kind, header: LocalizedStringKey, footer: LocalizedStringKey) -> some View {
        let rows = items(kind)
        if !rows.isEmpty {
            Section {
                ForEach(rows) { item in
                    NavigationLink(value: item.target.modelID) {
                        DeadlineRow(item: item, currencyCode: currencyCode)
                    }
                    .swipeActions(edge: .trailing) { quickAction(for: item) }
                }
            } header: {
                Text(header)
            } footer: {
                Text(footer)
            }
        }
    }

    /// Swipe: mark a notice paid or an order returned.
    @ViewBuilder
    private func quickAction(for item: DeadlineItem) -> some View {
        switch item.target {
        case .notice(let notice):
            Button("Paid", systemImage: "checkmark.circle") {
                withAnimation { notice.paidAt = .now }
                try? context.save()
            }
            .tint(.green)
        case .purchase(let purchase) where item.kind == .returnWindow:
            Button("Returned", systemImage: "shippingbox.and.arrow.backward") {
                withAnimation { purchase.returnedAt = .now }
                try? context.save()
            }
            .tint(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func destination(for id: PersistentIdentifier) -> some View {
        if let purchase = purchases.first(where: { $0.persistentModelID == id }) {
            PurchaseDetailView(purchase: purchase)
        } else if let notice = notices.first(where: { $0.persistentModelID == id }) {
            PaymentNoticeDetailView(notice: notice)
        } else if let subscription = subscriptions.first(where: { $0.persistentModelID == id }) {
            SubscriptionDetailView(subscription: subscription)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Deadlines", systemImage: "calendar.badge.clock")
        } description: {
            Text("Orders you can still return, warranties, free trials and pagoPA notices appear here. Scan your email in Settings, or add them by hand.")
        } actions: {
            Button("Add Purchase") { isAddingPurchase = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            Button("Add pagoPA Notice") { isAddingNotice = true }
                .buttonBorderShape(.capsule)
        }
    }
}

private struct ArchiveRow: View {
    let kind: DeadlineItem.Kind
    let title: String
    let detail: Text

    var body: some View {
        HStack(spacing: 14) {
            DeadlineIcon(kind: kind, size: 32)
                .saturation(0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DeadlinesView()
        .modelContainer(PreviewData.container)
}
