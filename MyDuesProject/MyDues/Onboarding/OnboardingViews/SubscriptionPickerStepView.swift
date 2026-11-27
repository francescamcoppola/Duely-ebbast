//
//  SubscriptionPickerStepView.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//


import SwiftUI

struct SubscriptionPickerStepView: View {
    @Bindable var model: OnboardingViewModel
    let onFinish: () -> Void

    private var selectedCount: Int { model.selectedServiceIDs.count }

    var body: some View {
        OnboardingStepLayout(
            step: .subscriptions,
            symbol: "rectangle.stack.badge.plus",
            title: "Which subscriptions do you have?",
            subtitle: "Pick up to \(OnboardingViewModel.maxStarterSelections) to get started. You can add more later.",
            onSkip: skip
        ) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(StarterCatalog.categories) { category in
                    section(for: category)
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Text("\(selectedCount) of \(OnboardingViewModel.maxStarterSelections) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: selectedCount)

                OnboardingPrimaryButton("Continue", isEnabled: selectedCount > 0, action: onFinish)
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedServiceIDs)
    }

    private func section(for category: StarterCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(LocalizedStringKey(category.title))
            } icon: {
                Image(systemName: category.symbol)
                    .foregroundStyle(category.tint)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(category.services) { service in
                    let isSelected = model.isSelected(service)
                    SelectableChip(
                        title: service.name,
                        isSelected: isSelected,
                        isDisabled: !isSelected && !model.canSelectMore
                    ) {
                        model.toggle(service)
                    }
                }
            }
        }
    }

    private func skip() {
        model.selectedServiceIDs.removeAll()
        onFinish()
    }
}

#Preview {
    NavigationStack {
        SubscriptionPickerStepView(model: OnboardingViewModel(), onFinish: {})
    }
}
