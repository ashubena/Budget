import SwiftUI
import SwiftData

/// Edit sheet for an existing bucket. Lets the user rename, change kind,
/// adjust the planned amount/timeline/rollover, change the auto-link
/// category, or delete the bucket entirely (soft-delete via BucketService).
///
/// Allocations made against the bucket are preserved on delete (the row
/// stays in the DB, just hidden) — consistent with the soft-delete pattern
/// used elsewhere.
struct EditBucketSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var bucket: Bucket

    @State private var draftName: String = ""
    @State private var draftKind: BucketKind = .spendingPlan
    @State private var draftPlannedText: String = ""
    @State private var draftTimeline: BucketTimeline = .monthly
    @State private var draftRollover: Bool = false
    @State private var draftLinkedCategoryID: UUID? = nil
    @State private var showingDeleteConfirm = false
    @State private var error: String? = nil

    @Query(
        filter: #Predicate<Category> { $0.kindRaw == "expense" },
        sort: \Category.name
    )
    private var expenseCategories: [Category]

    private var isDirty: Bool {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if trimmed != bucket.name { return true }
        if draftKind != bucket.kind { return true }
        if draftTimeline != bucket.timeline { return true }
        if draftRollover != bucket.rolloverUnused { return true }
        if draftLinkedCategoryID != bucket.linkedCategory?.id { return true }
        let parsedPlanned = Parser.parseAmountToken(
            draftPlannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if parsedPlanned != bucket.plannedAmount { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $draftName)
                }

                Section("Type") {
                    Picker("Kind", selection: $draftKind) {
                        Text("Spending plan").tag(BucketKind.spendingPlan)
                        Text("Reserve").tag(BucketKind.reserve)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Plan") {
                    TextField("Planned amount (optional)", text: $draftPlannedText)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    Picker("Resets", selection: $draftTimeline) {
                        Text("Weekly").tag(BucketTimeline.weekly)
                        Text("Monthly").tag(BucketTimeline.monthly)
                        Text("Yearly").tag(BucketTimeline.yearly)
                    }
                    Toggle("Roll over unused", isOn: $draftRollover)
                }

                Section {
                    Picker("Auto-link category", selection: $draftLinkedCategoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(expenseCategories) { cat in
                            Text(cat.name).tag(Optional(cat.id))
                        }
                    }
                } header: {
                    Text("Auto-link")
                } footer: {
                    Text("Transactions in this category will be auto-deducted from this bucket.")
                }

                Section("Status") {
                    LabeledContent("Currently allocated",
                                   value: TransactionService.formatPKR(bucket.allocatedAmount))
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete bucket", systemImage: "trash")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(bucket.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isDirty || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(
                "Delete \(bucket.name)?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    softDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allocation history is kept. The bucket itself disappears from the Plan canvas.")
            }
            .onAppear { loadDraft() }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 560)
        #endif
    }

    // MARK: - Actions

    private func loadDraft() {
        draftName = bucket.name
        draftKind = bucket.kind
        if let p = bucket.plannedAmount {
            draftPlannedText = "\(p)"
        } else {
            draftPlannedText = ""
        }
        draftTimeline = bucket.timeline
        draftRollover = bucket.rolloverUnused
        draftLinkedCategoryID = bucket.linkedCategory?.id
    }

    private func save() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        bucket.name = trimmed
        bucket.kindRaw = draftKind.rawValue
        bucket.timelineRaw = draftTimeline.rawValue
        bucket.rolloverUnused = draftRollover
        bucket.plannedAmount = Parser.parseAmountToken(
            draftPlannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        bucket.linkedCategory = draftLinkedCategoryID.flatMap { id in
            expenseCategories.first(where: { $0.id == id })
        }

        do {
            try context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func softDelete() {
        let service = BucketService(context: context)
        do {
            try service.softDelete(bucket)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
