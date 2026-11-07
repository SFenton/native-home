import CoreGraphics

/// The title display mode of a page. Owner, 2026-10-28: "Bring back the title collapse." Where the title sits below the bar
/// (`ShellChrome.titleInHeader == false`: iPhone, any iPad window including a compact one, the unfolded Duo, everywhere the
/// hamburger shows) the page has the system's large title, which collapses into the inline title as it scrolls, leading aligned
/// where the hamburger shows. Only the folded Duo's vertical bar (`titleInHeader == true`) shows the inline title from the
/// start (header-edge-fade R7).
enum PageChromeTitle {
    /// Whether the page has a large title that collapses on scrolling.
    static func collapses(titleInHeader: Bool) -> Bool { !titleInHeader }
}

/// How a page's title is drawn in the navigation bar (pure, so it is unit tested).
///
/// On the iPhone Duo's vertical bar (the folded outer display, and the inner display in landscape) the system's inline title is
/// small and its bar minimises while a page scrolls, which takes the title with it. A page here is navigation-focused, so the bar
/// stays and the title stays with it, at one medium size the system never shrinks (header-edge-fade R7 (6), owner 2026-10-29).
/// Every other window keeps the system's own title untouched (owner, 2026-10-30: "Unfolded portrait should just use the normal
/// iPhone style title. Unfolded landscape/partial landscape should use 24pt").
enum BarTitleTreatment: Equatable {
    /// The system's title: large and collapsing, or the plain inline title.
    case system
    /// A fixed medium inline title that never collapses, in a bar that never minimises (the Duo's vertical bar).
    case fixedMedium

    /// Owner, 2026-10-29: "Yes, 24 is the right font." Points at the default text size.
    static let pointSize: CGFloat = 24
    /// The most the title grows with Dynamic Type, so a long title still fits beside the header buttons at AX5.
    static let maximumPointSize: CGFloat = 30

    /// The treatment for a window.
    static func resolve(inVerticalBar: Bool) -> BarTitleTreatment { inVerticalBar ? .fixedMedium : .system }

    /// Whether the page's title collapses from a large title into the bar: never on the vertical bar, else as the system decides.
    static func collapses(inVerticalBar: Bool, titleInHeader: Bool) -> Bool {
        PageChromeTitle.collapses(titleInHeader: titleInHeader || resolve(inVerticalBar: inVerticalBar) == .fixedMedium)
    }
}
