//
//  SharedStore.swift
//  MyDues (app, widgets, Screen Time monitor)
//
//  Data the app shares with its extensions through the App Group container. The extensions
//  never open the app's database: the app writes small, ready-to-show snapshots here.
//  • `WidgetSnapshot`: upcoming payments and the monthly total, for the widgets.
//  • `UsageLinks`: which app each subscription is linked to in Screen Time, and the days it was
//    used, written by the Screen Time monitor.
//

import Foundation

nonisolated enum SharedStore {
    static let appGroup = "group.com.francescamariacoppola.Duely"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: key)
    }
}

// MARK: - Widgets

/// Everything the widgets show, already worked out and translated by the app, so they follow
/// the app's language and need no database.
nonisolated struct WidgetSnapshot: Codable, Sendable {
    struct Payment: Codable, Hashable, Sendable {
        var name: String
        var date: Date
        var amount: Decimal
        /// A system color name: "red", "blue"… (see `SharedColor`).
        var color: String
    }

    /// Texts in the app's language.
    struct Labels: Codable, Sendable {
        var nextPayment: String
        var upcoming: String
        var perMonth: String
        var today: String
        var tomorrow: String
        /// "In %lld days" with the number already in place for 2…7 days, keyed by days.
        var inDays: [Int: String]
        var nothingDue: String
        var noSubscriptions: String
        var ofBudget: String
    }

    var currencyCode: String
    var localeIdentifier: String
    var monthlyTotal: Decimal
    var budget: Decimal?
    /// Next 31 days, soonest first.
    var upcoming: [Payment]
    var hasSubscriptions: Bool
    var labels: Labels
    var updated: Date

    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? { SharedStore.load(WidgetSnapshot.self, key: key) }
    func save() { SharedStore.save(self, key: Self.key) }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    func payments(from date: Date, calendar: Calendar = .current) -> [Payment] {
        let start = calendar.startOfDay(for: date)
        return upcoming.filter { $0.date >= start }
    }

    /// "Today", "Tomorrow", "In 3 days" or a short date.
    func dueText(for paymentDate: Date, from now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: paymentDate)).day ?? 0
        switch days {
        case ...0: return labels.today
        case 1: return labels.tomorrow
        default:
            if let text = labels.inDays[days] { return text }
            return paymentDate.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
    }

    func format(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}

// MARK: - Screen Time

/// A subscription linked to an app in Screen Time.
nonisolated struct UsageLink: Codable, Sendable {
    /// `FamilyActivitySelection`, encoded by the app. Opaque: only Screen Time can read which app it is.
    var selection: Data
    var name: String
    /// Notification texts in the app's language, ready for the monitor.
    var unusedTitle: String
    var unusedBody: String
    var linkedOn: Date
}

nonisolated enum UsageLinks {
    private static let linksKey = "usageLinks"
    private static let daysKey = "usageDays"
    private static let notifiedKey = "usageNotified"

    /// Usage key (stored on the subscription) → link.
    static var all: [String: UsageLink] {
        get { SharedStore.load([String: UsageLink].self, key: linksKey) ?? [:] }
        set { SharedStore.save(newValue, key: linksKey) }
    }

    /// Days (start of day) each linked app was used for at least the monitor's threshold.
    static var usedDays: [String: [Date]] {
        get { SharedStore.load([String: [Date]].self, key: daysKey) ?? [:] }
        set { SharedStore.save(newValue, key: daysKey) }
    }

    static func recordUse(key: String, on date: Date = .now, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        var days = usedDays
        var list = days[key] ?? []
        if !list.contains(day) { list.append(day) }
        // A couple of months is plenty for weekly check-ins and insights.
        days[key] = Array(list.sorted().suffix(70))
        usedDays = days
    }

    static func lastUse(key: String) -> Date? { usedDays[key]?.max() }

    /// Was the app used on any day of the 7 starting at `weekStart`?
    static func wasUsed(key: String, inWeekStarting weekStart: Date, calendar: Calendar = .current) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: weekStart)) else { return false }
        return (usedDays[key] ?? []).contains { $0 >= calendar.startOfDay(for: weekStart) && $0 < end }
    }

    /// When the "you haven't used it" notification was last sent, so it goes out at most weekly.
    static var lastNotified: [String: Date] {
        get { SharedStore.load([String: Date].self, key: notifiedKey) ?? [:] }
        set { SharedStore.save(newValue, key: notifiedKey) }
    }
}
