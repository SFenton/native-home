import SwiftUI

public extension EnvironmentValues {
    /// Whether the values behind the tiles have not arrived yet (`EntityStore.hasReceivedFirstState` is false): the first
    /// sign-in on a phone, before the disk snapshot exists and before Home Assistant has sent its first full set. Tiles and ``StatusPill``s keep their names and draw a soft
    /// ``PendingValueBar`` where the value goes (no full-screen spinner anywhere). False everywhere else, including a
    /// relaunch, which draws the snapshot's values at once.
    @Entry var valuesPending = false
}

/// The soft placeholder where a tile's value will go until live data lands (owner, 2026-10-17).
///
/// A rounded bar about the width of a short value that breathes between 35% and 100% of a soft white (1.4 s, one repeating animation). It sizes itself to
/// the tile's value line (`footnote`), so the tile does not change height when the value arrives. With Reduce Motion it
/// holds still half way, because a loop of movement or light is what the setting asks to avoid. Hidden from
/// accessibility: the tile's value reads "Loading".
public enum PendingValueBar {
    /// Seconds for the bar to breathe in and out.
    public nonisolated static let period: TimeInterval = 1.4
}
