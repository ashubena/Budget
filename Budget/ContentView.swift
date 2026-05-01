//
//  ContentView.swift
//  Budget
//
//  Created by Ayesha Zulfiqar on 01/05/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query private var buckets: [Bucket]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Budget")
                    .font(.largeTitle.bold())
                Text("Schema online.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Accounts: \(accounts.count)")
                    Text("Transactions: \(transactions.count)")
                    Text("Buckets: \(buckets.count)")
                }
                .font(.callout.monospaced())
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding()
            .navigationTitle("Budget")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
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
        ], inMemory: true)
}
