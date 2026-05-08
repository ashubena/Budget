import SwiftUI
import SwiftData

/// Sheet for creating a new bucket OR a new savings goal.
/// Used by both BucketsView (+ in toolbar) and GoalsView (+ in toolbar).
/// `initialKind` lets the caller pre-select savingsGoal so the goal-shaped
/// fields (target amount, target date) are visible from the start.
struct AddBucketSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let initialKind: BucketKind

    @State private var name: String = ""
    @State private var kind: BucketKind
    @State private var plannedText: String = ""
    @State private var timeline: BucketTimeline = .monthly
    @State private var rolloverUnused: Bool = false
    @State private var linkedCategoryID: UUID? = nil

    // Goal-specific fields
    @State private var targetText: String = ""
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

    @Query(
        filter: #Predicate<Category> { $0.kindRaw == "expense" },
        sort: \Category.name
    )
    private var expenseCategories: [Category]

    init(initialKind: BucketKind = .spendingPlan) {
        self.initialKind = initialKind
        self._kind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(namePlaceholder, text: $name)
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

                spendingSection
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
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 560)
        #endif
    }

    // MARK: - Sections

    private var spendingSection: some View {
        Group {
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
        }
    }

    // MARK: - Helpers

    private var namePlaceholder: String {
        "e.g. Food, Rent, Transport"
    }

    private var navigationTitle: String {
        "New bucket"
    }

    private var kindHint: String {
        switch kind {
        case .spendingPlan:
            return "A regular budget bucket that resets each period (Food, Rent, Transport)."
        case .reserve:
            return "Money set aside that doesn't reset (Buffer, Slush)."
        case .savingsGoal:
            return ""
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let now = Date()

        let planned = Parser.parseAmountToken(
            plannedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let linkedCategory: Category? = linkedCategoryID.flatMap { id in
            expenseCategories.first(where: { $0.id == id })
        }
        let bucket = Bucket(
            name: trimmed,
            kind: kind,
            timeline: timeline,
            periodStart: now,
            periodEnd: nextPeriodEnd(from: now, timeline: timeline),
            plannedAmount: planned,
            rolloverUnused: rolloverUnused,
            linkedCategory: linkedCategory
        )

        context.insert(bucket)
        try? context.save()
        dismiss()
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
