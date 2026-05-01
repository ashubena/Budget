//
//  BudgetApp.swift
//  Budget
//
//  Created by Ayesha Zulfiqar on 01/05/2026.
//

import SwiftUI
import SwiftData

@main
struct BudgetApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
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
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
