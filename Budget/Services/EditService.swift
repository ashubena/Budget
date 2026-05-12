import Foundation
import SwiftData

/// Edits and voids on existing transactions.
/// Per design: 7-day window for full edits; older requires a corrective entry.
/// All changes write a TransactionAudit row.
@MainActor
struct EditService {
    let context: ModelContext

    static let editWindow: TimeInterval = 7 * 24 * 60 * 60   // 7 days

    enum EditError: Error, LocalizedError {
        case noTransactions
        case lockedByWindow(daysOld: Int)
        case alreadyVoided

        var errorDescription: String? {
            switch self {
            case .noTransactions:
                return "No transactions yet."
            case .lockedByWindow(let days):
                return "That's locked (\(days) days old, window is 7). Add a corrective entry instead."
            case .alreadyVoided:
                return "That transaction is already voided."
            }
        }
    }

    /// Finds the most recent non-voided transaction.
    func mostRecent() throws -> Transaction? {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { !$0.isVoided },
            sortBy: [SortDescriptor(\Transaction.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Voids the most recent non-voided transaction. Reverses balance + bucket
    /// allocation, logs an audit row.
    func voidMostRecent() throws -> Transaction {
        guard let txn = try mostRecent() else { throw EditError.noTransactions }
        try void(txn)
        return txn
    }

    /// Voids a specific transaction. Reverses real balance and any bucket
    /// allocation tied to it, logs audit. Honors the 7-day edit window.
    func void(_ txn: Transaction) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }
        let age = Date().timeIntervalSince(txn.occurredAt)
        if age > Self.editWindow {
            throw EditError.lockedByWindow(daysOld: Int(age / 86_400))
        }

        // Reverse account balance.
        if let account = txn.account {
            switch txn.direction {
            case .outflow: account.realBalance += txn.amount
            case .inflow:  account.realBalance -= txn.amount
            }
        }

        // Reverse loan tracking.
        if let loan = txn.loan {
            // Loan balance: was incremented for loan_out/in, decremented for repayments.
            // Just invert what the original transaction did.
            // Note: this is best-effort; complex loan histories may need manual correction.
            switch txn.direction {
            case .outflow:
                // could be: loan_out (increased loan balance) or loan_payment_out (decreased)
                // For loan_out, the transaction was money going out and loan getting bigger.
                if loan.type == .givenOut {
                    loan.currentBalance -= txn.amount
                    loan.principal -= txn.amount
                } else {
                    // Was a "I paid them back" — reversing means I owe more again.
                    loan.currentBalance += txn.amount
                }
            case .inflow:
                if loan.type == .taken {
                    // Reversing a "borrowed from them" event
                    loan.currentBalance -= txn.amount
                    loan.principal -= txn.amount
                } else {
                    // Reversing a "they paid me back" — they owe me more again
                    loan.currentBalance += txn.amount
                }
            }
            loan.status = (loan.currentBalance == 0) ? .paid : .active
        }

        // No bucket-allocation reversal: bucket spent is now derived from
        // (non-voided) transactions in BucketCard's @Query. Marking the
        // transaction voided automatically excludes it from those queries.

        // Mark voided + audit.
        txn.isVoided = true
        txn.modifiedAt = Date()

        let audit = TransactionAudit(
            transaction: txn,
            changeType: .void,
            fieldChanged: "isVoided",
            oldValue: "false",
            newValue: "true"
        )
        context.insert(audit)

        try context.save()
    }

    /// Reassign a transaction to a different category (within window).
    /// Reverses the old bucket allocation (if any) and creates a new one
    /// for the new category's bucket (if any). Logs an audit row.
    func updateCategory(of txn: Transaction, to newCategory: Category?, reason: String? = nil) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }
        let age = Date().timeIntervalSince(txn.occurredAt)
        if age > Self.editWindow {
            throw EditError.lockedByWindow(daysOld: Int(age / 86_400))
        }

        let oldName = txn.category?.name ?? "(uncategorized)"
        let newName = newCategory?.name ?? "(uncategorized)"
        if txn.category?.id == newCategory?.id { return }

        // No bucket re-allocation: bucket spent is derived from
        // (non-voided) transactions matching the bucket's linkedCategory
        // in the current period. Reassigning the transaction's category
        // automatically moves it between bucket queries on next render.
        txn.category = newCategory
        txn.needsCategory = (newCategory == nil)

        let audit = TransactionAudit(
            transaction: txn,
            changeType: .edit,
            fieldChanged: "category",
            oldValue: oldName,
            newValue: newName,
            reason: reason
        )
        context.insert(audit)
        txn.modifiedAt = Date()

        try context.save()
    }

    /// Update the amount of an existing transaction (within window).
    /// Reverses the difference on account balance + bucket allocation.
    func updateAmount(of txn: Transaction, to newAmount: Decimal, reason: String? = nil) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }
        let age = Date().timeIntervalSince(txn.occurredAt)
        if age > Self.editWindow {
            throw EditError.lockedByWindow(daysOld: Int(age / 86_400))
        }

        let oldAmount = txn.amount
        let delta = newAmount - oldAmount   // positive means amount went up

        // Adjust account balance — outflow grows when amount grows; inflow grows too but inverse sign.
        if let account = txn.account {
            switch txn.direction {
            case .outflow: account.realBalance -= delta   // larger expense = lower balance
            case .inflow:  account.realBalance += delta
            }
        }

        // No bucket-allocation adjustment: bucket spent is derived from
        // the transaction's (now-updated) amount on next render of
        // BucketCard's @Query.

        let audit = TransactionAudit(
            transaction: txn,
            changeType: .edit,
            fieldChanged: "amount",
            oldValue: "\(oldAmount)",
            newValue: "\(newAmount)",
            reason: reason
        )
        context.insert(audit)

        txn.amount = newAmount
        txn.modifiedAt = Date()

        try context.save()
    }
}
