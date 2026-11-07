#if os(iOS)
import ObjectiveC
import UIKit

/// A page scrolls only once its content outgrows it: the UIKit counterpart of ``SwiftUICore/View/scrollsOnlyWhenNeeded()``
/// (`.agents/patterns/scroll-fit.md`). A scroll view that fits its content neither bounces nor answers a drag, so a short
/// page no longer stretches and snaps back; the decision is geometry, never a device check.
@MainActor
enum UKScrollFit {
    /// Applies the rule to a vertical scroll view. `UIScrollView` bounces vertically only when its content is taller than the
    /// view while `alwaysBounceVertical` is off, which is the rule; `UICollectionView` and `UITableView` default it on in
    /// some configurations, so it is switched off here.
    static func apply(to scrollView: UIScrollView) {
        scrollView.alwaysBounceVertical = false
        UKScrollRate.attach(to: scrollView)
        pinWidth(of: scrollView)
    }

    /// A page body never scrolls sideways (owner, 2026-11-01: Settings could be dragged horizontally in the split): no horizontal bounce
    /// or indicator, and any horizontal offset a layout transient leaves is put back at once. The width of the content itself is the
    /// page's to pin to the frame (`contentLayoutGuide` width = `frameLayoutGuide` width, or a frame-set content size of the frame's
    /// width); this is the backstop that makes it impossible for a page to forget.
    static func pinWidth(of scrollView: UIScrollView) {
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        guard objc_getAssociatedObject(scrollView, &lockKey) == nil else { return }
        let token = scrollView.observe(\.contentOffset, options: [.new]) { scroll, _ in
            MainActor.assumeIsolated {
                let rest = -scroll.adjustedContentInset.left
                if abs(scroll.contentOffset.x - rest) > 0.5 { scroll.contentOffset.x = rest }
            }
        }
        objc_setAssociatedObject(scrollView, &lockKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private nonisolated(unsafe) static var lockKey = 0

    /// The exception: a scroll view that pulls to refresh always bounces (`pullToRefresh`).
    static func allowsPullToRefresh(_ scrollView: UIScrollView) {
        scrollView.alwaysBounceVertical = true
        UKScrollRate.attach(to: scrollView)
    }
}
#endif
