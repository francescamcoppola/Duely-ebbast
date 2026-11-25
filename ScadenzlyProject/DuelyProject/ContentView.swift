//
//  ContentView.swift
//  DuelyProject
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(OnboardingKeys.hasCompleted) private var hasCompletedOnboarding = false
    @State private var language = LanguageController.shared

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                RootTabView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: hasCompletedOnboarding)
        // A language change rebuilds the whole app in the new language: the "restart".
        .environment(\.locale, language.locale)
        // Weekday and month names (calendar grid, check-in, Settings) follow `\.calendar`, not
        // `\.locale`.
        .environment(\.calendar, language.calendar)
        .id(language.generation)
        .transition(.opacity.animation(.smooth(duration: 0.35)))
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
