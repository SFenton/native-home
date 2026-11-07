#if os(iOS)
import UIKit

/// The fallback for a second tap on the selected tab when the page does not name its scroll view (``ScrollToTopBridge``): the
/// largest visible vertical scroll view in the page.
enum UKScrollToTop {
    @MainActor
    static func mainScrollView(in root: UIView) -> UIScrollView? {
        guard let window = root.window else { return nil }
        var best: (view: UIScrollView, area: CGFloat)?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            guard let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01 else { continue }
            let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
            guard visible.width > 200, visible.height > 200,
                  scroll.contentSize.height > scroll.bounds.height + 1 || scroll.alwaysBounceVertical else { continue }
            let area = visible.width * visible.height
            if best == nil || area > best!.area { best = (scroll, area) }
        }
        return best?.view
    }
}
#endif
