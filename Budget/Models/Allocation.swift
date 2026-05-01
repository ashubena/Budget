import Foundation
import SwiftData

@Model
final class Allocation {
    var id: UUID = UUID()
    var bucket: Bucket?
    var amount: Decimal = Decimal(0)
    var reasonRaw: String = AllocationReason.manualMove.rawValue
    var transaction: Transaction?
    var relatedBucket: Bucket?
    var occurredAt: Date = Date()
    var note: String?

    init(
        id: UUID = UUID(),
        bucket: Bucket?,
        amount: Decimal,
        reason: AllocationReason,
        transaction: Transaction? = nil,
        relatedBucket: Bucket? = nil,
        occurredAt: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.bucket = bucket
        self.amount = amount
        self.reasonRaw = reason.rawValue
        self.transaction = transaction
        self.relatedBucket = relatedBucket
        self.occurredAt = occurredAt
        self.note = note
    }

    var reason: AllocationReason {
        get { AllocationReason(rawValue: reasonRaw) ?? .manualMove }
        set { reasonRaw = newValue.rawValue }
    }
}

@Model
final class BucketPeriod {
    var id: UUID = UUID()
    var bucket: Bucket?
    var periodStart: Date?
    var periodEnd: Date?
    var planned: Decimal?
    var spent: Decimal = Decimal(0)
    var rolledOver: Decimal = Decimal(0)
    var closedAt: Date?

    init(
        id: UUID = UUID(),
        bucket: Bucket?,
        periodStart: Date?,
        periodEnd: Date?,
        planned: Decimal? = nil,
        spent: Decimal = 0,
        rolledOver: Decimal = 0,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.bucket = bucket
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.planned = planned
        self.spent = spent
        self.rolledOver = rolledOver
        self.closedAt = closedAt
    }
}
