import AppIntents

/// Registers `LogExpenseIntent` with the system so it shows up in Shortcuts
/// and is invocable via Siri without setup. The user just installs/launches
/// the app once and can then say "Hey Siri, log Budget expense".
struct BudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log \(.applicationName) expense",
                "Log \(.applicationName)",
                "\(.applicationName) log",
                "Add to \(.applicationName)",
            ],
            shortTitle: "Log expense",
            systemImageName: "wallet.pass"
        )
    }
}
