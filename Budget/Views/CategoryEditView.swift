import SwiftUI
import SwiftData

/// Edit view for a single Category — name, keywords, view aliases, delete.
/// Pushed from SettingsView when the user taps a category row.
struct CategoryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var category: Category

    @State private var draftName: String = ""
    @State private var draftKind: CategoryKind = .expense
    @State private var newKeywordText: String = ""
    @State private var showingDeleteConfirm = false
    @State private var error: String? = nil

    // Keep the originals so we can reset / detect dirty state
    @State private var originalName: String = ""
    @State private var originalKind: CategoryKind = .expense

    private var isDirty: Bool {
        draftName.trimmingCharacters(in: .whitespaces) != originalName
            || draftKind != originalKind
    }

    private var transactionCount: Int {
        (category.transactions ?? []).count
    }

    private var keywordsForThisCategory: [CategoryKeyword] {
        (category.keywords ?? []).sorted { $0.keyword < $1.keyword }
    }

    private var aliasesForThisCategory: [CategoryAlias] {
        (category.aliases ?? []).sorted { $0.alias < $1.alias }
    }

    var body: some View {
        Form {
            nameSection
            keywordsSection
            aliasesSection
            statsSection
            deleteSection

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(originalName.isEmpty ? "Category" : originalName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isDirty || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            draftName = category.name
            draftKind = category.kind
            originalName = category.name
            originalKind = category.kind
        }
        .confirmationDialog(
            "Delete \(originalName)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteWarningMessage)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name & kind") {
            TextField("Name", text: $draftName)
            Picker("Kind", selection: $draftKind) {
                Text("Expense").tag(CategoryKind.expense)
                Text("Income").tag(CategoryKind.income)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var keywordsSection: some View {
        Section {
            if keywordsForThisCategory.isEmpty {
                Text("No keywords. Add some so chat input like \"500 \(category.name.lowercased())\" routes here automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keywordsForThisCategory) { kw in
                    HStack {
                        Text(kw.keyword)
                        Spacer()
                        Image(systemName: kw.isStrong ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(kw.isStrong ? Color.yellow : Color.secondary)
                    }
                }
                .onDelete(perform: deleteKeywords)
            }

            HStack {
                TextField("Add keyword (lowercase)", text: $newKeywordText)
                    .onSubmit { addKeyword() }
                Button("Add") { addKeyword() }
                    .disabled(newKeywordText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Keywords")
        } footer: {
            Text("Strong keywords (★) override learned aliases. Add common words you use for this category, e.g. \"chai, biryani, lunch\" for Food.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var aliasesSection: some View {
        if !aliasesForThisCategory.isEmpty {
            Section {
                ForEach(aliasesForThisCategory) { a in
                    HStack {
                        Text(a.alias).font(.body)
                        Spacer()
                        Text("learned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteAliases)
            } header: {
                Text("Learned aliases")
            } footer: {
                Text("Words the app remembered when you taught it. Swipe to remove.")
                    .font(.caption)
            }
        }
    }

    private var statsSection: some View {
        Section("Usage") {
            LabeledContent("Transactions") {
                Text("\(transactionCount)")
                    .font(.body.monospacedDigit())
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete category", systemImage: "trash")
            }
        }
    }

    private var deleteWarningMessage: String {
        var lines: [String] = []
        if transactionCount > 0 {
            lines.append("\(transactionCount) transaction\(transactionCount == 1 ? "" : "s") will become uncategorized.")
        }
        let kwCount = keywordsForThisCategory.count
        if kwCount > 0 {
            lines.append("\(kwCount) keyword\(kwCount == 1 ? "" : "s") will be removed.")
        }
        let aliasCount = aliasesForThisCategory.count
        if aliasCount > 0 {
            lines.append("\(aliasCount) learned alias\(aliasCount == 1 ? "" : "es") will be removed.")
        }
        if lines.isEmpty {
            return "This can't be undone."
        }
        return lines.joined(separator: "\n") + "\nThis can't be undone."
    }

    // MARK: - Actions

    private func save() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        category.name = trimmed
        category.kindRaw = draftKind.rawValue
        do {
            try context.save()
            originalName = trimmed
            originalKind = draftKind
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addKeyword() {
        let trimmed = newKeywordText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }

        // Prevent duplicates (across all categories)
        do {
            let existing = try context.fetch(FetchDescriptor<CategoryKeyword>(
                predicate: #Predicate { $0.keyword == trimmed }
            ))
            if let dup = existing.first {
                if dup.category?.id == category.id {
                    self.error = "Already exists for this category."
                } else {
                    self.error = "\"\(trimmed)\" is already used by \(dup.category?.name ?? "another category")."
                }
                return
            }
            context.insert(CategoryKeyword(keyword: trimmed, category: category, isStrong: true))
            try context.save()
            newKeywordText = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteKeywords(at offsets: IndexSet) {
        let toRemove = offsets.map { keywordsForThisCategory[$0] }
        for kw in toRemove { context.delete(kw) }
        try? context.save()
    }

    private func deleteAliases(at offsets: IndexSet) {
        let toRemove = offsets.map { aliasesForThisCategory[$0] }
        for a in toRemove { context.delete(a) }
        try? context.save()
    }

    private func performDelete() {
        context.delete(category)
        do {
            try context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
