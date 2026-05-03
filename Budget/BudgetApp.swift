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
        do {
            return try BudgetSchema.makeContainer()
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
