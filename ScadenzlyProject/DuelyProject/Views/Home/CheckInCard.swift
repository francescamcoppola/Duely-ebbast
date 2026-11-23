//
//  CheckInCard.swift
//  DuelyProject
//
//  Shown on Home only while a weekly check-in is pending.
//

import SwiftUI

struct CheckInCard: View {
    let week: Date
    let action: () -> Void

    @Environment(\.calendar) private var calendar

    private var weekEnd: Date { calendar.date(byAdding: .day, value: 6, to: week) ?? week }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Check-In")
                        .font(.headline)
                    Text("Which subscriptions did you use from \((week..<weekEnd).formatted(.interval.day().month(.abbreviated)))? It takes 10 seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: action) {
                Text("Start Check-In")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .cardStyle()
    }
}

#Preview {
    CheckInCard(week: CheckInSchedule.reviewedWeekStart(for: .now)) {}
        .padding()
        .background(Color(.systemGroupedBackground))
}
