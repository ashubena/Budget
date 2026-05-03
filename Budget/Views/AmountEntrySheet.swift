import SwiftUI
import SwiftData

/// Modal sheet for adding or removing PKR to/from a bucket via the Plan canvas.
/// Hits BucketService.allocate(_:to:) under the hood.
struct AmountEntrySheet: View {
    let bucket: Bucket
    let direction: AmountRequest.Adjustment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bucket", value: bucket.name)
                    LabeledContent("Currently",
                                   value: TransactionService.formatPKR(bucket.allocatedAmount))
                    if let planned = bucket.plannedAmount {
                        LabeledContent("Planned",
                                       value: TransactionService.formatPKR(planned))
                    }
                }

                Section("Amount (PKR)") {
                    TextField("e.g. 5000 or 2k", text: $amountText)
                        .font(.title3)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedAmount == nil)
                }
            }
        }
    }

    private var title: String {
        switch direction {
        case .add:    return "Add to \(bucket.name)"
        case .remove: return "Remove from \(bucket.name)"
        }
    }

    private var parsedAmount: Decimal? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Parser.parseAmountToken(trimmed)
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let signed: Decimal = (direction == .add) ? amount : -amount
        let service = BucketService(context: context)
        do {
            try service.allocate(signed, to: bucket, reason: .manualMove)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
