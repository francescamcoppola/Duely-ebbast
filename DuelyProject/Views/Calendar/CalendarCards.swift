//
//  CalendarCards.swift
//  DuelyProject
//
//  Agenda for the selected day, and the month's real charges.
//  Rows here describe a *payment* (charged or due on a date), not a plan; plan details belong
//  to the Subscriptions tab.
//

import SwiftUI
import SwiftData

// MARK: - Shared styling

private enum Style {
    static let cardRadius: CGFloat = 24
    static let chargedColor = Color.green
    static let dueColor = Color.orange
}

private struct SurfaceBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

private extension View {
    func surfaceBackground() -> some View { modifier(SurfaceBackground()) }
}

/// Row button style with a soft highlight and a subtle press effect.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Small tinted capsule used for payment status.
private struct StatusPill: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Day agenda

struct DayAgendaView: View {
    let day: Date
    let payments: [ScheduledPayment]
    let currencyCode: String
    let onSelect: (Subscription) -> Void

    private var dayTotal: Decimal { payments.reduce(Decimal.zero) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if payments.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                        Button {
                            onSelect(payment.subscription)
                        } label: {
                            PaymentRow(payment: payment, currencyCode: currencyCode)
                        }
                        .buttonStyle(RowPressStyle())

                        if index < payments.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }

                    if payments.count > 1 {
                        totalFooter
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous))
                .surfaceBackground()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: payments.count)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day, format: .dateTime.weekday(.wide))
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.tint)

                Text(day, format: .dateTime.day().month(.wide))
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            if !payments.isEmpty {
                Text(dayTotal, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text("No payments on this day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .surfaceBackground()
    }

    private var totalFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dayTotal, format: .currency(code: currencyCode))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PaymentRow: View {
    let payment: ScheduledPayment
    let currencyCode: String

    var body: some View {
        AdaptiveStack(spacing: 14) {
            MonogramTile(subscription: payment.subscription, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(payment.subscription.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if payment.isPast {
                        StatusPill(title: "Charged", systemImage: "checkmark.circle.fill", color: Style.chargedColor)
                    } else {
                        StatusPill(title: "Due", systemImage: "clock.fill", color: Style.dueColor)
                    }
                    Text(payment.subscription.cycle.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(payment.amount, format: .currency(code: currencyCode))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(payment.isPast ? Color.secondary : Color.primary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows subscription details"))
    }
}

// MARK: - Month summary

struct MonthSummaryCard: View {
    let schedule: MonthSchedule
    let currencyCode: String
    let today: Date

    @Environment(\.calendar) private var calendar

    private var isCurrentMonth: Bool { schedule.month.contains(today, calendar: calendar) }

    /// Fraction of the month's total that has already been charged (0...1).
    private var chargedFraction: Double {
        guard schedule.total > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: schedule.chargedTotal / schedule.total).doubleValue
        return min(max(ratio, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hero
            VStack(alignment: .leading, spacing: 6) {
                Text("Charges in \(Text(schedule.month.start, format: .dateTime.month(.wide)))")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.tint)

                Text(schedule.total, format: .currency(code: currencyCode))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)

            if isCurrentMonth && schedule.total > 0 {
                progressBar
            }

            AdaptiveStack(verticalAlignment: .top, spacing: 10) {
                if isCurrentMonth {
                    stat("Charged",
                         Text(schedule.chargedTotal, format: .currency(code: currencyCode)),
                         systemImage: "checkmark.circle.fill",
                         color: Style.chargedColor)
                    stat("Still to come",
                         Text(schedule.upcomingTotal, format: .currency(code: currencyCode)),
                         systemImage: "clock.fill",
                         color: Style.dueColor)
                }
                stat("Payments",
                     Text(schedule.paymentCount, format: .number),
                     systemImage: "creditcard.fill",
                     color: .accentColor)
            }

            Label("Actual charges, on each subscription's billing date.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Style.dueColor.opacity(0.25))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Style.chargedColor.opacity(0.7), Style.chargedColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * chargedFraction, chargedFraction > 0 ? 8 : 0))
                }
            }
            .frame(height: 8)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: chargedFraction)

            Text("\(Int((chargedFraction * 100).rounded()))% already charged")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Month progress"))
        .accessibilityValue(Text("\(Int((chargedFraction * 100).rounded())) percent charged"))
    }

    private func stat(_ title: LocalizedStringKey,
                      _ value: Text,
                      systemImage: String,
                      color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                value
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.tertiarySystemGroupedBackground).opacity(0.7),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
