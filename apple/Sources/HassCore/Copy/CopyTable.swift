import Foundation
import os

/// Resolves user-facing copy by id: an inline prop first, then an override table, then the compiled catalog default.
///
/// The compiled defaults live in `Copy.xcstrings`, a package resource read at run time with
/// `Bundle.localizedString(forKey:value:table:)` because the ids are known only at run time (`String(localized:)` takes a literal).
/// Overrides come from a dictionary the caller supplies, so a host test builds a table with no bundle involved in that path.
///
/// Templates use `{{name}}` placeholders. A `count` argument selects `<id>_one` when the count is exactly 1 and `<id>_other`
/// otherwise (English only), in the override table and the catalog alike, so both share one resolver and one syntax.
///
/// This is the seed for the strings lane: it adds no contract, decoder or typed keys yet.
public final class CopyTable: Sendable {
    /// The catalog's table name (`Copy.xcstrings`).
    public static let tableName = "Copy"

    /// The table over the compiled defaults with no overrides.
    public static let standard = CopyTable()

    private let overrides: [String: String]
    private let bundle: Bundle
    private let recorded = OSAllocatedUnfairLock(initialState: [CopyDiagnostic]())

    /// Creates a table.
    /// - Parameters:
    ///   - overrides: Authored entries keyed by id (plural members as `id_one` and `id_other`); empty by default.
    ///   - bundle: The bundle holding the compiled catalog; `nil` means this package's resource bundle (`Bundle.module`).
    public init(overrides: [String: String] = [:], bundle: Bundle? = nil) {
        self.overrides = overrides
        self.bundle = bundle ?? .module
    }

    /// The faults recorded so far, in order and without repeats.
    public var diagnostics: [CopyDiagnostic] { recorded.withLock { $0 } }

    /// Resolves `id` and fills its placeholders.
    ///
    /// - Parameters:
    ///   - id: The copy id, such as `copy.sample.allClosed`.
    ///   - args: Values for `{{name}}` placeholders. A `count` entry also selects the plural member.
    ///   - inline: Text authored on the node itself; when present it wins and is filled like any template.
    ///   - fallback: Returned, unfilled, when no source knows the id. The fault is recorded.
    /// - Returns: The text to show.
    public func text(_ id: String, _ args: [String: String] = [:], inline: String? = nil, fallback: String) -> String {
        let template: String
        if let inline {
            template = inline
        } else if let found = lookup(id, count: args["count"]) {
            template = found
        } else {
            record(.missingKey(id))
            return fallback
        }
        return fill(template, id: id, args)
    }

    // MARK: - Lookup

    private func lookup(_ id: String, count: String?) -> String? {
        for key in Self.candidates(id, count: count) {
            if let value = overrides[key] { return value }
            let sentinel = "\u{0}missing"
            let value = bundle.localizedString(forKey: key, value: sentinel, table: Self.tableName)
            if value != sentinel { return value }
        }
        return nil
    }

    /// The keys to try, most specific first: the plural member for the count, then the bare id.
    private static func candidates(_ id: String, count: String?) -> [String] {
        guard let count, let number = Double(count) else { return [id] }
        return [number == 1 ? "\(id)_one" : "\(id)_other", id]
    }

    // MARK: - Interpolation

    private func fill(_ template: String, id: String, _ args: [String: String]) -> String {
        var text = template
        for (name, value) in args { text = text.replacingOccurrences(of: "{{\(name)}}", with: value) }
        if let open = text.range(of: "{{"), let close = text.range(of: "}}", range: open.upperBound..<text.endIndex) {
            record(.unfilledPlaceholder(id: id, name: String(text[open.upperBound..<close.lowerBound])))
        }
        return text
    }

    private func record(_ diagnostic: CopyDiagnostic) {
        recorded.withLock { if !$0.contains(diagnostic) { $0.append(diagnostic) } }
    }
}
