import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings tab — account, learned aliases (review/edit/delete), categories.
/// Per design, this is the smallest surface — most settings are minor.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Account.name)
    private var accounts: [Account]

    @Query(sort: \CategoryAlias.alias)
    private var aliases: [CategoryAlias]

    @Query(sort: \Category.name)
    private var categories: [Category]

    @Query(sort: \Loan.startDate, order: .reverse)
    private var loans: [Loan]

    @State private var showingResetConfirm = false
    @State private var showingExporter = false
    @State private var exportContent = ""
    @State private var exportError: String? = nil

    var body: some View {
        Form {
            // ─── Account ───
            Section("Account") {
                if let account = accounts.first {
                    LabeledContent("Name", value: account.name)
                    LabeledContent("Balance",
                                   value: TransactionService.formatPKR(account.realBalance))
                } else {
                    Text("No account yet — log something to create one.")
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    RecentTransactionsView()
                } label: {
                    Label("Recent transactions", systemImage: "list.bullet.rectangle")
                }
            }

            // ─── Loans ───
            if !loans.isEmpty {
                Section {
                    ForEach(loans) { loan in
                        LoanRow(loan: loan)
                    }
                } header: {
                    Text("Loans")
                } footer: {
                    Text("Tracked from chat: “lent ahmed 5000”, “borrowed 2k from sara”, “ahmed paid back 1000”.")
                        .font(.caption)
                }
            }

            // ─── Learned aliases ───
            Section {
                if aliases.isEmpty {
                    Text("None yet. The app learns when you teach it new words (\"j. → Clothes\").")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(aliases) { alias in
                        AliasRow(alias: alias, categories: categories)
                    }
                    .onDelete(perform: deleteAliases)
                }
            } header: {
                Text("Learned aliases")
            } footer: {
                Text("Words you've taught. Swipe to delete; tap to reassign to a different category.")
                    .font(.caption)
            }

            // ─── Categories ───
            Section {
                ForEach(categories) { cat in
                    NavigationLink {
                        CategoryEditView(category: cat)
                    } label: {
                        HStack {
                            Image(systemName: cat.kind == .income ? "arrow.down.circle" : "arrow.up.circle")
                                .foregroundStyle(cat.kind == .income ? Color.green : Color.secondary)
                            Text(cat.name)
                            Spacer()
                            Text("\(cat.transactions?.count ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Tap to edit name, manage keywords, or delete.")
                    .font(.caption)
            }

            // ─── Export ───
            Section {
                Button {
                    prepareExport()
                } label: {
                    Label("Export to Postgres (.sql)", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Generates a re-runnable Postgres SQL dump (CREATE TABLE + INSERTs). Run with `psql -f budget_export.sql` against your local DB.")
                    .font(.caption)
            }

            // ─── Danger zone ───
            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Reset all data", systemImage: "trash")
                }
            } header: {
                Text("Danger zone")
            } footer: {
                Text("Wipes all transactions, buckets, goals, loans, and learned aliases. Defaults will reseed on next launch.")
                    .font(.caption)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset everything?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: SQLExportDocument(content: exportContent),
            contentType: .text,
            defaultFilename: "budget_export"
        ) { result in
            if case .failure(let err) = result {
                exportError = err.localizedDescription
            }
        }
        .alert("Export error",
               isPresented: Binding(
                   get: { exportError != nil },
                   set: { if !$0 { exportError = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func prepareExport() {
        let service = ExportService(context: context)
        do {
            exportContent = try service.generatePostgresDump()
            showingExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func deleteAliases(at offsets: IndexSet) {
        for idx in offsets {
            context.delete(aliases[idx])
        }
        try? context.save()
    }

    private func resetAll() {
        // Delete in dependency order: allocations & audits → transactions → loans → buckets → tags → aliases/keywords → categories → accounts.
        do {
            try context.delete(model: Allocation.self)
            try context.delete(model: TransactionAudit.self)
            try context.delete(model: Transaction.self)
            try context.delete(model: PlanInstance.self)
            try context.delete(model: Plan.self)
            try context.delete(model: Loan.self)
            try context.delete(model: BucketPeriod.self)
            try context.delete(model: Bucket.self)
            try context.delete(model: Tag.self)
            try context.delete(model: CategoryAlias.self)
            try context.delete(model: CategoryKeyword.self)
            try context.delete(model: Category.self)
            try context.delete(model: Account.self)
            try context.save()
            // Reseed defaults so the app is usable immediately.
            SeedData.seedIfNeeded(context: context)
        } catch {
            print("Reset failed: \(error)")
        }
    }
}

// MARK: - Rows

private struct LoanRow: View {
    let loan: Loan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: loan.type == .givenOut ? "arrow.up.right" : "arrow.down.left")
                    .foregroundStyle(loan.type == .givenOut ? Color.orange : Color.blue)
                Text(loan.counterparty).font(.body)
                Spacer()
                Text(TransactionService.formatPKR(loan.currentBalance))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(loan.status == .paid ? .secondary : .primary)
            }
            HStack {
                Text(loan.type == .givenOut ? "lent" : "borrowed")
                Text("· principal \(TransactionService.formatPKR(loan.principal))")
                Spacer()
                Text(loan.status.rawValue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch loan.status {
        case .active:  return .blue
        case .partial: return .orange
        case .paid:    return .green
        case .overdue: return .red
        }
    }
}

private struct AliasRow: View {
    @Environment(\.modelContext) private var context
    let alias: CategoryAlias
    let categories: [Category]

    @State private var pickerCategoryID: UUID?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.alias).font(.body)
                Text("→ \(alias.category?.name ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(categories) { cat in
                    Button {
                        alias.category = cat
                        try? context.save()
                    } label: {
                        if alias.category?.id == cat.id {
                            Label(cat.name, systemImage: "checkmark")
                        } else {
                            Text(cat.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
    }
}
