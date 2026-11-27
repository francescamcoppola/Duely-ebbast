//
//  CheckInScheduleTests.swift
//  DuelyProjectTests
//
//  Reference week (UTC): Mon 9 Nov 2026 … Sun 15 Nov 2026, then Wed 18 Nov 2026 as "now".
//

import Foundation
import Testing
@testable import DuelyProject

@Suite("CheckInSchedule")
struct CheckInScheduleTests {
    private let calendar = TestCalendar.utc
    /// The default: Sunday at 18:00.
    private let sunday = CheckInSchedule(weekday: 1, minutes: 18 * 60)
    private let wednesday = date(2026, 11, 18, 12)

    // MARK: Occurrences

    @Test("Components match the stored weekday and minutes")
    func components() {
        let schedule = CheckInSchedule(weekday: 4, minutes: 9 * 60 + 30)
        #expect(schedule.components == DateComponents(hour: 9, minute: 30, weekday: 4))
    }

    @Test("Latest occurrence is the most recent check-in moment")
    func latestOccurrence() {
        #expect(sunday.latestOccurrence(atOrBefore: wednesday, calendar: calendar) == date(2026, 11, 15, 18))
    }

    @Test("At the exact check-in moment, that check-in is the latest one")
    func latestOccurrenceIsInclusive() {
        #expect(sunday.latestOccurrence(atOrBefore: date(2026, 11, 15, 18), calendar: calendar) == date(2026, 11, 15, 18))
    }

    @Test("A minute before the check-in, the latest one is the previous week's")
    func latestOccurrenceJustBefore() {
        #expect(sunday.latestOccurrence(atOrBefore: date(2026, 11, 15, 17, 59), calendar: calendar) == date(2026, 11, 8, 18))
    }

    @Test("Next occurrence is the coming check-in")
    func nextOccurrence() {
        #expect(sunday.nextOccurrence(after: wednesday, calendar: calendar) == date(2026, 11, 22, 18))
    }

    // MARK: Reviewed week

    @Test("A check-in reviews the 7 days ending on its own day")
    func reviewedWeek() {
        #expect(CheckInSchedule.reviewedWeekStart(for: date(2026, 11, 15, 18), calendar: calendar) == date(2026, 11, 9))
    }

    @Test("A Monday check-in reviews Tuesday to Monday")
    func reviewedWeekForMonday() {
        let monday = CheckInSchedule(weekday: 2, minutes: 9 * 60)
        #expect(monday.currentWeek(now: wednesday, calendar: calendar) == date(2026, 11, 10))
    }

    // MARK: Due week

    @Test("The latest unanswered check-in is due")
    func dueWhenUnanswered() {
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [], skippedWeek: nil,
                                 trackingSince: date(2026, 11, 1), calendar: calendar)
        #expect(due == date(2026, 11, 9))
    }

    @Test("An answered week is no longer due")
    func notDueWhenAnswered() {
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [date(2026, 11, 9)], skippedWeek: nil,
                                 trackingSince: date(2026, 11, 1), calendar: calendar)
        #expect(due == nil)
    }

    @Test("A skipped week is no longer due, whatever the time it was skipped at")
    func notDueWhenSkipped() {
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [], skippedWeek: date(2026, 11, 9, 15, 42),
                                 trackingSince: date(2026, 11, 1), calendar: calendar)
        #expect(due == nil)
    }

    @Test("Skipping an older week doesn't hide the current one")
    func olderSkipDoesNotHideCurrentWeek() {
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [], skippedWeek: date(2026, 11, 2),
                                 trackingSince: date(2026, 11, 1), calendar: calendar)
        #expect(due == date(2026, 11, 9))
    }

    @Test("Nothing is due before the user started tracking")
    func notDueBeforeTracking() {
        // Started on Monday, after Sunday's check-in had already passed.
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [], skippedWeek: nil,
                                 trackingSince: date(2026, 11, 16), calendar: calendar)
        #expect(due == nil)
    }

    @Test("Nothing is due without any subscriptions to ask about")
    func notDueWithoutTracking() {
        let due = sunday.dueWeek(now: wednesday, answeredWeeks: [], skippedWeek: nil,
                                 trackingSince: nil, calendar: calendar)
        #expect(due == nil)
    }

    @Test("Missed weeks don't pile up: only the latest check-in can be due")
    func missedWeeksDoNotPileUp() {
        // Two Sundays (15th and 22nd) have passed unanswered by Wednesday the 25th.
        let due = sunday.dueWeek(now: date(2026, 11, 25, 12), answeredWeeks: [], skippedWeek: nil,
                                 trackingSince: date(2026, 11, 1), calendar: calendar)
        #expect(due == date(2026, 11, 16))
    }

    @Test("Opening the check-in on purpose shows the latest check-in's week")
    func currentWeek() {
        #expect(sunday.currentWeek(now: wednesday, calendar: calendar) == date(2026, 11, 9))
    }
}
