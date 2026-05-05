import SwiftUI
import SwiftData

/// Modal picker shown when the parser can't resolve the category fragment in
/// chat input. Replaces the older free-text reply flow — that was error-prone
/// (typing "gift" instead of "Gifts" created a duplicate).
///
/// Behavior: pick an existing category from a grouped list, or create a new
/// one inline. Either way, this both:
///   1. Patches the pending transaction's category
///   2. Records a learned `CategoryAlias` so the same fragment auto-routes
///      next time
struct CategoryPickerSheet: View {
    let unresolvedFragment: String
    let transactionID: UUID
    var onAssigned: ((Category) -> Void)? = nil
    var onSkipped: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.name) private var allCategories: [Category]

    @State private var showingCreateField = false
    @State private var newCategoryName = ""
    @State private var newCategoryKind: CategoryKind = .expense
    @State private var error: String? = nil

    private var expenseCategories: [Category] {
        allCategories.filter { $0.kind == .expense }
    }
    private var incomeCategories: [Category] {
        allCategories.filter { $0.kind == .income }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What is")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\"\(unresolvedFragment)\"")
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                if !expenseCategories.isEmpty {
                    Section("Expense") {
                        ForEach(expenseCategories) { cat in
                            categoryRow(cat)
                        }
                    }
                }

                if !incomeCategories.isEmpty {
                    Section("Income") {
                        ForEach(incomeCategories) { cat in
                            categoryRow(cat)
                        }
                    }
                }

                Section {
                    if showingCreateField {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("New category name", text: $newCategoryName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { createAndAssign() }
                            Picker("Kind", selection: $newCategoryKind) {
                                Text("Expense").tag(CategoryKind.expense)
                                Text("Income").tag(CategoryKind.income)
                            }
                            .pickerStyle(.segmented)
                            HStack {
                                Spacer()
                                Button("Cancel") {
                                    showingCreateField = false
                                    newCategoryName = ""
                                }
                                Button("Create & assign") { createAndAssign() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            showingCreateField = true
                            // Pre-fill with title-cased fragment as a friendly default.
                            if newCategoryName.isEmpty {
                                newCategoryName = unresolvedFragment.titleCased()
                            }
                        } label: {
                            Label("Create new category", systemImage: "plus.circle")
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pick a category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkipped?()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Row builder

    private func categoryRow(_ cat: Category) -> some View {
        Button {
            assign(cat)
        } label: {
            HStack {
                Image(systemName: cat.kind == .income ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(cat.kind == .income ? Color.green : Color.secondary)
                Text(cat.name)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func assign(_ cat: Category) {
        do {
            try patchTransactionAndLearnAlias(category: cat)
            onAssigned?(cat)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createAndAssign() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // If a category with this name already exists, reuse it.
        if let existing = allCategories.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            assign(existing)
            return
        }

        let newCat = Category(name: trimmed, kind: newCategoryKind)
        context.insert(newCat)
        do {
            try context.save()
            try patchTransactionAndLearnAlias(category: newCat)
            onAssigned?(newCat)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func patchTransactionAndLearnAlias(category: Category) throws {
        let txID = transactionID
        let txns = try context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == txID })
        )
        guard let txn = txns.first else {
            throw NSError(
                domain: "CategoryPicker", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Transaction not found."]
            )
        }
        txn.category = category
        txn.needsCategory = false

        let aliasFragment = unresolvedFragment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !aliasFragment.isEmpty {
            // Avoid duplicate aliases for the same string.
            let existingAliases = try context.fetch(FetchDescriptor<CategoryAlias>(
                predicate: #Predicate { $0.alias == aliasFragment }
            ))
            if let existing = existingAliases.first {
                existing.category = category
                existing.lastUsedAt = Date()
            } else {
                context.insert(CategoryAlias(
                    alias: aliasFragment,
                    category: category,
                    source: .learned
                ))
            }
        }

        try context.save()
    }
}

private extension String {
    /// "lunch with sara" → "Lunch With Sara"
    func titleCased() -> String {
        split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
