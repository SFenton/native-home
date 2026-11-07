import SwiftUI

extension EnvironmentValues {
    /// A test seam: forces Reduce Motion on or off for the views below. The system setting is read-only in SwiftUI
    /// (`accessibilityReduceMotion` has no setter), so a hosted test cannot reach the Reduce Motion paths of ``GlassTile``,
    /// ``TickerLabel`` or the disc glyph swap otherwise. Nothing in the app sets it; nil follows the system.
    @Entry var reduceMotionOverride: Bool?
}
