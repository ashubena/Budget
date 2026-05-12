import SwiftUI
import SwiftData
import Charts

/// Reports tab — pie chart of actual expenses (or income) per category
/// over a chosen time range. Reality layer only — reports on transactions,
/// not bucket allocations.
///
/// Scalability: the filter (date range + direction + voided) is pushed
/// into a child view's `@Query` predicate so SwiftData fetches only the
/// matching rows instead of loading the entire transaction history into
/// memory and filtering in Swift.
struct ReportsView: View {
    @State private var range: ReportRange = .month
    @State private var directionFilter: ReportDirection = .expenses

    @Query(filter: #Predicate<Account> { $0.isActive })
    private var accounts: [Account]

    private var totalBalance: Decimal {
        accounts.map(\.realBalance).reduce(Decimal(0), +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                balanceHeader
                Divider()
                filtersBar
                Divider()

                FilteredReport(range: range, direction: directionFilter)
                    // Force a fresh @Query when filters change
                    .id("\(range.rawValue)-\(directionFilter.rawValue)")
            }
            .padding()
        }
        .scrollIndicators(.visible)
        .navigationTitle("Reports")
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BALANCE")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text(TransactionService.formatPKR(totalBalance))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(totalBalance < 0 ? Color.red : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filtersBar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $range) {
                ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("", selection: $directionFilter) {
                ForEach(ReportDirection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Filter enums (top-level so the child view can use them in its init)

enum ReportRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"
    var id: String { rawValue }

    func startDate(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        switch self {
        case .week:  return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: return cal.dateInterval(of: .month, for: now)?.start ?? now
        case .year:  return cal.dateInterval(of: .year, for: now)?.start ?? now
        case .all:   return .distantPast
        }
    }
}

enum ReportDirection: String, CaseIterable, Identifiable {
    case expenses = "Expenses"
    case income = "Income"
    var id: String { rawValue }

    var directionRaw: String {
        switch self {
        case .expenses: return Direction.outflow.rawValue
        case .income:   return Direction.inflow.rawValue
        }
    }
}

// MARK: - Filtered child

/// Has its own @Query whose predicate is built from the params at init.
/// Rebuilt by the parent (via .id) when the filters change.
///
/// `disabledCategories` is local @State — toggling a legend row adds/removes
/// the category from this set. The pie chart, the summary header, and the
/// legend's row order are all derived from it.
private struct FilteredReport: View {
    @Query private var transactions: [Transaction]
    private let direction: ReportDirection

    @State private var disabledCategories: Set<String> = []

    init(range: ReportRange, direction: ReportDirection) {
        self.direction = direction
        let cutoff = range.startDate()
        let dirRaw = direction.directionRaw
        _transactions = Query(
            filter: #Predicate<Transaction> {
                !$0.isVoided
                    && $0.occurredAt >= cutoff
                    && $0.directionRaw == dirRaw
            },
            sort: \Transaction.occurredAt
        )
    }

    private struct CategoryTotal: Identifiable {
        var id: String { name }
        let name: String
        let amount: Decimal
        let count: Int
    }

    /// All categories with totals, sorted by amount desc.
    private var totalsByCategory: [CategoryTotal] {
        let groups = Dictionary(grouping: transactions) { $0.category?.name ?? "Uncategorized" }
        return groups.map { (name, txns) in
            CategoryTotal(
                name: name,
                amount: txns.map(\.amount).reduce(Decimal(0), +),
                count: txns.count
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    /// Categories currently included in the pie + summary.
    private var enabledTotals: [CategoryTotal] {
        totalsByCategory.filter { !disabledCategories.contains($0.name) }
    }

    /// Categories the user has toggled off; shown greyed at the bottom of the legend.
    private var disabledTotals: [CategoryTotal] {
        totalsByCategory.filter { disabledCategories.contains($0.name) }
    }

    /// Header reflects what's visible in the pie, not the raw query result.
    private var grandTotal: Decimal {
        enabledTotals.map(\.amount).reduce(Decimal(0), +)
    }

    private var enabledTransactionCount: Int {
        enabledTotals.map(\.count).reduce(0, +)
    }

    /// Toggle a category. Refuses to disable the last enabled one — at least
    /// one category must remain in the pie at all times.
    private func toggle(_ name: String) {
        if disabledCategories.contains(name) {
            disabledCategories.remove(name)
        } else if enabledTotals.count > 1 {
            disabledCategories.insert(name)
        }
        // else: would leave zero enabled — silently ignore
    }

    var body: some View {
        if transactions.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader
                chart
                legend
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(direction == .expenses ? "TOTAL SPENT" : "TOTAL EARNED")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text(TransactionService.formatPKR(grandTotal))
                .font(.system(size: 28, weight: .bold))
            Text("\(enabledTransactionCount) transactions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart(enabledTotals) { item in
            SectorMark(
                angle: .value("Amount", NSDecimalNumber(decimal: item.amount).doubleValue),
                innerRadius: .ratio(0.55),
                angularInset: 2
            )
            .foregroundStyle(by: .value("Category", item.name))
            .cornerRadius(4)
        }
        .frame(height: 280)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.25), value: disabledCategories)
    }

    @ViewBuilder
    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(enabledTotals) { item in
                legendRow(item, isEnabled: true)
            }
            if !disabledTotals.isEmpty {
                Color.clear.frame(height: 8)
                Text("HIDDEN")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .tracking(1.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                ForEach(disabledTotals) { item in
                    legendRow(item, isEnabled: false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: disabledCategories)
    }

    private func legendRow(_ item: CategoryTotal, isEnabled: Bool) -> some View {
        Button {
            toggle(item.name)
        } label: {
            HStack {
                Image(systemName: isEnabled ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                Text(item.name)
                    .strikethrough(!isEnabled, color: .secondary)
                Spacer()
                Text("\(item.count)x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(TransactionService.formatPKR(item.amount))
                    .font(.body.monospacedDigit())
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .background(
            Divider().offset(y: 16),
            alignment: .bottomLeading
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No \(direction.rawValue.lowercased()) in this range")
                .font(.headline)
            Text("Log something on the Chat tab.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
