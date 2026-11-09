#if os(iOS)
import HassDesign
import UIKit

/// A page of a sheet that hosts a content controller, with an optional bar pinned under it (``UKPagePinnedBar``, the one pinned-bar
/// component; owner 2026-10-31: every page a modal shows is a ``UKPageViewController``). `content` lives in
/// ``UKPageViewController/contentView``, so nothing runs under the folded Duo's rail; the bar sits in the page's view and its height
/// joins the page's safe area, which `content` inherits. Used by the sheets that have a section bar or a pinned action under content that
/// is its own controller. Title and subtitle are set on this page's `navigationItem`.
@MainActor
final class UKSheetPinnedBarPage: UKPageViewController {
    let content: UIViewController
    private let pinnedBar: UKPagePinnedBar?
    private let scrollView: UIScrollView?

    /// - Parameters:
    ///   - content: The page's content.
    ///   - bar: The bar; its height comes from its own layout. Nil hosts `content` alone (a sheet root that is not a page itself).
    ///   - scrollView: The content's scroll view: the page's scroll view (header fade, soft edge, scroll only when needed) and the bar's
    ///     scroll edge interaction.
    ///   - barMaterial: Whether before iOS 26 the bar sits on the bar material.
    init(content: UIViewController, bar: UIView?, scrollView: UIScrollView? = nil, barMaterial: Bool = false) {
        self.content = content
        self.scrollView = scrollView
        pinnedBar = bar.map { UKPagePinnedBar(bar: $0, scrollView: scrollView, barMaterial: barMaterial) }
        super.init(sheetTitle: content.title)
        navigationItem.title = content.navigationItem.title ?? content.title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        contentView.addSubview(content.view)
        content.view.ukPin(to: contentView)
        content.didMove(toParent: self)
        if let scrollView { setPageScrollView(scrollView) }
        pinnedBar?.install(in: self)
    }

    /// The scroll views a content controller builds after load (the hero and tabs columns, one or two by width). The right-hand column
    /// is the page's scroller (the header fade and scroll to top follow it); every column gets the page's scroll rules and soft edges.
    func setScrollers(_ scrolls: [UIScrollView]) {
        for scroll in scrolls {
            scroll.backgroundColor = .clear
            UKScrollFit.apply(to: scroll)
            UKHeaderEdgeFade.applySoftEdge(to: scroll)
        }
        setPageScrollView(scrolls.last)
        pinnedBar?.follow(scrolls.last)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pinnedBar?.layoutChanged()
    }
}
#endif
