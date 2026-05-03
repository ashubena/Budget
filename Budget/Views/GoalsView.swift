import SwiftUI
import SwiftData

/// Goals tab — savings_goal buckets get their own surface separate from the
/// regular Plan canvas. Two segments: Active (working toward) and Past
/// (completed/abandoned via soft-delete; kept for history per design).
struct GoalsView: View {
    @Environment(\.modelContext) private var context

    enum Segment: String, CaseIterable, Identifiable {
        case active = "Active"
        case past = "Past"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .active
    @State private var amountRequest: AmountRequest? = nil
    @State private var showAddSheet = false

    @Query(
        filter: #Predicate<Bucket> { $0.kindRaw == "savingsGoal" },
        sort: \Bucket.createdAt
    )
    private var allGoals: [Bucket]

    private var activeGoals: [Bucket] {
        allGoals.filter { !$0.isDeleted }
    }

    private var pastGoals: [Bucket] {
        allGoals.filter { $0.isDeleted }
            .sorted(by: { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) })
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
            ScrollView {
                contentBody
                    .padding()
            }
        }
        .navigationTitle("Goals")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddSheet) {
            AddBucketSheet(initialKind: .savingsGoal)
        }
        .sheet(item: $amountRequest) { req in
            AmountEntrySheet(bucket: req.bucket, direction: req.direction)
        }
    }

    // MARK: - Sub-views

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddSheet = true
            } label: {
                Label("Add Goal", systemImage: "plus")
            }
            .disabled(segment != .active)
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        let goals = (segment == .active) ? activeGoals : pastGoals
        if goals.isEmpty {
            emptyState
        } else {
            goalsList(goals)
        }
    }

    private func goalsList(_ goals: [Bucket]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(goals) { goal in
                goalRow(for: goal)
            }
        }
    }

    private func goalRow(for goal: Bucket) -> some View {
        NavigationLink {
            GoalDetailView(goal: goal)
        } label: {
            GoalCard(
                goal: goal,
                isPast: segment == .past,
                onAdjust: { dir in
                    amountRequest = AmountRequest(bucket: goal, direction: dir)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: segment == .active ? "target" : "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(segment == .active ? "No active goals" : "No past goals")
                .font(.headline)
            if segment == .active {
                Text("Tap + to add one — e.g. Emergency Fund, Japan Trip.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Goal card

struct GoalCard: View {
    let goal: Bucket
    let isPast: Bool
    let onAdjust: (AmountRequest.Adjustment) -> Void

    private var progress: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        let frac = NSDecimalNumber(decimal: goal.allocatedAmount).doubleValue /
                   NSDecimalNumber(decimal: target).doubleValue
        return max(0, min(1, frac))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            amountLine
            if goal.targetAmount != nil {
                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .accentColor)
            }
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(goal.name).font(.headline)
            Spacer()
            if isPast {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var amountLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(TransactionService.formatPKR(goal.allocatedAmount))
                .font(.title2.weight(.semibold))
            if let target = goal.targetAmount {
                Text("of \(TransactionService.formatPKR(target))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if let date = goal.targetDate {
                Label(date.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isPast {
                adjustButtons
            }
        }
    }

    private var adjustButtons: some View {
        HStack(spacing: 4) {
            Button {
                onAdjust(.remove)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                onAdjust(.add)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Detail

struct GoalDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let goal: Bucket

    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            summarySection
            allocationsSection
            transactionsSection
            if !goal.isDeleted {
                deleteSection
            }
        }
        .navigationTitle(goal.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Move \(goal.name) to Past?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Past", role: .destructive) {
                let service = BucketService(context: context)
                try? service.softDelete(goal)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("History stays — you'll find it under Past on the Goals tab.")
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Allocated",
                           value: TransactionService.formatPKR(goal.allocatedAmount))
            if let target = goal.targetAmount {
                LabeledContent("Target",
                               value: TransactionService.formatPKR(target))
            }
            if let date = goal.targetDate {
                LabeledContent("Target date",
                               value: date.formatted(date: .abbreviated, time: .omitted))
            }
            if let deletedAt = goal.deletedAt {
                LabeledContent("Closed",
                               value: deletedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    @ViewBuilder
    private var allocationsSection: some View {
        let allocs = (goal.allocations ?? []).sorted(by: { $0.occurredAt > $1.occurredAt })
        Section("Allocations") {
            if allocs.isEmpty {
                Text("No allocations yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allocs) { a in
                    allocationRow(a)
                }
            }
        }
    }

    private func allocationRow(_ a: Allocation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(TransactionService.formatPKR(a.amount))
                    .foregroundStyle(a.amount < 0 ? Color.red : Color.primary)
                Spacer()
                Text(a.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(a.reason.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transactionsSection: some View {
        let txns = (goal.transactions ?? [])
            .filter { !$0.isVoided }
            .sorted(by: { $0.occurredAt > $1.occurredAt })
        if !txns.isEmpty {
            Section("Linked transactions") {
                ForEach(txns) { t in
                    transactionRow(t)
                }
            }
        }
    }

    private func transactionRow(_ t: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(TransactionService.formatPKR(t.amount))
                Spacer()
                Text(t.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let raw = t.rawInput {
                Text(raw)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Mark complete / abandon", systemImage: "checkmark.circle")
            }
        }
    }
}
