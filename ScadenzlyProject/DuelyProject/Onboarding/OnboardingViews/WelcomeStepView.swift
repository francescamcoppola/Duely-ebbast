//
//  WelcomeStepView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//


import SwiftUI

struct WelcomeStepView: View {
    let onGetStarted: () -> Void

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var featureIconWidth: CGFloat = 44

    private struct Feature: Identifiable {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var id: String { symbol }
    }

    private var features: [Feature] {
        [
            Feature(symbol: "rectangle.stack",
                    title: "Everything in one place",
                    detail: "See every subscription you pay for, and what it costs you each month."),
            Feature(symbol: "bell.badge",
                    title: "Never miss a deadline",
                    detail: "Get reminded before each payment is due, so nothing renews by surprise."),
            Feature(symbol: "chart.pie",
                    title: "Know what's worth it",
                    detail: "Insights show which subscriptions you actually use for what you pay."),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 44) {
                hero
                featureList
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .frame(maxWidth: AppMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onboardingActionBar {
            OnboardingPrimaryButton("Get Started", action: onGetStarted)
        }
        .onAppear { isVisible = true }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            AppMark()
                .scaleEffect(isVisible || reduceMotion ? 1 : 0.85)
                .opacity(isVisible ? 1 : 0)
                .animation(.smooth(duration: 0.5), value: isVisible)

            VStack(spacing: 10) {
                Text("Welcome to \(AppInfo.name)")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Manage your subscriptions and deadlines in just one place.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: feature.symbol)
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: featureIconWidth)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible || reduceMotion ? 0 : 14)
                .animation(.smooth(duration: 0.5).delay(0.2 + Double(index) * 0.08), value: isVisible)
            }
        }
    }
}

/// The app's logo, square. Keep `AppLogo` in the asset catalog in sync with the AppIcon artwork.
struct AppMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 100

    /// Grows with Dynamic Type, capped so the welcome text stays on screen.
    private var markSize: CGFloat { min(size, 160) }

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: markSize, height: markSize)
            // Square, like the logo artwork itself.
            .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 8)
            .accessibilityHidden(true)
    }
}

#Preview {
    WelcomeStepView(onGetStarted: {})
}
