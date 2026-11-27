//
//  InputSanitizingTests.swift
//  MyDuesTests
//
//  Amount and name input cleanup used by onboarding and the editors.
//

import Testing
@testable import MyDues

@MainActor
@Suite("Input sanitizing")
struct InputSanitizingTests {
    // MARK: Amounts

    @Test("Amounts keep digits and one decimal separator", arguments: [
        ("1500", ",", "1500"),
        ("12.5", ",", "12,5"),        // A dot typed in a comma locale becomes a comma.
        ("12,5", ".", "12.5"),        // And the other way round.
        ("1,2,3", ",", "1,23"),       // Only the first separator counts.
        ("$1a2 €", ".", "12"),        // Symbols, letters and spaces are dropped.
        ("", ".", ""),
    ])
    func amounts(input: String, separator: String, expected: String) {
        #expect(OnboardingViewModel.sanitizedAmount(input, decimalSeparator: separator) == expected)
    }

    @Test("Leading zeros are dropped, but a lone zero stays", arguments: [
        ("007", "7"),
        ("00", "0"),
        ("0", "0"),
        ("0.5", "0.5"),
    ])
    func leadingZeros(input: String, expected: String) {
        #expect(OnboardingViewModel.sanitizedAmount(input, decimalSeparator: ".") == expected)
    }

    @Test("Starting with the separator adds the leading zero")
    func leadingSeparator() {
        #expect(OnboardingViewModel.sanitizedAmount(",5", decimalSeparator: ",") == "0,5")
    }

    @Test("Cents are capped at the currency's decimal places")
    func fractionDigits() {
        #expect(OnboardingViewModel.sanitizedAmount("12.345", decimalSeparator: ".") == "12.34")
    }

    @Test("Currencies without decimals drop everything after the separator")
    func noDecimalCurrency() {
        // Switching "12.5" from EUR to JPY must give 12, not 125.
        #expect(OnboardingViewModel.sanitizedAmount("12.5", decimalSeparator: ".", maxFractionDigits: 0) == "12")
    }

    @Test("Whole amounts are capped at seven digits")
    func integerDigits() {
        #expect(OnboardingViewModel.sanitizedAmount("123456789", decimalSeparator: ".") == "1234567")
    }

    @Test("Digits from other scripts become ASCII digits")
    func otherScripts() {
        #expect(OnboardingViewModel.sanitizedAmount("١٢٣", decimalSeparator: ".") == "123")   // Arabic-Indic
        #expect(OnboardingViewModel.sanitizedAmount("१२", decimalSeparator: ".") == "12")     // Devanagari
    }

    // MARK: Names

    @Test("Names are cut to the maximum length")
    func longName() {
        let limited = OnboardingViewModel.limitedName("Maximiliana Alexandra")
        #expect(limited == "Maximiliana Ale")
        #expect(limited.count == OnboardingViewModel.maxNameLength)
    }

    @Test("Short names are left alone")
    func shortName() {
        #expect(OnboardingViewModel.limitedName("Diego") == "Diego")
    }

    @Test("Emoji and accented letters count as one character each")
    func graphemeClusters() {
        let family = "👨‍👩‍👧‍👦"
        #expect(OnboardingViewModel.limitedName(family + "é", maxLength: 2) == family + "é")
        #expect(OnboardingViewModel.limitedName(family + "éa", maxLength: 2) == family + "é")
    }
}
