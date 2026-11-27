//
//  OnboardingModel.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//



import SwiftUI
import Observation
import UIKit

// MARK: - App info

enum AppInfo {
    /// Display name used in onboarding copy. Change it in one place when the final name is decided.
    static let name = "MyDues"

    /// Support site and privacy policy, published from docs/ in the repository (GitHub Pages).
    /// The same addresses go in App Store Connect as Support URL and Privacy Policy URL.
    static let supportURL = URL(string: "https://francescamcoppola.github.io/Duely-ebbast/")!
    static let privacyPolicyURL = URL(string: "https://francescamcoppola.github.io/Duely-ebbast/privacy.html")!
    static let supportEmail = "myduesapp@gmail.com"

    /// "1.0 (2)", for support emails.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// A new email to support, with the details that help answer it already filled in.
    static var supportEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(name) support"),
            URLQueryItem(name: "body", value: "\n\n—\n\(name) \(version) · iOS \(UIDevice.current.systemVersion)"),
        ]
        return components.url
    }
}

// MARK: - Persistence keys

/// Keys shared by onboarding and the rest of the app (`@AppStorage` / `UserDefaults`).
enum OnboardingKeys {
    static let hasCompleted = "hasCompletedOnboarding"
    static let userName = "userName"
    /// Stored as a String (e.g. "1500.5") so no precision is lost with money.
    static let monthlyBudget = "monthlyBudget"
    /// ISO 4217 code, e.g. "EUR".
    static let currencyCode = "currencyCode"
    /// The first screen (language) was confirmed. Survives the rebuild a language change causes.
    static let languageChosen = "onboardingLanguageChosen"
}

// MARK: - Steps

enum OnboardingStep: Int, Hashable, CaseIterable {
    case name = 1
    case budget
    /// Offered only when Gmail import can run on this device.
    case email
    case subscriptions

    var number: Int { rawValue }
    static var total: Int { allCases.count }
}

// MARK: - Currency

/// Everything the UI needs to show money in one currency, resolved for the user's locale.
struct CurrencyOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let symbol: String
    /// True for "$1.00", false for "1,00 €".
    let symbolLeads: Bool
    /// 2 for EUR/USD, 0 for JPY/KRW, 3 for KWD…
    let fractionDigits: Int

    var id: String { code }

    init(code: String, locale: Locale = .current) {
        self.code = code
        // The name is in the app's language (it follows an in-app language change); the
        // symbol and its position below still follow `locale`.
        self.name = LocalizedBundle.locale.localizedString(forCurrencyCode: code)
            ?? locale.localizedString(forCurrencyCode: code) ?? code

        // Let Foundation format a sample and read symbol, position and decimals from it.
        // This respects each locale's rules instead of hard-coding them.
        let sample = Decimal(1).formatted(.currency(code: code).locale(locale))
        let parsed = Self.parse(sample: sample, decimalSeparator: locale.decimalSeparator ?? ".")
        self.symbol = parsed.symbol.isEmpty ? code : parsed.symbol
        self.symbolLeads = parsed.symbolLeads
        self.fractionDigits = parsed.fractionDigits
    }

    /// Splits a formatted sample like "MX$1.00", "1,00 €" or "¥1" into its parts.
    static func parse(sample: String, decimalSeparator: String) -> (symbol: String, symbolLeads: Bool, fractionDigits: Int) {
        guard let firstDigit = sample.firstIndex(where: \.isNumber),
              let lastDigit = sample.lastIndex(where: \.isNumber) else {
            return (sample.trimmingCharacters(in: Self.trimSet), true, 2)
        }
        let numberCore = sample[firstDigit...lastDigit]
        let before = sample[..<firstDigit].trimmingCharacters(in: Self.trimSet)
        let after = sample[sample.index(after: lastDigit)...].trimmingCharacters(in: Self.trimSet)

        var fractionDigits = 0
        if let separatorRange = numberCore.range(of: decimalSeparator) {
            fractionDigits = numberCore[separatorRange.upperBound...].filter(\.isNumber).count
        }
        let leads = !before.isEmpty
        return (leads ? before : after, leads, fractionDigits)
    }

    /// Whitespace plus the invisible direction marks some locales insert around currency symbols.
    private static let trimSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{200E}\u{200F}\u{061C}"))

    static var current: CurrencyOption {
        CurrencyOption(code: AppDefaults.currencyCode)
    }

    /// Every ISO currency in common use, sorted by localized name. Computed each time (not
    /// cached) so the names are in the current app language.
    static var all: [CurrencyOption] {
        Locale.commonISOCurrencyCodes
            .map { CurrencyOption(code: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The user's own currency first, then widely used ones. No duplicates.
    static var suggested: [CurrencyOption] {
        let localCode = Locale.current.currency?.identifier
        let codes = [localCode, "USD", "EUR", "MXN", "GBP", "CAD", "JPY"].compactMap { $0 }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }.map { CurrencyOption(code: $0) }
    }
}

// MARK: - Starter catalog

struct StarterService: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct StarterCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let services: [StarterService]
}

