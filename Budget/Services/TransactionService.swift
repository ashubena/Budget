import Foundation
import SwiftData

/// Service that turns parsed input into actual SwiftData writes.
/// Owns the rules for category resolution, account-balance updates,
/// and loan tracking.
@MainActor
struct TransactionService {
    let context: ModelContext

    struct LogResult {
        let message: String
        let needsCategoryFollowUp: Bool
        let unresolvedFragment: String?
        let transactionID: UUID?
    }

    // MARK: - Public dispatch

    func log(_ result: ParseResult, occurredAt: Date = Date(), rawInput: String? = nil) throws -> LogResult {
        switch result {
        case .expense(let amount, let fragment):
            return try logExpense(amount: amount, fragment: fragment, raw: rawInput, occurredAt: occurredAt)
        case .income(let amount, let fragment):
            return try logIncome(amount: amount, fragment: fragment, raw: rawInput, occurredAt: occurredAt)
        case .loanOut(let counterparty, let amount):
            return try logLoanOut(counterparty: counterparty, amount: amount, raw: rawInput, occurredAt: occurredAt)
        case .loanIn(let counterparty, let amount):
            return try logLoanIn(counterparty: counterparty, amount: amount, raw: rawInput, occurredAt: occurredAt)
        case .loanPaymentIn(let counterparty, let amount):
            return try logLoanPayment(counterparty: counterparty, amount: amount, incoming: true, raw: rawInput, occurredAt: occurredAt)
        case .loanPaymentOut(let counterparty, let amount):
            return try logLoanPayment(counterparty: counterparty, amount: amount, incoming: false, raw: rawInput, occurredAt: occurredAt)
        case .voidLast:
            return try voidLastTransaction()
        }
    }

    private func voidLastTransaction() throws -> LogResult {
        let editor = EditService(context: context)
        do {
            let txn = try editor.voidMostRecent()
            let amountStr = Self.formatPKR(txn.amount)
            let categoryName = txn.category?.name ?? "—"
            let dateStr = txn.occurredAt.formatted(date: .abbreviated, time: .shortened)
            return LogResult(
                message: "Voided: \(amountStr) on \(categoryName) (\(dateStr)).\nBalance has been restored.",
                needsCategoryFollowUp: false,
                unresolvedFragment: nil,
                transactionID: txn.id
            )
        } catch let err as EditService.EditError {
            return LogResult(
                message: err.localizedDescription,
                needsCategoryFollowUp: false,
                unresolvedFragment: nil,
                transactionID: nil
            )
        }
    }

    // MARK: - Expense

    func logExpense(amount: Decimal, fragment: String, raw: String?, occurredAt: Date = Date()) throws -> LogResult {
        let account = try fetchOrCreateMainAccount()
        let category = try resolveCategory(fragment: fragment)

        let txn = Transaction(
            account: account,
            amount: amount,
            direction: .outflow,
            category: category,
            occurredAt: occurredAt,
            rawInput: raw,
            rawFragment: fragment.isEmpty ? nil : fragment,
            needsCategory: category == nil,
            inputMethod: .text
        )
        context.insert(txn)
        account.realBalance -= amount

        try context.save()

        let amountStr = Self.formatPKR(amount)
        let balanceStr = Self.formatPKR(account.realBalance)
        let message: String
        if let cat = category {
            let extra = (fragment.isEmpty || fragment == cat.name.lowercased()) ? "" : " (\(fragment))"
            // Bucket display is now derived in BucketCard's @Query; we
            // don't compute a per-bucket spent here because it would mean
            // an extra fetch per chat message. Just confirm the log.
            message = "Logged \(amountStr) on \(cat.name)\(extra).\nBalance: \(balanceStr)"
        } else {
            let frag = fragment.isEmpty ? "?" : "\"\(fragment)\""
            message = "Logged \(amountStr) — pick a category for \(frag)…"
        }

        return LogResult(
            message: message,
            needsCategoryFollowUp: category == nil,
            unresolvedFragment: category == nil ? fragment : nil,
            transactionID: txn.id
        )
    }

    // MARK: - Income

