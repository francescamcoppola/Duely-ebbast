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
    @AppStorage(OnboardingKeys.languageChosen) private var languageChosen = false

    var body: some View {
        if !languageChosen {
            LanguageStepView {
                withAnimation(.smooth) { languageChosen = true }
            }
            .transition(.opacity)
        } else {
            NavigationStack(path: $model.path) {
                WelcomeStepView {
                    model.go(to: .name)
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step)
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .name:
            NameStepView(model: model) { model.go(to: .budget) }
        case .budget:
            BudgetStepView(model: model) {
                model.go(to: EmailStepView.isAvailable ? .email : .subscriptions)
            }
        case .email:
            EmailStepView(onConnected: { finish(scanEmail: true) },
                          onManual: { model.go(to: .subscriptions) })
        case .subscriptions:
            SubscriptionPickerStepView(model: model) { finish(scanEmail: false) }
        }
    }

    /// With Gmail connected, the manual pick is skipped: the scan starts now and its results
    /// are shown on Home for review.
    private func finish(scanEmail: Bool) {
        model.save()
        if scanEmail {
            EmailImportModel.shared.startScan(existing: [], presentResultsOnHome: true)
        } else {
            StarterSeeder.insert(serviceIDs: model.selectedServiceIDs, into: context)
        }
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
