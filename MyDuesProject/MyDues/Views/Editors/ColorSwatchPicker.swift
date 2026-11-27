//
//  ColorSwatchPicker.swift
//  MyDues
//
//  Reminders-style swatch grid. The first swatch keeps the category's color automatically.
//

import SwiftUI

struct ColorSwatchPicker: View {
    @Binding var selection: SubscriptionTint?
    /// Shown on the "Automatic" swatch (the category's color).
    let automaticColor: Color

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            swatch(color: automaticColor, isSelected: selection == nil,
                   label: "Automatic", symbol: "wand.and.stars") {
                selection = nil
            }
            ForEach(SubscriptionTint.allCases) { tint in
                swatch(color: tint.color, isSelected: selection == tint, label: tint.name) {
                    selection = tint
                }
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func swatch(
        color: Color,
        isSelected: Bool,
        label: LocalizedStringKey,
        symbol: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        // `.plain` matters: inside a Form row, default-styled buttons would all fire on any tap.
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(4)
                .overlay {
                    Circle()
                        .strokeBorder(color, lineWidth: 2.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: AppMetrics.minimumHitTarget, height: AppMetrics.minimumHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var tint: SubscriptionTint? = nil
    Form {
        Section("Color") {
            ColorSwatchPicker(selection: $tint, automaticColor: .red)
        }
    }
}
