import Foundation

// MARK: - Text case

/// The letter case a `format` argument can ask for (`formats[name] = { text: { case: "title" } }`, `sh.pipeline-operands@1`).
public enum ServerUITextCase: String, Sendable, CaseIterable {
    /// `armed_away` is `Armed Away`, `heat cool` is `Heat cool`.
    case title

    /// `text` in this case.
    public func apply(to text: String) -> String {
        switch self {
        case .title: Self.titleCase(text)
        }
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
