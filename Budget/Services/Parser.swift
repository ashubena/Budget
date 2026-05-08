import Foundation

// MARK: - Errors

enum ParserError: Error, LocalizedError {
    case empty
    case noAmountFound
    case missingCounterparty(verb: String)

    var errorDescription: String? {
        switch self {
        case .empty: return "Empty input."
        case .noAmountFound:
            return "I didn't see an amount. Try \"500 food\"."
        case .missingCounterparty(let verb):
            return "Who's the \"\(verb)\" with? Try \"\(verb) ahmed 5000\"."
        }
    }
}

// MARK: - Result

/// Unified parse result. Tiers:
///   1 — default expense
///   2 — income (keywords: got, earned, received, got paid)
///   3 — loans (keywords: lent, borrowed, paid back)
enum ParseResult: Equatable {
    case expense(amount: Decimal, fragment: String)
    case income(amount: Decimal, fragment: String)            // empty fragment → defaults to Salary
    case loanOut(counterparty: String, amount: Decimal)       // I lent them money
    case loanIn(counterparty: String, amount: Decimal)        // I borrowed from them
    case loanPaymentIn(counterparty: String, amount: Decimal) // they paid me back
    case loanPaymentOut(counterparty: String, amount: Decimal)// I paid them back
    case voidLast                                             // undo most recent
}

// MARK: - Parse output (with date)

struct ParseOutput {
    let result: ParseResult
    let occurredAt: Date           // defaults to now if no date phrase found
    let datePhrase: String?        // human-readable, e.g. "yesterday", "monday"
}

// MARK: - Parser

enum Parser {
    /// Public entry point. Runs date extraction, then tier matching on the
    /// remainder. Returns both the parsed action and the date it should be
    /// recorded against.
    static func parse(_ input: String) throws -> ParseOutput {
        let extracted = DateExtractor.extract(from: input)
        let result = try parseCore(extracted.strippedInput)
        return ParseOutput(
            result: result,
            occurredAt: extracted.date ?? Date(),
            datePhrase: extracted.phrase
        )
    }

