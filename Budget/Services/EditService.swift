import Foundation
import SwiftData

@MainActor
struct EditService {
    let context: ModelContext

    enum EditError: Error, LocalizedError {
        case noTransactions
        case alreadyVoided

        var errorDescription: String? {
            switch self {
            case .noTransactions: return "No transactions yet."
            case .alreadyVoided:  return "That transaction is already voided."
            }
        }
    }

    func mostRecent() throws -> Transaction? {
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { !$0.isVoided },
            sortBy: [SortDescriptor(\Transaction.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func voidMostRecent() throws -> Transaction {
        guard let txn = try mostRecent() else { throw EditError.noTransactions }
        try void(txn)
        return txn
    }

    func void(_ txn: Transaction) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }

        if let account = txn.account {
            switch txn.direction {
            case .outflow: account.realBalance += txn.amount
            case .inflow:  account.realBalance -= txn.amount
            }
        }

        if let loan = txn.loan {
            switch txn.direction {
            case .outflow:
                if loan.type == .givenOut {
                    loan.currentBalance -= txn.amount
                    loan.principal -= txn.amount
                } else {
                    loan.currentBalance += txn.amount
                }
            case .inflow:
                if loan.type == .taken {
                    loan.currentBalance -= txn.amount
                    loan.principal -= txn.amount
                } else {
                    loan.currentBalance += txn.amount
                }
            }
            loan.status = (loan.currentBalance == 0) ? .paid : .active
        }

        txn.isVoided = true
        txn.modifiedAt = Date()

        context.insert(TransactionAudit(
            transaction: txn,
            changeType: .void,
            fieldChanged: "isVoided",
            oldValue: "false",
            newValue: "true"
        ))

        try context.save()
    }

    func updateCategory(of txn: Transaction, to newCategory: Category?, reason: String? = nil) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }
        if txn.category?.id == newCategory?.id { return }

        let oldName = txn.category?.name ?? "(uncategorized)"
        let newName = newCategory?.name ?? "(uncategorized)"

        txn.category = newCategory
        txn.needsCategory = (newCategory == nil)

        context.insert(TransactionAudit(
            transaction: txn,
            changeType: .edit,
            fieldChanged: "category",
            oldValue: oldName,
            newValue: newName,
            reason: reason
        ))
        txn.modifiedAt = Date()

        try context.save()
    }

    func updateAmount(of txn: Transaction, to newAmount: Decimal, reason: String? = nil) throws {
        guard !txn.isVoided else { throw EditError.alreadyVoided }

        let oldAmount = txn.amount
        let delta = newAmount - oldAmount

        if let account = txn.account {
            switch txn.direction {
            case .outflow: account.realBalance -= delta
            case .inflow:  account.realBalance += delta
            }
        }

        context.insert(TransactionAudit(
            transaction: txn,
            changeType: .edit,
            fieldChanged: "amount",
            oldValue: "\(oldAmount)",
            newValue: "\(newAmount)",
            reason: reason
        ))

        txn.amount = newAmount
        txn.modifiedAt = Date()

        try context.save()
    }
}
