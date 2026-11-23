//
//  AppComponents.swift
//  DuelyProject
//
//  Small views shared across tabs.
//

import SwiftUI
import SwiftData

// MARK: - Constants

enum AppMetrics {
    /// Keeps text at a readable line length on iPad and in landscape.
    static let readableWidth: CGFloat = 560
    static let horizontalPadding: CGFloat = 24
    /// HIG minimum hit target on iOS.
    static let minimumHitTarget: CGFloat = 44
}

enum AppDefaults {
    /// Fallback for `OnboardingKeys.currencyCode` before the user picks one.
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
}

// MARK: - Card

extension View {
    /// Grouped-content card used on Home. Standard system fills keep it correct in Dark Mode
    /// and with Increase Contrast; no Liquid Glass here because cards are content, not controls.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Adaptive stack

/// A row that stacks vertically at accessibility text sizes, so long text and large numbers
/// never get squeezed side by side (HIG: Dynamic Type layouts should adapt, not truncate).
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                InlineTextButton(actionTitle, action: action)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Small text button that still has a 44 pt tall hit target.
struct InlineTextButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .frame(minHeight: AppMetrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Contrast

extension Color {
    /// White or black, whichever reads on top of this color. White is kept while it reaches
    /// 3:1 (WCAG for large text and glyphs); light tints like yellow or mint get black.
    func contrastingForeground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        // Relative luminance needs linear components (`red`/`green`/`blue` are gamma-encoded).
        let luminance = 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
        let whiteContrast = 1.05 / (luminance + 0.05)
        return whiteContrast >= 3 ? .white : .black
    }
}

// MARK: - Monogram

/// Brand-neutral tile: first letter on the subscription's color. Real logos need each brand's permission.
struct MonogramTile: View {
    let name: String
    let color: Color
    @ScaledMetric private var size: CGFloat
    private let baseSize: CGFloat

    @Environment(\.self) private var environment

    init(name: String, color: Color, size: CGFloat = 40) {
        self.name = name
        self.color = color
        self.baseSize = size
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    init(subscription: Subscription, size: CGFloat = 40) {
        self.init(name: subscription.name, color: subscription.displayColor, size: size)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// Grows with Dynamic Type, but never more than double, so rows keep room for text.
    private var tileSize: CGFloat { min(size, baseSize * 2) }

    var body: some View {
        RoundedRectangle(cornerRadius: tileSize * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: tileSize, height: tileSize)
            .overlay {
                Text(initial)
                    .font(.system(size: tileSize * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(color.contrastingForeground(in: environment))
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Sheet toolbar buttons

/// System ✕ button for dismissing a sheet without saving.
struct SheetCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button("Cancel", systemImage: "xmark", role: .close, action: action)
    }
}

/// Tinted ✓ button for confirming a sheet. Multi-step flows pass an arrow for "Next".
struct SheetConfirmButton: View {
    let title: LocalizedStringKey
    var systemImage = "checkmark"
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, role: .confirm, action: action)
            .disabled(!isEnabled)
    }
}
