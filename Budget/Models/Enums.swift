import Foundation

enum Direction: String, Codable, CaseIterable {
    case inflow
    case outflow
}

enum AccountType: String, Codable, CaseIterable {
    case checking
    case cash
    case savings
    case credit
}

enum CategoryKind: String, Codable, CaseIterable {
    case expense
    case income
}

enum AliasSource: String, Codable, CaseIterable {
    case `default`
    case learned
}

enum InputMethod: String, Codable, CaseIterable {
    case text
    case voice
}

enum ChangeType: String, Codable, CaseIterable {
    case create
    case edit
    case void
}

enum BucketKind: String, Codable, CaseIterable {
    case spendingPlan
    case savingsGoal
    case reserve
}

enum BucketTimeline: String, Codable, CaseIterable {
    case weekly
    case monthly
    case yearly
    case custom
}

enum AllocationReason: String, Codable, CaseIterable {
    case transaction
    case rollover
    case manualMove
    case planReset
    case editCorrection
}

enum PlanFrequency: String, Codable, CaseIterable {
    case weekly
    case monthly
    case yearly
}

enum PlanMode: String, Codable, CaseIterable {
    case autoCreate
    case expectation
}

enum PlanInstanceStatus: String, Codable, CaseIterable {
    case pending
    case fulfilled
    case skipped
    case overdue
}

enum LoanType: String, Codable, CaseIterable {
    case givenOut
    case taken
}

enum LoanStatus: String, Codable, CaseIterable {
    case active
    case paid
    case partial
    case overdue
}

enum BucketStatusColor: String, Codable, CaseIterable {
    case green
    case yellow
    case red
}
