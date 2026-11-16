import Foundation

// MARK: - Light and dark colour pairs

/// Finds a light and dark colour pair (`solid-appearance { light, dark }`, `sh.solid-appearance@1`) anywhere in a document.
///
/// A document that holds one must declare the capability, so the manifest check needs to know without every slot reporting it: the pair
/// is allowed in a glyph, a fill, a rule case, a bound colour's fallback, a room card colour and a state style fill. What a `literal`
/// holds is data the author typed as text, never a colour slot, so it is skipped.
enum ServerUIAppearanceScan {
    /// The capability, without `sh.` and `@1`.
    static let capability = "solid-appearance"

    /// Whether `json` holds a pair outside any `literal`.
    static func holdsPair(_ json: JSONValue) -> Bool {
        switch json {
        case .object(let fields):
            if fields["type"] == .string("literal") { return false }
            if fields["type"] == .string("solid-appearance") { return true }
            return fields.values.contains(where: holdsPair)
        case .array(let items):
            return items.contains(where: holdsPair)
        default:
            return false
        }
    }
}
