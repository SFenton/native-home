#if os(iOS)
import HassDesign
import UIKit

/// The title of a page that is shown in a column (``UKColumnsViewController``): a large, left-aligned heading at the top of the page's
/// content, in the style of the system large title, that scrolls away with the content (owner, 2026-11-02). The section's bar spans
/// both columns and carries the page header, so a column page never sets a bar title. One component for every column page
/// (``UKPageViewController`` attaches it by itself while the page is a child of the columns).
///
/// The page's top additional safe area makes room for the heading, so every page body (a scroll view the system insets, or a short
/// page that lays out from the safe area) starts below it. The heading is a subview of the page's content, parked in that room and
/// moved up with the scroll view's offset (and faded as it goes, so it never crosses the header). Its height depends only on the
/// text style, so nothing here feeds layout.
@MainActor
final class UKColumnTitleHeader: UILabel {
    private weak var scroll: UIScrollView?
    private weak var page: UIViewController?
    private var reserved: CGFloat = 0
    private var offsetObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .ukFont(.largeTitle, weight: .bold)
        adjustsFontForContentSizeCategory = true
        textColor = UKDesignInk.primary
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.6
        accessibilityTraits = .header
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var height: CGFloat { ceil(font.lineHeight) + HassTokens.Spacing.m }

    /// Puts the heading in `host` (the page's content view), tracking `scroll`, with `title` as its text.
    func attach(to scroll: UIScrollView, in page: UIViewController, host: UIView, title: String?) {
        text = title
        isHidden = title == nil
        guard self.scroll !== scroll else { place(); return }
        detach()
        self.scroll = scroll
        self.page = page
        reserved = height
        page.additionalSafeAreaInsets.top += reserved
        host.addSubview(self)
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.place() }
        }
        place()
    }

    /// Takes the heading and its room away.
    func detach() {
        guard scroll != nil else { return }
        offsetObservation = nil
        page?.additionalSafeAreaInsets.top -= reserved
        reserved = 0
        removeFromSuperview()
        scroll = nil
        page = nil
    }

    /// Parks the heading in its room and moves it with the scroll offset (call from the page's layout; it writes no inset).
    func place() {
        guard let scroll, let page, let host = superview, reserved > 0 else { return }
        let scrolled = max(0, scroll.contentOffset.y + scroll.adjustedContentInset.top)
        let top = page.view.safeAreaInsets.top - reserved
        frame = CGRect(x: UKPageMetrics.side, y: top - scrolled, width: max(0, host.bounds.width - 2 * UKPageMetrics.side), height: reserved)
        alpha = max(0, 1 - scrolled / reserved)
    }
}

/// What the column group of a bar shows (``UKColumnBarHosting``).
struct UKColumnBar {
    enum Kind { case none, close, back }
    /// The open page's own bar items, leading to trailing, before the Back or Close item.
    var items: [UIBarButtonItem] = []
    var kind: Kind = .none
    /// False while the open page holds itself open (a save in flight): the item is dimmed and does nothing.
    var isEnabled = true
    /// What Back or Close does.
    var perform: () -> Void = {}
}

/// Anything that owns a navigation bar and can show a column group beside the shell's items (``UKPageViewController``).
@MainActor
protocol UKColumnBarHosting: AnyObject {
    /// Sets the column group, or nil when the window shows no columns. The group is one stable leading group holding a single Back or
    /// Close item: it appears, disappears and changes between Back and Close by hiding and restyling that item inside the page's
    /// motion, so the bar (the Duo's vertical bar too) animates it instead of swapping groups.
    func setColumnBar(_ bar: UKColumnBar?)
}
#endif
