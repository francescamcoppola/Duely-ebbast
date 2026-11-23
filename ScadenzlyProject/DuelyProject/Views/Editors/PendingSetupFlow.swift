//
//  PendingSetupFlow.swift
//  DuelyProject
//
//  Sets up several "Needs Setup" subscriptions in one go: each Save moves on to the next one
//  instead of closing the sheet. Cancel at any point keeps what was already saved.
//

import SwiftUI
import SwiftData

/// What to present: the subscriptions to set up, in order. Identifiable for `.sheet(item:)`.
struct PendingSetup: Identifiable {
    let id = UUID()
    let subscriptions: [Subscription]

    /// Starts at the tapped subscription, then continues with the others in their usual order.
    init(starting first: Subscription, in pending: [Subscription]) {
        subscriptions = [first] + pending.filter { $0.id != first.id }
    }
}

struct PendingSetupFlow: View {
    /// Fixed when the flow opens: saving removes a subscription from "Needs Setup", which must not
    /// reshuffle the steps that are still to come.
    @State private var queue: [Subscription]
    @State private var index = 0

    @Environment(\.dismiss) private var dismiss

    init(_ setup: PendingSetup) {
        _queue = State(initialValue: setup.subscriptions)
    }

    var body: some View {
        if queue.indices.contains(index) {
            let subscription = queue[index]
            SubscriptionEditorView(
                subscription: subscription,
                progress: (current: index + 1, total: queue.count),
                onDone: advance
            )
            .id(subscription.id)   // A fresh editor per step, so fields reload for each one.
            .transition(.push(from: .trailing))
        }
    }

    private func advance() {
        if index + 1 < queue.count {
            withAnimation(.smooth) { index += 1 }
        } else {
            dismiss()
        }
    }
}

#Preview {
    let container = PreviewData.emptyContainer
    let pending = ["Netflix", "Spotify", "iCloud+"].map { Subscription(name: $0) }
    pending.forEach { container.mainContext.insert($0) }
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            PendingSetupFlow(PendingSetup(starting: pending[0], in: pending))
        }
        .modelContainer(container)
}
