import Foundation

// MARK: - Text

/// Word handling shared by the index and the resolver: normalising, stemming and number words.
///
/// Names and questions pass through the same functions, so a word means the same on both sides of a match.
enum AskText {
    /// Lower-cases, drops a possessive (`Sam's` reads `sam`) and other apostrophes, joins `PM2.5` to `pm25` and
    /// turns every other non-alphanumeric run into one space.
    static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "'s ", with: " ")
        if s.hasSuffix("'s") { s.removeLast(2) }
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingOccurrences(of: "°", with: " degrees ")
        // `pm2.5` and `pm 2.5` become `pm25`.
        s = s.replacingOccurrences(of: #"pm\s?2\.5"#, with: "pm25", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<=\d)\.(?=\d)"#, with: "_", options: .regularExpression)
        var out = ""
        out.reserveCapacity(s.count)
        var space = true
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "_" {
                out.append(ch)
                space = false
            } else if !space {
                out.append(" ")
                space = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The stem of a lower-case word: plural endings only. `lights` reads `light`, `batteries` reads `battery`, `glass` stays.
    static func stem(_ word: String) -> String {
        let w = word
        guard w.count > 3, !w.contains("_") else { return w }
        if w.hasSuffix("ies"), w.count > 4 { return String(w.dropLast(3)) + "y" }
        for tail in ["sses", "ches", "shes", "xes", "zes"] where w.hasSuffix(tail) { return String(w.dropLast(2)) }
        if w.hasSuffix("ss") || w.hasSuffix("us") || w.hasSuffix("is") { return w }
        if w.hasSuffix("s") { return String(w.dropLast()) }
        return w
    }

    /// The stemmed, synonym-mapped words of `text`. A synonym may expand to several words (`lounge` reads `living room`).
    static func words(_ text: String, synonyms: [String: String] = [:]) -> [String] {
        var out: [String] = []
        for raw in normalize(text).split(separator: " ") {
            let word = tens[String(raw)] ?? String(raw)
            if let mapped = synonyms[word] ?? synonyms[stem(word)] {
                out.append(contentsOf: mapped.split(separator: " ").map { stem(String($0)) })
            } else {
                out.append(stem(word))
            }
        }
        return out
    }

    /// Spoken tens, read as digits so `thirty seconds` matches `30 seconds` in a name.
    private static let tens = ["twenty": "20", "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90"]

    /// The value of a spoken number word (`two` is 2), or nil.
    static func number(_ word: String) -> Int? {
        numberWords[word] ?? Int(word)
    }

    private static let numberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12,
    ]

    /// Whether `needle` occurs in `haystack` as a run of whole words.
    static func containsRun(_ haystack: [String], _ needle: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle { return start }
        return nil
    }
}
