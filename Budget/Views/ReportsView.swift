import SwiftUI
import SwiftData
import Charts

/// Reports tab — pie chart of actual expenses (or income) per category
/// over a chosen time range. Reality layer only — reports on transactions,
/// not bucket allocations.
struct ReportsView: View {
    @Environment(\.modelContext) private var context

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case all = "All"
        var id: String { rawValue }
    }

    enum DirectionFilter: String, CaseIterable, Identifiable {
        case expenses = "Expenses"
        case income = "Income"
        var id: String { rawValue }
    }

    @State private var range: Range = .month
    @State private var directionFilter: DirectionFilter = .expenses

    @Query(
        filter: #Predicate<Transaction> { !$0.isVoided },
        sort: \Transaction.occurredAt
    )
    private var allTransactions: [Transaction]

    private var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .week:  return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: return cal.dateInterval(of: .month, for: now)?.start ?? now
        case .year:  return cal.dateInterval(of: .year, for: now)?.start ?? now
        case .all:   return .distantPast
        }
    }

    private var filtered: [Transaction] {
        let dirRaw = (directionFilter == .expenses) ? Direction.outflow.rawValue : Direction.inflow.rawValue
        let cutoff = startDate
        return allTransactions.filter {
            $0.occurredAt >= cutoff && $0.directionRaw == dirRaw
        }
    }

    private struct CategoryTotal: Identifiable {
        var id: String { name }
        let name: String
        let amount: Decimal
        let count: Int
    }

    private var totalsByCategory: [CategoryTotal] {
        let groups = Dictionary(grouping: filtered) { $0.category?.name ?? "Uncategorized" }
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
        filtered.map(\.amount).reduce(Decimal(0), +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filtersBar
                Divider()

                if filtered.isEmpty {
                    emptyState
                } else {
                    summaryHeader
                    chart
                    legend
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
    }

    // MARK: - Pieces

    private var filtersBar: some View {
        VStack(spacing: 8) {
            Picker("", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("", selection: $directionFilter) {
                ForEach(DirectionFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(directionFilter == .expenses ? "TOTAL SPENT" : "TOTAL EARNED")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text(TransactionService.formatPKR(grandTotal))
                .font(.system(size: 28, weight: .bold))
            Text("\(filtered.count) transactions")
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
            Text("No \(directionFilter.rawValue.lowercased()) in this range")
                .font(.headline)
            Text("Log something on the Chat tab.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
