#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import UIKit

/// One tab's stack: the UIKit counterpart of `MainTabView.sectionStack`. The ``ShellNavigator`` stays the source of truth for
/// what is pushed (so route restore, push and Spotlight opens, Quick Links and the second tap on a tab work unchanged); this
/// controller reconciles its `UINavigationController` stack to the navigator's routes, builds each pushed page through
/// ``UKScreens`` and writes a back swipe or Back tap into the navigator.
///
/// **Columns.** A page that hosts a ``UKColumnsViewController`` (``UKColumnsHosting``) shows the routes that follow it as columns while
/// the window splits (``SplitPolicy``): the stack stops at that page and the navigator's trailing routes show beside it; where the
/// window does not split the same routes are the normal push stack. The hosts are the section roots Settings and Chores (their pages
/// are routes ``ShellRoute/settings(_:)``, ``ShellRoute/household(_:)``, ``ShellRoute/chores(_:)``) and the Food hub on Home's stack (the
/// Food spaces, ``ShellRoute/foodSpace(_:)``). This controller owns that decision for the section (``splitting``), because it is on
/// screen whichever page is showing, and flips it one run-loop turn after layout. Pages that were pushed locally (no route: Vacation
/// Mode) while the window was narrow move into the columns when it widens.
///
/// **Motion (owner, 2026-11-02, `.agents/design/single-page-motion.md`).** Where the section is a plain stack (the columns are not
/// active: iPhone, the folded Duo, Duo and iPad portrait) a push and a pop run ``UKStackMotion``: both pages move a full width over
/// the one wallpaper behind the tab controller, the edge swipe follows the finger, Reduce Motion cross-fades. The controller, its
/// transition containers and the pages are transparent; nothing here paints a ground.
///
/// It also presents the header sheets (Quick Links, Your Summary) once per section, scrolls the root to its top on a second
/// tap of the tab, and returns VoiceOver focus to the menu button after the flyout closes.
@MainActor
final class UKSectionNavigationController: UINavigationController, UINavigationControllerDelegate {
    let section: AppSection
    private(set) var pageContext: UKContext
    private let navigator: ShellNavigator
    private let bag = UKObservationBag()
    private var routeOf: [ObjectIdentifier: ShellRoute] = [:]
    private var pendingQuickLink: HomeRoute?
    private var isPresentingHeaderSheet = false
    private var lastScrollToTop = 0
    private var lastFocusToken = 0
    private var reconciled = false
    /// Pushes animate once the shell is on screen; a route restore at launch puts the stack back without motion.
    var isSettled = false
    private var lastTop: UIViewController?
    /// The window splits, so the top page's trailing routes show as columns (see the type's notes).
    private(set) var splitting = false
    /// How many of the navigator's trailing routes the top page shows as columns instead of the stack.
    private(set) var hostedCount = 0
    private var isApplyingColumns = false
    private var columnsChangePending = false
    private var pushMeasurement: NavigationMeasurement?
    /// The push, pop and edge swipe of the single-page layouts (nil until the view loads).
    private(set) var stackMotion: UKStackMotion?
    /// The section's pages ignore touches from the moment Quick Links chooses a page until that page has finished arriving: the
    /// pages underneath a dismissing sheet are visible and live otherwise, and a second tap meant for the sheet's tile (or made
    /// while nothing seems to happen) lands on whatever sits under the finger, such as a camera tile that opens its modal over
    /// the page that is about to push.
    private var holdsTouches = false {
        didSet { view.isUserInteractionEnabled = !holdsTouches }
    }

    init(section: AppSection, context: UKContext, navigator: ShellNavigator) {
        self.section = section
        self.navigator = navigator
        pageContext = context.with { $0.section = section; $0.surface = .page }
        let root = UKPageHost.wrapped(UKScreens.root(for: section, context: pageContext), context: pageContext)
        (root as? UKPageViewController)?.isSectionRoot = true
        super.init(rootViewController: root)
        delegate = self
        UKNavigationBarStyle.apply(to: navigationBar, large: true)
        navigationBar.accessibilityIdentifier = nil
        // The Chores badge and the title are read from the section, not the page: the tab item.
        let item = UITabBarItem(title: section.title, image: UIImage(systemName: section.symbol), selectedImage: nil)
        item.accessibilityIdentifier = section.navigationIdentifier
        tabBarItem = item
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Binding

    private func bind() {
        lastScrollToTop = navigator.scrollToTopRequests[section] ?? 0
        lastFocusToken = navigator.focusReturnToken
        // The routes the navigator holds for this section.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.navigator.routes(in: self.section)
            self.apply()
        }
        // A second tap on the selected tab, at the root, scrolls the root to its top.
        bag.observe { [weak self] in
            guard let self else { return }
            let token = self.navigator.scrollToTopRequests[self.section] ?? 0
            guard token != self.lastScrollToTop else { return }
            self.lastScrollToTop = token
            self.scrollTopToTop()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let token = self.navigator.focusReturnToken
            guard token != self.lastFocusToken else { return }
            self.lastFocusToken = token
            (self.viewControllers.first as? UKPageViewController)?.focusMenuButton()
        }
        // Quick Links and Account, presented once per section.
        bag.observe { [weak self] in
            guard let self else { return }
            let sheet: ShellSheet? = self.navigator.sheet(in: self.section).wrappedValue
            self.sheetChanged(sheet)
        }
    }

