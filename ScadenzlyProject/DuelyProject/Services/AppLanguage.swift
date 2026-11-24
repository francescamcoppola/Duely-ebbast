//
//  AppLanguage.swift
//  DuelyProject
//
//  The app's language, chosen at first launch or in Settings › Language.
//
//  iOS reads an app's language once, at launch, and an app may not quit itself. So a change is
//  applied in three ways at once, which together look like a restart:
//  1. `AppleLanguages` is written, as the system's own per-app language setting does: every
//     later launch starts in the new language.
//  2. `Bundle.main` looks up strings in the chosen language from now on (`String(localized:)`,
//     errors, notifications).
//  3. The whole interface is rebuilt with the new locale (`LanguageController.generation` is the
//     root view's identity), so every screen, date and price switches immediately.
//
//  Inglisc is our own language: Italian with every word's final vowels turned into "s"
//  ("ti voglio bene" → "ti vogls bens"). iOS has no code for it, so it uses Italian as spoken in
//  Vatican City ("it-VA"): its own translations, with Italian dates and numbers.
//

import Foundation
import Observation
import ObjectiveC

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

    /// The app localization (lproj) this choice resolves to.
    var localization: String {
        guard self == .system else { return rawValue }
        let available = Bundle.main.localizations.filter { $0 != "Base" && $0 != "it-VA" }
        return Bundle.preferredLocalizations(from: available, forPreferences: Self.deviceLanguages).first ?? "en"
    }

    /// The device's languages. Read live: once this app's override is removed, the lookup falls
    /// through to the system's list (`Locale.preferredLanguages` is fixed at launch).
    static var deviceLanguages: [String] {
        UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    }

    /// Locale for formatting: the chosen language with the device's region (Inglisc: Italian rules).
    var locale: Locale {
        let region = Locale.current.region?.identifier ?? "IT"
        return switch self {
        case .inglisc: Locale(identifier: "it_VA")
        case .system: Locale(identifier: "\(localization)_\(region)")
        default: Locale(identifier: "\(rawValue)_\(region)")
        }
    }

    /// Saves the choice so every later launch uses it.
    fileprivate func persist(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
            defaults.set(rawValue, forKey: Self.storageKey)
        }
    }
}

// MARK: - Controller

@MainActor
@Observable
final class LanguageController {
    static let shared = LanguageController()

    private(set) var language: AppLanguage = .stored()
    /// Changes on every switch. Used as the root view's identity, so the whole app is rebuilt.
    private(set) var generation = 0

    var locale: Locale { language.locale }

    /// Call once at launch.
    func start() {
        LocalizedBundle.use(language.localization)
    }

    /// Applies a new language right away, as if the app had restarted.
    func change(to newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        newLanguage.persist()
        language = newLanguage
        LocalizedBundle.use(newLanguage.localization)
        generation += 1
    }
}

// MARK: - Bundle lookup

/// Makes `Bundle.main` answer string lookups from the chosen language's .lproj, so text built
/// outside SwiftUI views (`String(localized:)`) follows the choice without a relaunch.
enum LocalizedBundle {
    nonisolated(unsafe) fileprivate static var current: Bundle?

    static func use(_ localization: String) {
        if object_getClass(Bundle.main) != OverridingBundle.self {
            object_setClass(Bundle.main, OverridingBundle.self)
        }
        current = Bundle.main.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

private final class OverridingBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = LocalizedBundle.current {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
