import AppIntents
import SwiftData

/// Siri / Shortcuts entry point for logging from outside the app.
///
/// Examples:
///   "Hey Siri, log Budget expense" → asks "What's the expense?" → "500 food"
///   Or invoke from Shortcuts.app with a hard-coded phrase.
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log expense"

    static var description = IntentDescription(
        "Log an expense, income, or loan from a phrase like '500 food', 'got 80000 salary', or 'lent ahmed 5000'."
    )

    /// Run silently without bringing the app forward.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Phrase",
        description: "Plain-English description of what you spent, earned, or lent."
    )
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try BudgetSchema.makeContainer()
        let context = ModelContext(container)

        // Make sure defaults exist in case the user fires Siri before opening the app.
        SeedData.seedIfNeeded(context: context)

        do {
            let parsed = try Parser.parse(phrase)
            let service = TransactionService(context: context)
            let result = try service.log(parsed.result, occurredAt: parsed.occurredAt)
            return .result(dialog: IntentDialog(stringLiteral: result.message))
        } catch let err as ParserError {
            return .result(dialog: IntentDialog(stringLiteral: err.localizedDescription))
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Couldn't log that: \(error.localizedDescription)")
            )
        }
    }
}
