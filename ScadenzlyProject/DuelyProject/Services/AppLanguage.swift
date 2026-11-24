//
//  AppLanguage.swift
//  DuelyProject
//
//  The language chosen in Settings › Language. iOS reads an app's language once, at launch,
//  from `AppleLanguages`; writing it here is what the system's own per-app language setting
//  does, so the choice applies the next time the app opens.
//
//  Inglisc is our own language: Italian with every word's final vowels turned into "s"
//  ("ti voglio bene" → "ti vogls bens"). iOS has no code for it, so it uses Italian as spoken in
//  Vatican City ("it-VA"): its own translations, with Italian dates and numbers.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case italian = "it"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case dutch = "nl"
    case inglisc = "it-VA"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// Each language in its own words, like the iOS language list. `nil` for the device language.
    var nativeName: String? {
        switch self {
        case .system: nil
        case .italian: "Italiano"
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .dutch: "Nederlands"
        case .inglisc: "Inglisc"
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Saves the choice; it takes effect at the next launch.
    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
            defaults.set(rawValue, forKey: Self.storageKey)
        }
    }
}
