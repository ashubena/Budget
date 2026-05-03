import SwiftUI
import SwiftData

/// Plan canvas — visual grid of buckets with the Unallocated pool on top.
/// Per design: only spendingPlan + reserve buckets show here.
/// Goals (savingsGoal kind) live on their own Goals tab.
struct BucketsView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Bucket> { !$0.isDeleted && $0.kindRaw != "savingsGoal" },
        sort: [SortDescriptor(\Bucket.displayOrder), SortDescriptor(\Bucket.name)]
    )
    private var buckets: [Bucket]

    // For Unallocated computation:
    @Query(filter: #Predicate<Account> { $0.isActive })
    private var accounts: [Account]

    @Query(filter: #Predicate<Bucket> { !$0.isDeleted })
    private var allBuckets: [Bucket]

    @State private var amountRequest: AmountRequest? = nil
    @State private var showAddSheet = false

    private var unallocated: Decimal {
        let totalCash = accounts.map(\.realBalance).reduce(Decimal(0), +)
        let totalAlloc = allBuckets.map(\.allocatedAmount).reduce(Decimal(0), +)
        return totalCash - totalAlloc
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                unallocatedHeader
                Divider()
                if buckets.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(buckets) { bucket in
                            BucketCard(bucket: bucket) { direction in
                                amountRequest = AmountRequest(bucket: bucket, direction: direction)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Bucket", systemImage: "plus")
                }
            }
        }
        .sheet(item: $amountRequest) { req in
            AmountEntrySheet(bucket: req.bucket, direction: req.direction)
        }
        .sheet(isPresented: $showAddSheet) {
            AddBucketSheet()
        }
    }

    // MARK: - Pieces

    private var unallocatedHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UNALLOCATED")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text(TransactionService.formatPKR(unallocated))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(unallocated < 0 ? Color.red : Color.primary)
            if unallocated < 0 {
                Text("Over-allocated by \(TransactionService.formatPKR(-unallocated))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No buckets yet")
                .font(.headline)
            Text("Tap + to add one — e.g. Food, Rent, Transport.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Sheet request type

struct AmountRequest: Identifiable {
    enum Adjustment { case add, remove }
    let id = UUID()
    let bucket: Bucket
    let direction: Adjustment
}

// MARK: - One bucket card

struct BucketCard: View {
    let bucket: Bucket
    let onAdjust: (AmountRequest.Adjustment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bucket.name)
                .font(.headline)
                .lineLimit(1)

            Text(TransactionService.formatPKR(bucket.allocatedAmount))
                .font(.title3.weight(.semibold))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let planned = bucket.plannedAmount {
                Text("of \(TransactionService.formatPKR(planned))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    onAdjust(.remove)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    onAdjust(.add)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1.5)
        )
    }

    private var amountColor: Color {
        bucket.allocatedAmount < 0 ? .red : .primary
    }

    private var cardBackground: Color {
        switch bucket.statusColor {
        case .green: return Color.green.opacity(0.08)
        case .yellow: return Color.yellow.opacity(0.15)
        case .red: return Color.red.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch bucket.statusColor {
        case .green: return Color.green.opacity(0.45)
        case .yellow: return Color.yellow.opacity(0.65)
        case .red: return Color.red.opacity(0.7)
        }
    }
}

#Preview {
    NavigationStack {
        BucketsView()
    }
    .modelContainer(for: [
        Account.self, Category.self, CategoryKeyword.self, CategoryAlias.self,
        Tag.self, Transaction.self, TransactionAudit.self, Bucket.self,
        Allocation.self, BucketPeriod.self, Plan.self, PlanInstance.self, Loan.self,
    ], inMemory: true)
}
