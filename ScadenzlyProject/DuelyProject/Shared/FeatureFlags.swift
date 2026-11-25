//
//  FeatureFlags.swift
//  DuelyProject
//
//  Features that are built but not shipped yet. While a flag is off, nothing about the feature
//  appears in the app (onboarding, Settings, Home, details, Privacy); the code stays so it can
//  be turned back on by flipping the flag.
//

import Foundation

nonisolated enum FeatureFlags {
    /// Import from Gmail. Off until Google verifies the app for the `gmail.readonly` scope.
    /// When turning it on, also restore the Gmail sections of docs/privacy.html and docs/index.html.
    static let emailImport = false

    /// Screen Time usage tracking. Off until Apple grants the Family Controls (Distribution)
    /// capability and it's added to MyDues.entitlements.
    static let screenTime = false
}
