import Foundation

/// The disc of a tile that *chooses* (owner, 2026-10-27, option C of selection-tiles): vacuum rooms and Solo Trip travelers.
///
/// **Not a provider.** The choice lives in a controller that already owns it (the vacuum's room order, the Solo Trip traveler), so
/// there is no entity to read: the feature hands the position or the flag to these builders, which return the spec the
/// tile draws. A spec built here has no ``TileActionSpec/call``; the body and the disc both run the feature's own toggle.
///
/// | choice | symbol | selection |
/// |---|---|---|
/// | single, chosen | `checkmark` | ``TileActionSpec/Selection/single(isSelected:)`` true |
/// | single, not chosen | `circle` | false |
/// | ordered, chosen at place n | the number n (the disc draws it) | ``TileActionSpec/Selection/ordered(position:)`` n |
/// | ordered, not chosen | `circle` | position nil |
public enum SelectionActions {
    /// The action's id.
    public static let actionId = "select"

    /// One of several, chosen or not. `isEnabled` false dims the disc in place (a traveler's tile while a trip runs).
    public static func single(isSelected: Bool, isEnabled: Bool = true, label: String? = nil) -> TileActionSpec {
        TileActionSpec(id: actionId, verb: isSelected ? "Deselect" : "Select", symbol: isSelected ? "checkmark" : "circle",
                       phase: isEnabled ? .ready : .unavailable, feedback: .optimistic, label: label, selection: .single(isSelected: isSelected))
    }

    /// One of an ordered set. `position` is the 1-based cleaning order, nil when not chosen.
    public static func ordered(position: Int?, isEnabled: Bool = true, label: String? = nil) -> TileActionSpec {
        let place = position.flatMap { $0 > 0 ? $0 : nil }
        return TileActionSpec(id: actionId, verb: place == nil ? "Select" : "Deselect", symbol: place.map { "\($0).circle" } ?? "circle",
                              phase: isEnabled ? .ready : .unavailable, feedback: .optimistic, label: label, selection: .ordered(position: place))
    }

    /// The spoken order for an ordered choice: "Cleans 1st", "Not included" (the mockup's subtitles, as words).
    public static func orderText(_ position: Int?) -> String {
        guard let position, position > 0 else { return "Not included" }
        let suffix: String
        switch position % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch position % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "Cleans \(position)\(suffix)"
    }
}