    private func scrollTopToTop() {
        guard let top = topViewController else { return }
        if let page = top as? UKPageViewController {
            page.scrollToTop()
        } else if let scroll = UKScrollToTop.mainScrollView(in: top.view) {
            let target = -scroll.adjustedContentInset.top
            if scroll.contentOffset.y > target + 0.5 { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: true) }
        }
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        // The wallpaper is the shell's, behind the tab controller: this controller and its transition containers draw no ground.
        view.backgroundColor = .clear
        view.isOpaque = false
        // The columns (not the stack) move while the window splits and the section's root hosts column routes (the old `columnsActive`).
        // A deeper column host (the Food hub) keeps the stack's motion; its swipe goes to its columns while a page is open (UKStackMotion).
        stackMotion = UKStackMotion(navigation: self) { [weak self] in
            guard let self else { return true }
            return !(self.splitting && (self.viewControllers.first as? UKColumnsHosting)?.hostsColumnRoutes == true)
        }
    }

    // MARK: Columns

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !columnsChangePending, let window = view.window else { return }
        let wanted = SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular)
        guard wanted != splitting else { return }
        // One run-loop turn after the layout pass, unanimated: a layout input is never written from layout (Festival #346).
        columnsChangePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.columnsChangePending = false
            guard let window = self.view.window else { return }
            self.setSplitting(SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular))
        }
    }

    /// Moves the section's trailing routes between the push stack and the top page's columns.
    private func setSplitting(_ value: Bool) {
        guard value != splitting else { return }
        splitting = value
        apply(forcingUnanimated: true)
    }

    /// Brings the stack and the columns in line with the navigator: the routes that sit on the stack are reconciled, and the top page, if it
    /// hosts columns, is switched wide or narrow and shown the rest.
    private func apply(forcingUnanimated: Bool = false) {
        let desired = navigator.routes(in: section)
        let hosted = ColumnRouting.hostedCount(in: desired, splitting: splitting, rootHostsColumns: (viewControllers.first as? UKColumnsHosting)?.hostsColumnRoutes == true)
        hostedCount = hosted
        let stackRoutes = Array(desired.dropLast(hosted))
        // Pages pushed locally while the window was narrow keep their place in the columns.
        var locals: [UIViewController] = []
        if splitting, viewControllers.count > 1,
           let firstLocal = viewControllers.indices.dropFirst().first(where: { routeOf[ObjectIdentifier(viewControllers[$0])] == nil }),
           // Everything between the host and the first local page has a route, so it goes to the columns too (Vacation Mode under Vacation).
           viewControllers[..<firstLocal].contains(where: { ($0 as? UKColumnsHosting)?.hostsColumnRoutes == true }) {
            locals = Array(viewControllers[firstLocal...])
            isApplyingColumns = true
            setViewControllers(Array(viewControllers[..<firstLocal]), animated: false)
            isApplyingColumns = false
        }
        isApplyingColumns = true
        reconcile(to: stackRoutes, forcingUnanimated: forcingUnanimated)
        isApplyingColumns = false
        routeOf = routeOf.filter { key, _ in viewControllers.contains { ObjectIdentifier($0) == key } }
        lastTop = viewControllers.last
        // Every hosting page on the stack is narrow except the top one, and that one only while the window splits.
        var host: UKColumnsHosting?
        for page in viewControllers {
            guard let hosting = page as? UKColumnsHosting, hosting.hostsColumnRoutes else { continue }
            let wide = splitting && page === viewControllers.last
            hosting.columns.setWide(wide)
            if wide { host = hosting }
        }
        if let host {
            let routes = desired.suffix(hosted).compactMap { $0 }
            host.syncColumnRoutes(routes, animated: !forcingUnanimated && isSettled && view.window != nil)
            host.columns.adopt(locals)
        } else if !locals.isEmpty {
            // No page hosts them: back onto the stack.
            for page in locals { pushViewController(page, animated: false) }
        }
    }

    // MARK: Reconciling the stack with the navigator

    private func currentRoutes() -> [ShellRoute?] {
        viewControllers.dropFirst().map { routeOf[ObjectIdentifier($0)] }
    }

    private func reconcile(to desired: [ShellRoute?], forcingUnanimated: Bool = false) {
        // Entries the navigator knows no route for cannot be built; they are left out (the path and the stack then differ only there).
        let wanted = desired.compactMap { $0 }
        let current = currentRoutes().compactMap { $0 }
        let animated = !forcingUnanimated && reconciled && isSettled && isViewLoaded && view.window != nil && navigator.isShowing(section) && transitionCoordinator == nil
        defer { reconciled = true }
        var common = 0
        while common < min(wanted.count, current.count), wanted[common] == current[common] { common += 1 }
        if current.count > common {
            // Pop to the page that stays (the root when nothing does).
            let keep = viewControllers[common]
            popToViewController(keep, animated: animated)
        }
        guard wanted.count > common else { return }
        var stack = viewControllers
        for route in wanted[common...] {
            let page = makePage(for: route)
            routeOf[ObjectIdentifier(page)] = route
            stack.append(page)
        }
        if animated, wanted.count == common + 1 {
            pushMeasurement = pageContext.motion?.measure(.push(Self.measuredName(for: wanted[common])))
            setViewControllers(stack, animated: true)
        } else {
            setViewControllers(stack, animated: false)
        }
    }

    private func makePage(for route: ShellRoute) -> UIViewController {
        let page: UIViewController
        switch route {
        case let .home(home): page = UKScreens.destination(for: home, context: pageContext)
        case let .household(household): page = UKScreens.destination(for: household, context: pageContext)
        case let .settings(settings): page = UKScreens.destination(for: settings, context: pageContext)
        case let .chores(id): page = UKScreens.choresPage(id, context: pageContext)
        case let .foodSpace(raw): page = UKScreens.foodSpace(raw, context: pageContext)
        }
        let wrapped = UKPageHost.wrapped(page, context: pageContext)
        if let wrapped = wrapped as? UKPageViewController {
            wrapped.route = route
            wrapped.measuredPageName = Self.measuredName(for: route)
        }
        return wrapped
    }

    /// The name a push is recorded under (`pageDestination(for:measuring:)`): the route's title for a Home route, else "Page".
    static func measuredName(for route: ShellRoute) -> String {
        if case let .home(home) = route { return home.title }
        return "Page"
    }

    // MARK: UINavigationControllerDelegate

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let previous = lastTop
        lastTop = viewController
        guard animated, let previous, previous !== viewController, let coordinator = transitionCoordinator else { return }
        let isPop = !viewControllers.contains(previous)
        if isPop, let route = routeOf[ObjectIdentifier(previous)] {
            let measurement = pageContext.motion?.measure(.pop(Self.measuredName(for: route)))
            coordinator.animate(alongsideTransition: nil) { _ in measurement?.settled() }
        }
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        stackMotion?.navigationController(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        stackMotion?.navigationController(navigationController, interactionControllerFor: animationController)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        stackMotion?.navigationController(navigationController, didShow: viewController, animated: animated)
        holdsTouches = false
        pushMeasurement?.settled()
        pushMeasurement = nil
        // A back swipe or Back tap popped pages: the navigator's path follows the stack. The routes the top page shows as columns are not
        // on the stack: they are kept while the stack is as deep as the navigator holds its own routes, and go with the page that hosts them.
        guard !isApplyingColumns else { return }
        // The page that is now on top may host columns that were narrow while another page covered it (the hub under Recipes).
        if splitting, viewController is UKColumnsHosting {
            DispatchQueue.main.async { [weak self] in self?.apply(forcingUnanimated: true) }
        }
        let depth = viewControllers.count - 1
        routeOf = routeOf.filter { key, _ in viewControllers.contains { ObjectIdentifier($0) == key } }
        guard currentRoutes().allSatisfy({ $0 != nil }) else { return }
        if hostedCount > 0, depth >= navigator.routes(in: section).count - hostedCount { return }
        navigator.trimPath(in: section, toDepth: depth)
    }

    // MARK: Header sheets

    private func sheetChanged(_ sheet: ShellSheet?) {
        guard let sheet else {
            if isPresentingHeaderSheet, presentedViewController != nil, !(presentedViewController?.isBeingDismissed ?? true) {
                if pendingQuickLink != nil { holdsTouches = true }
                dismiss(animated: true) { [weak self] in self?.sheetDismissed() }
            }
            return
        }
        guard !isPresentingHeaderSheet, presentedViewController == nil, isViewLoaded, view.window != nil else { return }
        isPresentingHeaderSheet = true
        let sheetContext = pageContext.with { $0.surface = .sheet }
        let page: UIViewController
        let width: HassSheetWidth
        switch sheet {
        case .account:
            page = UKScreens.yourSummary(sheetContext)
            width = .form
        case .quickLinks:
            page = UKScreens.quickLinks(sheetContext) { [weak self] route in self?.pendingQuickLink = route }
            width = .page
        }
        presentHeaderSheet(page, width: width)
    }

    private func presentHeaderSheet(_ page: UIViewController, width: HassSheetWidth) {
        let measurement = pageContext.motion?.measure(.sheetPresent(page.title ?? "Sheet"))
        if let modal = page as? UKHassModalController {
            // The modal's own presentation (detents that follow its content, grabber, width), not a copy of it: it re-fits on a rotation.
            modal.overrideUserInterfaceStyle = UKSystemAppearance.style(for: view)
            modal.present(from: self) { measurement?.settled() }
            modal.presentationController?.delegate = self
        } else {
            // Any other page goes through the same modal class (``UKShellSheet``).
            UKShellSheet.present(page, from: self, width: width, height: .full) { measurement?.settled() }
            presentedViewController?.presentationController?.delegate = self
        }
    }

    fileprivate func sheetDismissed() {
        isPresentingHeaderSheet = false
        // A page Quick Links chose pushes after the sheet has gone, so the push never races the dismissal.
        if let route = pendingQuickLink {
            pendingQuickLink = nil
            // Touches stay held through the push; `didShow` releases them. A route that is already showing pushes nothing.
            let pushed = navigator.pushOnHome(route)
            if pushed, section == .home {
                // A push that never reaches `didShow` (the stack reconciled to what it showed) must not leave the section dead.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.holdsTouches = false
                }
            } else {
                holdsTouches = false
            }
        } else {
            holdsTouches = false
        }
    }
}

