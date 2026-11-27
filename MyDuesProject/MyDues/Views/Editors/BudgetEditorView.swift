//
//  BudgetEditorView.swift
//  MyDues
//
//  Edit or remove the monthly budget. The currency lives in Settings.
//


import SwiftUI

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OnboardingKeys.monthlyBudget) private var budgetString = ""
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @State private var amountText = ""
    @State private var didLoad = false
    @FocusState private var isAmountFocused: Bool

    private var currency: CurrencyOption { CurrencyOption(code: currencyCode) }
    private var amount: Decimal? { amountText.isEmpty ? nil : Decimal(string: amountText, locale: .current) }
    private var hasBudget: Bool { BillingMath.storedAmount(budgetString) != nil }
    private var canSave: Bool { (amount ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                        Text(currency.code)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Monthly Budget")
                } footer: {
                    Text("You'll see a warning on Home when your subscriptions get close to this amount.")
                }

                if hasBudget {
                    Section {
                        Button("Remove Budget", role: .destructive) {
                            budgetString = ""
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Save", isEnabled: canSave, action: save)
                }
            }
            .onChange(of: amountText) { _, newValue in
                let clean = sanitize(newValue)
                if clean != newValue { amountText = clean }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func sanitize(_ text: String) -> String {
        OnboardingViewModel.sanitizedAmount(text, maxFractionDigits: currency.fractionDigits)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let stored = BillingMath.storedAmount(budgetString) {
            amountText = sanitize(BillingMath.storedString(stored))   // "1500.5" → "1500,5" in comma locales
        }
        isAmountFocused = true
    }

    private func save() {
        guard canSave else { return }
        if let amount, amount > 0 {
            budgetString = BillingMath.storedString(amount)
        }
        dismiss()
    }
}

#Preview {
    BudgetEditorView()
}
