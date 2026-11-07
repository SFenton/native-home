import Foundation

/// Counted nouns that agree with their number ("1 sensor", "3 sensors").
///
/// The app has no String Catalog yet (localization is deferred), and Foundation's `^[\(n) item](inflect: true)` does not
/// resolve outside a running app (host tests print it unchanged), so this is the one place that decides the plural. When
/// localization lands it becomes a String Catalog variation and the call sites stay.
public enum PluralCopy {
    /// `count` followed by `singular` when it is exactly one, else by `plural` (default: `singular` plus "s").
    ///
    /// - Parameters:
    ///   - count: How many.
    ///   - singular: The noun for one ("room").
    ///   - plural: The noun for any other count; defaults to `singular + "s"`.
    public static func count(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(noun(count, singular, plural: plural))"
    }

    /// Just the noun that agrees with `count` ("sensor" for one, "sensors" otherwise).
    public static func noun(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        count == 1 ? singular : (plural ?? singular + "s")
    }
}
