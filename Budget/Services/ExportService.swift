import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Generates a Postgres-compatible SQL dump of the user's Budget data.
/// Output is a single .sql file containing CREATE TABLE statements + INSERTs,
/// wrapped in a BEGIN/COMMIT block. Re-runnable (drops existing tables first).
///
/// Usage on the Postgres side (her existing local Docker):
///     psql -h localhost -U postgres -d budget -f budget_export.sql
@MainActor
struct ExportService {
    let context: ModelContext

    func generatePostgresDump() throws -> String {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let buckets = try context.fetch(FetchDescriptor<Bucket>())
        let loans = try context.fetch(FetchDescriptor<Loan>())
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let allocations = try context.fetch(FetchDescriptor<Allocation>())

        var s = String()

        s += "-- Budget app export\n"
        s += "-- Generated: \(Self.iso8601(Date()))\n"
        s += "-- Rows: \(accounts.count) accounts, \(categories.count) categories, "
        s += "\(buckets.count) buckets, \(loans.count) loans, "
        s += "\(transactions.count) transactions, \(allocations.count) allocations\n\n"

        s += "BEGIN;\n\n"

        // Drop in reverse FK order
        s += "DROP TABLE IF EXISTS allocations CASCADE;\n"
        s += "DROP TABLE IF EXISTS transactions CASCADE;\n"
        s += "DROP TABLE IF EXISTS buckets CASCADE;\n"
        s += "DROP TABLE IF EXISTS loans CASCADE;\n"
        s += "DROP TABLE IF EXISTS categories CASCADE;\n"
        s += "DROP TABLE IF EXISTS accounts CASCADE;\n\n"

        // CREATE TABLE
        s += createAccountsSQL
        s += createCategoriesSQL
        s += createBucketsSQL
        s += createLoansSQL
        s += createTransactionsSQL
        s += createAllocationsSQL
        s += "\n"

        // INSERTs
        for a in accounts { s += insert(account: a) }
        s += "\n"
        for c in categories { s += insert(category: c) }
        s += "\n"
        for b in buckets { s += insert(bucket: b) }
        s += "\n"
        for l in loans { s += insert(loan: l) }
        s += "\n"
        for t in transactions { s += insert(transaction: t) }
        s += "\n"
        for a in allocations { s += insert(allocation: a) }

        s += "\nCOMMIT;\n"
        return s
    }

    // MARK: - CREATE TABLE

    private let createAccountsSQL = """
    CREATE TABLE accounts (
        id              UUID PRIMARY KEY,
        name            TEXT NOT NULL,
        type            TEXT,
        real_balance    NUMERIC(14,2) NOT NULL DEFAULT 0,
        is_active       BOOLEAN NOT NULL DEFAULT TRUE,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    """

    private let createCategoriesSQL = """
    CREATE TABLE categories (
        id              UUID PRIMARY KEY,
        name            TEXT NOT NULL,
        kind            TEXT NOT NULL,  -- 'expense' | 'income'
        icon            TEXT,
        color           TEXT
    );

    """

    private let createBucketsSQL = """
    CREATE TABLE buckets (
        id                 UUID PRIMARY KEY,
        name               TEXT NOT NULL,
        kind               TEXT NOT NULL,  -- 'spendingPlan' | 'savingsGoal' | 'reserve'
        timeline           TEXT NOT NULL,
        period_start       DATE,
        period_end         DATE,
        planned_amount     NUMERIC(14,2),
        allocated_amount   NUMERIC(14,2) NOT NULL DEFAULT 0,
        rollover_unused    BOOLEAN NOT NULL DEFAULT FALSE,
        target_amount      NUMERIC(14,2),
        target_date        DATE,
        linked_category_id UUID REFERENCES categories(id),
        is_deleted         BOOLEAN NOT NULL DEFAULT FALSE,
        deleted_at         TIMESTAMPTZ,
        created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    """

    private let createLoansSQL = """
    CREATE TABLE loans (
        id                 UUID PRIMARY KEY,
        type               TEXT NOT NULL,  -- 'givenOut' | 'taken'
        counterparty       TEXT NOT NULL,
        principal          NUMERIC(14,2) NOT NULL,
        current_balance    NUMERIC(14,2) NOT NULL,
        interest_rate      NUMERIC(5,2),
        start_date         DATE NOT NULL,
        due_date           DATE,
        status             TEXT NOT NULL,
        notes              TEXT
    );

    """

    private let createTransactionsSQL = """
    CREATE TABLE transactions (
        id              UUID PRIMARY KEY,
        account_id      UUID REFERENCES accounts(id),
        amount          NUMERIC(14,2) NOT NULL,
        direction       TEXT NOT NULL,  -- 'inflow' | 'outflow'
        category_id     UUID REFERENCES categories(id),
        bucket_id       UUID REFERENCES buckets(id),
        loan_id         UUID REFERENCES loans(id),
        occurred_at     TIMESTAMPTZ NOT NULL,
        raw_input       TEXT,
        raw_fragment    TEXT,
        is_voided       BOOLEAN NOT NULL DEFAULT FALSE,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        modified_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX idx_transactions_occurred_at ON transactions(occurred_at);
    CREATE INDEX idx_transactions_category    ON transactions(category_id);

    """

