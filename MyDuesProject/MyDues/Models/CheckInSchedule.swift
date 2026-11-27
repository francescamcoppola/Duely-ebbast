//
//  CheckInSchedule.swift
//  DuelyProject
//
//  When the weekly check-in happens, which week it asks about, and whether one is due.
//  Pure value logic: no notifications or UI here.
//

import Foundation

nonisolated enum CheckInKeys {
    static let enabled = "checkInEnabled"
    /// 1 = Sunday … 7 = Saturday (Foundation's numbering).
    static let weekday = "checkInWeekday"
    /// Minutes after midnight, e.g. 1080 = 18:00.
    static let minutes = "checkInMinutes"
    /// Week start of a check-in the user chose to skip (seconds since 1970; 0 = none).
    static let skippedWeek = "checkInSkippedWeek"
    static let paymentRemindersEnabled = "paymentRemindersEnabled"
}

/// `nonisolated`: also used off the main actor by `NotificationService`.
nonisolated struct CheckInSchedule: Equatable, Sendable {
    static let defaultWeekday = 1            // Sunday
    static let defaultMinutes = 18 * 60      // 6 PM

    var weekday: Int
    var minutes: Int

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    var components: DateComponents {
        DateComponents(hour: hour, minute: minute, weekday: weekday)
    }

    /// The most recent check-in moment at or before `now`.
    func latestOccurrence(atOrBefore now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now.addingTimeInterval(1),
            matching: components,
            matchingPolicy: .nextTime,
            direction: .backward
        )
    }

    func nextOccurrence(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    /// The 7 days a check-in asks about end on the check-in day: Sunday's check-in covers Mon–Sun.
    static func reviewedWeekStart(for occurrence: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: occurrence)
        return calendar.date(byAdding: .day, value: -6, to: day) ?? day
    }

    /// The week a check-in should be shown for right now, or `nil` if nothing is pending.
    ///
    /// Only the latest check-in can be due (missed weeks don't pile up), and never one from
    /// before the user started tracking.
    func dueWeek(
        now: Date,
        answeredWeeks: Set<Date>,
        skippedWeek: Date?,
        trackingSince: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let trackingSince,
              let occurrence = latestOccurrence(atOrBefore: now, calendar: calendar),
              occurrence >= trackingSince else { return nil }

        let week = Self.reviewedWeekStart(for: occurrence, calendar: calendar)
        if answeredWeeks.contains(week) { return nil }
        if let skippedWeek, calendar.isDate(skippedWeek, inSameDayAs: week) { return nil }
        return week
    }

    /// Week shown when the check-in is opened on purpose (e.g. from a notification) even if
    /// it isn't "due": the latest check-in's week, or the 7 days ending today.
    func currentWeek(now: Date, calendar: Calendar = .current) -> Date {
        Self.reviewedWeekStart(for: latestOccurrence(atOrBefore: now, calendar: calendar) ?? now, calendar: calendar)
    }
}
