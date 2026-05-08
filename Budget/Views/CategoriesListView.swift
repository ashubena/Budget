import SwiftUI
import SwiftData

/// Standalone list of all categories, grouped by kind. Pushed from
/// Settings → Manage categories. Tap a row to edit, swipe to delete.
/// Splitting this out keeps SettingsView short enough that the parent Form
/// scrolls cleanly even with many categories.
struct CategoriesListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.name) private var categories: [Category]

    @State private var pendingDelete: Category? = nil
    @State private var showingAddSheet = false

    private var expenseCategories: [Category] {
        categories.filter { $0.kind == .expense }
    }
    private var incomeCategories: [Category] {
        categories.filter { $0.kind == .income }
    }

    var body: some View {
        listContent
            .navigationTitle("Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAddSheet) {
                AddCategorySheet()
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: deleteBinding,
                titleVisibility: .visible,
                actions: { deleteActions },
                message: { Text(deleteMessage) }
            )
    }

    // MARK: - Sub-views

    private var listContent: some View {
        List {
            Section("Expense") {
                ForEach(expenseCategories) { cat in
                    row(for: cat)
                }
                .onDelete(perform: requestDeleteExpense)
            }

            Section("Income") {
                ForEach(incomeCategories) { cat in
                    row(for: cat)
                }
                .onDelete(perform: requestDeleteIncome)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Category", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var deleteActions: some View {
        Button("Delete", role: .destructive) { performDelete() }
        Button("Cancel", role: .cancel) { pendingDelete = nil }
    }

    private func row(for cat: Category) -> some View {
        NavigationLink {
            CategoryEditView(category: cat)
        } label: {
            HStack {
                Image(systemName: cat.kind == .income ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(cat.kind == .income ? Color.green : Color.secondary)
                Text(cat.name)
                Spacer()
                Text("\((cat.transactions ?? []).count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Delete state plumbing

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteTitle: String {
        guard let cat = pendingDelete else { return "" }
        return "Delete \(cat.name)?"
    }

    private var deleteMessage: String {
        guard let cat = pendingDelete else { return "" }
        let txnCount = (cat.transactions ?? []).count
        let kwCount = (cat.keywords ?? []).count
        let aliasCount = (cat.aliases ?? []).count
        var lines: [String] = []
        if txnCount > 0 {
            lines.append("\(txnCount) transaction\(txnCount == 1 ? "" : "s") will become uncategorized.")
        }
        if kwCount > 0 {
            lines.append("\(kwCount) keyword\(kwCount == 1 ? "" : "s") will be removed.")
        }
        if aliasCount > 0 {
            lines.append("\(aliasCount) learned alias\(aliasCount == 1 ? "" : "es") will be removed.")
        }
        if lines.isEmpty { return "This can't be undone." }
        return lines.joined(separator: "\n") + "\nThis can't be undone."
    }

    // MARK: - Delete actions

    private func requestDeleteExpense(_ offsets: IndexSet) {
        if let idx = offsets.first { pendingDelete = expenseCategories[idx] }
    }

    private func requestDeleteIncome(_ offsets: IndexSet) {
        if let idx = offsets.first { pendingDelete = incomeCategories[idx] }
    }

    private func performDelete() {
        guard let cat = pendingDelete else { return }
        context.delete(cat)
        try? context.save()
        pendingDelete = nil
    }
}

// MARK: - Add Category sheet

struct AddCategorySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: CategoryKind = .expense
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Subscriptions", text: $name)
                }
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        Text("Expense").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 360)
        #endif
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let existing = try context.fetch(FetchDescriptor<Category>())
            if existing.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
                error = "A category named \"\(trimmed)\" already exists."
                return
            }
            context.insert(Category(name: trimmed, kind: kind))
            try context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
