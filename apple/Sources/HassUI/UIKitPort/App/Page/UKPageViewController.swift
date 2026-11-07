#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The base class of every screen the shell shows: what `.pageChrome()` (``MainTabView``'s `PageChrome`), `sectionRootChrome()`
/// and `modalChrome()` give a SwiftUI page, given once. A feature page subclasses it, puts its content in ``contentView`` and
/// names its scroll view; everything else is the shell's. See `.agents/platforms/apple/uikit-port-shell.md`.
///
/// **A page on the wallpaper** (``UKContext/surface`` `.page`, the default):
/// - the page is transparent: the wallpaper is the window's one ``UKBackdropView`` (the shell's, or the gallery host's), behind the tab
///   controller, so a push, pop, tab switch or split moves content over a wallpaper that never moves (``UKStackMotion``,
///   `.agents/design/single-page-motion.md` S1); a page never creates one;
/// - ``contentView`` is full-bleed and carries the header edge fade (``UKHeaderEdgeFade``): content fades out under the header
///   and the navigation bar draws no band of its own;
/// - the bar's trailing items are Quick Links and Profile (``UKShellHeaderItems``), and a section root has the menu button
///   leading when the window shows the flyout (`nav.open`);
/// - the title is the large title below the bar that collapses into a leading bar title (iPhone), or always the leading bar
///   title (the folded Duo's rail): the system's own, leading aligned where the menu button shows
///   (`UINavigationItem.Style.browser`, header-edge-fade R7 (5)). Set ``title`` (or `navigationItem.title`) and nothing else;
/// - the scroll view named with ``install(scrollView:)`` or ``setPageScrollView(_:)`` is transparent, scrolls only when its
///   content outgrows it (``UKScrollFit``), has its iOS 26 top edge effect hidden, drives the fade and the large title;
/// - the tab bar is hidden in flyout style and the page is hidden from VoiceOver while the flyout is open, by the shell.
///
/// **A page in a sheet** (``UKContext/surface`` `.sheet`): no wallpaper (the system's grouped ground), no header buttons or
/// menu, inline title, the same transparent bar, fade (uncapped) and scroll rules (`modalChrome()`).
///
/// **Arrival.** The wallpaper and the header arrive with Home after a sign-in by themselves; an element that should rise or
/// slide in calls ``UIView/ukArrivalMotion(_:kind:index:)`` once.
@MainActor
class UKPageViewController: UIViewController, UKColumnBarHosting {
    /// What the page was created with (store, caller, navigator, section, surface …).
    let context: UKContext
    /// Everything the page draws goes here, edge to edge: it is masked by the header fade, so content reaches under the bar.
    let contentView = UIView()
    /// The scroll view that drives the large title, the fade and scroll-to-top.
    private(set) var contentScrollView: UIScrollView?
    /// This page is a tab's root (the shell sets it): it gets the menu button in flyout layouts and is what a second tap on its
    /// tab scrolls.
    var isSectionRoot = false
    /// The route a push opened this page for (the shell sets it); nil for roots and sheets.
    var route: ShellRoute?
    /// The name its navigation is measured under (`measuresNavigation`); nil for a tab root.
    var measuredPageName: String?

    let bag = UKObservationBag()
    /// A strip pinned above the bottom safe area (a gallery's last-call line, a status strip), on the bar material. The page base
    /// installs it and adds its height to the safe area once (``UKPagePinnedBar``): a page never computes a bottom inset for a bar.
    var bottomAccessory: UIView? {
        didSet { if isViewLoaded, oldValue !== bottomAccessory { installBottomAccessory() } }
    }
    private var accessoryBar: UKPagePinnedBar?
    private var headerFade: UKHeaderEdgeFade?
    private var headerItems: UKShellHeaderItems?
    private var menuItem: UIBarButtonItem?
    private let fixedBarTitle = UKFixedBarTitle()

    override var title: String? {
        didSet {
            guard isViewLoaded else { return }
            syncBarTitle(inVerticalBar: context.shell?.inVerticalBar ?? false)
            columnTitle?.text = title
        }
    }

    /// Whether the page is drawn in a sheet (``UKContext/surface``).
    var isSheet: Bool { context.surface == .sheet }

