//
//  UsageMonitorExtension.swift
//  UsageMonitor
//
//  Screen Time (DeviceActivity) monitor. iOS runs it, not the app: every day it's told when a
//  linked app has been used for a few minutes, and records that day in the App Group, where the
//  app reads it for check-ins and insights. At the end of each day it checks for subscriptions
//  whose app hasn't been opened for a week and sends one reminder (at most weekly).
//  Screen Time never reveals which app a subscription is linked to, or how long it was used:
//  only that the threshold was reached.
//

import DeviceActivity
import Foundation
import UserNotifications

final class UsageMonitorExtension: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        UsageLinks.recordUse(key: event.rawValue)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        remindAboutUnusedApps()
    }

    private func remindAboutUnusedApps(now: Date = .now) {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return }
        var notified = UsageLinks.lastNotified

        for (key, link) in UsageLinks.all {
            // Only after a full week of tracking, and not if it was used during it.
            guard link.linkedOn <= weekAgo else { continue }
            if let lastUse = UsageLinks.lastUse(key: key), lastUse >= calendar.startOfDay(for: weekAgo) { continue }
            if let last = notified[key], last >= weekAgo { continue }

            let content = UNMutableNotificationContent()
            content.title = link.unusedTitle
            content.body = link.unusedBody
            content.sound = .default
            let request = UNNotificationRequest(identifier: "unused-\(key)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            notified[key] = now
        }
        UsageLinks.lastNotified = notified
    }
}
