//
//  ContentView.swift
//  Budget
//
//  Created by Ayesha Zulfiqar on 01/05/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            }

            NavigationStack {
                BucketsView()
            }
            .tabItem {
                Label("Plan", systemImage: "rectangle.grid.2x2.fill")
            }

            NavigationStack {
                GoalsView()
            }
            .tabItem {
                Label("Goals", systemImage: "target")
            }

            NavigationStack {
                ReportsView()
            }
            .tabItem {
                Label("Reports", systemImage: "chart.pie.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
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
