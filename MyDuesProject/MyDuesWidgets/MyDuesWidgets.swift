//
//  MyDuesWidgets.swift
//  MyDuesWidgets
//
//  Home Screen and Lock Screen widgets. They read the snapshot the app writes to the App Group
//  (`WidgetSnapshot`): upcoming payments, the monthly total and texts in the app's language.
//

import WidgetKit
import SwiftUI

@main
struct MyDuesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPaymentWidget()
        UpcomingPaymentsWidget()
    }
}

// MARK: - Timeline

struct PaymentsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct PaymentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaymentsEntry {
        PaymentsEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PaymentsEntry) -> Void) {
        completion(PaymentsEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshot.load() ?? .preview))
    }

    /// One entry per day for a week, so "Tomorrow" becomes "Today" at midnight. The app also
    /// asks for a reload whenever its data changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PaymentsEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [PaymentsEntry(date: .now, snapshot: snapshot)]
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(PaymentsEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Next payment (Home Screen small + Lock Screen)

struct NextPaymentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPayment", provider: PaymentsProvider()) { entry in
            NextPaymentView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Payment")
        .description("Your next subscription or bill, and when it's due.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextPaymentView: View {
    let entry: PaymentsEntry
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Payment? { entry.snapshot?.payments(from: entry.date).first }

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryInline: inline(snapshot)
            case .accessoryCircular: circular(snapshot)
            case .accessoryRectangular: rectangular(snapshot)
            default: small(snapshot)
            }
        } else {
            Image(systemName: "calendar.badge.clock")
                .font(.title)
                .widgetAccentable()
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.labels.nextPayment)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            if let next {
                Circle()
                    .fill(SharedColor.color(named: next.color).gradient)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(next.name.prefix(1)).uppercased())
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text(next.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(snapshot.format(next.amount))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(snapshot.dueText(for: next.date, from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Text(snapshot.hasSubscriptions ? snapshot.labels.nothingDue : snapshot.labels.noSubscriptions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inline(_ snapshot: WidgetSnapshot) -> some View {
        if let next {
            Label("\(next.name) · \(snapshot.format(next.amount)) · \(snapshot.dueText(for: next.date, from: entry.date))",
                  systemImage: "creditcard")
        } else {
            Label(snapshot.labels.nothingDue, systemImage: "checkmark.circle")
        }
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date),
                                                           to: Calendar.current.startOfDay(for: next.date)).day ?? 0
                VStack(spacing: 0) {
                    Text(String(next.name.prefix(3)))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text("\(max(days, 0))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .widgetAccentable()
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
            }
        }
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.labels.nextPayment)
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let next {
                Text(next.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(snapshot.format(next.amount)) · \(snapshot.dueText(for: next.date, from: entry.date))")
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text(snapshot.labels.nothingDue)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Upcoming payments (Home Screen medium / large)

struct UpcomingPaymentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingPayments", provider: PaymentsProvider()) { entry in
            UpcomingPaymentsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Payments")
        .description("What's due soon and your monthly total.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct UpcomingPaymentsView: View {
    let entry: PaymentsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            let payments = Array(snapshot.payments(from: entry.date).prefix(family == .systemLarge ? 7 : 3))
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot)
                if payments.isEmpty {
                    Spacer(minLength: 0)
                    Text(snapshot.hasSubscriptions ? snapshot.labels.nothingDue : snapshot.labels.noSubscriptions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 8) {
                        ForEach(payments, id: \.self) { payment in
                            row(payment, snapshot: snapshot)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.tint)
        }
    }

    private func header(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.labels.upcoming)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(snapshot.format(snapshot.monthlyTotal)) \(snapshot.labels.perMonth)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            if let budget = snapshot.budget, budget > 0 {
                let ratio = min(NSDecimalNumber(decimal: snapshot.monthlyTotal / budget).doubleValue, 1)
                ProgressView(value: ratio)
                    .tint(ratio >= 1 ? .red : ratio >= 0.85 ? .orange : .green)
                    .accessibilityLabel(Text(String(format: snapshot.labels.ofBudget, snapshot.format(snapshot.monthlyTotal), snapshot.format(budget))))
            }
        }
    }

    private func row(_ payment: WidgetSnapshot.Payment, snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(SharedColor.color(named: payment.color))
                .frame(width: 5, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(payment.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot.dueText(for: payment.date, from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(snapshot.format(payment.amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - Preview data

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now }
        return WidgetSnapshot(
            currencyCode: "EUR",
            localeIdentifier: Locale.current.identifier,
            monthlyTotal: 48.97,
            budget: 80,
            upcoming: [
                .init(name: "Netflix", date: day(1), amount: 13.99, color: "red"),
                .init(name: "Spotify", date: day(4), amount: 11.99, color: "green"),
                .init(name: "iCloud+", date: day(9), amount: 2.99, color: "blue"),
            ],
            hasSubscriptions: true,
            labels: .init(nextPayment: "Next Payment", upcoming: "Up Next", perMonth: "/mo", today: "Today",
                          tomorrow: "Tomorrow", inDays: [4: "In 4 days", 9: "In 9 days"],
                          nothingDue: "Nothing due", noSubscriptions: "No subscriptions", ofBudget: "%@ of %@"),
            updated: .now
        )
    }
}
