import SwiftUI
import SwiftData

/// Unified create + edit sheet for buckets. Replaces the old
/// `AddBucketSheet` and `EditBucketSheet` (~340 LOC → ~200 LOC).
///
/// Usage:
///     BucketSheet()                  // create new
///     BucketSheet(editing: bucket)   // edit existing (also offers delete)
struct BucketSheet: View {
    enum Mode {
        case create
        case edit(Bucket)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode

    // Form state — populated from the bucket on edit, defaults on create.
    @State private var name: String = ""
    @State private var kind: BucketKind = .spendingPlan
    @State private var plannedText: String = ""
    @State private var timeline: BucketTimeline = .monthly
    @State private var rolloverUnused: Bool = false
    @State private var linkedCategoryID: UUID? = nil
    @State private var showingDeleteConfirm = false
    @State private var error: String? = nil

    @Query(
        filter: #Predicate<Category> { $0.kindRaw == "expense" },
        sort: \Category.name
    )
    private var expenseCategories: [Category]

    init() {
        self.mode = .create
    }

    init(editing bucket: Bucket) {
        self.mode = .edit(bucket)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingBucket: Bucket? {
        if case .edit(let b) = mode { return b }
        return nil
    }

    private var isDirty: Bool {
        guard let b = editingBucket else { return true }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed != b.name { return true }
        if kind != b.kind { return true }
        if timeline != b.timeline { return true }
        if rolloverUnused != b.rolloverUnused { return true }
        if linkedCategoryID != b.linkedCategory?.id { return true }
        let parsedPlanned = Parser.parseAmountToken(
            plannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if parsedPlanned != b.plannedAmount { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Food, Rent, Transport", text: $name)
                }

                Section("Type") {
                    Picker("Kind", selection: $kind) {
                        Text("Spending plan").tag(BucketKind.spendingPlan)
                        Text("Reserve").tag(BucketKind.reserve)
                    }
                    .pickerStyle(.segmented)
                    Text(kindHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Plan") {
                    TextField("Planned amount (optional)", text: $plannedText)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    Picker("Resets", selection: $timeline) {
                        Text("Weekly").tag(BucketTimeline.weekly)
                        Text("Monthly").tag(BucketTimeline.monthly)
                        Text("Yearly").tag(BucketTimeline.yearly)
                    }
                    Toggle("Roll over unused", isOn: $rolloverUnused)
                }

                Section {
                    Picker("Auto-link category", selection: $linkedCategoryID) {
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

                if let b = editingBucket {
                    Section("Status") {
                        LabeledContent("Currently allocated",
                                       value: TransactionService.formatPKR(b.allocatedAmount))
                    }
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete bucket", systemImage: "trash")
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        commit()
                    }
                    .disabled(!canCommit)
                }
            }
            .confirmationDialog(
                editingBucket.map { "Delete \($0.name)?" } ?? "",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allocation history is kept. The bucket disappears from the Plan canvas.")
            }
            .onAppear { loadDraft() }
        }
        .macOSSheetSize(.standard)
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        if let b = editingBucket { return b.name }
        return "New bucket"
    }

    private var kindHint: String {
        switch kind {
        case .spendingPlan:
            return "A regular budget bucket that resets each period (Food, Rent, Transport)."
        case .reserve:
            return "Money set aside that doesn't reset (Buffer, Slush)."
        case .savingsGoal:
            return ""  // never picked from UI; backward-compat only
        }
    }

    private var canCommit: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if isEditing { return isDirty }
        return true
    }

    // MARK: - Actions

    private func loadDraft() {
        guard let b = editingBucket else { return }
        name = b.name
        kind = b.kind
        plannedText = b.plannedAmount.map { "\($0)" } ?? ""
        timeline = b.timeline
        rolloverUnused = b.rolloverUnused
        linkedCategoryID = b.linkedCategory?.id
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parsedPlanned = Parser.parseAmountToken(
            plannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let linkedCategory: Category? = linkedCategoryID.flatMap { id in
            expenseCategories.first(where: { $0.id == id })
        }

        if let b = editingBucket {
            b.name = trimmed
            b.kindRaw = kind.rawValue
            b.timelineRaw = timeline.rawValue
            b.rolloverUnused = rolloverUnused
            b.plannedAmount = parsedPlanned
            b.linkedCategory = linkedCategory
        } else {
            let now = Date()
            let bucket = Bucket(
                name: trimmed,
                kind: kind,
                timeline: timeline,
                periodStart: now,
                periodEnd: nextPeriodEnd(from: now, timeline: timeline),
                plannedAmount: parsedPlanned,
                rolloverUnused: rolloverUnused,
                linkedCategory: linkedCategory
            )
            context.insert(bucket)
        }

        do {
            try context.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performDelete() {
        guard let b = editingBucket else { return }
        let service = BucketService(context: context)
        do {
            try service.softDelete(b)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func nextPeriodEnd(from start: Date, timeline: BucketTimeline) -> Date? {
        let cal = Calendar.current
        switch timeline {
        case .weekly:  return cal.date(byAdding: .weekOfYear, value: 1, to: start)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: start)
        case .yearly:  return cal.date(byAdding: .year, value: 1, to: start)
        case .custom:  return nil
        }
    }
}
