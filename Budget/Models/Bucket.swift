import Foundation
import SwiftData

@Model
final class Bucket {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = BucketKind.spendingPlan.rawValue
    var timelineRaw: String = BucketTimeline.monthly.rawValue
    var periodStart: Date?
    var periodEnd: Date?
    var plannedAmount: Decimal?
    var allocatedAmount: Decimal = Decimal(0)
    var rolloverUnused: Bool = false
    var targetAmount: Decimal?
    var targetDate: Date?
    var displayOrder: Int = 0
    var isDeleted: Bool = false
    var deletedAt: Date?
    var createdAt: Date = Date()

    var linkedCategory: Category?
    var parentBucket: Bucket?

    @Relationship(deleteRule: .nullify, inverse: \Bucket.parentBucket)
    var childBuckets: [Bucket]? = []

    @Relationship(deleteRule: .cascade, inverse: \Allocation.bucket)
    var allocations: [Allocation]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.bucket)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \BucketPeriod.bucket)
    var periods: [BucketPeriod]? = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: BucketKind,
        timeline: BucketTimeline = .monthly,
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        plannedAmount: Decimal? = nil,
        allocatedAmount: Decimal = 0,
        rolloverUnused: Bool = false,
        targetAmount: Decimal? = nil,
        targetDate: Date? = nil,
        linkedCategory: Category? = nil,
        parentBucket: Bucket? = nil,
        displayOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.timelineRaw = timeline.rawValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.plannedAmount = plannedAmount
        self.allocatedAmount = allocatedAmount
        self.rolloverUnused = rolloverUnused
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.linkedCategory = linkedCategory
        self.parentBucket = parentBucket
        self.displayOrder = displayOrder
        self.isDeleted = false
        self.createdAt = Date()
    }

    var kind: BucketKind {
        get { BucketKind(rawValue: kindRaw) ?? .spendingPlan }
        set { kindRaw = newValue.rawValue }
    }

    var timeline: BucketTimeline {
        get { BucketTimeline(rawValue: timelineRaw) ?? .monthly }
        set { timelineRaw = newValue.rawValue }
    }

    /// Computed status color per the design doc:
    /// red = overspent (allocated < 0), yellow = over plan but still positive, green = healthy.
    var statusColor: BucketStatusColor {
        if allocatedAmount < 0 { return .red }
        if let planned = plannedAmount, allocatedAmount > planned { return .yellow }
        return .green
    }
}
