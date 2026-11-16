import Foundation

// MARK: - Text case

/// The letter case a `format` argument can ask for (`formats[name] = { text: { case: "title" } }`, `sh.pipeline-operands@1`).
public enum ServerUITextCase: String, Sendable, CaseIterable {
    /// `armed_away` is `Armed Away`, `heat cool` is `Heat cool`.
    case title
    /// `Wheel stuck` is `Wheel Stuck`, `heat_cool` is `Heat Cool` (`sh.text-case-words@1`).
    case words

    /// The capability a format in this case needs, without `sh.` and `@1`: `title` rides on `pipeline-operands`, `words` has its own id and
    /// must decode whether or not `pipeline-operands` is listed.
    public var capability: String {
        switch self {
        case .title: "pipeline-operands"
        case .words: "text-case-words"
        }
    }

    /// `text` in this case.
    public func apply(to text: String) -> String {
        switch self {
        case .title: Self.titleCase(text)
        case .words: Self.wordsCase(text)
        }
    }

    /// Splits at `_` and at U+0020 (a tab or a newline stays inside its word), keeps every empty part, makes each part's first scalar upper
    /// case when it is an ASCII `a` to `z`, leaves the rest, and joins the parts with one space. Empty text stays empty.
    ///
    /// It works on `unicodeScalars`, never `capitalized` or `Character.uppercased()`, so it is byte-equal with `wordsCase` in the Studio's
    /// `text.ts`: `a  b` is `A  B`, `_x` is ` X`, `x ` is `X `, `élan vital` is `élan Vital`.
    static func wordsCase(_ text: String) -> String {
        var parts: [String.UnicodeScalarView] = [.init()]
        for scalar in text.unicodeScalars {
            if scalar == "_" || scalar == " " { parts.append(.init()) } else { parts[parts.count - 1].append(scalar) }
        }
        return parts.map { part -> String in
            var scalars = part
            if let first = scalars.first, ("a"..."z").contains(first) {
                scalars.replaceSubrange(scalars.startIndex..<scalars.index(after: scalars.startIndex), with: [Unicode.Scalar(first.value - 32)!])
            }
            return String(scalars)
        }.joined(separator: " ")
    }

    /// Only `_` separates words (an empty part stays, so `a__b` is `A  B`), each part's first character is made upper case when it is an ASCII
    /// `a` to `z`, the rest is left as it is, and the parts are joined by one space.
    ///
    /// This is `StateText.titleCase` except that a non-ASCII first letter is left alone, so JavaScript and Swift cannot differ on a case mapping,
    /// and empty text stays empty (a lowering that wants `Unknown` for a missing state adds it with a rule).
    static func titleCase(_ text: String) -> String {
        text.split(separator: "_", omittingEmptySubsequences: false).map { part -> String in
            var scalars = String.UnicodeScalarView(part.unicodeScalars)
            guard let first = scalars.first, ("a"..."z").contains(first) else { return String(part) }
            scalars.replaceSubrange(scalars.startIndex..<scalars.index(after: scalars.startIndex),
                                    with: [Unicode.Scalar(first.value - 32)!])
            return String(scalars)
        }.joined(separator: " ")
    }
}
