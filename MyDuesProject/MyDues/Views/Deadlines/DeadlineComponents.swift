//
//  DeadlineComponents.swift
//  MyDues
//
//  Small views shared by the Deadlines tab, its detail screens, Home and the import review.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Icon

/// The kind's symbol on its color, the same size and shape as `MonogramTile`.
struct DeadlineIcon: View {
    let kind: DeadlineItem.Kind
    @ScaledMetric private var size: CGFloat
    private let baseSize: CGFloat

    init(kind: DeadlineItem.Kind, size: CGFloat = 40) {
        self.kind = kind
        self.baseSize = size
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var tileSize: CGFloat { min(size, baseSize * 2) }

    var body: some View {
        RoundedRectangle(cornerRadius: tileSize * 0.28, style: .continuous)
            .fill(kind.color.gradient)
            .frame(width: tileSize, height: tileSize)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: tileSize * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Row

struct DeadlineRow: View {
    let item: DeadlineItem
    let currencyCode: String

    @Environment(\.calendar) private var calendar

    private var daysAway: Int? {
        item.date.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: $0)).day ?? 0 }
    }

    /// Red when it's today, tomorrow or overdue.
    private var isUrgent: Bool { (daysAway ?? .max) <= 1 }

    var body: some View {
        AdaptiveStack(spacing: 14) {
            DeadlineIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                detail
                    .font(.subheadline)
                    .foregroundStyle(isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }

            Spacer(minLength: 8)

            if let amount = item.amount {
                Text(amount, format: .currency(code: item.kind == .notice ? "EUR" : currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        if let date = item.date, let daysAway {
            let day = Text(date, format: .dateTime.day().month(.abbreviated).year())
            switch item.kind {
            case .returnWindow:
                daysAway == 0 ? Text("Last day to return") : Text("Return by \(day) · \(relative(daysAway))")
            case .warranty:
                Text("Warranty until \(day)")
            case .trial:
                Text("Trial ends \(day) · \(relative(daysAway))")
            case .notice:
                daysAway < 0 ? Text("Overdue since \(day)") : Text("Due \(day) · \(relative(daysAway))")
            }
        } else {
            Text("No due date")
        }
    }

    private func relative(_ days: Int) -> String {
        HomeSummary.relativeDay(days)
    }
}

// MARK: - Amount field

/// A price typed with the keyboard, bound to a `Decimal`. Accepts "." and ",".
struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var amount: Decimal
    var currencyCode: String

    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(currencyCode)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if text.isEmpty, amount > 0 {
                text = OnboardingViewModel.sanitizedAmount(BillingMath.storedString(amount))
            }
        }
        .onChange(of: text) { _, newValue in
            let clean = OnboardingViewModel.sanitizedAmount(newValue)
            if clean != newValue { text = clean; return }
            let normalized = clean.replacingOccurrences(of: ",", with: ".")
            amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }
    }
}

// MARK: - QR code

/// A QR code drawn from a string, sharp at any size.
struct QRCodeImage: View {
    let payload: String

    var body: some View {
        if let image = Self.image(for: payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(Text("pagoPA QR code"))
        }
    }

    private static func image(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Copyable value

/// A code with a Copy button, like the ones printed on a pagoPA notice.
struct CopyableValueRow: View {
    let title: LocalizedStringKey
    let value: String
    var copiedValue: String?

    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.body.monospacedDigit())
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = copiedValue ?? value
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: AppMetrics.minimumHitTarget, minHeight: AppMetrics.minimumHitTarget)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: copied) { _, now in now }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }
}
