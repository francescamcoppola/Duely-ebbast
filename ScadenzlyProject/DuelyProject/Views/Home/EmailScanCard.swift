//
//  EmailScanCard.swift
//  DuelyProject
//
//  Shown on Home while the Gmail scan started at the end of onboarding runs, or if it failed.
//  Its results open for review as soon as it finishes (RootTabView).
//

import SwiftUI
import SwiftData

struct EmailScanCard: View {
    @State private var emailImport = EmailImportModel.shared
    @Query private var subscriptions: [Subscription]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Searching Your Email")
                        .font(.headline)
                    status
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            progress
            actions
        }
        .cardStyle()
    }

    @ViewBuilder
    private var status: some View {
        switch emailImport.phase {
        case .failed(let message):
            Text(message)
        default:
            Text("Apple Intelligence is looking for subscriptions and free trials, bills and taxes, orders you can still return, warranties and pagoPA notices, on this device. You can use other apps meanwhile: you'll get a notification when it's done.")
        }
    }

    @ViewBuilder
    private var progress: some View {
        if case .scanning(let progress) = emailImport.phase {
            switch progress.stage {
            case .searching:
                ProgressView()
            case .filtering:
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Skipping ads and newsletters…").font(.caption)
                }
            case .reading:
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Reading emails…").font(.caption)
                } currentValueLabel: {
                    Text("\(progress.done) of \(progress.total)").font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if case .failed = emailImport.phase {
            HStack {
                Button("Scan Again") {
                    emailImport.startScan(existing: subscriptions, presentResultsOnHome: true)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                Button("Not Now") { emailImport.dismissReview() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        } else {
            Button("Stop Scanning", role: .cancel) { emailImport.cancelScan() }
                .font(.subheadline)
        }
    }
}
