//
//  BudgetStepView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//



import SwiftUI

struct BudgetStepView: View {
    @Bindable var model: OnboardingViewModel
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isPickingCurrency = false
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 64

    private var subtitle: LocalizedStringKey {
        model.trimmedName.isEmpty
            ? "Set a monthly limit for your subscriptions. We'll let you know when you're getting close."
            : "Nice to meet you, \(model.trimmedName). Set a monthly limit and we'll let you know when you're getting close."
    }

    var body: some View {
        OnboardingStepLayout(
            step: .budget,
            symbol: "banknote",
            title: "What's your monthly budget?",
            subtitle: subtitle,
            onSkip: skip
        ) {
            VStack(spacing: 12) {
                amountCard

                Text("You can change this anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            OnboardingPrimaryButton("Continue", isEnabled: model.canContinueFromBudget, action: submit)
        }
        .onChange(of: model.budgetText) { _, newValue in
            let clean = sanitize(newValue)
            if clean != newValue { model.budgetText = clean }
        }
        .onChange(of: model.currency) { _, _ in
            // e.g. switching EUR → JPY drops decimals that JPY doesn't have.
            model.budgetText = sanitize(model.budgetText)
        }
        .sheet(isPresented: $isPickingCurrency, onDismiss: { isFocused = true }) {
            CurrencyPickerView(selection: $model.currency)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            isFocused = true
        }
    }

    // MARK: Amount card

    private var amountCard: some View {
        VStack(spacing: 16) {
            // A real text field, so the cursor, paste, select-all and hardware keyboards all work.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if model.currency.symbolLeads { currencySymbol }
                TextField("0", text: $model.budgetText)
                    .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .focused($isFocused)
                    .accessibilityLabel(Text("Monthly budget"))
                if !model.currency.symbolLeads { currencySymbol }
            }
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            currencyButton
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var currencyButton: some View {
        Button {
            isPickingCurrency = true
        } label: {
            HStack(spacing: 6) {
                Text(model.currency.name)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            // The bordered style adds ~7 pt above and below, so the button ends up 44 pt tall.
            .frame(minHeight: AppMetrics.minimumHitTarget - 14)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(model.currency.name))
        .accessibilityHint(Text("Shows a list of currencies"))
    }

    // MARK: Formatting

    /// Scales with Dynamic Type, capped so long amounts still fit on one line.
    private var amountFontSize: CGFloat { min(amountSize, 96) }

    private var currencySymbol: some View {
        Text(model.currency.symbol)
            .font(.system(size: amountFontSize * 0.6, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)   // The currency button below speaks it.
    }

    private func sanitize(_ text: String) -> String {
        OnboardingViewModel.sanitizedAmount(text, maxFractionDigits: model.currency.fractionDigits)
    }

    // MARK: Actions

    private func submit() {
        guard model.canContinueFromBudget else { return }
        isFocused = false
        onContinue()
    }

    private func skip() {
        model.budgetText = ""
        isFocused = false
        onContinue()
    }
}

#Preview {
    NavigationStack {
        BudgetStepView(model: OnboardingViewModel(), onContinue: {})
    }
}
