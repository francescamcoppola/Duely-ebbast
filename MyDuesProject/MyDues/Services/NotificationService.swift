//
//  NotificationService.swift
//  MyDues
//
//  Local notifications only (nothing leaves the device):
//  • one repeating weekly check-in reminder
//  • payment and deadline reminders (returns, warranties, trials, pagoPA), rebuilt from the data every time something changes or the app opens
//
//  Permission is never requested at launch. It's requested when the user turns a reminder on
//  or picks a reminder for a subscription (HIG: ask in context, when the benefit is clear).
//

import Foundation
import UserNotifications

nonisolated enum NotificationService {
    static var checkInIdentifier: String { NotificationIDs.checkIn }

    private static var center: UNUserNotificationCenter { .current() }

    // MARK: Permission

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Shows the system prompt only the first time; never nags after a "Don't Allow".
    static func requestAuthorizationIfNeeded() async {
        if await authorizationStatus() == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: Scheduling

    /// Replaces every notification this app owns with the given plan.
    static func reschedule(checkIn: CheckInSchedule?, payments: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0 == checkInIdentifier || $0.hasPrefix(NotificationIDs.paymentPrefix)
                || $0.hasPrefix(NotificationIDs.deadlinePrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        if let checkIn {
            let content = UNMutableNotificationContent()
            content.title = String(appLocalized: "Weekly Check-In")
            content.body = String(appLocalized: "Which subscriptions did you use this week? It takes 10 seconds.")
            content.sound = .default
            content.threadIdentifier = "check-in"
            let trigger = UNCalendarNotificationTrigger(dateMatching: checkIn.components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: checkInIdentifier, content: content, trigger: trigger))
        }

        let calendar = Calendar.current
        for reminder in payments {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = reminder.id.hasPrefix(NotificationIDs.deadlinePrefix) ? "deadlines" : "payments"
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
}
