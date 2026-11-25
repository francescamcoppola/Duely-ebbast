//
//  DeadlinesCard.swift
//  DuelyProject
//
//  Home's "Due Soon": the nearest returns, trials, pagoPA notices and warranties of the next two
//  weeks. Taps open the Deadlines tab.
//

import SwiftUI

struct DeadlinesCard: View {
    let items: [DeadlineItem]
    let currencyCode: String
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: onSelect) {
                    DeadlineRow(item: item, currencyCode: currencyCode)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
