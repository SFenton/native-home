import SwiftUI

public extension EnvironmentValues {
    /// Whether the page the view is on is being scrolled; a ticker holds still meanwhile (`.agents/design/motion.md` §9.10).
    /// Set by ``SwiftUICore/View/pausesTickersWhileScrolling()``.
    @Entry var pageIsScrolling = false
    /// Whether the view's section is on screen; a ticker holds still behind another tab. True outside the shell.
    @Entry var tickerIsOnScreen = true
}


