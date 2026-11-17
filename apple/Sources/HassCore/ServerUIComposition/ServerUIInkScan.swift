import Foundation

// MARK: - Opacity in a colour

/// Finds an `rgba` colour anywhere in a document (`sh.text-style@1`).
///
/// A document that holds one must declare the capability, so the manifest check needs to know without every slot reporting it. What a
/// `literal` holds is data the author typed as text, never a colour slot, so it is skipped. A slot that existed before the id refuses an
/// `rgba` in the shape, so only the slots the id adds can reach the manifest check.
enum ServerUIInkScan {
    /// Whether `json` holds an `rgba` outside any `literal`.
    static func holdsRGBA(_ json: JSONValue) -> Bool {
        switch json {
        case .object(let fields):
            if fields["type"] == .string("literal") { return false }
            if fields["type"] == .string("rgba") { return true }
            return fields.values.contains(where: holdsRGBA)
        case .array(let items):
            return items.contains(where: holdsRGBA)
        default:
            return false
        }
    }
}
