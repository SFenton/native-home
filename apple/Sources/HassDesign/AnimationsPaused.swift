import SwiftUI

public extension EnvironmentValues {
    /// Holds every continuous animation inside still: the ``ArcSpinner``s, the ``PendingValueBar`` pulse and the
    /// reconnecting chip. Only for galleries and UI tests: an animation that never stops keeps the app from ever going
    /// idle, so XCUITest waits out its idle timeout on every action and can lose the runner (iPad, 2026-10-14).
    @Entry var animationsPaused = false
}