enum StarterCatalog {
    static let categories: [StarterCategory] = [
        StarterCategory(
            id: "film-tv", title: "Film & TV", symbol: "tv", tint: .red,
            services: [
                StarterService(id: "netflix", name: "Netflix"),
                StarterService(id: "hbo-max", name: "HBO Max"),
                StarterService(id: "disney-plus", name: "Disney+"),
                StarterService(id: "prime-video", name: "Prime Video"),
                StarterService(id: "apple-tv", name: "Apple TV"),
            ]
        ),
        StarterCategory(
            id: "leisure", title: "Leisure", symbol: "gamecontroller", tint: .purple,
            services: [
                StarterService(id: "discord-nitro", name: "Discord Nitro"),
                StarterService(id: "game-pass", name: "Xbox Game Pass"),
                StarterService(id: "ps-plus", name: "PlayStation Plus"),
                StarterService(id: "switch-online", name: "Nintendo Switch Online"),
                StarterService(id: "duolingo", name: "Duolingo"),
            ]
        ),
        StarterCategory(
            id: "music", title: "Music", symbol: "music.note", tint: .green,
            services: [
                StarterService(id: "spotify", name: "Spotify"),
                StarterService(id: "apple-music", name: "Apple Music"),
                StarterService(id: "amazon-music", name: "Amazon Music"),
                StarterService(id: "youtube-music", name: "YouTube Music"),
                StarterService(id: "tidal", name: "Tidal"),
            ]
        ),
    ]
}

// MARK: - View model

@Observable
final class OnboardingViewModel {
    static let maxStarterSelections = 3
    /// Long enough for full names like "Diego Alonso Tamez Flores", short enough for greetings and headers.
    static let maxNameLength = 15

    var path: [OnboardingStep] = []
    var name = ""
    /// Raw text from the budget field, already sanitized (ASCII digits + one locale decimal separator).
    var budgetText = ""
    var currency = CurrencyOption.current
    /// Ordered so the Home screen can show them in the order the user picked.
    var selectedServiceIDs: [String] = []

    // MARK: Derived state

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var monthlyBudget: Decimal? {
        guard !budgetText.isEmpty else { return nil }
        return Decimal(string: budgetText, locale: .current)
    }

    var canContinueFromName: Bool { !trimmedName.isEmpty }
    var canContinueFromBudget: Bool { (monthlyBudget ?? 0) > 0 }
    var canSelectMore: Bool { selectedServiceIDs.count < Self.maxStarterSelections }

    func isSelected(_ service: StarterService) -> Bool {
        selectedServiceIDs.contains(service.id)
    }

    // MARK: Actions

    func go(to step: OnboardingStep) {
        path.append(step)
    }

    func toggle(_ service: StarterService) {
        if let index = selectedServiceIDs.firstIndex(of: service.id) {
            selectedServiceIDs.remove(at: index)
        } else if canSelectMore {
            selectedServiceIDs.append(service.id)
        }
    }

    /// Writes everything the user entered. Skipped fields are removed so stale values never survive a re-run.
    func save(to defaults: UserDefaults = .standard) {
        if trimmedName.isEmpty {
            defaults.removeObject(forKey: OnboardingKeys.userName)
        } else {
            defaults.set(trimmedName, forKey: OnboardingKeys.userName)
        }

        if let budget = monthlyBudget, budget > 0 {
            defaults.set(NSDecimalNumber(decimal: budget).stringValue, forKey: OnboardingKeys.monthlyBudget)
        } else {
            defaults.removeObject(forKey: OnboardingKeys.monthlyBudget)
        }

        // Saved even when the budget is skipped: every price in the app needs a currency.
        defaults.set(currency.code, forKey: OnboardingKeys.currencyCode)
    }

    // MARK: Input helpers (pure, unit-testable)

    /// Cuts a name to `maxLength` user-perceived characters (emoji and accents count as one).
    static func limitedName(_ input: String, maxLength: Int = maxNameLength) -> String {
        input.count > maxLength ? String(input.prefix(maxLength)) : input
    }

    /// Keeps only digits and a single decimal separator, limits digits, and drops leading zeros.
    /// Digits from any script (e.g. Arabic-Indic) become ASCII, and both "." and "," are accepted
    /// as separators and normalized to the locale's one.
    static func sanitizedAmount(
        _ input: String,
        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
        maxIntegerDigits: Int = 7,
        maxFractionDigits: Int = 2
    ) -> String {
        var result = ""
        var hasSeparator = false
        var integerDigits = 0
        var fractionDigits = 0

        for character in input {
            if character.isNumber, let value = character.wholeNumberValue, (0...9).contains(value) {
                if hasSeparator {
                    guard fractionDigits < maxFractionDigits else { continue }
                    fractionDigits += 1
                } else {
                    if result == "0" {           // "07" -> "7"
                        result = ""
                        integerDigits = 0
                    }
                    guard integerDigits < maxIntegerDigits else { continue }
                    integerDigits += 1
                }
                result += String(value)
            } else if character == "." || character == "," || String(character) == decimalSeparator {
                guard !hasSeparator else { continue }
                // Currency without decimals (JPY, KRW…): everything after the separator is dropped,
                // so switching "12.5" from EUR to JPY gives 12, not 125.
                guard maxFractionDigits > 0 else { break }
                hasSeparator = true
                if result.isEmpty {              // ".5" -> "0.5"
                    result = "0"
                    integerDigits = 1
                }
                result += decimalSeparator
            }
        }
        return result
    }
}
