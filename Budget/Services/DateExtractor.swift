import Foundation

/// Extracts date phrases from chat input so logs can be backdated.
/// Runs as a pre-pass before the rest of the parser.
///
/// Handles: today / yesterday / tomorrow, "on monday"/Monday-Sunday
/// (most recent past — same-weekday means 7 days ago), "N days ago",
/// "N weeks ago", "last week".
struct ExtractedDate {
    /// Extracted date, or nil if no date phrase was found.
    let date: Date?
    /// The input with the date phrase removed (and any "on" preceding it).
    let strippedInput: String
    /// Human-readable phrase that matched, for display in responses.
    let phrase: String?
}

enum DateExtractor {
    static func extract(from input: String) -> ExtractedDate {
        let originalTokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let tokens = originalTokens.map { $0.lowercased() }
        guard !tokens.isEmpty else {
            return ExtractedDate(date: nil, strippedInput: input, phrase: nil)
        }

        let cal = Calendar.current
        let now = Date()

        // 1. "N day(s)/week(s) ago"
        if tokens.count >= 3 {
            for i in 0...(tokens.count - 3) {
                guard let n = Int(tokens[i]), n > 0 else { continue }
                let unitWord = tokens[i + 1]
                guard tokens[i + 2] == "ago" else { continue }
                let unit: Calendar.Component
                switch unitWord {
                case "day", "days": unit = .day
                case "week", "weeks": unit = .weekOfYear
                case "month", "months": unit = .month
                default: continue
                }
                let date = cal.date(byAdding: unit, value: -n, to: now)
                let stripped = removeIndices([i, i + 1, i + 2], from: originalTokens).joined(separator: " ")
                return ExtractedDate(
                    date: date,
                    strippedInput: stripped,
                    phrase: "\(n) \(unitWord) ago"
                )
            }
        }

        // 2. "last week" / "last month"
        if tokens.count >= 2 {
            for i in 0...(tokens.count - 2) {
                if tokens[i] == "last" {
                    let unit: Calendar.Component?
                    switch tokens[i + 1] {
                    case "week": unit = .weekOfYear
                    case "month": unit = .month
                    case "year": unit = .year
                    default: unit = nil
                    }
                    if let unit {
                        let date = cal.date(byAdding: unit, value: -1, to: now)
                        let stripped = removeIndices([i, i + 1], from: originalTokens).joined(separator: " ")
                        return ExtractedDate(
                            date: date,
                            strippedInput: stripped,
                            phrase: "last \(tokens[i + 1])"
                        )
                    }
                }
            }
        }

        // 3. Single relative keyword
        let singleOffsets: [String: Int] = [
            "today": 0,
            "yesterday": -1,
            "tomorrow": 1,
        ]
        for (keyword, offset) in singleOffsets {
            if let idx = tokens.firstIndex(of: keyword) {
                let date = cal.date(byAdding: .day, value: offset, to: now)
                let indices = removalIndices(at: idx, in: tokens)
                let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
                return ExtractedDate(date: date, strippedInput: stripped, phrase: keyword)
            }
        }

        // 4. Weekday name → most recent past occurrence (or 7 days ago if today)
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (offset, name) in weekdays.enumerated() {
            guard let idx = tokens.firstIndex(of: name) else { continue }
            let target = offset + 1            // Calendar.weekday is 1-based, Sunday=1
            let today = cal.component(.weekday, from: now)
            var diff = today - target
            if diff <= 0 { diff += 7 }
            let date = cal.date(byAdding: .day, value: -diff, to: now)
            let indices = removalIndices(at: idx, in: tokens)
            let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
            return ExtractedDate(date: date, strippedInput: stripped, phrase: name)
        }

        return ExtractedDate(date: nil, strippedInput: input, phrase: nil)
    }

    // MARK: - Helpers

    /// Returns indices to remove for the matched token at `idx`, including a
    /// preceding "on" if present.
    private static func removalIndices(at idx: Int, in tokens: [String]) -> [Int] {
        var indices = [idx]
        if idx > 0 && tokens[idx - 1] == "on" {
            indices.append(idx - 1)
        }
        return indices
    }

    private static func removeIndices(_ indices: [Int], from arr: [String]) -> [String] {
        let toRemove = Set(indices)
        return arr.enumerated()
            .compactMap { toRemove.contains($0.offset) ? nil : $0.element }
    }
}
