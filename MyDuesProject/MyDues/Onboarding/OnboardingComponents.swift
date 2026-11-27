//
//  OnboardingComponents.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//



import SwiftUI

// MARK: - Bottom action bar

extension View {
    /// Pins the step's main action to the bottom, above the keyboard, in a bar with the
    /// system scroll-edge effect so content fades under Liquid Glass.
    func onboardingActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let content = bar()
            .padding(.horizontal, AppMetrics.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: AppMetrics.readableWidth)
            .frame(maxWidth: .infinity)

        return safeAreaBar(edge: .bottom, spacing: 0) { content }
    }
}

// MARK: - Primary button

/// The one prominent action per screen. Liquid Glass on iOS 26, filled capsule before that.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    init(_ title: LocalizedStringKey, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

// MARK: - Step layout

/// Header (symbol + title + subtitle), scrollable content and a pinned action bar that rides above the keyboard.
struct OnboardingStepLayout<Content: View, Footer: View>: View {
    let step: OnboardingStep
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let onSkip: (() -> Void)?
    let content: Content
    let footer: Footer

    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 40

    init(
        step: OnboardingStep,
        symbol: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        onSkip: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.step = step
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.onSkip = onSkip
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                content
            }
            .padding(.horizontal, AppMetrics.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: AppMetrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onboardingActionBar { footer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StepIndicator(current: step.number, total: OnboardingStep.total)
            }
            if let onSkip {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: onSkip)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.smooth, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current) of \(total)"))
    }
}

// MARK: - Selectable chip

/// Content-layer control: uses standard fills, not Liquid Glass (HIG: no glass in the content layer).
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .frame(minHeight: AppMetrics.minimumHitTarget)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Flow layout

/// Wraps children onto new lines like tags. Leading-aligned.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // Very large Dynamic Type: let the child use the full row.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let height = frames.isEmpty ? 0 : y + rowHeight
        return (frames, CGSize(width: usedWidth, height: height))
    }
}
