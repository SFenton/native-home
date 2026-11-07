import SwiftUI

/// The volume slider's rules, shared with the UIKit slider (`UKTileVolumeSlider`); the SwiftUI view was removed. Presentational, no store (pattern: `.agents/patterns/action-tiles.md`).
///
/// A horizontal pan sets the level from where the finger is across the track; the level is written once, on release
/// (the main-thread invariant: a drag never sends a service call per frame). VoiceOver adjusts by ``step`` percent.
public enum TileVolumeSlider {
    /// The VoiceOver step, in percent.
    public nonisolated static let step = 5
    /// A shown level gives way to the live one after this long even if the server never echoes it.
    static let pendingTimeout: Duration = .seconds(4)

    /// The track's thickness inside the 44 pt target.
    public nonisolated static let trackHeight: CGFloat = 8

    // MARK: - Pure helpers

    /// `value` moved by `delta`, clamped to 0...100.
    public nonisolated static func stepped(_ value: Int, by delta: Int) -> Int {
        min(100, max(0, value + delta))
    }

    /// The level for a touch at `x` across a track `width` wide, clamped to 0...100.
    public nonisolated static func percent(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(100, max(0, Double(x / width) * 100))
    }

    /// The spoken value: "45 percent" (the media remote sheet says it the same way).
    public nonisolated static func spokenValue(percent: Int) -> String { "\(percent) percent" }

    /// The 10% step a drag is in, which ticks the haptic as it changes; nil when not dragging.
    nonisolated static func hapticStep(_ dragPercent: Double?) -> Int? {
        dragPercent.map { Int(($0 / 10).rounded(.down)) }
    }
}
