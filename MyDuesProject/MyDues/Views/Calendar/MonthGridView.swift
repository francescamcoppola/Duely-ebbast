//
//  MonthGridView.swift
//  MyDues
//
//  Month grid modeled on the Calendar app: today's number in the accent color, the selected day
//  filled, colored dots for days with charges. Swipe or use the chevrons to change month.
//

import SwiftUI
import SwiftData

struct MonthGridView: View {
    let month: CalendarMonth
    let schedule: MonthSchedule
    /// Returns, trials, pagoPA notices and warranties: shown as extra dots.
    var deadlines: [DeadlineItem] = []
    @Binding var selectedDay: Date
    let onChangeMonth: (Int) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which way the last month change went, so the grid slides the matching direction.
    @State private var direction = 1
    /// Bumped only when the user taps a day, so programmatic changes (month switch, Today) stay silent.
    @State private var dayTaps = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            grid
        }
        .cardStyle(padding: 12)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(month.start, format: .dateTime.month(.wide).year())
                .font(.title3.bold())
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            monthButton(offset: -1, symbol: "chevron.left", label: "Previous Month")
            monthButton(offset: 1, symbol: "chevron.right", label: "Next Month")
        }
        .padding(.leading, 6)
    }

    private func monthButton(offset: Int, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            change(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: AppMetrics.minimumHitTarget, height: AppMetrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)   // Each day cell already speaks its full date.
    }

    // MARK: Grid

    /// ZStack so the outgoing and incoming months overlap while sliding, instead of stacking.
    private var grid: some View {
        ZStack {
            monthGrid
                .id(month.start)   // New identity per month → animated transition.
                .transition(monthTransition)
        }
        .clipped()
        .simultaneousGesture(   // Simultaneous, so vertical scrolling still works over the grid.
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > 60, abs(horizontal) > abs(value.translation.height) else { return }
                    change(by: horizontal < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: dayTaps)
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            ForEach(month.days, id: \.self) { day in
                DayCell(
                    day: day,
                    payments: schedule.payments(on: day, calendar: calendar),
                    deadlineColors: deadlines
                        .filter { item in item.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
                        .map(\.kind.color),
                    isToday: calendar.isDateInToday(day),
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDay)
                ) {
                    selectedDay = day
                    dayTaps += 1
                }
            }
        }
    }

    private var monthTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        // Push already moves the old month out the opposite side.
        return .push(from: direction > 0 ? .trailing : .leading)
    }

    private func change(by offset: Int) {
        direction = offset
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.35)) {
            onChangeMonth(offset)
        }
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let payments: [ScheduledPayment]
    let deadlineColors: [Color]
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledCircle: CGFloat = 36
    /// Grows with Dynamic Type, capped so seven columns still fit on an iPhone.
    private var circleSize: CGFloat { min(scaledCircle, 48) }

    /// One dot per distinct subscription or deadline color (max 4), so a busy day stays readable.
    private var dotColors: [Color] {
        var seen = Set<Color>()
        return Array(
            (payments.map(\.subscription.displayColor) + deadlineColors)
                .filter { seen.insert($0).inserted }
                .prefix(4)
        )
    }

    private var numberColor: Color {
        if isSelected { return Color(.systemBackground) }
        if isToday { return .accentColor }
        return .primary
    }

    private var fillColor: Color {
        isToday ? .accentColor : .primary
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.day())
                    .font(.body.weight(isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: circleSize, height: circleSize)
                    .background {
                        if isSelected {
                            Circle().fill(fillColor)
                        }
                    }

                HStack(spacing: 3) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: circleSize + 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: Text {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(LocalizedBundle.locale))
        let prefix = isToday ? String(appLocalized: "Today, \(date)") : date
        guard !payments.isEmpty else { return Text(prefix) }
        let names = payments.map(\.subscription.name).formatted(.list(type: .and).locale(LocalizedBundle.locale))
        return Text("\(prefix). ^[\(payments.count) payment](inflect: true): \(names)")
    }
}