    func logIncome(amount: Decimal, fragment: String, raw: String? = nil, occurredAt: Date = Date()) throws -> LogResult {
        let account = try fetchOrCreateMainAccount()
        let category = try resolveCategory(fragment: fragment, prefer: .income)
            ?? (try? fetchCategory(named: "Salary"))

        let txn = Transaction(
            account: account,
            amount: amount,
            direction: .inflow,
            category: category,
            occurredAt: occurredAt,
            rawInput: raw,
            rawFragment: fragment.isEmpty ? nil : fragment,
            needsCategory: category == nil,
            inputMethod: .text
        )
        context.insert(txn)
        account.realBalance += amount

        try context.save()

        let amountStr = Self.formatPKR(amount)
        let balanceStr = Self.formatPKR(account.realBalance)
        let catName = category?.name ?? "Income"
        let message = "Logged \(amountStr) income on \(catName).\nBalance: \(balanceStr)"

        return LogResult(
            message: message,
            needsCategoryFollowUp: false,
            unresolvedFragment: nil,
            transactionID: txn.id
        )
    }

    // MARK: - Loans

    func logLoanOut(counterparty: String, amount: Decimal, raw: String? = nil, occurredAt: Date = Date()) throws -> LogResult {
        let account = try fetchOrCreateMainAccount()
        let loan = try fetchOrCreateLoan(counterparty: counterparty, type: .givenOut)
        let category = try? fetchCategory(named: "Loan Out")

        let txn = Transaction(
            account: account,
            amount: amount,
            direction: .outflow,
            category: category,
            loan: loan,
            occurredAt: occurredAt,
            rawInput: raw,
            inputMethod: .text
        )
        context.insert(txn)
        account.realBalance -= amount

        // Track on the loan record.
        let isNewLoan = (loan.principal == 0)
        if isNewLoan {
            loan.principal = amount
            loan.currentBalance = amount
            loan.startDate = Date()
        } else {
            loan.principal += amount
            loan.currentBalance += amount
        }
        loan.status = .active

        try context.save()

        let amountStr = Self.formatPKR(amount)
        let balanceStr = Self.formatPKR(account.realBalance)
        let outstanding = Self.formatPKR(loan.currentBalance)
        let message = "Lent \(amountStr) to \(counterparty).\nOutstanding: \(outstanding)\nBalance: \(balanceStr)"

        return LogResult(message: message, needsCategoryFollowUp: false, unresolvedFragment: nil, transactionID: txn.id)
    }

    func logLoanIn(counterparty: String, amount: Decimal, raw: String? = nil, occurredAt: Date = Date()) throws -> LogResult {
        let account = try fetchOrCreateMainAccount()
        let loan = try fetchOrCreateLoan(counterparty: counterparty, type: .taken)
        let category = try? fetchCategory(named: "Loan In")

        let txn = Transaction(
            account: account,
            amount: amount,
            direction: .inflow,
            category: category,
            loan: loan,
            occurredAt: occurredAt,
            rawInput: raw,
            inputMethod: .text
        )
        context.insert(txn)
        account.realBalance += amount

        let isNewLoan = (loan.principal == 0)
        if isNewLoan {
            loan.principal = amount
            loan.currentBalance = amount
            loan.startDate = Date()
        } else {
            loan.principal += amount
            loan.currentBalance += amount
        }
        loan.status = .active

        try context.save()

        let amountStr = Self.formatPKR(amount)
        let balanceStr = Self.formatPKR(account.realBalance)
        let owed = Self.formatPKR(loan.currentBalance)
        let message = "Borrowed \(amountStr) from \(counterparty).\nYou owe: \(owed)\nBalance: \(balanceStr)"

        return LogResult(message: message, needsCategoryFollowUp: false, unresolvedFragment: nil, transactionID: txn.id)
    }

