import Foundation
import SwiftData

@Model
final class Transaction {
    var id: UUID = UUID()
    var account: Account?
    var amount: Decimal = Decimal(0)
    var directionRaw: String = Direction.outflow.rawValue
    var category: Category?
    var bucket: Bucket?
    var loan: Loan?
    var occurredAt: Date = Date()
    var note: String?
    var rawInput: String?
    var rawFragment: String?
    var needsCategory: Bool = false
    var inputMethodRaw: String?
    var isVoided: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var tags: [Tag]? = []

    @Relationship(deleteRule: .cascade, inverse: \TransactionAudit.transaction)
    var auditEntries: [TransactionAudit]? = []

    @Relationship(deleteRule: .cascade, inverse: \Allocation.transaction)
    var allocations: [Allocation]? = []

    init(
        id: UUID = UUID(),
        account: Account? = nil,
        amount: Decimal,
        direction: Direction,
        category: Category? = nil,
        bucket: Bucket? = nil,
        loan: Loan? = nil,
        occurredAt: Date = Date(),
        note: String? = nil,
        rawInput: String? = nil,
        rawFragment: String? = nil,
        needsCategory: Bool = false,
        inputMethod: InputMethod? = nil,
        isVoided: Bool = false
    ) {
        self.id = id
        self.account = account
        self.amount = amount
        self.directionRaw = direction.rawValue
        self.category = category
        self.bucket = bucket
        self.loan = loan
        self.occurredAt = occurredAt
        self.note = note
        self.rawInput = rawInput
        self.rawFragment = rawFragment
        self.needsCategory = needsCategory
        self.inputMethodRaw = inputMethod?.rawValue
        self.isVoided = isVoided
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .outflow }
        set { directionRaw = newValue.rawValue }
    }

    var inputMethod: InputMethod? {
        get { inputMethodRaw.flatMap(InputMethod.init(rawValue:)) }
        set { inputMethodRaw = newValue?.rawValue }
    }

    /// Signed amount based on direction. Outflow is negative, inflow positive.
    var signedAmount: Decimal {
        direction == .outflow ? -amount : amount
    }
}

@Model
final class TransactionAudit {
    var id: UUID = UUID()
    var transaction: Transaction?
    var changedAt: Date = Date()
    var changeTypeRaw: String = ChangeType.edit.rawValue
    var fieldChanged: String?
    var oldValue: String?
    var newValue: String?
    var reason: String?

    init(
        id: UUID = UUID(),
        transaction: Transaction?,
        changeType: ChangeType,
        fieldChanged: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.transaction = transaction
        self.changedAt = Date()
        self.changeTypeRaw = changeType.rawValue
        self.fieldChanged = fieldChanged
        self.oldValue = oldValue
        self.newValue = newValue
        self.reason = reason
    }

    var changeType: ChangeType {
        get { ChangeType(rawValue: changeTypeRaw) ?? .edit }
        set { changeTypeRaw = newValue.rawValue }
    }
}
