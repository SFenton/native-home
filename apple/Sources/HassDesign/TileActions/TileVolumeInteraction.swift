import SwiftUI

/// The slider's interaction state, apart from the view so drag, release and adjust are unit-testable. Like ``BrightnessInteraction``,
/// but it only ever yields a level (no power), and nothing is sent until a drag ends.
struct TileVolumeInteraction: Equatable {
    var dragPercent: Double?
    var pendingPercent: Int?
    var dragAxis: BrightnessInteraction.DragAxis?

    /// The level to draw: the drag in progress, else the level just committed, else `live`.
    func shown(live: Int) -> Int {
        if let dragPercent { return Int(dragPercent.rounded()) }
        return pendingPercent ?? live
    }

    /// The first movement picks the axis; only a horizontal drag sets the level. Nothing is sent.
    mutating func dragChanged(translation: CGSize, x: CGFloat, width: CGFloat) {
        if dragAxis == nil { dragAxis = abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical }
        guard dragAxis == .horizontal else { return }
        dragPercent = TileVolumeSlider.percent(atX: x, width: width)
    }

    /// Release: a horizontal drag commits the level under the finger, once; a vertical one does nothing.
    mutating func dragEnded(x: CGFloat, width: CGFloat, live: Int) -> Int? {
        defer { dragAxis = nil }
        guard dragAxis == .horizontal, dragPercent != nil else { return nil }
        dragPercent = nil
        return commit(Int(TileVolumeSlider.percent(atX: x, width: width).rounded()), live: live)
    }

    /// The system took the touch: drop the drag without committing.
    mutating func dragCancelled() {
        dragAxis = nil
        dragPercent = nil
    }

    /// VoiceOver adjust by `delta` percent, clamped; nil when nothing changes. Each step commits once.
    mutating func adjust(by delta: Int, live: Int) -> Int? {
        commit(TileVolumeSlider.stepped(shown(live: live), by: delta), live: live)
    }

    private mutating func commit(_ value: Int, live: Int) -> Int? {
        guard value != shown(live: live) else { return nil }
        pendingPercent = value
        return value
    }
}
