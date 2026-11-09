#if os(iOS)
import UIKit

/// Gives a screen that is not a ``UKPageViewController`` the page chrome anyway, with the screen's view filling
/// ``UKPageViewController/contentView``.
///
/// **On the wallpaper** the shell wraps what ``UKScreens`` returns in it, so a screen that has not been ported yet
/// (``UKPlaceholderViewController``) and a plain controller look like every other page: the wallpaper, the header buttons, the title and
/// the fade. The largest scroll view the screen shows becomes the page's scroll view once it is on screen.
///
/// **In a sheet** (``sheetWrapped(_:)``, owner 2026-10-31): ``UKHassModalController`` wraps every root and every pushed controller that is
/// not already a page, so nothing in a sheet can pin to the page's own edges and run under the folded Duo's rail
/// (``UKPageViewController/contentView`` is inset by the side safe areas). The hosted controller keeps everything else it had:
/// - its title and `navigationItem` bar items, back button and title view are mirrored onto the host's, which is what the sheet's
///   navigation bar reads (the modal's Close is added to the host);
/// - ``UKSheetFitting`` is forwarded, so a fitted sheet measures the same scroller and header it did unhosted;
/// - its scroll view is not taken over (no fade, no scroll-fit rule): it scrolls and bounces as it did.
final class UKPageHost: UKPageViewController, UKSheetFitting {
    let child: UIViewController
    private let linksScroll: Bool
    private var linked = false
    private var observations: [NSKeyValueObservation] = []

    /// - Parameters:
    ///   - linksScroll: Whether the screen's main scroll view becomes the page's (the large title, the fade, scroll-to-top). True on the
    ///     wallpaper; a sheet leaves the screen's scroll view alone.
    init(child: UIViewController, context: UKContext, linksScroll: Bool = true) {
        self.child = child
        self.linksScroll = linksScroll
        super.init(context: context, title: child.title)
    }

    /// `controller` as a page: itself when it already is one (or is a navigation controller, which brings its own bar), else hosted.
    static func wrapped(_ controller: UIViewController, context: UKContext) -> UIViewController {
        if controller is UKPageViewController || controller is UINavigationController { return controller }
        return UKPageHost(child: controller, context: context)
    }

    /// `controller` as a page of a sheet: itself when it already is one (or is a navigation controller), else hosted on the sheet surface
    /// without taking over its scroll view.
    static func sheetWrapped(_ controller: UIViewController) -> UIViewController {
        if controller is UKPageViewController || controller is UINavigationController { return controller }
        return UKPageHost(child: controller, context: .sheetPlaceholder, linksScroll: false)
    }

    // MARK: UKSheetFitting

    var sheetFitScrollView: UIScrollView? { (child as? UKSheetFitting)?.sheetFitScrollView }
    var sheetHeaderIsStandard: Bool { (child as? UKSheetFitting)?.sheetHeaderIsStandard ?? true }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)
        child.view.frame = contentView.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.view.backgroundColor = child.view.backgroundColor ?? .clear
        contentView.addSubview(child.view)
        child.didMove(toParent: self)
        title = child.title
        if isSheet { mirrorChrome() }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if isSheet { syncChrome() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard linksScroll, !linked, let scroll = UKScrollToTop.mainScrollView(in: child.view) else { return }
        linked = true
        setPageScrollView(scroll)
    }

    override var childForStatusBarStyle: UIViewController? { child }
    override var childForStatusBarHidden: UIViewController? { child }

    // MARK: Chrome mirrored from the hosted screen

    /// The hosted screen configures its own `navigationItem` (it was the navigation controller's page before); the sheet's bar reads
    /// the host's. Values the screen has set are copied across now and whenever they change; the host's own (the modal's Close, the sheet
    /// title) stay where the screen sets nothing.
    private func mirrorChrome() {
        let item = child.navigationItem
        observations = [
            item.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.rightBarButtonItems) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.leftBarButtonItems) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.hidesBackButton) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            item.observe(\.titleView) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
            child.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncChrome() } },
        ]
        syncChrome()
    }

    private func syncChrome() {
        let source = child.navigationItem
        let host = navigationItem
        if let title = source.title ?? child.title, host.title != title { host.title = title }
        if let right = source.rightBarButtonItems, !right.isEmpty, host.rightBarButtonItems != right { host.rightBarButtonItems = right }
        if let left = source.leftBarButtonItems, !left.isEmpty, host.leftBarButtonItems != left { host.leftBarButtonItems = left }
        if host.hidesBackButton != source.hidesBackButton { host.hidesBackButton = source.hidesBackButton }
        if host.leftItemsSupplementBackButton != source.leftItemsSupplementBackButton { host.leftItemsSupplementBackButton = source.leftItemsSupplementBackButton }
        if let titleView = source.titleView, host.titleView !== titleView { host.titleView = titleView }
    }
}
#endif
