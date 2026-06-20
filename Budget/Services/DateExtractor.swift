import Foundation

struct ExtractedDate {
    let date: Date?
    let strippedInput: String
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

        // "N day(s)/week(s)/month(s) ago"
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
                return ExtractedDate(date: date, strippedInput: stripped, phrase: "\(n) \(unitWord) ago")
            }
        }

        // "last week" / "last month" / "last year"
        if tokens.count >= 2 {
            for i in 0...(tokens.count - 2) where tokens[i] == "last" {
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
                    return ExtractedDate(date: date, strippedInput: stripped, phrase: "last \(tokens[i + 1])")
                }
            }
        }

        // today / yesterday / tomorrow
        let singleOffsets: [String: Int] = ["today": 0, "yesterday": -1, "tomorrow": 1]
        for (keyword, offset) in singleOffsets {
            if let idx = tokens.firstIndex(of: keyword) {
                let date = cal.date(byAdding: .day, value: offset, to: now)
                let indices = removalIndices(at: idx, in: tokens)
                let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
                return ExtractedDate(date: date, strippedInput: stripped, phrase: keyword)
            }
        }

        // Weekday → most recent past occurrence (same weekday → 7 days ago)
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        for (offset, name) in weekdays.enumerated() {
            guard let idx = tokens.firstIndex(of: name) else { continue }
            let target = offset + 1
            let today = cal.component(.weekday, from: now)
            var diff = today - target
            if diff <= 0 { diff += 7 }
            let date = cal.date(byAdding: .day, value: -diff, to: now)
            let indices = removalIndices(at: idx, in: tokens)
            let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
            return ExtractedDate(date: date, strippedInput: stripped, phrase: name)
        }

        // Month-name dates: "17 June", "17th of June", "June 17", "on the 17th of June"
        if let hit = parseMonthName(tokens: tokens, originalTokens: originalTokens, now: now) {
            return hit
        }

        // Numeric dates: "17/6", "17/6/2026", "17-6-26"
        if let hit = parseNumericDate(tokens: tokens, originalTokens: originalTokens, now: now) {
            return hit
        }

        return ExtractedDate(date: nil, strippedInput: input, phrase: nil)
    }

    // MARK: - Month-name parsing

    private static let monthLookup: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static func dayFromToken(_ token: String) -> Int? {
        var t = token.lowercased()
        for suffix in ["st", "nd", "rd", "th"] {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count))
                break
            }
        }
        guard let day = Int(t), (1...31).contains(day) else { return nil }
        return day
    }

    private static func parseMonthName(tokens: [String], originalTokens: [String], now: Date) -> ExtractedDate? {
        let cal = Calendar.current
        for (i, token) in tokens.enumerated() {
            guard let month = monthLookup[token] else { continue }

            var day: Int?
            var indices: [Int] = [i]

            // "DD of MM" or "DD MM" (day before month)
            if i >= 1, let d = dayFromToken(tokens[i - 1]) {
                day = d
                indices.append(i - 1)
            } else if i >= 2, tokens[i - 1] == "of", let d = dayFromToken(tokens[i - 2]) {
                day = d
                indices.append(i - 1)
                indices.append(i - 2)
                if i - 3 >= 0 && tokens[i - 3] == "the" {
                    indices.append(i - 3)
                }
            }

            // "MM DD" (month before day)
            if day == nil, i + 1 < tokens.count, let d = dayFromToken(tokens[i + 1]) {
                day = d
                indices.append(i + 1)
            }

            guard let d = day else { continue }

            // Strip "on" if it leads the date phrase
            let minIdx = indices.min() ?? i
            if minIdx > 0 && tokens[minIdx - 1] == "on" {
                indices.append(minIdx - 1)
            }

            var year = cal.component(.year, from: now)
            var date = makeDate(year: year, month: month, day: d)
            if let dt = date, dt > now {
                year -= 1
                date = makeDate(year: year, month: month, day: d)
            }
            guard let resolved = date else { continue }
            let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
            return ExtractedDate(date: resolved, strippedInput: stripped, phrase: "\(d) \(token)")
        }
        return nil
    }

    // MARK: - Numeric date parsing (DD/MM[/YY])

    private static func parseNumericDate(tokens: [String], originalTokens: [String], now: Date) -> ExtractedDate? {
        let cal = Calendar.current
        for (i, token) in tokens.enumerated() {
            let parts = token.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
            guard parts.count == 2 || parts.count == 3 else { continue }
            guard let day = Int(parts[0]), (1...31).contains(day),
                  let month = Int(parts[1]), (1...12).contains(month) else { continue }

            var year = cal.component(.year, from: now)
            var hasExplicitYear = false
            if parts.count == 3, let y = Int(parts[2]) {
                year = y < 100 ? 2000 + y : y
                hasExplicitYear = true
            }

            var date = makeDate(year: year, month: month, day: day)
            if !hasExplicitYear, let dt = date, dt > now {
                year -= 1
                date = makeDate(year: year, month: month, day: day)
            }
            guard let resolved = date else { continue }

            var indices = [i]
            if i > 0 && tokens[i - 1] == "on" {
                indices.append(i - 1)
            }
            let stripped = removeIndices(indices, from: originalTokens).joined(separator: " ")
            return ExtractedDate(date: resolved, strippedInput: stripped, phrase: token)
        }
        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    // MARK: - Token-removal helpers

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
