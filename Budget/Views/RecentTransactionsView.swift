import SwiftUI
import SwiftData

/// Recent transactions list — newest first. Linked from Settings.
/// Swipe a row to void (within 7-day window). Tap to edit the amount.
struct RecentTransactionsView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Transaction> { !$0.isVoided },
        sort: \Transaction.occurredAt,
        order: .reverse
    )
    private var transactions: [Transaction]

    @State private var editTarget: Transaction? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        List {
            ForEach(transactions) { txn in
                RecentTransactionRow(transaction: txn)
                    .contentShape(Rectangle())
                    .onTapGesture { editTarget = txn }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            voidTxn(txn)
                        } label: {
                            Label("Void", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Recent")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet",
                    description: Text("Log something on the Chat tab.")
                )
            }
        }
        .sheet(item: $editTarget) { txn in
            EditTransactionSheet(transaction: txn)
        }
        .alert("Couldn't void",
               isPresented: Binding(
                   get: { errorMessage != nil },
                   set: { if !$0 { errorMessage = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func voidTxn(_ txn: Transaction) {
        let editor = EditService(context: context)
        do {
            try editor.void(txn)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct RecentTransactionRow: View {
    let transaction: Transaction

    private var isOutsideEditWindow: Bool {
        Date().timeIntervalSince(transaction.occurredAt) > EditService.editWindow
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.category?.name ?? "Uncategorized")
                        .font(.body)
                    if isOutsideEditWindow {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let raw = transaction.rawInput {
                    Text(raw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountString)
                .font(.body.monospacedDigit())
                .foregroundStyle(amountColor)
        }
    }

    private var amountString: String {
        let prefix = (transaction.direction == .outflow) ? "-" : "+"
        return prefix + TransactionService.formatPKR(transaction.amount)
    }

    private var amountColor: Color {
        transaction.direction == .outflow ? .primary : .green
    }
}

// MARK: - Edit sheet

struct EditTransactionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction

    @State private var amountText: String = ""
    @State private var error: String? = nil

    private var isOutsideWindow: Bool {
        Date().timeIntervalSince(transaction.occurredAt) > EditService.editWindow
    }

    private var parsedAmount: Decimal? {
        Parser.parseAmountToken(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Category", value: transaction.category?.name ?? "—")
                    LabeledContent("Date",
                                   value: transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Direction", value: transaction.direction.rawValue)
                    if let raw = transaction.rawInput {
                        LabeledContent("Original", value: raw)
                    }
                }

                if isOutsideWindow {
                    Section {
                        Label("Locked — older than 7 days. Add a corrective entry on the Chat tab.",
                              systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Edit amount") {
                        TextField("New amount", text: $amountText)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    }

                    if let error {
                        Section {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }

                let audits = (transaction.auditEntries ?? [])
                    .sorted(by: { $0.changedAt > $1.changedAt })
                if !audits.isEmpty {
                    Section("History") {
                        ForEach(audits) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.changeType.rawValue) · \(a.fieldChanged ?? "")")
                                    .font(.caption.weight(.semibold))
                                if let old = a.oldValue, let new = a.newValue {
                                    Text("\(old) → \(new)").font(.caption2)
                                }
                                Text(a.changedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !isOutsideWindow {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(parsedAmount == nil || parsedAmount == transaction.amount)
                    }
                }
            }
            .onAppear {
                amountText = "\(transaction.amount)"
            }
        }
    }

    private func save() {
        guard let newAmount = parsedAmount else { return }
        let editor = EditService(context: context)
        do {
            try editor.updateAmount(of: transaction, to: newAmount)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
