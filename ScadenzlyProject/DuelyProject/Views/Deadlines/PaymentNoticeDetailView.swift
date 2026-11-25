//
//  PaymentNoticeDetailView.swift
//  DuelyProject
//
//  One pagoPA notice: pay it on pagoPA's official checkout with its codes already filled in,
//  copy the codes, or show its QR code to scan with IO or a bank app on another device. Then
//  mark it as paid. `NewPaymentNoticeView` adds one by hand or from a PDF.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Detail

struct PaymentNoticeDetailView: View {
    @Bindable var notice: PaymentNotice

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var webPage: WebPage?
    @State private var isConfirmingDelete = false
    @State private var isShowingQR = false

    var body: some View {
        Form {
            summarySection

            if !notice.isPaid, let code = notice.code {
                Section {
                    Button {
                        webPage = WebPage(url: code.checkoutURL)
                    } label: {
                        Label("Pay with pagoPA", systemImage: "creditcard")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: AppMetrics.minimumHitTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Opens checkout.pagopa.it, pagoPA's official site, with this notice already filled in. Pay by card, PayPal, Satispay or your bank. The amount is checked again there.")
                }
            }

            if let code = notice.code {
                Section {
                    CopyableValueRow(title: "Notice Code", value: code.groupedNoticeNumber, copiedValue: code.noticeNumber)
                    CopyableValueRow(title: "Creditor Tax Code", value: code.fiscalCode)
                    DisclosureGroup("QR Code", isExpanded: $isShowingQR) {
                        QRCodeImage(payload: code.qrPayload())
                            .frame(maxWidth: 240)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                } header: {
                    Text("Codes")
                } footer: {
                    Text("To pay in the IO app, your bank's app or at a tobacconist: scan the QR code from another device, or enter the two codes.")
                }
            }

            Section {
                Button(notice.isPaid ? "Mark as Not Paid" : "Mark as Paid",
                       systemImage: notice.isPaid ? "arrow.uturn.backward" : "checkmark.circle") {
                    withAnimation { notice.paidAt = notice.isPaid ? nil : .now }
                }
            } footer: {
                if let paidAt = notice.paidAt {
                    Text("Marked as paid on \(Text(paidAt, format: .dateTime.day().month(.wide).year())).")
                }
            }

            NoticeFields(notice: notice)

            Section {
                Button("Delete Notice", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(notice.displayName.isEmpty ? String(appLocalized: "pagoPA Notice") : notice.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safariSheet($webPage)
        .onDisappear { try? context.save() }
        .confirmationDialog(Text("Delete this notice?"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Notice", role: .destructive) {
                context.delete(notice)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("It's only removed from \(AppInfo.name): if it isn't paid, it still has to be.")
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.amount, format: .currency(code: "EUR"))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if !notice.reason.isEmpty {
                    Text(notice.reason)
                        .font(.headline)
                }
                if let due = notice.dueDate {
                    Group {
                        if notice.isPaid {
                            Text("Paid")
                        } else if notice.isOverdue() {
                            Text("Overdue since \(Text(due, format: .dateTime.day().month(.wide).year()))")
                        } else {
                            Text("Due \(Text(due, format: .dateTime.day().month(.wide).year()))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(notice.isOverdue() ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Editable fields

private struct NoticeFields: View {
    @Bindable var notice: PaymentNotice
    @State private var hasDueDate = false
    @State private var didLoad = false

    var body: some View {
        Section {
            TextField("Issued By", text: $notice.payee)
                .textInputAutocapitalization(.words)
            TextField("Reason", text: $notice.reason)
            AmountField(title: "Amount", amount: $notice.amount, currencyCode: "EUR")
            Toggle("Due Date", isOn: $hasDueDate.animation())
            if hasDueDate {
                DatePicker("Due", selection: dueDate, displayedComponents: .date)
                Picker("Reminder", selection: $notice.reminderDaysBefore) {
                    Text("On the Day").tag(0)
                    ForEach([1, 3, 7], id: \.self) { days in
                        Text(ReminderOption.title(days)).tag(days)
                    }
                }
            }
        } header: {
            Text("Details")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            hasDueDate = notice.dueDate != nil
        }
        .onChange(of: hasDueDate) { _, has in
            notice.dueDate = has ? (notice.dueDate ?? Calendar.current.startOfDay(for: .now)) : nil
        }
    }

    private var dueDate: Binding<Date> {
        Binding { notice.dueDate ?? .now } set: { notice.dueDate = Calendar.current.startOfDay(for: $0) }
    }
}

// MARK: - New

struct NewPaymentNoticeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var payee = ""
    @State private var reason = ""
    @State private var noticeNumber = ""
    @State private var fiscalCode = ""
    @State private var amount: Decimal = 0
    @State private var hasDueDate = true
    @State private var dueDate = Date.now
    @State private var isImporting = false
    @State private var isReading = false
    @State private var importMessage: String?
    /// Other notices in the same PDF (installments), added together.
    @State private var extraNotices: [DetectedNotice] = []
    @State private var fieldsID = UUID()

    private var code: PagoPACode? { PagoPACode(noticeNumber: noticeNumber, fiscalCode: fiscalCode) }
    private var canAdd: Bool { code != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isImporting = true
                    } label: {
                        if isReading {
                            Label { Text("Reading the PDF…") } icon: { ProgressView() }
                        } else {
                            Label("Import from PDF", systemImage: "doc.viewfinder")
                        }
                    }
                    .disabled(isReading)
                } footer: {
                    if let importMessage {
                        Text(importMessage)
                    } else {
                        Text("Pick the notice's PDF: its QR code and details are read on this device.")
                    }
                }

                Section {
                    TextField("Notice Code (18 digits)", text: $noticeNumber)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                    TextField("Creditor Tax Code (11 digits)", text: $fiscalCode)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                } header: {
                    Text("Codes")
                } footer: {
                    if !noticeNumber.isEmpty, !fiscalCode.isEmpty, code == nil {
                        Text("Check the codes: the notice code has 18 digits, the creditor's tax code 11.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Printed on the notice, next to the QR code.")
                    }
                }

                Section {
                    TextField("Issued By", text: $payee)
                        .textInputAutocapitalization(.words)
                    TextField("Reason", text: $reason)
                    AmountField(title: "Amount", amount: $amount, currencyCode: "EUR")
                        .id(fieldsID)
                    Toggle("Due Date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if !extraNotices.isEmpty {
                        Text("^[\(extraNotices.count) more installment](inflect: true) from the same PDF will be added too.")
                    }
                }
            }
            .navigationTitle("New pagoPA Notice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Add", isEnabled: canAdd, action: add)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { return }
                Task { await importPDF(at: url) }
            }
        }
    }

    private func importPDF(at url: URL) async {
        isReading = true
        defer { isReading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = String(appLocalized: "The file couldn't be opened.")
            return
        }
        let found = await PaymentNoticeScanner.notices(inPDF: data)
        guard let first = found.first else {
            importMessage = String(appLocalized: "No pagoPA codes were found in this PDF. Enter them by hand.")
            return
        }
        noticeNumber = first.code.noticeNumber
        fiscalCode = first.code.fiscalCode
        if !first.payee.isEmpty { payee = first.payee }
        if !first.reason.isEmpty { reason = first.reason }
        if let value = first.amount { amount = value; fieldsID = UUID() }
        hasDueDate = first.dueDate != nil
        if let due = first.dueDate { dueDate = due }
        extraNotices = Array(found.dropFirst())
        importMessage = String(appLocalized: "Found in the PDF. Check the details before adding.")
    }

    private func add() {
        guard let code else { return }
        let trimmedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(PaymentNotice(code: code, payee: trimmedPayee, amount: amount,
                                     dueDate: hasDueDate ? dueDate : nil,
                                     reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
        for extra in extraNotices where extra.code != code {
            context.insert(PaymentNotice(code: extra.code, payee: extra.payee.isEmpty ? trimmedPayee : extra.payee,
                                         amount: extra.amount ?? 0, dueDate: extra.dueDate, reason: extra.reason))
        }
        try? context.save()
        Task { await NotificationService.requestAuthorizationIfNeeded() }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PaymentNoticeDetailView(notice: PaymentNotice(code: PagoPACode(noticeNumber: "301000000000123456", fiscalCode: "80014890638")!,
                                                      payee: "Comune di Napoli", amount: 128.5, dueDate: .now, reason: "TARI 2026 – rata 1"))
    }
    .modelContainer(PreviewData.emptyContainer)
}
