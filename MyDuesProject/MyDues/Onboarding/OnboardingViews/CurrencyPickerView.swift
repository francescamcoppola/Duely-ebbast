//
//  CurrencyPickerView.swift
//  MyDues
//
//  Created by Diego Alonso Tamez Flores on 17/11/2026.
//


import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selection: CurrencyOption

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let suggested = CurrencyOption.suggested
    private let all = CurrencyOption.all

    private var results: [CurrencyOption] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return all }
        return all.filter {
            $0.name.localizedStandardContains(term)
                || $0.code.localizedStandardContains(term)
                || $0.symbol.localizedStandardContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Suggested") {
                        ForEach(suggested) { row(for: $0) }
                    }
                    Section("All Currencies") {
                        ForEach(all) { row(for: $0) }
                    }
                } else {
                    ForEach(results) { row(for: $0) }
                }
            }
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search currencies")
            )
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark", role: .close) { dismiss() }
    }

    private func row(for option: CurrencyOption) -> some View {
        let isSelected = option.code == selection.code
        return Button {
            selection = option
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(option.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 44, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                        .foregroundStyle(.primary)
                    Text(option.code)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("\(option.name), \(option.code)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection = CurrencyOption.current
    Color.clear.sheet(isPresented: .constant(true)) {
        CurrencyPickerView(selection: $selection)
    }
}
