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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
private struct FilteredReport: View {
    @Query private var transactions: [Transaction]
    private let direction: ReportDirection

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

    private var grandTotal: Decimal {
        transactions.map(\.amount).reduce(Decimal(0), +)
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
            Text("\(transactions.count) transactions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart(totalsByCategory) { item in
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
    }

    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(totalsByCategory) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text("\(item.count)x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TransactionService.formatPKR(item.amount))
                        .font(.body.monospacedDigit())
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
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
