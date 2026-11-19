//
//  OnboardingView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//


import SwiftUI
import SwiftData

struct OnboardingView: View {
    /// Called after the data is saved. The owner flips `hasCompletedOnboarding`.
    let onComplete: () -> Void

    @State private var model = OnboardingViewModel()
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeStepView {
                model.go(to: .name)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OnboardingStep.self) { step in
                destination(for: step)
            }
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .name:
            NameStepView(model: model) { model.go(to: .budget) }
        case .budget:
            BudgetStepView(model: model) { model.go(to: .subscriptions) }
        case .subscriptions:
            SubscriptionPickerStepView(model: model) { finish() }
        }
    }

    private func finish() {
        model.save()
        StarterSeeder.insert(serviceIDs: model.selectedServiceIDs, into: context)
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
