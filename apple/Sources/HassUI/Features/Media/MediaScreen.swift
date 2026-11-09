import HassCore
import HassDesign
import SwiftUI

/// One media tile: opens a remote, or runs its command. Direction G: dark with a pink glyph while off, filled
/// media pink while on (``ColorFamily/media``).
///
/// A remote is a navigation tile (*glyph · text · chevron*) with its actions from ``MediaTransportActions``: Power beside the
/// chevron while it is off or idle; previous / play-pause / next centred below the text, and a volume slider under them, while it
/// plays or is paused. The set changing shape animates the tile's height when it spans its row (``TileActionSetTransition``).
///
/// A Music Room source is a selection tile (check disc, ``SourceSelectActions``); Nintendo Switch and Cinema Streamer are action tiles
/// with a tracked power disc (``ScriptPowerActions``).
struct MediaCardTile {
    var card: MediaPageConfig.Card
    var controller: MediaRemoteController
    var caller: any HassServiceCalling
    /// The tile spans its whole row (a section's lead), so a change of action set may animate its height.
    var spansFullRow = false
    var openRemote: (MediaRemoteConfig) -> Void

    private var identifier: String { "media.card.\(Self.slug(card.section)).\(Self.slug(card.device.title))" }


    /// The discs a remote shows on a tile for its shown `state` (``MediaTransportActions``).
    static func specs(for remote: MediaRemoteConfig, state: EntityState?) -> [TileActionSpec] {
        MediaTransportActions(config: remote).actions(for: state)
    }




    /// The tile's icon and tap semantics for its current display.
    static func look(_ card: MediaPageConfig.Card, display: MediaRemoteController.DeviceDisplay) -> (symbol: String, kind: GlassTileKind) {
        let off = MediaRemoteState.isOff(display.state)
        let icon = off ? card.offIcon ?? card.device.icon : card.device.icon
        let kind: GlassTileKind = switch display.semantics {
        case .toggle: .toggle
        case .selection: .selection(isSelected: display.isActive)
        case .command, .state: .command
        }
        return (SymbolMap.symbol(for: icon), kind)
    }

    /// `Living Room Streamer` → `living-room-streamer`.
    static func slug(_ text: String) -> String {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    }
}
