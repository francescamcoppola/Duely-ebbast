//
//  PaymentSchedule.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 18/11/2026.
//

import Foundation
import SwiftData

// MARK: - Occurrences (pure)

extension BillingMath {
    /// Every payment date in `[start, end)`, stepping whole periods from the anchor in both
    /// directions so month-end dates never drift (Jan 31 → Feb 28 → Mar 31).
    static func occurrences(
        anchor: Date,
        cycle: BillingCycle,
        from start: Date,
        to end: Date,
        limit: Int = 64,
        calendar: Calendar = .current
    ) -> [Date] {
        guard start < end else { return [] }
        let anchorDay = calendar.startOfDay(for: anchor)
        let (component, step) = cycle.step

        // Periods between anchor and start, truncated toward zero (can be negative).
        let elapsed = calendar.dateComponents([component], from: anchorDay, to: calendar.startOfDay(for: start))
            .value(for: component) ?? 0
        // Begin one period early to absorb truncation and month-end clamping.
        var period = Int((Double(elapsed) / Double(step)).rounded(.down)) - 1

        var dates: [Date] = []
        for _ in 0..<max(limit, 1) {   // A month holds at most 6 weekly payments; the limit is a hard safety stop.
            guard let date = calendar.date(byAdding: component, value: period * step, to: anchorDay) else { break }
            if date >= end { break }
            if date >= start { dates.append(date) }
            period += 1
        }
        return dates
    }
}

// MARK: - Month grid (pure)

struct CalendarMonth: Equatable {
    /// First day of the month, at midnight.
    let start: Date
    /// First day of the next month, at midnight (exclusive bound).
    let end: Date
    let days: [Date]
    /// Empty cells before day 1, following the region's first weekday (Monday in Italy, Sunday in the US).
    let leadingBlanks: Int
    /// "M T W T F S S", already rotated to start on the region's first weekday.
    let weekdaySymbols: [String]

    init(containing date: Date, calendar: Calendar = .current) {
        let interval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        start = interval.start
        end = interval.end

        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        self.days = days

        let weekday = calendar.component(.weekday, from: interval.start)   // 1 = Sunday
        leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = (calendar.firstWeekday - 1) % max(symbols.count, 1)
        weekdaySymbols = Array(symbols[shift...] + symbols[..<shift])
    }

    func adding(months: Int, calendar: Calendar = .current) -> CalendarMonth {
        CalendarMonth(containing: calendar.date(byAdding: .month, value: months, to: start) ?? start,
                      calendar: calendar)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, equalTo: start, toGranularity: .month)
    }
}

// MARK: - Schedule

struct ScheduledPayment: Identifiable {
    struct ID: Hashable {
        let subscription: PersistentIdentifier
        let date: Date
    }

    let subscription: Subscription
    let date: Date
    /// Before today: assumed already charged.
    let isPast: Bool

    var amount: Decimal { subscription.price }
    /// Today or later, and marked as paid by hand.
    var isMarkedPaid: Bool { !isPast && subscription.isMarkedPaid(on: date) }
    /// Counted as charged: past, or marked as paid.
    var isPaid: Bool { isPast || isMarkedPaid }
    var id: ID { ID(subscription: subscription.persistentModelID, date: date) }
}

struct MonthSchedule {
    let month: CalendarMonth
    let paymentsByDay: [Date: [ScheduledPayment]]
    let total: Decimal
    let chargedTotal: Decimal
    let upcomingTotal: Decimal
    let paymentCount: Int

    init(subscriptions: [Subscription], month: CalendarMonth, today: Date = .now, calendar: Calendar = .current) {
        self.month = month
        let todayStart = calendar.startOfDay(for: today)
        var byDay: [Date: [ScheduledPayment]] = [:]

        for subscription in subscriptions where subscription.hasCharges {
            // Don't invent history: show past charges only from when tracking began.
            let from = max(month.start, subscription.trackingStart(calendar: calendar))

            for date in subscription.paymentDates(from: from, to: month.end, calendar: calendar) {
                byDay[date, default: []].append(
                    ScheduledPayment(subscription: subscription, date: date, isPast: date < todayStart)
                )
            }
        }

        for key in byDay.keys {
            byDay[key]?.sort { $0.subscription.name.localizedStandardCompare($1.subscription.name) == .orderedAscending }
        }
        paymentsByDay = byDay

        let all = byDay.values.joined()
        paymentCount = all.count
        total = all.reduce(Decimal.zero) { $0 + $1.amount }
        chargedTotal = all.filter(\.isPaid).reduce(Decimal.zero) { $0 + $1.amount }
        upcomingTotal = total - chargedTotal
    }

    func payments(on day: Date, calendar: Calendar = .current) -> [ScheduledPayment] {
        paymentsByDay[calendar.startOfDay(for: day)] ?? []
    }
}

// MARK: - Compared with the monthly average

extension MonthSchedule {
    /// How this month's actual charges compare with Home's monthly average.
    enum Comparison: Equatable {
        /// Noticeably higher. `renewals` names the non-monthly plans charged this month
        /// (yearly, quarterly, weekly), most expensive first: usually the reason.
        case higher(renewals: [String])
        /// Noticeably lower, usually because longer plans renew in other months.
        case lower
        /// Within `typicalTolerance` of the average.
        case typical
    }

    /// ±15 %: smaller differences aren't worth explaining.
    static let typicalTolerance = 0.15

    func comparison(toMonthlyAverage average: Decimal) -> Comparison {
        let averageValue = BillingMath.double(average)
        guard averageValue > 0 else { return .typical }
        let difference = (BillingMath.double(total) - averageValue) / averageValue

        if difference > Self.typicalTolerance {
            var seen = Set<String>()
            let renewals = paymentsByDay.values.joined()
                .filter { $0.subscription.cycle != .monthly }
                .sorted { $0.amount > $1.amount }
                .map(\.subscription.name)
                .filter { seen.insert($0).inserted }
            return .higher(renewals: renewals)
        }
        if difference < -Self.typicalTolerance { return .lower }
        return .typical
    }
}
