//
//  PurchaseDetailView.swift
//  DuelyProject
//
//  One order: its return window and warranty, editable in place like a Reminders item, with
//  the store's orders page one tap away. `NewPurchaseView` adds one by hand.
//

import SwiftUI
import SwiftData

// MARK: - Shared form

/// What, where, how much and when: the fields the deadlines are worked out from.
private struct PurchaseFields: View {
    @Bindable var purchase: Purchase
    let currencyCode: String

    @State private var isDelivered = false
    @State private var didLoad = false

    var body: some View {
        Section {
            TextField("Item", text: $purchase.title)
                .textInputAutocapitalization(.sentences)
            TextField("Store", text: $purchase.store)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            AmountField(title: "Price", amount: $purchase.price, currencyCode: currencyCode)
        }

        Section {
            DatePicker("Ordered", selection: $purchase.orderDate, in: ...Date.now, displayedComponents: .date)
            Toggle("Delivered", isOn: $isDelivered.animation())
            if isDelivered {
                DatePicker("Delivery Date", selection: deliveryDate, in: purchase.orderDate..., displayedComponents: .date)
            }
        } footer: {
            if !isDelivered {
                Text("Until it's delivered, the deadlines assume it arrives \(ReturnPolicy.estimatedDeliveryDays) days after the order.")
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            isDelivered = purchase.deliveryDate != nil
        }
        .onChange(of: isDelivered) { _, delivered in
            purchase.deliveryDate = delivered ? max(purchase.deliveryDate ?? .now, purchase.orderDate) : nil
            purchase.recomputeDeadlines()
        }
        .onChange(of: purchase.orderDate) { purchase.recomputeDeadlines() }
        .onChange(of: purchase.deliveryDate) { purchase.recomputeDeadlines() }
        .onChange(of: purchase.store) { purchase.recomputeDeadlines() }
    }

    private var deliveryDate: Binding<Date> {
        Binding { purchase.deliveryDate ?? .now } set: { purchase.deliveryDate = Calendar.current.startOfDay(for: $0) }
    }
}

/// Return window and warranty, with their reminder switches.
private struct PurchaseDeadlineSections: View {
    @Bindable var purchase: Purchase
    let currencyCode: String

    var body: some View {
        Section {
            if let returnBy = purchase.returnBy {
                LabeledContent("Return By") {
                    Text(returnBy, format: .dateTime.day().month(.wide).year())
                        .foregroundStyle(purchase.isReturnOpen() ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
            Toggle("Return Reminder", isOn: $purchase.returnReminderEnabled)
        } header: {
            Text("Return")
        } footer: {
            if purchase.isReturned {
                Text("Marked as returned.")
            } else if purchase.returnByIsEstimated {
                Text("Estimated from the order date. Set the delivery date for the exact deadline.")
            } else {
                Text("Reminders \(ReminderPlanner.returnDaysBefore) days before and on the last day.")
            }
        }

        Section {
            if let until = purchase.warrantyUntil {
                LabeledContent("Warranty Until") {
                    Text(until, format: .dateTime.day().month(.wide).year())
                }
            }
            Toggle("Warranty Reminder", isOn: $purchase.warrantyReminderEnabled)
        } header: {
            Text("Warranty")
        } footer: {
            Text("The legal warranty lasts 2 years from delivery. The reminder comes a month before it ends.")
        }
    }
}

// MARK: - Detail

struct PurchaseDetailView: View {
    @Bindable var purchase: Purchase

    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            PurchaseFields(purchase: purchase, currencyCode: currencyCode)
            PurchaseDeadlineSections(purchase: purchase, currencyCode: currencyCode)

            Section {
                if let url = purchase.ordersPageURL, !purchase.isReturned {
                    // In Safari, where the user is signed in to the store.
                    Button(purchase.isAmazon ? LocalizedStringKey("Open Amazon Orders") : LocalizedStringKey("Open \(purchase.store)"),
                           systemImage: "arrow.up.forward.app") {
                        openURL(url)
                    }
                }
                Button(purchase.isReturned ? "Mark as Not Returned" : "Mark as Returned",
                       systemImage: purchase.isReturned ? "arrow.uturn.backward" : "shippingbox.and.arrow.backward") {
                    withAnimation { purchase.returnedAt = purchase.isReturned ? nil : .now }
                }
            } footer: {
                if let number = purchase.orderNumber {
                    Text("Order \(number)")
                }
            }

            Section {
                Button("Delete Purchase", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(purchase.title.isEmpty ? String(appLocalized: "Purchase") : purchase.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .confirmationDialog(Text("Delete \(purchase.title)?"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Purchase", role: .destructive) {
                context.delete(purchase)
                try? context.save()
                dismiss()
            }
        }
    }
}

// MARK: - New

struct NewPurchaseView: View {
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Not inserted until Add, so Cancel leaves nothing behind.
    @State private var purchase = Purchase(title: "", store: "Amazon", orderDate: .now, websiteDomain: "amazon.it")

    private var canAdd: Bool {
        !purchase.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !purchase.store.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                PurchaseFields(purchase: purchase, currencyCode: currencyCode)
                PurchaseDeadlineSections(purchase: purchase, currencyCode: currencyCode)
            }
            .navigationTitle("New Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Add", isEnabled: canAdd) {
                        purchase.title = purchase.title.trimmingCharacters(in: .whitespaces)
                        purchase.store = purchase.store.trimmingCharacters(in: .whitespaces)
                        if !ReturnPolicy.isAmazon(purchase.store) { purchase.websiteDomain = nil }
                        context.insert(purchase)
                        try? context.save()
                        Task { await NotificationService.requestAuthorizationIfNeeded() }
                        dismiss()
                    }
                }
            }
            // The warranty reminder follows the price until the user sets it.
            .onChange(of: purchase.price) { _, price in
                purchase.warrantyReminderEnabled = WarrantyPolicy.remindsByDefault(price: price)
            }
        }
        .interactiveDismissDisabled(canAdd)
    }
}

#Preview {
    NavigationStack {
        PurchaseDetailView(purchase: Purchase(title: "AirPods Pro", store: "Amazon", orderDate: .now.addingTimeInterval(-86_400 * 5),
                                              deliveryDate: .now.addingTimeInterval(-86_400 * 3), price: 249))
    }
    .modelContainer(PreviewData.emptyContainer)
}
