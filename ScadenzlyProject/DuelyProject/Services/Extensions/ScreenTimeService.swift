//
//  ScreenTimeService.swift
//  DuelyProject
//
//  Links subscriptions to the apps they're used in, through Apple's Screen Time API, so usage
//  is known without asking:
//  • the user picks the app in Apple's own picker (MyDues only gets an opaque token, never the
//    app's name or what's done in it);
//  • a DeviceActivity schedule runs every day, with one event per linked app: "used for at
//    least 5 minutes today". The UsageMonitor extension records those days in the App Group;
//  • completed weeks are then answered automatically in the weekly check-in, and the monitor
//    sends a reminder when a paid app hasn't been opened for a week.
//
//  Requires the Family Controls capability. Apple grants it for development builds; for
//  TestFlight and the App Store it must be requested (see README). Without it, everything here
//  reports `.unavailable` and the rest of the app works as before.
//

import Foundation
import SwiftData
import Observation
import FamilyControls
import DeviceActivity

@MainActor
@Observable
final class ScreenTimeService {
    static let shared = ScreenTimeService()

    enum Status: Equatable {
        case notDetermined
        case approved
        case denied
        /// This build doesn't have the Family Controls capability, or the device can't use it.
        case unavailable
    }

    private(set) var status: Status = .notDetermined
    private(set) var isRequesting = false

    /// Minutes of use in a day that count as "used".
    static let dailyThresholdMinutes = 5
    private static let activity = DeviceActivityName("daily-subscription-usage")

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: status = .approved
        case .denied: status = status == .unavailable ? .unavailable : .denied
        default: if status != .unavailable { status = .notDetermined }
        }
    }

    /// Shows the system's Screen Time permission prompt (Face ID / passcode).
    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshStatus()
        } catch let error as FamilyControlsError {
            switch error {
            case .authorizationCanceled, .authorizationConflict: refreshStatus()
            case .restricted: status = .denied
            default: status = .unavailable
            }
        } catch {
            status = .unavailable
        }
    }

    // MARK: Links

    func isLinked(_ subscription: Subscription) -> Bool {
        guard let key = subscription.usageKey else { return false }
        return UsageLinks.all[key] != nil
    }

    func selection(for subscription: Subscription) -> FamilyActivitySelection {
        guard let key = subscription.usageKey, let data = UsageLinks.all[key]?.selection,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    /// Links (or relinks) the apps picked for a subscription and restarts monitoring.
    func link(_ subscription: Subscription, selection: FamilyActivitySelection, currencyCode: String,
              context: ModelContext) {
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty else {
            unlink(subscription, context: context)
            return
        }
        let key = subscription.usageKey ?? UUID().uuidString
        subscription.usageKey = key
        try? context.save()

        var links = UsageLinks.all
        let monthly = subscription.monthlyCost.formatted(.currency(code: currencyCode).locale(LanguageController.shared.locale))
        links[key] = UsageLink(
            selection: (try? JSONEncoder().encode(selection)) ?? Data(),
            name: subscription.name,
            unusedTitle: String(appLocalized: "You haven't opened \(subscription.name) this week"),
            unusedBody: String(appLocalized: "It costs you \(monthly) a month. Is it still worth it?"),
            linkedOn: links[key]?.linkedOn ?? .now
        )
        UsageLinks.all = links
        restartMonitoring()
    }

    func unlink(_ subscription: Subscription, context: ModelContext) {
        if let key = subscription.usageKey {
            var links = UsageLinks.all
            links[key] = nil
            UsageLinks.all = links
        }
        subscription.usageKey = nil
        try? context.save()
        restartMonitoring()
    }

    /// Drops links to subscriptions that no longer exist (deleted here or on another device).
    func pruneLinks(keeping subscriptions: [Subscription]) {
        let keys = Set(subscriptions.compactMap(\.usageKey))
        let links = UsageLinks.all
        let kept = links.filter { keys.contains($0.key) }
        if kept.count != links.count {
            UsageLinks.all = kept
            restartMonitoring()
        }
    }

    /// One daily schedule, with an event per linked subscription.
    func restartMonitoring() {
        let center = DeviceActivityCenter()
        center.stopMonitoring([Self.activity])
        let links = UsageLinks.all
        guard status == .approved, !links.isEmpty else { return }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (key, link) in links {
            guard let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: link.selection) else { continue }
            events[DeviceActivityEvent.Name(key)] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: Self.dailyThresholdMinutes)
            )
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try? center.startMonitoring(Self.activity, during: schedule, events: events)
    }

    // MARK: Usage

    /// Whether a linked subscription's app was used in the 7 days starting at `weekStart`.
    /// `nil` when it isn't linked, or wasn't linked yet for that whole week.
    func usage(of subscription: Subscription, inWeekStarting weekStart: Date) -> Bool? {
        guard let key = subscription.usageKey, let link = UsageLinks.all[key] else { return nil }
        if UsageLinks.wasUsed(key: key, inWeekStarting: weekStart) { return true }
        return link.linkedOn <= weekStart ? false : nil
    }

    /// When every subscription is linked, answers the latest check-in week from Screen Time, so
    /// no check-in needs to be asked. Otherwise the check-in is still shown, with linked
    /// subscriptions preselected (a week with any answer counts as checked in).
    func recordFinishedWeek(subscriptions: [Subscription], schedule: CheckInSchedule,
                            context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let configured = subscriptions.filter { !$0.needsSetup }
        guard !configured.isEmpty, configured.allSatisfy(isLinked),
              let occurrence = schedule.latestOccurrence(atOrBefore: now, calendar: calendar) else { return }
        let week = CheckInSchedule.reviewedWeekStart(for: occurrence, calendar: calendar)
        var changed = false
        for subscription in configured {
            let answered = (subscription.usageEntries ?? []).contains { calendar.isDate($0.weekStart, inSameDayAs: week) }
            guard !answered, let used = usage(of: subscription, inWeekStarting: week) else { continue }
            context.insert(UsageEntry(weekStart: week, used: used, subscription: subscription))
            changed = true
        }
        if changed { try? context.save() }
    }
}
