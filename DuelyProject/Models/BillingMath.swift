//
//  BillingMath.swift
//  DuelyProject
//
//  Pure date and money helpers. No SwiftData, no UI, so they are easy to unit test.
//

import Foundation

enum BillingMath {
    static func monthlyEquivalent(price: Decimal, cycle: BillingCycle) -> Decimal {
        price * cycle.paymentsPerYear / 12
    }

    static func yearlyEquivalent(price: Decimal, cycle: BillingCycle) -> Decimal {
        price * cycle.paymentsPerYear
    }

    /// First payment on or after the start of `reference`'s day.
    ///
    /// Always adds whole periods to the *anchor* instead of chaining from the previous payment,
    /// so a plan billed on the 31st gives Feb 28 → Mar 31, not Feb 28 → Mar 28.
    static func nextPayment(
        anchor: Date,
        cycle: BillingCycle,
        onOrAfter reference: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let start = calendar.startOfDay(for: reference)
        let anchorDay = calendar.startOfDay(for: anchor)
        if anchorDay >= start { return anchorDay }

        let (component, step) = cycle.step
        let elapsed = calendar.dateComponents([component], from: anchorDay, to: start).value(for: component) ?? 0
        var periods = max(elapsed / step, 0)

        // The estimate is at most one period short; a few iterations cover month-end clamping.
        for _ in 0..<4 {
            guard let candidate = calendar.date(byAdding: component, value: periods * step, to: anchorDay) else {
                return nil
            }
            if candidate >= start { return candidate }
            periods += 1
        }
        return nil
    }

    /// Whole calendar days from `from` to `to` (0 = same day).
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// Money as a Double, only for ratios and chart proportions (never for display or storage).
    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Budget is stored by onboarding as "1500.5" (always "." — `NSDecimalNumber.stringValue`).
    static func storedAmount(_ string: String) -> Decimal? {
        guard !string.isEmpty,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    static func storedString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
