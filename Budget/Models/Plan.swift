import Foundation
import SwiftData

@Model
final class Plan {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Decimal?
    var directionRaw: String = Direction.outflow.rawValue
    var category: Category?
    var bucket: Bucket?
    var frequencyRaw: String = PlanFrequency.monthly.rawValue
    var nextDueDate: Date = Date()
    var modeRaw: String = PlanMode.expectation.rawValue
    var isActive: Bool = true
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PlanInstance.plan)
    var instances: [PlanInstance]? = []

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal? = nil,
        direction: Direction = .outflow,
        category: Category? = nil,
        bucket: Bucket? = nil,
        frequency: PlanFrequency = .monthly,
        nextDueDate: Date,
        mode: PlanMode = .expectation,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.directionRaw = direction.rawValue
        self.category = category
        self.bucket = bucket
        self.frequencyRaw = frequency.rawValue
        self.nextDueDate = nextDueDate
        self.modeRaw = mode.rawValue
        self.isActive = isActive
        self.createdAt = Date()
    }

    var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .outflow }
        set { directionRaw = newValue.rawValue }
    }

    var frequency: PlanFrequency {
        get { PlanFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var mode: PlanMode {
        get { PlanMode(rawValue: modeRaw) ?? .expectation }
        set { modeRaw = newValue.rawValue }
    }
}

@Model
final class PlanInstance {
    var id: UUID = UUID()
    var plan: Plan?
    var dueDate: Date?
    var expectedAmount: Decimal?
    var statusRaw: String = PlanInstanceStatus.pending.rawValue
    var transaction: Transaction?
    var actualAmount: Decimal?
    var variance: Decimal?

    init(
        id: UUID = UUID(),
        plan: Plan?,
        dueDate: Date?,
        expectedAmount: Decimal? = nil,
        status: PlanInstanceStatus = .pending,
        transaction: Transaction? = nil,
        actualAmount: Decimal? = nil,
        variance: Decimal? = nil
    ) {
        self.id = id
        self.plan = plan
        self.dueDate = dueDate
        self.expectedAmount = expectedAmount
        self.statusRaw = status.rawValue
        self.transaction = transaction
        self.actualAmount = actualAmount
        self.variance = variance
    }

    var status: PlanInstanceStatus {
        get { PlanInstanceStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
