//
//  SubscriptionEditorView.swift
//  DuelyProject
//
//  Add or edit a subscription. Presented as a sheet; standard Form so it matches Settings-style
//  editors people already know.
//

import SwiftUI
import SwiftData

struct SubscriptionEditorView: View {
    /// `nil` adds a new subscription.
    let subscription: Subscription?
    /// Called after a delete, so a detail screen underneath can close too.
    var onDeleted: (() -> Void)? = nil
    /// Set when the editor is one step of `PendingSetupFlow`: shown as "2 of 4" under the title.
    var progress: (current: Int, total: Int)? = nil
    /// Called instead of dismissing after a save or delete, so a flow can move to the next one.
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// A plans page shown in an in-app Safari sheet.
    @State private var webPage: WebPage?
    @AppStorage(OnboardingKeys.currencyCode) private var currencyCode = AppDefaults.currencyCode

    @State private var name = ""
    @State private var priceText = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var category: SubscriptionCategory = .other
    @State private var nextPayment = Date.now
    @State private var reminderDays = 1
    @State private var tint: SubscriptionTint?
    /// Plan picked from the catalog. Kept if the price is edited (a promo, an old price), dropped
    /// if the billing cycle no longer matches it (see `resolvedPlanName`).
    @State private var planName: String?
    @State private var catalog = PlanCatalogStore.shared
    @State private var didLoad = false
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, price }

    private var currency: CurrencyOption { CurrencyOption(code: currencyCode) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var price: Decimal? { priceText.isEmpty ? nil : Decimal(string: priceText, locale: .current) }
    private var canSave: Bool { !trimmedName.isEmpty && (price ?? 0) > 0 }
    private var isNew: Bool { subscription == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MonogramTile(name: trimmedName.isEmpty ? "?" : trimmedName,
                                     color: tint?.color ?? category.color,
                                     size: 32)
                            .animation(.smooth(duration: 0.2), value: tint)
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .price }
                    }

                    ForEach(nameSuggestions) { service in
                        Button {
                            choose(service)
                        } label: {
                            ServiceSuggestionRow(service: service, currencyCode: currencyCode)
                        }
                        .foregroundStyle(.primary)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(SubscriptionCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                }

                if let matchedService {
                    plansSection(for: matchedService)
                } else if trimmedName.count >= 2, nameSuggestions.isEmpty {
                    // Not in the catalog: find its own website and plans page.
                    Section {
                        FindPlansButton(name: trimmedName, knownDomain: subscription?.websiteDomain) { url in
                            webPage = WebPage(url: url)
                        }
                    } footer: {
                        Text("Opens \(trimmedName)'s own plans page to compare prices, then enter the one you pay for below.")
                    }
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $tint, automaticColor: category.color)
                }

                Section {
                    HStack {
                        Text("Price")
                        Spacer(minLength: 16)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .price)
                        Text(currency.code)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Billing Cycle", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.title).tag(cycle)
                        }
                    }

                    DatePicker("Next Payment", selection: $nextPayment, displayedComponents: .date)
                } footer: {
                    if cycle != .monthly, let price, price > 0 {
                        Text("About \(Text(BillingMath.monthlyEquivalent(price: price, cycle: cycle), format: .currency(code: currencyCode))) per month.")
                    }
                }

                Section {
                    Picker("Reminder", selection: $reminderDays) {
                        ForEach(ReminderOption.all, id: \.self) { days in
                            Text(ReminderOption.title(days)).tag(days)
                        }
                    }
                }

                if !isNew {
                    Section {
                        if let subscription {
                            CancelSubscriptionButton(subscription: subscription)
                        }
                        Button("Delete Subscription", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("Cancel Subscription opens the service's own cancellation page. Delete only removes it from \(AppInfo.name).")
                    }
                }
            }
            .navigationTitle(isNew ? "New Subscription" : "Edit Subscription")
            .progressSubtitle(progressText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: confirmTitle,
                                       systemImage: isNew || isLastStep ? "checkmark" : "arrow.right",
                                       isEnabled: canSave, action: save)
                }
            }
            .confirmationDialog(
                Text("Delete \(trimmedName.isEmpty ? String(localized: "this subscription") : trimmedName)?"),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Subscription", role: .destructive, action: delete)
            } message: {
                Text("Its check-in history will be deleted too.")
            }
            .onChange(of: priceText) { _, newValue in
                let clean = OnboardingViewModel.sanitizedAmount(newValue, maxFractionDigits: currency.fractionDigits)
                if clean != newValue { priceText = clean }
            }
            .onAppear(perform: load)
            .task {
                guard isNew else { return }
                try? await Task.sleep(for: .milliseconds(450))
                focusedField = .name
            }
        }
        .safariSheet($webPage)
        // Unsaved edits shouldn't be lost by an accidental swipe-down.
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: Plans

    /// The catalog service for the name typed so far, if it's a known one.
    private var matchedService: CatalogService? {
        catalog.service(matching: trimmedName)
    }

    /// Known services matching what's being typed, while the name field is focused.
    private var nameSuggestions: [CatalogService] {
        guard focusedField == .name, !trimmedName.isEmpty else { return [] }
        let results = catalog.suggestions(for: trimmedName)
        // Once the name is exactly a known service, the plans section takes over.
        if results.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) { return [] }
        return results
    }

    /// The selected plan's name, only if it belongs to the service the name refers to and its
    /// billing cycle is still the one chosen.
    private var resolvedPlanName: String? {
        guard let planName,
              let plan = matchedService?.plans.first(where: { $0.name == planName }),
              BillingCycle(rawValue: plan.cycle) == cycle else { return nil }
        return planName
    }

    @ViewBuilder
    private func plansSection(for service: CatalogService) -> some View {
        let priced = service.plans(in: currencyCode)
        Section {
            if priced.isEmpty {
                ForEach(service.plans) { plan in
                    Button {
                        planName = plan.name
                        cycle = BillingCycle(rawValue: plan.cycle) ?? cycle
                    } label: {
                        PlanRow(name: plan.name, details: plan.details, price: nil,
                                cycle: BillingCycle(rawValue: plan.cycle) ?? .monthly,
                                currencyCode: currencyCode, isSelected: resolvedPlanName == plan.name)
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                ForEach(priced) { option in
                    Button {
                        apply(option)
                    } label: {
                        PlanRow(name: option.plan.name, details: option.plan.details, price: option.price,
                                cycle: option.cycle, currencyCode: currencyCode,
                                isSelected: resolvedPlanName == option.plan.name)
                    }
                    .foregroundStyle(.primary)
                }
            }
            if let website = service.website.flatMap(URL.init(string:)) {
                Button {
                    webPage = WebPage(url: website)
                } label: {
                    Label("See All Plans on \(service.name)'s Website", systemImage: "safari")
                }
            }
        } header: {
            Text("\(service.name) Plans")
        } footer: {
            if priced.isEmpty {
                Text("Plan prices aren't available in \(currency.name). Pick a plan to set its billing cycle, then enter the price.")
            } else {
                Text("Choose a plan to fill in the price and billing cycle. Typical prices as of \(catalogDate); check the current price with the provider.")
            }
        }
    }

    private var catalogDate: String {
        let parts = catalog.catalog.updated.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return catalog.catalog.updated
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func choose(_ service: CatalogService) {
        name = service.name
        if isNew || category == .other { category = service.subscriptionCategory }
        planName = nil
        focusedField = nil
        // A service with a single plan needs no choice.
        let priced = service.plans(in: currencyCode)
        if priced.count == 1, let only = priced.first { apply(only) }
    }

    private func apply(_ option: PricedPlan) {
        planName = option.plan.name
        cycle = option.cycle
        priceText = OnboardingViewModel.sanitizedAmount(
            BillingMath.storedString(option.price),
            maxFractionDigits: currency.fractionDigits
        )
        focusedField = nil
    }

    // MARK: Helpers

    private var isLastStep: Bool { progress.map { $0.current >= $0.total } ?? true }

    private var confirmTitle: LocalizedStringKey {
        if isNew { return "Add" }
        return isLastStep ? "Save" : "Next"
    }

    private var progressText: Text? {
        guard let progress, progress.total > 1 else { return nil }
        return Text("\(progress.current) of \(progress.total)")
    }

    /// Closes the sheet, or hands control back to the flow that presented this step.
    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private var hasChanges: Bool {
        guard let subscription else { return !trimmedName.isEmpty || !priceText.isEmpty }
        return trimmedName != subscription.name
            || price != (subscription.price > 0 ? subscription.price : nil)
            || cycle != subscription.cycle
            || category != subscription.category
            || reminderDays != subscription.reminderDaysBefore
            || tint != subscription.tint
            || resolvedPlanName != subscription.planName
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let subscription else { return }
        name = subscription.name
        cycle = subscription.cycle
        category = subscription.category
        reminderDays = ReminderOption.all.contains(subscription.reminderDaysBefore) ? subscription.reminderDaysBefore : 1
        tint = subscription.tint
        planName = subscription.planName
        nextPayment = subscription.nextPayment() ?? .now
        if subscription.price > 0 {
            priceText = OnboardingViewModel.sanitizedAmount(
                BillingMath.storedString(subscription.price),
                maxFractionDigits: currency.fractionDigits
            )
        }
    }

    private func save() {
        guard canSave, let price else { return }

        let target: Subscription
        if let subscription {
            target = subscription
        } else {
            target = Subscription(name: trimmedName)
            context.insert(target)
        }
        if DetectedSubscription.matchKey(target.name) != DetectedSubscription.matchKey(trimmedName) {
            // Another service: its website and cancellation page must be found again.
            target.cancelURL = nil
            target.websiteDomain = nil
        }
        target.name = trimmedName
        target.price = price
        target.cycle = cycle
        target.category = category
        target.anchorDate = Calendar.current.startOfDay(for: nextPayment)
        target.reminderDaysBefore = reminderDays
        target.tint = tint
        target.planName = resolvedPlanName

        do {
            try context.save()
        } catch {
            assertionFailure("Save failed: \(error)")
        }
        finish()

        // The user just asked to be reminded: the natural moment for the system prompt (first time only).
        if reminderDays > 0 {
            Task { await NotificationService.requestAuthorizationIfNeeded() }
        }
    }

    private func delete() {
        guard let subscription else { return }
        context.delete(subscription)
        try? context.save()
        finish()
        onDeleted?()
    }
}

// MARK: - Rows

private struct ServiceSuggestionRow: View {
    let service: CatalogService
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            MonogramTile(name: service.name, color: service.subscriptionCategory.color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                if let cheapest = service.plans(in: currencyCode).first {
                    Text("From \(Text(cheapest.monthlyCost, format: .currency(code: currencyCode))) a month · ^[\(service.plans.count) plan](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Fills in the name and shows its plans")
    }
}

private struct PlanRow: View {
    let name: String
    let details: String?
    let price: Decimal?
    let cycle: BillingCycle
    let currencyCode: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let price {
                    Text(price, format: .currency(code: currencyCode))
                        .monospacedDigit()
                }
                Text(cycle.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("New") {
    SubscriptionEditorView(subscription: nil)
        .modelContainer(PreviewData.container)
}

private extension View {
    /// Adds a navigation subtitle only when there is one, so a single edit keeps a one-line title.
    @ViewBuilder
    func progressSubtitle(_ subtitle: Text?) -> some View {
        if let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}