    func logLoanPayment(counterparty: String, amount: Decimal, incoming: Bool, raw: String? = nil, occurredAt: Date = Date()) throws -> LogResult {
        let account = try fetchOrCreateMainAccount()
        let loanType: LoanType = incoming ? .givenOut : .taken
        let loan = try findLoan(counterparty: counterparty, type: loanType)

        let category = try? fetchCategory(named: "Loan Repayment")
        let direction: Direction = incoming ? .inflow : .outflow

        let txn = Transaction(
            account: account,
            amount: amount,
            direction: direction,
            category: category,
            loan: loan,
            occurredAt: occurredAt,
            rawInput: raw,
            inputMethod: .text
        )
        context.insert(txn)
        if incoming {
            account.realBalance += amount
        } else {
            account.realBalance -= amount
        }

        let priorBalance: Decimal
        if let loan {
            priorBalance = loan.currentBalance
            loan.currentBalance = max(0, loan.currentBalance - amount)
            loan.status = (loan.currentBalance == 0) ? .paid : .partial
        } else {
            priorBalance = 0
        }

        try context.save()

        let amountStr = Self.formatPKR(amount)
        let balanceStr = Self.formatPKR(account.realBalance)
        let verb = incoming ? "paid back" : "Paid back"
        let subject = incoming ? counterparty : counterparty
        let prefix = incoming ? "\(subject) \(verb)" : "\(verb) \(subject)"
        let suffix: String
        if let loan {
            suffix = "Remaining: \(Self.formatPKR(loan.currentBalance)) (was \(Self.formatPKR(priorBalance)))"
        } else {
            suffix = "(no matching loan found — recorded as standalone payment)"
        }
        let message = "\(prefix) \(amountStr).\n\(suffix)\nBalance: \(balanceStr)"

        return LogResult(message: message, needsCategoryFollowUp: false, unresolvedFragment: nil, transactionID: txn.id)
    }

    // MARK: - Lookups

    private func fetchOrCreateMainAccount() throws -> Account {
        let target = "Main"
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.name == target })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let new = Account(name: "Main", type: .checking)
        context.insert(new)
        return new
    }

    private func fetchCategory(named name: String) throws -> Category? {
        let target = name
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.name == target })
        return try context.fetch(descriptor).first
    }

    private func fetchOrCreateLoan(counterparty: String, type: LoanType) throws -> Loan {
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<Loan>(predicate: #Predicate {
            $0.counterparty == counterparty && $0.typeRaw == typeRaw && $0.statusRaw != "paid"
        })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let new = Loan(type: type, counterparty: counterparty, principal: 0)
        context.insert(new)
        return new
    }

    private func findLoan(counterparty: String, type: LoanType) throws -> Loan? {
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<Loan>(predicate: #Predicate {
            $0.counterparty == counterparty && $0.typeRaw == typeRaw && $0.statusRaw != "paid"
        })
        return try context.fetch(descriptor).first
    }

    // MARK: - Category resolution

    /// Look up a category by:
    ///   1. Whole-fragment exact match in keywords (strong)
    ///   2. Whole-fragment exact match in learned aliases
    ///   3. Token-by-token: each word against keywords/aliases
    /// If `prefer` is set, prefer categories of that kind.
    private func resolveCategory(fragment: String, prefer kind: CategoryKind? = nil) throws -> Category? {
        let normalized = fragment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let cat = try lookupExact(normalized, prefer: kind) { return cat }

        for token in normalized.split(separator: " ").map(String.init) where token != normalized {
            if let cat = try lookupExact(token, prefer: kind) { return cat }
        }

        return nil
    }

    private func lookupExact(_ phrase: String, prefer kind: CategoryKind?) throws -> Category? {
        let target = phrase
        let kwDescriptor = FetchDescriptor<CategoryKeyword>(
            predicate: #Predicate { $0.keyword == target }
        )
        let kwMatches = try context.fetch(kwDescriptor).compactMap { $0.category }
        if let preferred = kind, let cat = kwMatches.first(where: { $0.kindRaw == preferred.rawValue }) {
            return cat
        }
        if let cat = kwMatches.first { return cat }

        let aliasDescriptor = FetchDescriptor<CategoryAlias>(
            predicate: #Predicate { $0.alias == target }
        )
        let aliasMatches = try context.fetch(aliasDescriptor)
        if let preferred = kind,
           let alias = aliasMatches.first(where: { $0.category?.kindRaw == preferred.rawValue }) {
            alias.lastUsedAt = Date()
            return alias.category
        }
        if let alias = aliasMatches.first {
            alias.lastUsedAt = Date()
            return alias.category
        }

        return nil
    }

    // MARK: - Formatting

    static func formatPKR(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        let n = amount as NSDecimalNumber
        let s = nf.string(from: n) ?? "\(amount)"
        return "\(s) PKR"
    }
}