    private let createAllocationsSQL = """
    CREATE TABLE allocations (
        id                 UUID PRIMARY KEY,
        bucket_id          UUID REFERENCES buckets(id),
        amount             NUMERIC(14,2) NOT NULL,
        reason             TEXT,
        transaction_id     UUID REFERENCES transactions(id),
        related_bucket_id  UUID REFERENCES buckets(id),
        occurred_at        TIMESTAMPTZ NOT NULL,
        note               TEXT
    );
    CREATE INDEX idx_allocations_bucket ON allocations(bucket_id);

    """

    // MARK: - INSERT statements

    private func insert(account a: Account) -> String {
        let cols = "(id, name, type, real_balance, is_active, created_at)"
        let vals = [
            sqlUUID(a.id),
            sqlText(a.name),
            sqlText(a.typeRaw),
            sqlDecimal(a.realBalance),
            sqlBool(a.isActive),
            sqlTimestamp(a.createdAt),
        ].joined(separator: ", ")
        return "INSERT INTO accounts \(cols) VALUES (\(vals));\n"
    }

    private func insert(category c: Category) -> String {
        let cols = "(id, name, kind, icon, color)"
        let vals = [
            sqlUUID(c.id),
            sqlText(c.name),
            sqlText(c.kindRaw),
            sqlText(c.icon),
            sqlText(c.color),
        ].joined(separator: ", ")
        return "INSERT INTO categories \(cols) VALUES (\(vals));\n"
    }

    private func insert(bucket b: Bucket) -> String {
        let cols = "(id, name, kind, timeline, period_start, period_end, planned_amount, allocated_amount, rollover_unused, target_amount, target_date, linked_category_id, is_deleted, deleted_at, created_at)"
        let vals = [
            sqlUUID(b.id),
            sqlText(b.name),
            sqlText(b.kindRaw),
            sqlText(b.timelineRaw),
            sqlDate(b.periodStart),
            sqlDate(b.periodEnd),
            sqlDecimal(b.plannedAmount),
            sqlDecimal(b.allocatedAmount),
            sqlBool(b.rolloverUnused),
            sqlDecimal(b.targetAmount),
            sqlDate(b.targetDate),
            sqlUUID(b.linkedCategory?.id),
            sqlBool(b.isDeleted),
            sqlTimestamp(b.deletedAt),
            sqlTimestamp(b.createdAt),
        ].joined(separator: ", ")
        return "INSERT INTO buckets \(cols) VALUES (\(vals));\n"
    }

    private func insert(loan l: Loan) -> String {
        let cols = "(id, type, counterparty, principal, current_balance, interest_rate, start_date, due_date, status, notes)"
        let vals = [
            sqlUUID(l.id),
            sqlText(l.typeRaw),
            sqlText(l.counterparty),
            sqlDecimal(l.principal),
            sqlDecimal(l.currentBalance),
            sqlDecimal(l.interestRate),
            sqlDate(l.startDate),
            sqlDate(l.dueDate),
            sqlText(l.statusRaw),
            sqlText(l.notes),
        ].joined(separator: ", ")
        return "INSERT INTO loans \(cols) VALUES (\(vals));\n"
    }

    private func insert(transaction t: Transaction) -> String {
        let cols = "(id, account_id, amount, direction, category_id, bucket_id, loan_id, occurred_at, raw_input, raw_fragment, is_voided, created_at, modified_at)"
        let vals = [
            sqlUUID(t.id),
            sqlUUID(t.account?.id),
            sqlDecimal(t.amount),
            sqlText(t.directionRaw),
            sqlUUID(t.category?.id),
            sqlUUID(t.bucket?.id),
            sqlUUID(t.loan?.id),
            sqlTimestamp(t.occurredAt),
            sqlText(t.rawInput),
            sqlText(t.rawFragment),
            sqlBool(t.isVoided),
            sqlTimestamp(t.createdAt),
            sqlTimestamp(t.modifiedAt),
        ].joined(separator: ", ")
        return "INSERT INTO transactions \(cols) VALUES (\(vals));\n"
    }

    private func insert(allocation a: Allocation) -> String {
        let cols = "(id, bucket_id, amount, reason, transaction_id, related_bucket_id, occurred_at, note)"
        let vals = [
            sqlUUID(a.id),
            sqlUUID(a.bucket?.id),
            sqlDecimal(a.amount),
            sqlText(a.reasonRaw),
            sqlUUID(a.transaction?.id),
            sqlUUID(a.relatedBucket?.id),
            sqlTimestamp(a.occurredAt),
            sqlText(a.note),
        ].joined(separator: ", ")
        return "INSERT INTO allocations \(cols) VALUES (\(vals));\n"
    }

    // MARK: - SQL value formatting

    private func sqlText(_ value: String?) -> String {
        guard let value else { return "NULL" }
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }

    private func sqlUUID(_ value: UUID?) -> String {
        guard let value else { return "NULL" }
        return "'\(value.uuidString.lowercased())'"
    }

    private func sqlDecimal(_ value: Decimal?) -> String {
        guard let value else { return "NULL" }
        return "\(value)"
    }

    private func sqlBool(_ value: Bool) -> String {
        value ? "TRUE" : "FALSE"
    }

    private func sqlTimestamp(_ value: Date?) -> String {
        guard let value else { return "NULL" }
        return "'\(Self.iso8601(value))'::timestamptz"
    }

    private func sqlDate(_ value: Date?) -> String {
        guard let value else { return "NULL" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return "'\(f.string(from: value))'::date"
    }

    private static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

// MARK: - FileDocument for the SwiftUI .fileExporter

struct SQLExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.text, .data] }
    static var writableContentTypes: [UTType] { [.text, .data] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            self.content = s
        } else {
            self.content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

