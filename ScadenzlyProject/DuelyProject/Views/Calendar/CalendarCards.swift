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

// MARK: - Day agenda

struct DayAgendaView: View {
    let day: Date
    let payments: [ScheduledPayment]
    let currencyCode: String
    let onSelect: (Subscription) -> Void

    private var dayTotal: Decimal { payments.reduce(Decimal.zero) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.bold())
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            if payments.isEmpty {
                Label("No payments on this day.", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                        HStack(spacing: 0) {
                            Button {
                                onSelect(payment.subscription)
                            } label: {
                                PaymentRow(payment: payment, currencyCode: currencyCode)
                            }
                            .buttonStyle(.plain)

                            // Past payments are already charged; today's and later can be ticked off.
                            if !payment.isPast {
                                PaidCheckButton(subscription: payment.subscription, date: payment.date)
                                    .padding(.trailing, 6)
                            }
                        }

                        if index < payments.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }

                    if payments.count > 1 {
                        Divider()
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(dayTotal, format: .currency(code: currencyCode))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

private struct PaymentRow: View {
    let payment: ScheduledPayment
    let currencyCode: String

    var body: some View {
        AdaptiveStack(spacing: 14) {
            MonogramTile(subscription: payment.subscription, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(payment.subscription.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if payment.isPast {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Charged")
                    } else if payment.isMarkedPaid {
                        Text("Paid")
                    } else {
                        Text("Due")
                    }
                    Text("·").accessibilityHidden(true)
                    Text(payment.subscription.cycle.title)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(payment.amount, format: .currency(code: currencyCode))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(payment.isPaid ? Color.secondary : Color.primary)
        }
        .padding(.leading, 16)
        .padding(.trailing, payment.isPast ? 16 : 4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows subscription details"))
    }
}

// MARK: - Month summary

struct MonthSummaryCard: View {
    let schedule: MonthSchedule
    /// Home's "Average per month", so the card can explain why this month differs.
    let monthlyAverage: Decimal
    let currencyCode: String
    let today: Date

    @Environment(\.calendar) private var calendar

    private var isCurrentMonth: Bool { schedule.month.contains(today, calendar: calendar) }

    /// Share of the month's charges already paid, for the progress bar.
    private var chargedFraction: Double {
        let total = BillingMath.double(schedule.total)
        return total > 0 ? BillingMath.double(schedule.chargedTotal) / total : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Charges in \(Text(schedule.month.start, format: .dateTime.month(.wide))) · ^[\(schedule.paymentCount) payment](inflect: true)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(schedule.total, format: .currency(code: currencyCode))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Only the current month is split: past months are all charged, future ones all to come
            // (unless some are already marked as paid).
            if isCurrentMonth {
                VStack(alignment: .leading, spacing: 8) {
                    BudgetBar(ratio: chargedFraction, tint: .accentColor)
                    AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
                        // Fills the row, so "Still to come" sits on the right; no Spacer, which
                        // would stretch vertically once the row stacks at large text sizes.
                        amountLabel("Charged", schedule.chargedTotal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        amountLabel("Still to come", schedule.upcomingTotal)
                    }
                    .font(.footnote)
                }
            }

            Divider()

            explanation
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func amountLabel(_ title: LocalizedStringKey, _ amount: Decimal) -> some View {
        Text("\(Text(title).foregroundStyle(.secondary)) \(Text(amount, format: .currency(code: currencyCode)).fontWeight(.semibold).monospacedDigit())")
            .lineLimit(1)
            .fixedSize()
    }

    /// Answers "why isn't this the same as Home's average?" instead of describing how it's counted.
    private var explanation: Text {
        let average = Text(monthlyAverage, format: .currency(code: currencyCode))
        switch schedule.comparison(toMonthlyAverage: monthlyAverage) {
        case .higher(let renewals) where !renewals.isEmpty:
            let names = renewals.formatted(.list(type: .and).locale(LocalizedBundle.locale))
            return Text("Higher than your \(average) average because of plans that renew this month: \(names).")
        case .higher:
            return Text("Higher than your \(average) average because more payments fall in this month.")
        case .lower:
            return Text("Lower than your \(average) average: your longer plans renew in other months.")
        case .typical:
            return Text("Close to your \(average) monthly average.")
        }
    }
}


