import SwiftUI

/// The discs of a tile, laid out in a row: trailing (vertically centred, placed by ``GlassTile``) or below the text (centred).
///
/// One ``TapCounter`` serves the strip: every disc plays ``TapFeedback/tap`` when tapped and nothing later (tap-feedback
/// pattern: no success haptic). Each disc is a real `Button` labelled "verb title" ("Unlock Front Door"); only a toggle-styled
/// disc carries `.isToggle` and an On/Off value; identifiers are `<tile-id>.action.<item.id>`.
enum TileActionStrip {
    // MARK: Accessibility

    /// "Unlock Front Door", or the item's own whole label ("Turn Off TV").
    static func label(for item: TileActionItem, title: String) -> String { item.label ?? "\(item.verb) \(title)" }

    /// A toggle-styled disc is a toggle; a chosen selection disc is "selected" and never a switch.
    static func traits(for item: TileActionItem) -> AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if item.selection == nil, item.isOn != nil { traits.formUnion(.isToggle) }
        if item.selection?.isSelected == true { traits.formUnion(.isSelected) }
        return traits
    }

    /// On or Off for a toggle; the selection face speaks through its trait, so no value.
    static func value(for item: TileActionItem) -> String {
        guard item.selection == nil, let isOn = item.isOn else { return "" }
        return isOn ? "On" : "Off"
    }
}
