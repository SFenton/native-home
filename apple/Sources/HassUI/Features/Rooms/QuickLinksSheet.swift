import HassCore
import HassDesign
import SwiftUI

private extension QuickLink.Action {
    var isDetail: Bool {
        if case .detail = self { return true }
        return false
    }
}

/// One Quick Links tile (web `QuickLinkTile`): a solid colour per link with a filled white glyph and white text
/// (``QuickLinkPalette``); Security System's colour and glyph follow the alarm mode.
///
/// Every tile is a navigation tile with the chevron (owner, 2026-10-27). Security System also carries one disc left of it
/// (audit item 17; ``AlarmModeActions``): **Arm Home** while disarmed, **Disarm** (confirmed with today's alert) while armed, an arc
/// spinner while the panel is disarming. A tap on the disc goes through ``OptimisticActions`` like every call, so a
/// rejected call shows "Didn't Respond". While screenshots are redacted the disc is not drawn: its verb and glyph would give the alarm
/// mode away.
struct QuickLinkTile {
    var link: QuickLink
    /// Where the disc's call goes; nil draws no disc.
    var caller: (any HassServiceCalling)?
    var action: () -> Void = {}

    /// The fill a link takes (`.agents/design/direction-g.md`, Colour: Quick Links tiles). Security System follows the alarm
    /// mode, and is a neutral slate while redacted so screenshots don't show it.
    static func fill(_ link: QuickLink, alarmState: String?) -> UInt32? {
        QuickLinkPalette.fill(forLink: link.id, alarmState: alarmState, isRedacted: ScreenshotPrivacy.isRedacting)
    }

    /// The disc the tile carries: Security System's, when there is somewhere to send it and nothing to hide; else none.
    static func specs(_ link: QuickLink, alarm: EntityState?, canSend: Bool, isRedacting: Bool) -> [TileActionSpec] {
        guard TileActionCatalog.kind(of: link) == .alarmMode, canSend, !isRedacting else { return [] }
        return AlarmModeActions().actions(for: alarm)
    }

    /// The tile's accessibility identifier.
    static func identifier(_ link: QuickLink) -> String { "quickLinks.\(link.id)" }

}
