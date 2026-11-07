import SwiftUI

// MARK: - Geometry

/// Geometry of the fade that keeps scrolling content out from under a page or modal header
/// (pattern: `.agents/patterns/header-edge-fade.md`; owner, 2026-10-13: "Headers should not have the
/// translucent background behind them in pages or modals. Content should fade as it scrolls up to the
/// headers.").
///
/// Ported from FestivalNativeApps' `ModalTopEdgeFade` (`apple/Sources/FestivalUI/Design/ModalTopEdgeFade.swift`):
/// the header (the navigation bar: title, Close, toolbar items) has no band of its own. Content is fully
/// transparent at the header's bottom edge and fades back in over ``rampHeight`` points below it. At rest
/// (scrolled to the top) nothing is dimmed; the fade grows with the first ``rampHeight`` points of scrolling.
public enum HeaderEdgeFade {
    /// Height of the fade below the header (FestivalNativeApps `ScrollEdgeFade.topDistance`, the web
    /// `useScrollMask` `DEFAULT_SIZE` of 40 px).
    public static let rampHeight: CGFloat = 40

    /// Header height from the content's two readings.
    ///
    /// A full-bleed `List` reaches under the bar, so the header is its top safe-area inset and the container
    /// offset is 0. Content laid out below the bar is offset from the container's top by the header and still
    /// reports the same inset, so the readings are not added: the larger one is the header in both layouts.
    ///
    /// - Parameters:
    ///   - safeAreaInset: The content's top safe-area inset.
    ///   - containerOffset: How far the content's top sits below the container's top.
    /// - Returns: The header height; 0 for negative or non-finite readings.
    public static func headerHeight(safeAreaInset: CGFloat, containerOffset: CGFloat) -> CGFloat {
        let readings = [safeAreaInset, containerOffset].filter(\.isFinite)
        return max(0, readings.max() ?? 0)
    }

    /// Where the inline navigation bar ends, for ``clearHeight(header:smallestInset:cap:)``.
    ///
    /// - Parameters:
    ///   - statusTop: The window's top safe-area inset (the status bar region).
    ///   - barHeight: A compact navigation bar's height.
    ///   - barIsRail: The system moved the bar into the iPhone Duo's trailing vertical rail (folded, outer display), so
    ///     no horizontal bar sits above the content and the cleared band is the status region only
    ///     (duo-ipad-fold-layout, decided 2026-10-24).
    /// - Returns: The cap; nil before the status region has been measured.
    public static func edgeCap(statusTop: CGFloat, barHeight: CGFloat, barIsRail: Bool) -> CGFloat? {
        guard statusTop > 0 else { return nil }
        return barIsRail ? statusTop : statusTop + barHeight
    }

    /// The band kept clear above the content: the header, but never a page's large title.
    ///
    /// On iOS 26 an expanded large title is drawn with the page's content and counts toward its top inset, so
    /// clearing the whole inset hid the title. The band stops at the inline bar's bottom edge instead: the
    /// smallest inset seen so far (the bar once the title has collapsed) or the window's estimate
    /// (``SwiftUI/EnvironmentValues/headerEdgeCap``), whichever is lower. The large title then fades under the
    /// bar with the rest of the content.
    ///
    /// - Parameters:
    ///   - header: The full header from ``headerHeight(safeAreaInset:containerOffset:)``.
    ///   - smallestInset: The smallest top inset seen on this page; nil before the first reading.
    ///   - cap: The window's estimate of the inline bar's bottom edge; nil where unknown.
    /// - Returns: The height to keep clear, at most `header`.
    public static func clearHeight(header: CGFloat, smallestInset: CGFloat?, cap: CGFloat?) -> CGFloat {
        let limits = [smallestInset, cap].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }
        return max(0, min(header, limits.min() ?? header))
    }

    /// How far the fade has grown.
    ///
    /// - Parameters:
    ///   - scrollOffset: Distance scrolled from the content's resting top (content offset plus top inset);
    ///     negative while pulled down past the top.
    ///   - rampHeight: The ramp's height; 0 is a hard edge as soon as the content scrolls.
    /// - Returns: 0 at rest or pulled down, rising linearly to 1 after `rampHeight` points; 0 for a
    ///   non-finite reading.
    public static func progress(scrollOffset: CGFloat, rampHeight: CGFloat = rampHeight) -> CGFloat {
        guard scrollOffset.isFinite else { return 0 }
        guard rampHeight > 0 else { return scrollOffset > 0 ? 1 : 0 }
        return min(max(scrollOffset / rampHeight, 0), 1)
    }

    /// Mask opacity at the header's bottom edge, where the ramp starts. Above the edge the mask is always
    /// clear, so content never shows under the header.
    ///
    /// - Parameter progress: The fade's growth from ``progress(scrollOffset:rampHeight:)``.
    /// - Returns: 1 at rest (content just below the header fully drawn), 0 once scrolled a full ramp.
    public static func edgeOpacity(progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 1 }
        return 1 - min(max(progress, 0), 1)
    }

    /// The offset the fade tracks, from a scroll view's own readings: whole points, clamped to the ramp so only changes that
    /// move the mask are ever reported.
    ///
    /// - Parameters:
    ///   - contentOffset: The scroll view's vertical content offset.
    ///   - topInset: Its top content inset (the bar the content rests below).
    ///   - rampHeight: The ramp's height.
    /// - Returns: The distance scrolled from the resting top, -1 when pulled down, at most `rampHeight + 1`.
    public static func trackedOffset(contentOffset: CGFloat, topInset: CGFloat, rampHeight: CGFloat = rampHeight) -> CGFloat {
        min(max((contentOffset + topInset).rounded(), -1), rampHeight + 1)
    }

    /// The ramp for the reader's settings: Reduce Transparency or Increase Contrast turns it into a hard edge
    /// (content cut cleanly at the header, never dimmed; FestivalNativeApps scroll-edge R7).
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency.
    ///   - increaseContrast: System Increase Contrast.
    ///   - tracksScroll: The system reports the scroll position (iOS 18 and later); without it the ramp
    ///     could not grow from zero at rest, so it is a hard edge.
    /// - Returns: ``rampHeight`` or 0.
    public static func ramp(reduceTransparency: Bool, increaseContrast: Bool, tracksScroll: Bool) -> CGFloat {
        reduceTransparency || increaseContrast || !tracksScroll ? 0 : rampHeight
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The window's estimate of where the inline navigation bar ends (status bar plus a compact bar), so a page's
    /// expanded large title is not taken for header (``HeaderEdgeFade/clearHeight(header:smallestInset:cap:)``).
    /// Set by the app's root; nil keeps the whole measured header clear.
    @Entry public var headerEdgeCap: CGFloat?
}
