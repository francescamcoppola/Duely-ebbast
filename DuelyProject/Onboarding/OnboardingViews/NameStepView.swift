//
//  NameStepView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//


import SwiftUI

struct NameStepView: View {
    @Bindable var model: OnboardingViewModel
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool
    /// Bumped each time input is cut at the limit; drives a light haptic.
    @State private var limitHits = 0

    private let maxLength = OnboardingViewModel.maxNameLength
    private var count: Int { model.name.count }
    /// The counter only appears near the limit, so it never adds noise for typical names.
    private var showsCounter: Bool { count >= maxLength - 5 }

    var body: some View {
        OnboardingStepLayout(
            step: .name,
            symbol: "person.crop.circle",
            title: "What should we call you?",
            subtitle: "We'll use your name to personalize your experience.",
            onSkip: skip
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                nameField

                Text("\(count)/\(maxLength)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(count >= maxLength ? Color.primary : Color.secondary)
                    .padding(.trailing, 4)
                    .opacity(showsCounter ? 1 : 0)
                    .accessibilityHidden(!showsCounter)
                    .accessibilityLabel(Text("\(count) of \(maxLength) characters"))
                    .animation(.smooth(duration: 0.2), value: showsCounter)
            }
        } footer: {
            OnboardingPrimaryButton("Continue", isEnabled: model.canContinueFromName, action: submit)
        }
        .onChange(of: model.name) { _, newValue in
            let limited = OnboardingViewModel.limitedName(newValue, maxLength: maxLength)
            if limited != newValue {
                model.name = limited
                limitHits += 1
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: limitHits)
        .task {
            // Wait for the push transition to finish; focusing earlier is ignored by UIKit.
            try? await Task.sleep(for: .milliseconds(450))
            isFocused = true
        }
    }

    private var nameField: some View {
        HStack(spacing: 0) {
            TextField("Your name", text: $model.name)
                .font(.title3)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($isFocused)
                .onSubmit(submit)
                .padding(.vertical, 14)

            // HIG: a Clear button at the trailing end helps people erase their input.
            if !model.name.isEmpty {
                Button {
                    model.name = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: AppMetrics.minimumHitTarget,
                               height: AppMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear name"))
                .transition(.opacity)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, model.name.isEmpty ? 16 : 0)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.15), value: model.name.isEmpty)
    }

    private func submit() {
        guard model.canContinueFromName else { return }
        isFocused = false
        onContinue()
    }

    private func skip() {
        model.name = ""
        isFocused = false
        onContinue()
    }
}

#Preview {
    NavigationStack {
        NameStepView(model: OnboardingViewModel(), onContinue: {})
    }
}