    init(context: UKContext, title: String? = nil) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    /// A page that only ever lives in a sheet and has no context of its own to hand down: the sheet surface over a placeholder context
    /// (``UKContext/sheetPlaceholder``). A sheet page that does have a context passes it to ``init(context:title:)`` with `surface = .sheet`.
    init(sheetTitle title: String? = nil) {
        context = .sheetPlaceholder
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func loadView() {
        view = UIView()
        view.backgroundColor = isSheet ? .systemGroupedBackground : .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentView.frame = view.bounds
        contentView.backgroundColor = .clear
        view.addSubview(contentView)

        let fade = UKHeaderEdgeFade(masking: contentView)
        headerFade = fade
        fade.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        fade.increaseContrast = traitCollection.accessibilityContrast == .high
        installBottomAccessory()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKPageViewController, _) in
            page.syncBarTitle(inVerticalBar: page.context.shell?.inVerticalBar ?? false)
            // The Profile badge's text follows the text size, so the items are rebuilt at the new one.
            if var state = page.headerItems?.lastState, state.contentSize != page.traitCollection.preferredContentSizeCategory {
                state.contentSize = page.traitCollection.preferredContentSizeCategory
                page.shellItems = page.headerItems?.items(for: state) ?? page.shellItems
                page.applyShellItems()
            }
        }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (page: UKPageViewController, _) in
            page.headerFade?.increaseContrast = page.traitCollection.accessibilityContrast == .high
        }
        navigationItem.backButtonDisplayMode = .default
        bindChrome()
        if let kind = houseLayoutSkeleton { houseGate = UKHouseLayoutGate(page: self, kind: kind) }
    }

    /// The skeleton a page that draws from the house layout shows while there is none (``UKHouseLayoutGate``): `.home` for Home, `.page`
    /// for every other layout-driven page. nil, the default, is a page that never depends on the document (navigation chrome,
    /// the Settings root, Profile, the Home Assistant modal).
    var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { nil }
    private var houseGate: UKHouseLayoutGate?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        accessoryBar?.layoutChanged()
        layoutContentView()
        columnTitle?.place()
    }

    private func installBottomAccessory() {
        if let old = accessoryBar {
            old.bar.removeFromSuperview()
            old.removeMaterial()
            additionalSafeAreaInsets.bottom = 0
            accessoryBar = nil
        }
        guard let bottomAccessory else { return }
        let bar = UKPagePinnedBar.accessory(bottomAccessory)
        accessoryBar = bar
        bar.install(in: self)
    }

    /// A sheet page's own full-bleed ground (the weather gradient, the camera viewer's dark ground): placed behind ``contentView`` over
    /// the whole sheet, so it runs under the folded Duo's rail while the content stays clear of it. Call from `viewDidLoad` after
    /// `super`. `ground` is the sheet's flat colour under it (the backdrop's base colour). A page on the wallpaper has the wallpaper and
    /// ignores this.
    func setSheetBackdrop(_ backdrop: UIView, ground: UIColor? = nil) {
        guard isSheet else { return }
        if let ground { view.backgroundColor = ground }
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(backdrop, at: 0)
    }

    /// Full height, but inside the side safe areas: the folded Duo's vertical bar takes the trailing edge, and a SwiftUI
    /// ScrollView keeps its content clear of it (the wallpaper behind stays full-bleed). Read again on every layout and whenever the
    /// insets change, so a fold, an unfold or a rotation never leaves the old rail's inset behind.
    private func layoutContentView() {
        guard isViewLoaded else { return }
        UKLayoutCensus.bump("page.\(type(of: self))")
        var insets = view.safeAreaInsets
        let side = geometricSideInsets()
        matchSideSafeArea(to: side)
        insets.left = side.left
        insets.right = side.right
        let frame = view.bounds.inset(by: UIEdgeInsets(top: 0, left: insets.left, bottom: 0, right: insets.right))
        if contentView.frame != frame { contentView.frame = frame }
        absorbSideInsetsForChildren(insets)
        headerFade?.layoutChanged()
        followTopInset()
    }

    /// A hosted test stands in for the Duo's rail with side insets the window does not have; nil (always, outside tests) measures them.
    var sideInsetsOverride: UIEdgeInsets? { didSet { if isViewLoaded { layoutContentView() } } }

    /// The side safe areas that actually overlap this page's view: the window's insets (the rail) against where the view sits. A view
    /// inside a navigation controller inside a split pane inherits the whole window inset through the controller hierarchy even when
    /// it ends clear of the rail (the Settings pane ended a rail's width short of its column: owner, 2026-11-01), so the inherited
    /// value is not used for the sides.
    private func geometricSideInsets() -> UIEdgeInsets {
        if let sideInsetsOverride { return sideInsetsOverride }
        guard let window = view.window else { return UIEdgeInsets(top: 0, left: view.safeAreaInsets.left, bottom: 0, right: view.safeAreaInsets.right) }
        let frame = view.convert(view.bounds, to: window)
        let safe = window.safeAreaInsets
        return UIEdgeInsets(top: 0, left: max(0, safe.left - frame.minX), bottom: 0, right: max(0, safe.right - (window.bounds.width - frame.maxX)))
    }

    /// Makes this page's own side safe area the geometric one (``geometricSideInsets()``), so the scroll views inside ``contentView``
    /// do not add the inherited rail inset on top of it (`.automatic` adjustment adds the side safe area). Changes only the page's
    /// `additionalSafeAreaInsets`, and only when the value differs; it settles in one more pass.
    private func matchSideSafeArea(to side: UIEdgeInsets) {
        let inheritedLeft = view.safeAreaInsets.left - additionalSafeAreaInsets.left
        let inheritedRight = view.safeAreaInsets.right - additionalSafeAreaInsets.right
        let left = side.left - inheritedLeft, right = side.right - inheritedRight
        guard abs(additionalSafeAreaInsets.left - left) > 0.5 || abs(additionalSafeAreaInsets.right - right) > 0.5 else { return }
        additionalSafeAreaInsets.left = left
        additionalSafeAreaInsets.right = right
    }

    /// ``contentView`` is already inset by the side safe areas (the rail), but a child view controller inherits this page's side insets
    /// through the controller hierarchy, not by geometry, so a pane or hosted page placed in the content view would be inset by the
    /// rail a second time (a split's trailing pane ended a rail's width short of its column: owner, 2026-11-01). The children get the
    /// side insets taken back. Written only when the value changes, from the inset callbacks, so it never feeds this layout.
    private func absorbSideInsetsForChildren(_ insets: UIEdgeInsets) {
        for child in children where child.additionalSafeAreaInsets.left != -insets.left || child.additionalSafeAreaInsets.right != -insets.right {
            child.additionalSafeAreaInsets.left = -insets.left
            child.additionalSafeAreaInsets.right = -insets.right
        }
    }

    /// A scroll view that rests at its top stays at its top when the bar above it changes height (the large title returns after a
    /// rotation, a fold, a tab switch or a sheet): its offset is moved to the new top. Without it the offset keeps the old inset's
    /// value, which is a scroll of the difference, so the bar collapses the title into the header on a page nobody scrolled
    /// (SwiftUI's `ScrollView` keeps its resting position the same way). A drag in progress is never moved.
    private var lastTopInset: CGFloat?

    func followTopInset() {
        guard let scroll = contentScrollView, scroll.window != nil else { return }
        let inset = scroll.adjustedContentInset.top
        defer { lastTopInset = inset }
        #if DEBUG
        // A probe's animated scroll starts at the top and collapses the title as it leaves; it is moving, as a drag is.
        if let until = debugScrollUntil, Date() < until { return }
        #endif
        guard let last = lastTopInset, abs(inset - last) > 0.5, !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { return }
        // At the top before the change, by the old inset or by the new one (the system may already have moved it).
        let y = scroll.contentOffset.y
        guard y <= -last + 1.5 || y <= -inset + 1.5 else { return }
        UKLayoutCensus.bump("followTop.move")
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -inset), animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layoutContentView()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.layoutContentView() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UKScrollRate.attachAll(in: view)
        if case let .home(route)? = route, let section = context.section { context.navigator?.routeAppeared(route, in: section) }
    }

    #if DEBUG
    deinit {
        // The Darwin probes hold this object unretained: a probe posted after it is gone would call into freed memory.
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    private var debugScrollStarted = false
    /// While a probe's animated scroll runs, ``followTopInset()`` leaves it alone (it read the scroll's first frames, still at the top,
    /// as a page resting there, and took it back: the folded Duo's hosted probe test, 2026-11-04).
    private var debugScrollUntil: Date?
    /// `FENTON_DEBUG_SCROLL="3:400,6:0"`: drives the section root's scroll view to `y` points below its top (animated) after each
    /// delay in seconds, so a host script can capture the collapse of the title at known moments. A probe, never in a release build.
    private func debugScroll(_ y: Double) {
        guard let scroll = contentScrollView else { return }
        // A negative `y` goes to the top as a person's drag does, where the large title is expanded (its extra height is not
        // in the inset while the title is collapsed).
        let target = y < 0 ? -scroll.adjustedContentInset.top - 52 : -scroll.adjustedContentInset.top + y
        debugScrollUntil = Date().addingTimeInterval(0.6)
        scroll.setContentOffset(CGPoint(x: 0, y: target), animated: true)
    }

    private func runDebugScroll() {
        guard !debugScrollStarted, isSectionRoot || isSheet else { return }
        debugScrollStarted = true
        // A sheet page takes only the timed `FENTON_DEBUG_SCROLL` steps below (the modal-standard shots of a sheet scrolling under its header).
        if isSheet { return runDebugScrollSteps() }
        // `xcrun simctl spawn <udid> notifyutil -p uk.debug.scrollDown|uk.debug.scrollTop`: the same, on demand (a fold or rotation in between).
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, me, { _, observer, _, _, _ in
            guard let observer else { return }
            let page = Unmanaged<UKPageViewController>.fromOpaque(observer).takeUnretainedValue()
            MainActor.assumeIsolated { page.debugScroll(500) }
        }, "uk.debug.scrollDown" as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, me, { _, observer, _, _, _ in
            guard let observer else { return }
            let page = Unmanaged<UKPageViewController>.fromOpaque(observer).takeUnretainedValue()
            MainActor.assumeIsolated { page.debugScroll(-1) }
        }, "uk.debug.scrollTop" as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, me, { _, observer, _, _, _ in
            guard let observer else { return }
            let page = Unmanaged<UKPageViewController>.fromOpaque(observer).takeUnretainedValue()
            MainActor.assumeIsolated { page.openQuickLinks() }
        }, "uk.debug.quickLinks" as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, me, { _, observer, _, _, _ in
            guard let observer else { return }
            let page = Unmanaged<UKPageViewController>.fromOpaque(observer).takeUnretainedValue()
            MainActor.assumeIsolated { _ = UKHomeAssistantSettings.present(context: page.context, from: page.navigationController?.tabBarController ?? page) }
        }, "uk.debug.haSettings" as CFString, nil, .deliverImmediately)
        runDebugScrollSteps()
    }

    private func runDebugScrollSteps() {
        guard let spec = ProcessInfo.processInfo.environment["FENTON_DEBUG_SCROLL"] else { return }
        for step in spec.split(separator: ",") {
            let parts = step.split(separator: ":")
            guard parts.count == 2, let delay = Double(parts[0]), let y = Double(parts[1]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.debugScroll(y) }
        }
    }
    #endif

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        // The ground is the base's: clear on the wallpaper, the grouped ground in a sheet (or the sheet backdrop's colour). A subclass
        // that painted its own is the black-pane bug; it is logged here so a gallery run shows it.
        if let color = view.backgroundColor, !isSheet, color != .clear, color.cgColor.alpha > 0.01 {
            NSLog("PAGEGROUND %@ painted %@", String(describing: type(of: self)), String(describing: color))
        }
        runDebugScroll()
        if ProcessInfo.processInfo.environment["FENTON_DEBUG_TITLE"] == "1" {
            // One line per page: is the large title expanded (the bar is taller than a compact one), and what the scroll view looks like.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, let bar = self.navigationController?.navigationBar else { return }
                let scroll = self.contentScrollView
                NSLog("TITLEPROBE %@ title=%@ barH=%.0f large=%d scroll=%@ offY=%.0f top=%.0f content=%.0f bounds=%.0f",
                      String(describing: type(of: self)), self.title ?? "-", bar.frame.height, bar.prefersLargeTitles ? 1 : 0,
                      scroll == nil ? "none" : "yes", scroll?.contentOffset.y ?? 0, scroll?.adjustedContentInset.top ?? 0,
                      scroll?.contentSize.height ?? 0, scroll?.bounds.height ?? 0)
            }
        }
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if case let .home(route)? = route, let section = context.section { context.navigator?.routeDisappeared(route, in: section) }
    }

    // MARK: Scroll view

    /// Adds `scrollView` edge to edge in ``contentView`` and makes it the page's scroll view.
    func install(scrollView: UIScrollView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        setPageScrollView(scrollView)
    }

    /// Names the scroll view that drives the large title, the header fade and scroll-to-top (call after the view is loaded). It
    /// is made transparent (`scrollContentBackground(.hidden)`) and scrolls only when its content outgrows it.
    func setPageScrollView(_ scrollView: UIScrollView?) {
        contentScrollView = scrollView
        if let scrollView {
            scrollView.backgroundColor = .clear
            // One rule for every page body: the system adds the bar, the large title and the pinned bar's inset (the safe area, which
            // ``UKPagePinnedBar`` raises). The centred message lays out in the whole frame under the fade, so it is the one exception.
            if !(scrollView is UKCenteredStateMessageView) { scrollView.contentInsetAdjustmentBehavior = .automatic }
            UKScrollFit.apply(to: scrollView)
            setContentScrollView(scrollView, for: .top)
            UKHeaderEdgeFade.applySoftEdge(to: scrollView)
        } else {
            setContentScrollView(nil, for: .top)
        }
        headerFade?.follow(scrollView)
        syncColumnTitle()
    }

    // MARK: Column title

    private var columnTitle: UKColumnTitleHeader?

    /// A page shown in a column (a child of ``UKColumnsViewController``) has its title as a large heading at the top of its scroll content,
    /// and sets no bar title: the section's bar above both columns is the header. Elsewhere (a push on the stack) the bar title is used.
    private func syncColumnTitle() {
        // A form that is a sheet elsewhere has its title as content too while it is a column (the todo form beside its list).
        guard isViewLoaded, !isSheet || parent is UKColumnsViewController else { return }
        if parent is UKColumnsViewController, let scroll = contentScrollView {
            let header = columnTitle ?? UKColumnTitleHeader()
            columnTitle = header
            header.attach(to: scroll, in: self, host: contentView, title: title)
        } else if let header = columnTitle {
            header.detach()
            columnTitle = nil
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        syncColumnTitle()
    }

    /// Scrolls the page to its top (the second tap on the selected tab).
    func scrollToTop(animated: Bool = true) {
        guard let scroll = contentScrollView ?? UKScrollToTop.mainScrollView(in: view) else { return }
        let top = -scroll.adjustedContentInset.top
        guard scroll.contentOffset.y > top + 0.5 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: animated)
    }

    // MARK: Chrome

    /// Header actions; a gallery or a test overrides them. They only ask the navigator to present a sheet.
    func openQuickLinks() { context.navigator?.openQuickLinks() }
    func openAccount() { context.navigator?.openAccount() }
    func openMenu() { context.navigator?.openFlyout() }

    /// Header buttons show when there is a navigator to ask (or a subclass overrides the actions and sets this).
    var showsHeaderButtons: Bool { context.navigator != nil }

    /// The name the Profile button shows (a gallery overrides it with a fixture).
    var headerProfileName: String? { context.navigator?.profileName }

    /// The photo the Profile button draws when the signed-in person has one (a gallery overrides it with a fixture's).
    var headerAvatar: AvatarBox? { context.avatars?.viewerBox ?? context.session?.avatars.viewerBox }

    private func bindChrome() {
        if isSheet {
            navigationItem.largeTitleDisplayMode = .never
            headerFade?.cap = nil
            return
        }
        let items = UKShellHeaderItems(openQuickLinks: { [weak self] in self?.openQuickLinks() },
                                       openAccount: { [weak self] in self?.openAccount() })
        headerItems = items
        items.bindAvatar { [weak self] in self?.headerAvatar }
        // The title mode and the menu button follow the chrome (a rotation to regular width swaps the tab bar for the flyout).
        bag.observe { [weak self] in
            guard let self else { return }
            let chrome = self.context.shell?.chrome ?? ShellChrome(showsMenuButton: false, titleInHeader: false)
            let cap = self.context.shell?.headerEdgeCap
            let inVerticalBar = self.context.shell?.inVerticalBar ?? false
            self.applyChrome(chrome, cap: cap)
            self.syncBarTitle(inVerticalBar: inVerticalBar)
        }
        bag.observe { [weak self] in
            guard let self, self.showsHeaderButtons else { return }
            let shell = self.context.shell
            let reconnecting = self.context.reconnecting
            let state = UKShellHeaderItems.State(
                profileName: self.headerProfileName, attentionCount: shell?.attentionCount ?? 0,
                isOffline: shell?.isOffline ?? false, reconnectingPresent: reconnecting?.isPresent == true,
                reconnectingLit: reconnecting?.isLit == true, isFirstConnect: reconnecting?.isFirstConnect == true,
                inVerticalBar: shell?.inVerticalBar ?? false, contentSize: self.traitCollection.preferredContentSizeCategory)
            self.shellItems = items.items(for: state)
            self.applyShellItems()
        }
    }

    // MARK: Shell and column items

    /// The shell's trailing items (Quick Links, Profile, the reconnecting arc), trailing-most first, as the page last built them.
    private var shellItems: [UIBarButtonItem] = []
    private var columnBar: UKColumnBar?
    private lazy var columnActionItem = UIBarButtonItem(image: nil, style: .plain, target: nil, action: nil)

    /// The column group of a page that hosts columns (``UKColumnBarHosting``). The leading group is built once, around one Back or Close
    /// item; after that the item is hidden, shown and restyled inside the page's motion, so the bar animates it and the shell group slides.
    func setColumnBar(_ bar: UKColumnBar?) {
        let had = columnBar != nil
        let sameItems = columnBar?.items == bar?.items
        columnBar = bar
        guard let bar else {
            applyShellItems()
            return
        }
        let configure = { [self] in
            switch bar.kind {
            case .close:
                columnActionItem.image = UIImage(systemName: "xmark")
                columnActionItem.title = "Close"
                columnActionItem.accessibilityLabel = "Close"
                columnActionItem.accessibilityIdentifier = "split.close"
                columnActionItem.primaryAction = UIAction(title: "Close", image: UIImage(systemName: "xmark")) { _ in bar.perform() }
            case .back:
                columnActionItem.image = UIImage(systemName: "chevron.backward")
                columnActionItem.title = "Back"
                columnActionItem.accessibilityLabel = "Back"
                columnActionItem.accessibilityIdentifier = "columns.back"
                columnActionItem.primaryAction = UIAction(title: "Back", image: UIImage(systemName: "chevron.backward")) { _ in bar.perform() }
            case .none: break
            }
            columnActionItem.isEnabled = bar.isEnabled
            columnActionItem.isHidden = bar.kind == .none
        }
        guard had, sameItems else {
            configure()
            applyShellItems()
            return
        }
        if view.window != nil, isViewLoaded {
            UKMotion.animate(.standard, reduced: .quick, animations: { [self] in
                configure()
                navigationController?.navigationBar.layoutIfNeeded()
            })
        } else {
            configure()
        }
    }

    /// With no column group the shell's items sit on the bar as they always did. With one, the column group (Back or Close and the open
    /// page's own items) is the bar's *leading* group, after the menu button where there is one, and the shell's items are the trailing
    /// group: a separate group each, so the Duo's vertical bar draws them apart, with the column group above the shell's, and, when the
    /// rail runs short, the trailing shell items are what fold into "More" (owner, 2026-11-02).
    private func applyShellItems() {
        let item = navigationItem
        guard showsHeaderButtons || columnBar != nil else {
            // A page with no shell items still takes a column group away when the window narrows (a stale Save stayed on the bar).
            if !item.leadingItemGroups.isEmpty { item.leadingItemGroups = [] }
            if !item.trailingItemGroups.isEmpty { item.trailingItemGroups = [] }
            return
        }
        if let columnBar {
            var shell = Array(shellItems.reversed()).filter { $0.customView != nil || $0.image != nil || $0.title != nil || $0.primaryAction != nil }
            #if DEBUG
            if let extra = ProcessInfo.processInfo.environment["FENTON_DEBUG_RAIL_EXTRA"].flatMap(Int.init), extra > 0 {
                // Crowds the rail to show what folds into "More": extra plain items in the shell group.
                for index in 0..<extra {
                    let dummy = UIBarButtonItem(image: UIImage(systemName: "\(index + 1).circle"), primaryAction: UIAction { _ in })
                    dummy.title = "Extra \(index + 1)"
                    shell.insert(dummy, at: 0)
                }
            }
            #endif
            var leading: [UIBarButtonItemGroup] = []
            if wantsMenuItem, let menuItem { leading.append(UIBarButtonItemGroup(barButtonItems: [menuItem], representativeItem: nil)) }
            leading.append(UIBarButtonItemGroup(barButtonItems: columnBar.items + [columnActionItem], representativeItem: nil))
            item.leadingItemGroups = leading
            item.trailingItemGroups = showsHeaderButtons && !shell.isEmpty ? [UIBarButtonItemGroup(barButtonItems: shell, representativeItem: nil)] : []
        } else {
            if !item.leadingItemGroups.isEmpty { item.leadingItemGroups = [] }
            if !item.trailingItemGroups.isEmpty { item.trailingItemGroups = [] }
            if item.pinnedTrailingGroup != nil { item.pinnedTrailingGroup = nil }
            if wantsMenuItem, item.leftBarButtonItem !== menuItem { item.leftBarButtonItem = menuItem }
            item.rightBarButtonItems = shellItems
        }
        #if DEBUG
        NSLog("COLBARS %@ leading=%d trailing=%d right=%d column=%d shell=%d", String(describing: type(of: self)), item.leadingItemGroups.count, item.trailingItemGroups.count, item.rightBarButtonItems?.count ?? 0, columnBar?.items.count ?? -1, shellItems.count)
        #endif
    }

    private func applyChrome(_ chrome: ShellChrome, cap: CGFloat?) {
        headerFade?.cap = cap
        let largeMode: UINavigationItem.LargeTitleDisplayMode = chrome.titleInHeader ? .never : .automatic
        let changed = navigationItem.largeTitleDisplayMode != largeMode || (navigationItem.style == .browser) != chrome.showsMenuButton
        navigationItem.largeTitleDisplayMode = largeMode
        // The system's own titles (header-edge-fade R7): leading aligned where the hamburger shows (`PageChromeTitle.role`).
        navigationItem.style = chrome.showsMenuButton ? .browser : .navigator
        if changed { refreshTitleBar() }
        // A section root has the menu button when the window shows the flyout (`sectionRootChrome()`).
        menuWanted = chrome.showsMenuButton
        if isSectionRoot, chrome.showsMenuButton {
            if menuItem == nil {
                let item = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), primaryAction: UIAction { [weak self] _ in self?.openMenu() })
                item.title = "Open Navigation"
                item.accessibilityLabel = "Open Navigation"
                item.accessibilityHint = "Opens the navigation menu"
                item.accessibilityIdentifier = "nav.open"
                menuItem = item
            }
            if columnBar == nil { navigationItem.leftBarButtonItem = menuItem }
        } else if menuItem != nil, navigationItem.leftBarButtonItem === menuItem {
            navigationItem.leftBarButtonItem = nil
        }
        if columnBar != nil { applyShellItems() }
    }

    private var wantsMenuItem: Bool { isSectionRoot && menuItem != nil && menuWanted }
    private var menuWanted = false

    /// The Duo's vertical bar keeps a fixed 24 pt title in a bar that never minimises (``UKFixedBarTitle``,
    /// `BarTitleTreatment.fixedMedium`); every other window keeps the system's title.
    private func syncBarTitle(inVerticalBar: Bool) {
        fixedBarTitle.update(item: navigationItem, fallbackTitle: title, fixed: inVerticalBar && !isSheet, traits: traitCollection)
    }

    /// A bar that was already showing the page (a rotation swapped the folded Duo's inline-only title for the large one, or back) reads
    /// the title mode and style again only when it is asked to: without this the page rests with the collapsed title at its top until
    /// the first scroll (`UINavigationBar.sizeToFit()` is the system's own refresh for `largeTitleDisplayMode`).
    private func refreshTitleBar() {
        guard isViewLoaded, view.window != nil, let bar = navigationController?.navigationBar, navigationController?.topViewController === self else { return }
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        bar.sizeToFit()
        view.setNeedsLayout()
        DispatchQueue.main.async { [weak self] in self?.followTopInset() }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        navigationController?.navigationBar.sizeToFit()
        followTopInset()
        syncBarTitle(inVerticalBar: context.shell?.inVerticalBar ?? false)
    }

    /// Moves VoiceOver focus to the menu button after the flyout closes.
    func focusMenuButton() {
        guard let menuItem, view.window != nil else { return }
        UIAccessibility.post(notification: .layoutChanged, argument: menuItem)
    }

    // MARK: Sheets

    /// Presents `page` as a sheet over this page, in the user's appearance (sheets follow the system while pages stay dark).
    /// // TODO(uikit-port): use UKSheet (the Design lane's `hassSheet`) when it lands.
    func presentSheet(_ page: UIViewController, width: HassSheetWidth = .form, height: HassSheetHeight = .fitted) {
        UKShellSheet.present(page, from: self, width: width, height: height)
    }
}
#endif
