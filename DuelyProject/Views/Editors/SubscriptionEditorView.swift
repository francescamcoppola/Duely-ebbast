//
//  SubscriptionEditorView.swift
//  DuelyProject
//
//  Add or edit a subscription. Presented as a sheet; standard Form so it matches Settings-style
//  editors people already know.
//

import SwiftUI
import SwiftData

struct SubscriptionEditorView: View {
    /// `nil` adds a new subscription.
    let subscription: Subscription?
    /// Called after a delete, so a detail screen underneath can close too.
    var onDeleted: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @State private var name = ""
    @State private var priceText = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var category: SubscriptionCategory = .other
    @State private var nextPayment = Date.now
    @State private var reminderDays = 1
    @State private var tint: SubscriptionTint?
    @State private var didLoad = false
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, price }

    private var currency: CurrencyOption { CurrencyOption(code: currencyCode) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var price: Decimal? { priceText.isEmpty ? nil : Decimal(string: priceText, locale: .current) }
    private var canSave: Bool { !trimmedName.isEmpty && (price ?? 0) > 0 }
    private var isNew: Bool { subscription == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MonogramTile(name: trimmedName.isEmpty ? "?" : trimmedName,
                                     color: tint?.color ?? category.color,
                                     size: 32)
                            .animation(.smooth(duration: 0.2), value: tint)
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .price }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(SubscriptionCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $tint, automaticColor: category.color)
                }

                Section {
                    HStack {
                        Text("Price")
                        Spacer(minLength: 16)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .price)
                        Text(currency.code)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Billing Cycle", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.title).tag(cycle)
                        }
                    }

                    DatePicker("Next Payment", selection: $nextPayment, displayedComponents: .date)
                } footer: {
                    if cycle != .monthly, let price, price > 0 {
                        Text("About \(Text(BillingMath.monthlyEquivalent(price: price, cycle: cycle), format: .currency(code: currencyCode))) per month.")
                    }
                }

                Section {
                    Picker("Reminder", selection: $reminderDays) {
                        ForEach(ReminderOption.all, id: \.self) { days in
                            Text(ReminderOption.title(days)).tag(days)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Subscription", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Subscription" : "Edit Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: isNew ? "Add" : "Save", isEnabled: canSave, action: save)
                }
            }
            .confirmationDialog(
                Text("Delete \(trimmedName.isEmpty ? String(localized: "this subscription") : trimmedName)?"),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Subscription", role: .destructive, action: delete)
            } message: {
                Text("Its check-in history will be deleted too.")
            }
            .onChange(of: priceText) { _, newValue in
                let clean = OnboardingViewModel.sanitizedAmount(newValue, maxFractionDigits: currency.fractionDigits)
                if clean != newValue { priceText = clean }
            }
            .onAppear(perform: load)
            .task {
                guard isNew else { return }
                try? await Task.sleep(for: .milliseconds(450))
                focusedField = .name
            }
        }
        // Unsaved edits shouldn't be lost by an accidental swipe-down.
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: Helpers

    private var hasChanges: Bool {
        guard let subscription else { return !trimmedName.isEmpty || !priceText.isEmpty }
        return trimmedName != subscription.name
            || price != (subscription.price > 0 ? subscription.price : nil)
            || cycle != subscription.cycle
            || category != subscription.category
            || reminderDays != subscription.reminderDaysBefore
            || tint != subscription.tint
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let subscription else { return }
        name = subscription.name
        cycle = subscription.cycle
        category = subscription.category
        reminderDays = ReminderOption.all.contains(subscription.reminderDaysBefore) ? subscription.reminderDaysBefore : 1
        tint = subscription.tint
        nextPayment = subscription.nextPayment() ?? .now
        if subscription.price > 0 {
            priceText = OnboardingViewModel.sanitizedAmount(
                BillingMath.storedString(subscription.price),
                maxFractionDigits: currency.fractionDigits
            )
        }
    }

    private func save() {
        guard canSave, let price else { return }

        let target: Subscription
        if let subscription {
            target = subscription
        } else {
            target = Subscription(name: trimmedName)
            context.insert(target)
        }
        target.name = trimmedName
        target.price = price
        target.cycle = cycle
        target.category = category
        target.anchorDate = Calendar.current.startOfDay(for: nextPayment)
        target.reminderDaysBefore = reminderDays
        target.tint = tint

        do {
            try context.save()
        } catch {
            assertionFailure("Save failed: \(error)")
        }
        dismiss()

        // The user just asked to be reminded: the natural moment for the system prompt (first time only).
        if reminderDays > 0 {
            Task { await NotificationService.requestAuthorizationIfNeeded() }
        }
    }

    private func delete() {
        guard let subscription else { return }
        context.delete(subscription)
        try? context.save()
        dismiss()
        onDeleted?()
    }
}

#Preview("New") {
    SubscriptionEditorView(subscription: nil)
        .modelContainer(PreviewData.container)
}