    /// Tier matching only (no date pre-pass). Exposed for tests.
    static func parseCore(_ input: String) throws -> ParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParserError.empty }

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let lowerTokens = tokens.map { $0.lowercased() }

        // Tier 0 — single-shot commands
        let lowered = trimmed.lowercased()
        if lowered == "undo" || lowered == "void last" || lowered == "delete last" {
            return .voidLast
        }

        // Tier 0.5 — explicit sign prefix: "+1000 freelance" / "-500 food"
        if let result = parseSignedShorthand(tokens: tokens) {
            return result
        }

        // Tier 3 — loans
        if let result = try parseLoan(tokens: tokens, lowerTokens: lowerTokens) {
            return result
        }

        // Tier 2 — income
        if let result = try parseIncome(tokens: tokens, lowerTokens: lowerTokens) {
            return result
        }

        // Tier 1 — default expense
        return try parseExpense(tokens: tokens, lowerTokens: lowerTokens, raw: trimmed)
    }

    // MARK: - Tier 0.5: sign prefix shorthand

    /// "+1000 freelance" → income, "-500 food" → expense.
    /// Sign must lead the first token; rest of token must parse as a number.
    /// Returns nil if no sign prefix or amount unparseable.
    private static func parseSignedShorthand(tokens: [String]) -> ParseResult? {
        guard let first = tokens.first else { return nil }
        let direction: Direction
        let stripped: String
        if first.hasPrefix("+") {
            direction = .inflow
            stripped = String(first.dropFirst())
        } else if first.hasPrefix("-") {
            direction = .outflow
            stripped = String(first.dropFirst())
        } else {
            return nil
        }
        guard !stripped.isEmpty, let amount = parseAmountToken(stripped) else { return nil }

        var rest = tokens
        rest.removeFirst()
        let fragment = rest.joined(separator: " ").lowercased()

        switch direction {
        case .inflow:  return .income(amount: amount, fragment: fragment)
        case .outflow: return .expense(amount: amount, fragment: fragment)
        }
    }

    // MARK: - Tier 1: expense

    private static func parseExpense(tokens: [String], lowerTokens: [String], raw: String) throws -> ParseResult {
        guard let (amount, idx) = findAmount(in: lowerTokens) else {
            throw ParserError.noAmountFound
        }
        var rest = tokens
        rest.remove(at: idx)
        let fragment = rest.joined(separator: " ").lowercased()
        return .expense(amount: amount, fragment: fragment)
    }

    // MARK: - Tier 2: income

    /// Income trigger words. The first word in input must be one of these
    /// (or "got" + "paid").
    private static let incomeTriggers: Set<String> = ["got", "earned", "received"]

    private static func parseIncome(tokens: [String], lowerTokens: [String]) throws -> ParseResult? {
        guard let first = lowerTokens.first else { return nil }

        // Special case "got paid …" — drop the "paid" so it doesn't conflict with loan flow.
        if first == "got", lowerTokens.count >= 2, lowerTokens[1] == "paid" {
            var stripped = tokens
            var lowerStripped = lowerTokens
            stripped.removeFirst(2)
            lowerStripped.removeFirst(2)
            guard let (amount, idx) = findAmount(in: lowerStripped) else { throw ParserError.noAmountFound }
            stripped.remove(at: idx)
            let fragment = stripped.joined(separator: " ").lowercased()
            return .income(amount: amount, fragment: fragment.isEmpty ? "salary" : fragment)
        }

        guard incomeTriggers.contains(first) else { return nil }

        var stripped = tokens
        var lowerStripped = lowerTokens
        stripped.removeFirst()
        lowerStripped.removeFirst()

        guard let (amount, idx) = findAmount(in: lowerStripped) else { throw ParserError.noAmountFound }
        stripped.remove(at: idx)
        let fragment = stripped.joined(separator: " ").lowercased()
        return .income(amount: amount, fragment: fragment)
    }

    // MARK: - Tier 3: loans

    private static func parseLoan(tokens: [String], lowerTokens: [String]) throws -> ParseResult? {
        guard let first = lowerTokens.first else { return nil }

        // "lent <name> <amount>"
        if first == "lent" {
            var rest = tokens
            var lowerRest = lowerTokens
            rest.removeFirst()
            lowerRest.removeFirst()
            guard let (amount, idx) = findAmount(in: lowerRest) else { throw ParserError.noAmountFound }
            rest.remove(at: idx)
            let counterparty = cleanCounterparty(rest)
            guard !counterparty.isEmpty else { throw ParserError.missingCounterparty(verb: "lent") }
            return .loanOut(counterparty: counterparty, amount: amount)
        }

        // "borrowed <amount> [from] <name>"
        if first == "borrowed" {
            var rest = tokens
            var lowerRest = lowerTokens
            rest.removeFirst()
            lowerRest.removeFirst()
            guard let (amount, idx) = findAmount(in: lowerRest) else { throw ParserError.noAmountFound }
            rest.remove(at: idx)
            lowerRest.remove(at: idx)
            // Strip "from" if present
            if let fromIdx = lowerRest.firstIndex(of: "from") {
                rest.remove(at: fromIdx)
            }
            let counterparty = cleanCounterparty(rest)
            guard !counterparty.isEmpty else { throw ParserError.missingCounterparty(verb: "borrowed") }
            return .loanIn(counterparty: counterparty, amount: amount)
        }

        // "paid back <name> <amount>"  (I paid them back)
        if first == "paid", lowerTokens.count >= 2, lowerTokens[1] == "back" {
            var rest = tokens
            var lowerRest = lowerTokens
            rest.removeFirst(2)
            lowerRest.removeFirst(2)
            guard let (amount, idx) = findAmount(in: lowerRest) else { throw ParserError.noAmountFound }
            rest.remove(at: idx)
            let counterparty = cleanCounterparty(rest)
            guard !counterparty.isEmpty else { throw ParserError.missingCounterparty(verb: "paid back") }
            return .loanPaymentOut(counterparty: counterparty, amount: amount)
        }

        // "<name> paid back <amount>"  (they paid me back)
        if let pbIdx = findPhrase(["paid", "back"], in: lowerTokens), pbIdx > 0 {
            var rest = tokens
            var lowerRest = lowerTokens
            // Take name = tokens before pbIdx
            let nameTokens = Array(rest[0..<pbIdx])
            // Remove name + "paid back"
            rest.removeFirst(pbIdx + 2)
            lowerRest.removeFirst(pbIdx + 2)
            guard let (amount, idx) = findAmount(in: lowerRest) else { throw ParserError.noAmountFound }
            _ = idx
            let counterparty = cleanCounterparty(nameTokens)
            guard !counterparty.isEmpty else { throw ParserError.missingCounterparty(verb: "paid back") }
            return .loanPaymentIn(counterparty: counterparty, amount: amount)
        }

        return nil
    }

    // MARK: - Helpers

    /// Find the first token in `tokens` that parses as an amount.
    /// Returns the parsed Decimal and the token index, or nil.
    private static func findAmount(in tokens: [String]) -> (Decimal, Int)? {
        for (i, t) in tokens.enumerated() {
            if let n = parseAmountToken(t) {
                return (n, i)
            }
        }
        return nil
    }

    /// Parse a single token as a Decimal. Handles 500, 1,200, 50.5, 2k, 1.5k.
    static func parseAmountToken(_ token: String) -> Decimal? {
        let cleaned = token.replacingOccurrences(of: ",", with: "").lowercased()
        if cleaned.hasSuffix("k") {
            let base = String(cleaned.dropLast())
            guard let dec = Decimal(string: base), dec > 0 else { return nil }
            return dec * 1000
        }
        guard let dec = Decimal(string: cleaned), dec > 0 else { return nil }
        return dec
    }

    /// Find the index where a multi-token phrase starts. Returns nil if not found.
    private static func findPhrase(_ phrase: [String], in tokens: [String]) -> Int? {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return nil }
        for i in 0...(tokens.count - phrase.count) {
            if Array(tokens[i..<(i + phrase.count)]) == phrase {
                return i
            }
        }
        return nil
    }

    /// Title-case the counterparty name (joins tokens with spaces).
    private static func cleanCounterparty(_ tokens: [String]) -> String {
        let trimmed = tokens.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return trimmed.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
