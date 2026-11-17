import Foundation

// MARK: - Default tile ink (`sh.tile-ink-default@1`)

/// Which ink a dark tile face draws for an icon with no colour of its own and for its state line (`sh.tile-ink-default@1`, option A).
///
/// The capability has no field. A document that lists it draws the primary ink (white on a page and in a dark sheet, black in a light sheet); one
/// that does not draws the muted grey it always drew. The Studio lists the id in every document it compiles, and a manifest made before the id
/// existed is still the manifest of that document (`.agents/design/mockups/proposals/sim-fidelity-contract`, section 1).
public enum ServerUITileInkDefault: Sendable {
    /// The capability id.
    public static let capability = "sh.tile-ink-default@1"

    /// The grey every tile drew before the capability.
    case muted
    /// The primary ink.
    case primary

    /// The ink for a manifest.
    public static func declared(by capabilities: [String]) -> Self { capabilities.contains(capability) ? .primary : .muted }

    /// Whether `capabilities` is the manifest of a document that needs `requirements`: equal to them, or to them plus the ink id.
    static func matches(_ capabilities: [String], requirements: Set<String>) -> Bool {
        let needed = requirements.sorted()
        return capabilities == needed || capabilities == (requirements.union([capability])).sorted()
    }
}
