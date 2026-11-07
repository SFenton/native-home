import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A dimmable light tile (web `LightBrightnessCard.tsx`, pattern: `.agents/patterns/entity-tile.md`), the light
/// dragger of direction G (`.agents/design/direction-g.md`, Controls).
///
/// Drawn as the warm lit tile whose bright band is the brightness. While dragging, the tile lifts, a "30%" bubble
/// floats over the band's edge and a selection haptic ticks every 10%. It is an action tile with a `power` disc (tap flips power),
/// or, when ``onOpen`` is set, a navigation tile that opens the light's details (web `tapAction: 'more-info'`) with the same disc
/// left of its chevron. A horizontal drag sets brightness from where the finger is across the body and commits on release, as on
/// the web; a vertical drag is left to the scroll view. VoiceOver activates the tap and swipes up or down to step brightness by
/// ``step``; the disc is its own button when the body opens details.
///
/// The SwiftUI tile was removed with the SwiftUI app; this keeps the rules the UIKit tile (`UKBrightnessTileView`) shares.
public enum BrightnessTile {
    /// VoiceOver adjust step, in percent.
    public nonisolated static let step = 10
    /// Optimistic values give way to live state after this long even if the server never echoes them.
    public static let pendingTimeout: Duration = .seconds(4)

    /// The tile's one action: a `power` disc, toggle-styled (owner, 2026-10-27, lights and switches use `power`), optimistic. A
    /// tile that opens details and is unavailable has none; an action tile keeps it, dimmed in place (``phase``).
    ///
    /// HassDesign has no HassCore dependency, so this is the item `PowerToggleActions.entity` yields, field for field (a HassUI
    /// test holds the two together).
    nonisolated static func powerItem(percent: Int, isUnavailable: Bool) -> TileActionItem {
        TileActionItem(id: powerId, verb: percent > 0 ? "Turn Off" : "Turn On", symbol: "power", isOn: percent > 0,
                       phase: isUnavailable ? .unavailable : .ready, feedback: .optimistic)
    }

    /// The disc's (and the tile's) action id: `<tile-id>.action.power`.
    public nonisolated static let powerId = "power"

    /// The discs the tile carries (none for an unavailable tile that opens details).
    nonisolated static func items(percent: Int, isUnavailable: Bool, opensDetails: Bool) -> [TileActionItem] {
        opensDetails && isUnavailable ? [] : [powerItem(percent: percent, isUnavailable: isUnavailable)]
    }

    /// The power disc's spoken label: what it will do.
    public nonisolated static func powerLabel(title: String, percent: Int) -> String {
        percent > 0 ? "Turn Off \(title)" : "Turn On \(title)"
    }

    /// The VoiceOver hint on the body: what a double-tap does, then how to adjust. Empty while unavailable.
    public nonisolated static func hint(percent: Int, isUnavailable: Bool, opensDetails: Bool) -> String {
        if isUnavailable { return "" }
        let tap = opensDetails ? "Double-tap for details." : "Double-tap to turn \(percent > 0 ? "off" : "on")."
        return tap + " Swipe up or down to adjust brightness."
    }

    /// Every state line the tile can show, so the grid sizes it for the longest and a live change never re-spans it.
    nonisolated static let stateCandidates = ["Off", "100%", "Unavailable"]

    // MARK: - Pure helpers

    /// Percent for a touch at `x` across a tile `width` wide, clamped to 0...100.
    public nonisolated static func percent(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(100, max(0, Double(x / width) * 100))
    }

    /// `value` moved by `delta`, clamped to 0...100.
    public nonisolated static func stepped(_ value: Int, by delta: Int) -> Int {
        min(100, max(0, value + delta))
    }

    /// The 10% step a drag is in, which ticks the haptic as it changes; nil when not dragging.
    public nonisolated static func hapticStep(_ dragPercent: Double?) -> Int? {
        dragPercent.map { Int(($0 / 10).rounded(.down)) }
    }

    /// Where the % bubble's centre sits across a tile `width` wide: over the band's edge, kept inside the tile.
    public nonisolated static func bubbleCenter(percent: Int, width: CGFloat) -> CGFloat {
        let half = BrightnessBubble.width / 2
        guard width > BrightnessBubble.width else { return width / 2 }
        return min(width - half, max(half, width * CGFloat(percent) / 100))
    }

    /// The tile's status line and accessibility value: `Off`, `45%` or `Unavailable`.
    public nonisolated static func status(percent: Int, isUnavailable: Bool) -> String {
        if isUnavailable { return "Unavailable" }
        return percent > 0 ? "\(percent)%" : "Off"
    }
}

/// The "30%" bubble that floats over the band's edge while dragging. VoiceOver hears the tile's value instead.
public enum BrightnessBubble {
    /// The bubble's width, wide enough for "100%".
    public nonisolated static let width: CGFloat = 60
    /// The bubble's height.
    public nonisolated static let height: CGFloat = 32
    /// How far above the tile's top edge the bubble's centre sits.
    public nonisolated static let lift: CGFloat = 24
}

/// The tile's interaction state, kept apart from the view so tap, drag and adjust are unit-testable.
///
/// It holds the drag in progress and the optimistic value shown until Home Assistant reports back,
/// and turns gestures into the intents the tile passes to its caller.
public struct BrightnessInteraction: Equatable {
    /// What the user asked for.
    public enum Intent: Equatable {
        case power(Bool)
        case brightness(Int)
    }

    public enum DragAxis { case horizontal, vertical }

    public var dragPercent: Double?
    public var pendingPercent: Int?
    public var dragAxis: DragAxis?

    public init() {}

    /// The percent to draw: the drag in progress, else the optimistic value, else `live`.
    public func shown(live: Int) -> Int {
        if let dragPercent { return Int(dragPercent.rounded()) }
        return pendingPercent ?? live
    }

    /// Tap: off turns on (optimistically full until the restored level arrives), on turns off.
    public mutating func flip(live: Int, isUnavailable: Bool) -> Intent? {
        guard !isUnavailable else { return nil }
        let on = shown(live: live) == 0
        pendingPercent = on ? 100 : 0
        return .power(on)
    }

    /// VoiceOver adjust by `delta` percent, clamped; `nil` when nothing changes.
    public mutating func adjust(by delta: Int, live: Int, isUnavailable: Bool) -> Intent? {
        guard !isUnavailable else { return nil }
        return commit(BrightnessTile.stepped(shown(live: live), by: delta), live: live)
    }

    /// The first movement picks the axis; only a horizontal drag sets the level.
    public mutating func dragChanged(translation: CGSize, x: CGFloat, width: CGFloat) {
        if dragAxis == nil {
            dragAxis = abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
        }
        guard dragAxis == .horizontal else { return }
        dragPercent = BrightnessTile.percent(atX: x, width: width)
    }

    /// Release: a horizontal drag commits the level under the finger; a vertical one does nothing.
    public mutating func dragEnded(x: CGFloat, width: CGFloat, live: Int) -> Intent? {
        defer { dragAxis = nil }
        guard dragAxis == .horizontal, dragPercent != nil else { return nil }
        dragPercent = nil
        return commit(Int(BrightnessTile.percent(atX: x, width: width).rounded()), live: live)
    }

    /// The system took the touch (a scroll won, or the tile went away): drop the drag without committing.
    public mutating func dragCancelled() {
        dragAxis = nil
        dragPercent = nil
    }

    private mutating func commit(_ value: Int, live: Int) -> Intent? {
        guard value != shown(live: live) else { return nil }
        pendingPercent = value
        return .brightness(value)
    }
}
