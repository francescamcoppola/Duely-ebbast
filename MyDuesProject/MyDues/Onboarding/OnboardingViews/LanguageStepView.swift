//
//  LanguageStepView.swift
//  MyDues
//
//  The very first screen: the app's language, preset to the device's. Picking one switches the
//  whole app to it right away, so the rest of onboarding is already in that language.
//

import SwiftUI

struct LanguageStepView: View {
    let onContinue: () -> Void

    @State private var controller = LanguageController.shared
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: symbolSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Language")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("You can change this anytime in Settings.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(option)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, AppMetrics.horizontalPadding)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .frame(maxWidth: AppMetrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .scrollBounceBehavior(.basedOnSize)
        .onboardingActionBar {
            OnboardingPrimaryButton("Continue", action: onContinue)
        }
        .sensoryFeedback(.selection, trigger: controller.language)
    }

    private func row(_ option: AppLanguage) -> some View {
        let isSelected = controller.language == option
        return Button {
            withAnimation(.smooth(duration: 0.35)) { controller.change(to: option) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = option.nativeName {
                        Text(verbatim: name)
                    } else {
                        Text("Device Language")
                        if let device = AppLanguage(rawValue: AppLanguage.system.localization)?.nativeName {
                            Text(verbatim: device)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    LanguageStepView(onContinue: {})
}
