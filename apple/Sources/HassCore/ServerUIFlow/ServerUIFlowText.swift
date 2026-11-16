import Foundation

// MARK: - Text and number rules a flow defines for itself

/// The text and number rules of a Data Flow, defined once because JavaScript and Swift disagree on them (pinned by the shared corpus
/// `pipelines/divergence-*`): strings are equal when their NFC forms are equal and ordered by the scalar values of their NFC forms; a
/// number prints as Swift prints a `Double`, except that a whole number below 1e15 has no `.0`; a tie rounds away from zero.
public enum ServerUIFlowText {
    /// NFC equality, which is Swift's `String ==`.
    public static func equals(_ a: String, _ b: String) -> Bool { a == b }

    /// Orders by the Unicode scalar values of the NFC forms: `-1`, `0` or `1`.
    public static func compare(_ a: String, _ b: String) -> Int {
        let x = Array(a.precomposedStringWithCanonicalMapping.unicodeScalars), y = Array(b.precomposedStringWithCanonicalMapping.unicodeScalars)
        for (left, right) in zip(x, y) where left != right { return left.value < right.value ? -1 : 1 }
        return x.count == y.count ? 0 : x.count < y.count ? -1 : 1
    }

    /// Whether `a` sorts before `b` by raw scalar values (names in a shape print the same everywhere).
    static func scalarsPrecede(_ a: String, _ b: String) -> Bool {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        for (left, right) in zip(x, y) where left != right { return left.value < right.value }
        return x.count < y.count
    }

    /// A number as Swift prints a `Double`, except that a whole number below 1e15 has no `.0`; negative zero prints as `0`.
    public static func numberText(_ number: Double) -> String {
        if number == 0 || !number.isFinite { return "0" }
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }

    /// A scalar as text: strings as they are, numbers as ``numberText(_:)``, booleans as `true` and `false`; anything else has none.
    public static func scalarText(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number): number.isFinite ? numberText(number) : nil
        case .bool(let flag): flag ? "true" : "false"
        default: nil
        }
    }

    /// The identity of a key for `group` and `unique`: its kind and text, so `1` and `"1"` differ and equal strings agree under NFC.
    /// `null` and anything that is not a scalar are one key.
    static func identity(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): "s" + text.precomposedStringWithCanonicalMapping
        case .number(let number): "n" + numberText(number)
        case .bool(let flag): "b\(flag)"
        default: "z"
        }
    }
}