extension UKSectionNavigationController: UIAdaptivePresentationControllerDelegate {
    /// A swipe down closes the sheet: tell the navigator, then run the dismissal's work.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        navigator.sheet(in: section).wrappedValue = nil
        sheetDismissed()
    }
}

// MARK: - Pushing from a page

extension ShellNavigator {
    /// Opens a Home page (a room, Media, Vacuums, Food & Recipes ...) on Home's own stack and moves the selection to Home: these
    /// are sub-pages of the Home tab, so reaching one from Security, Chores or any other tab shows Home selected in the tab bar,
    /// the rail and the flyout, and Back returns to Home's stack (owner, 2026-11-01). The push is recorded first, while Home is
    /// hidden, so the tab switch is the only motion.
    /// - Returns: Whether the page was pushed (false when it was already showing, or popped back to).
    @discardableResult
    func pushOnHome(_ route: HomeRoute) -> Bool {
        let pushed = push(route, in: .home)
        if selection != .home { selection = .home }
        return pushed
    }
}

extension UKContext {
    /// Pushes a Home route on this screen's section (Quick Links, room links, tiles that open a page). Nothing happens when
    /// the page is already showing; a page already in the stack pops back to it (``ShellNavigator/push(_:in:)``).
    @discardableResult
    func push(_ route: HomeRoute) -> Bool {
        guard let navigator, section != nil else { return false }
        return navigator.pushOnHome(route)
    }

    /// Pushes a Settings topic on this screen's section.
    func push(_ route: SettingsRoute) {
        guard let navigator, let section else { return }
        navigator.append(.settings(route), in: section)
    }

    /// Pushes a household settings page on this screen's section.
    func push(_ page: HouseholdSettingsPage) {
        guard let navigator, let section else { return }
        navigator.append(.household(page), in: section)
    }
}
#endif

#if os(iOS)
/// A page that shows the routes after it as columns (``UKColumnsViewController``) where the window splits: Settings and Chores (section
/// roots) and the Food hub (on Home's stack).
@MainActor
protocol UKColumnsHosting: UIViewController {
    /// The columns this page hosts; the section's navigation controller switches them between wide and narrow.
    var columns: UKColumnsViewController { get }
    /// Whether this page shows the navigator's routes as columns (a section root, the Food hub). A page that only hosts its own detail pane
    /// says no and decides its width itself.
    var hostsColumnRoutes: Bool { get }
    /// Makes the columns show `routes` (the navigator's routes this page hosts). Called when they turn wide and when the routes change.
    func syncColumnRoutes(_ routes: [ShellRoute], animated: Bool)
}

extension UKColumnsHosting {
    var hostsColumnRoutes: Bool { true }
}
#endif
