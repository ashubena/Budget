import Foundation
import SwiftData

/// Single source of truth for the SwiftData schema.
/// Used by both `BudgetApp` (the SwiftUI entry point) and `LogExpenseIntent`
/// (the App Intent that runs from Siri / Shortcuts) so they hit the same
/// underlying store.
enum BudgetSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self,
        Category.self,
        CategoryKeyword.self,
        CategoryAlias.self,
        Tag.self,
        Transaction.self,
        TransactionAudit.self,
        Bucket.self,
        Allocation.self,
        BucketPeriod.self,
        Plan.self,
        PlanInstance.self,
        Loan.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
