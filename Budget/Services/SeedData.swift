import Foundation
import SwiftData

/// First-launch seed data. Idempotent — safe to call on every launch.
/// Creates the default "Main" account and a baseline set of categories
/// with strong keywords so the parser has something to match against.
@MainActor
enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        do {
            try seedAccountIfNeeded(context: context)
            try seedCategoriesIfNeeded(context: context)
            try context.save()
        } catch {
            print("[SeedData] error: \(error)")
        }
    }

    // MARK: - Account

    private static func seedAccountIfNeeded(context: ModelContext) throws {
        let target = "Main"
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.name == target })
        if try context.fetchCount(descriptor) == 0 {
            context.insert(Account(name: "Main", type: .checking))
        }
    }

    // MARK: - Categories + keywords

    /// Default categories and the strong keywords that route to them.
    /// Keywords are case-insensitive; stored lowercased.
    private static let categoryDefaults: [CategorySeed] = [
        // ─── Expenses ───
        .init(name: "Food", kind: .expense, keywords: [
            "food", "lunch", "dinner", "breakfast", "snack",
            "chai", "biryani", "naan", "tea", "coffee",
        ]),
        .init(name: "Groceries", kind: .expense, keywords: [
            "groceries", "grocery",
        ]),
        .init(name: "Rent", kind: .expense, keywords: [
            "rent",
        ]),
        .init(name: "Transport", kind: .expense, keywords: [
            "transport", "uber", "careem", "petrol", "fuel",
            "rickshaw", "bus", "taxi",
        ]),
        .init(name: "Utilities", kind: .expense, keywords: [
            "utilities", "electricity", "k-electric", "kelectric",
            "internet", "wifi", "bill",
        ]),
        .init(name: "Clothes", kind: .expense, keywords: [
            "clothes", "clothing", "shirt", "shoes",
        ]),
        .init(name: "Entertainment", kind: .expense, keywords: [
            "entertainment", "movie", "netflix", "spotify",
        ]),
        .init(name: "Health", kind: .expense, keywords: [
            "health", "doctor", "medicine", "pharmacy",
        ]),
        .init(name: "Gifts", kind: .expense, keywords: [
            "gift", "gifts",
        ]),
        .init(name: "Loan Out", kind: .expense, keywords: []),
        .init(name: "Loan Repayment", kind: .expense, keywords: []),

        // ─── Inflows tied to loans ───
        .init(name: "Loan In", kind: .income, keywords: []),
        .init(name: "Correction", kind: .expense, keywords: []),
        .init(name: "Misc", kind: .expense, keywords: [
            "misc", "miscellaneous", "other",
        ]),

        // ─── Income ───
        .init(name: "Salary", kind: .income, keywords: [
            "salary",
        ]),
        .init(name: "Freelance", kind: .income, keywords: [
            "freelance",
        ]),
        .init(name: "Refund", kind: .income, keywords: [
            "refund",
        ]),
        .init(name: "Other Income", kind: .income, keywords: []),
    ]

    private static func seedCategoriesIfNeeded(context: ModelContext) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<Category>())
        guard existingCount == 0 else { return }

        for seed in categoryDefaults {
            let cat = Category(name: seed.name, kind: seed.kind)
            context.insert(cat)
            for kw in seed.keywords {
                context.insert(CategoryKeyword(keyword: kw, category: cat, isStrong: true))
            }
        }
    }

    private struct CategorySeed {
        let name: String
        let kind: CategoryKind
        let keywords: [String]
    }
}
