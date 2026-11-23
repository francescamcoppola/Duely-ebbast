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
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
