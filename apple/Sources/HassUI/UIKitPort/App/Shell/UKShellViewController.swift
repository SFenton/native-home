#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import Observation
import UIKit

/// The signed-in shell: the UIKit counterpart of ``MainTabView``. One `UITabBarController` in every window so each section
/// keeps its stack and scroll position; compact width shows the tab bar, regular width hides it and navigates through
/// ``UKNavigationFlyoutView`` instead (web `drawer-only`).
///
/// The shell owns what the SwiftUI shell kept in `@State` and `@Environment`: the ``ShellNavigator`` (the source of truth for the
/// selected tab and each stack, driving the section controllers), the ``SessionModels``, and the ``UKShellEnvironment`` it
/// publishes to every page through ``UKContext/shell``. It always draws dark (direction G: pages sit on the dimmed house photo);
/// sheets follow the system instead.
@MainActor
final class UKShellViewController: UIViewController, UITabBarControllerDelegate, UIGestureRecognizerDelegate {
    private let session: AppSession
    private let connection: HassConnection
    private let environment: UKShellEnvironment
    let navigator = ShellNavigator()
    private let sessionModels = SessionModels()
    private let tabs = UITabBarController()
    private var sections: [AppSection: UKSectionNavigationController] = [:]
    private let backdrop: UKBackdropView
    private var flyout: UKNavigationFlyoutView?
    private var offline: UKOfflineOverlay?
    private var reconnecting: UKReconnectingHost?
    private var arrivalChrome: UKArrivalChrome?
    private let bag = UKObservationBag()
    private let defaults = UKDefaultsTick()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var restored = false
    private var lastOverdue: Int??
    private var lastIconKey: String?
    private var profileTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var lastConnected: Bool?
    /// Presents the Setup flow's sheet (`SetupPresenter`).
    private var setupPresenter: UKSetupPresenter?
    private var lastLinked: Bool?

    /// A compact navigation bar's height on this device (the header edge cap's second half).
    private static let barHeight: CGFloat = UINavigationBar().sizeThatFits(CGSize(width: 1000, height: 1000)).height

    /// - Parameters:
    ///   - session: The app's one session.
    ///   - connection: The live connection of the signed-in phase.
    ///   - environment: What the root publishes to pages; the shell fills in its navigation style and chrome.
    init(session: AppSession, connection: HassConnection, environment: UKShellEnvironment) {
        self.session = session
        self.connection = connection
        self.environment = environment
        backdrop = UKBackdropView(store: session.backdrop, shell: environment)
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        #if DEBUG
        // The Darwin probes hold this object unretained: a probe posted after it is gone would call into freed memory.
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        #endif
    }

    /// The context every section's pages are created with.
    private lazy var context: UKContext = {
        var context = UKContext(store: connection.store, caller: connection)
        context.connection = connection
        context.session = session
        context.push = session.push
        context.location = session.location
        context.backdrop = session.backdrop
        context.motion = session.motion
        context.navigator = navigator
        context.sessionModels = sessionModels
        context.shell = environment
        context.reconnecting = reconnecting?.indicator
        return context
    }()

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(rgb: SignInStyle.base)
        // Also behind the root, where no page draws: under the tab bar and the home indicator.
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)

        reconnecting = UKReconnectingHost(connection: connection)
        setupPresenter = UKSetupPresenter(setup: session.setup, host: self)
        updateStyle()
        // Before any state has arrived (a first sign-in; a snapshot launch never is): tiles keep their names and show a soft bar.
        let pageContext = context.with { $0.reconnecting = reconnecting?.indicator; $0.valuesPending = !connection.store.hasReceivedFirstState }
        context = pageContext
        let controllers = AppSection.allCases.map { section -> UKSectionNavigationController in
            let controller = UKSectionNavigationController(section: section, context: pageContext, navigator: navigator)
            sections[section] = controller
            return controller
        }
        tabs.setViewControllers(controllers, animated: false)
        tabs.delegate = self
        addChild(tabs)
        // Clear all the way down: the wallpaper above is the window's one, and every page, section stack and tab container shows it.
        tabs.view.backgroundColor = .clear
        tabs.view.isOpaque = false
        tabs.view.frame = view.bounds
        tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tabs.view)
        tabs.didMove(toParent: self)

        let flyout = UKNavigationFlyoutView(navigator: navigator, shell: environment)
        flyout.frame = view.bounds
        flyout.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flyout)
        self.flyout = flyout
        offline = UKOfflineOverlay(host: view)
        arrivalChrome = UKArrivalChrome(shell: self, environment: environment)

        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        pan.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.delegate = self
        view.addGestureRecognizer(pan)
        edgePan = pan

        bindShell()
        observeDefaults()
        #if DEBUG
        installTabProbe()
        #endif
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitDisplayScale.self]) { (shell: UKShellViewController, _) in
            shell.updateStyle()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !restored else { return }
        restored = true
        navigator.selection = Self.storedSelection(in: view.window?.windowScene?.session)
        restoreRoutes()
        // A relaunch draws the disk snapshot's values on this first frame: that is when the snapshot is shown.
        if connection.store.freshness != .empty { Telemetry.endTracked(Telemetry.Name.snapshotShown) }
        tabs.selectedIndex = AppSection.allCases.firstIndex(of: navigator.selection) ?? 0
        // A scroll cost launch (`FENTON_SCROLLCOST_OPEN`) starts on the page it measures.
        if let path = ScrollCostProbe.launchPath { navigator.open(PushDestination(dashboardPath: path)) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sectionControllers.forEach { $0.isSettled = true }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UKLayoutCensus.bump("shell")
        let top = view.safeAreaInsets.top.rounded()
        let cap = HeaderEdgeFade.edgeCap(statusTop: top, barHeight: Self.barHeight, barIsRail: environment.inVerticalBar)
        if cap != environment.headerEdgeCap { UKLayoutCensus.note("cap \(String(describing: environment.headerEdgeCap)) -> \(cap)") }
        if cap != environment.headerEdgeCap { environment.headerEdgeCap = cap }
        // The window's full size, which the wallpaper is rendered for and fills on every page.
        let canvas = view.bounds.size
        if canvas != environment.canvas {
            environment.canvas = canvas
            session.backdrop?.setWindow(canvas, scale: Double(traitCollection.displayScale))
        }
        offline?.hostLaidOut()
        updateStyle()
    }

    /// The navigation style and chrome follow the window's width class, its hinge (the unfolded Duo keeps the tab bar) and whether
    /// the system made a vertical bar.
    private func updateStyle() {
        let style = ShellNavigationStyle.resolve(isRegularWidth: traitCollection.horizontalSizeClass == .regular,
                                                 hasHinge: environment.windowFold.hinge != nil)
        let chrome = ShellChrome.resolve(style: style, inVerticalBar: environment.inVerticalBar)
        if style != environment.style || chrome != environment.chrome { UKLayoutCensus.note("style \(style) chrome \(chrome) size \(view.bounds.size) hinge \(environment.windowFold.hinge != nil)") }
        if style != environment.style { environment.style = style }
        if chrome != environment.chrome { environment.chrome = chrome }
        edgePan?.isEnabled = chrome.edgeSwipe
        // Regular width hides the tab bar (the flyout navigates); on iPadOS 18+ the floating top tab bar too.
        let hidden = style == .flyout
        if UKGlassEra.hasIOS18, #available(iOS 18.0, *) {
            if tabs.isTabBarHidden != hidden { tabs.setTabBarHidden(hidden, animated: false) }
        } else {
            tabs.tabBar.isHidden = hidden
        }
        if !chrome.showsMenuButton { navigator.dismissFlyout() }
    }

    #if DEBUG
    /// `xcrun simctl spawn <udid> notifyutil -p uk.debug.tab.<home|security|climate|chores|settings>`: selects a tab, for rotation probes.
    private func installTabProbe() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        for section in AppSection.allCases {
            CFNotificationCenterAddObserver(center, me, { _, observer, name, _, _ in
                guard let observer, let raw = (name?.rawValue as String?)?.split(separator: ".").last, let section = AppSection(rawValue: String(raw)) else { return }
                let shell = Unmanaged<UKShellViewController>.fromOpaque(observer).takeUnretainedValue()
                MainActor.assumeIsolated { shell.navigator.selection = section }
            }, "uk.debug.tab.\(section.rawValue)" as CFString, nil, .deliverImmediately)
        }
    }
    #endif

    // MARK: Binding

    private func bindShell() {
        let navigator = navigator
        // A fold or unfold need not change the size class: the hinge and the vertical bar arrive after layout (``UKDeviceSignals``).
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.environment.windowFold
            _ = self.environment.inVerticalBar
            self.updateStyle()
        }
        // The selected tab follows the navigator (a notification's page, Quick Links, the flyout).
        bag.observe { [weak self] in
            guard let self else { return }
            let selection = navigator.selection
            let index = AppSection.allCases.firstIndex(of: selection) ?? 0
            if self.tabs.selectedIndex != index { self.tabs.selectedIndex = index }
            self.saveSelection(selection)
        }
        // The Chores tab's badge: the viewer's overdue chores (``OverdueChoresBadge``), spoken with the name as the flyout row does.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.defaults.version
            let count = OverdueChoresBadge.overdue(viewerUserId: UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey),
                                                   store: self.connection.store)
            if self.lastOverdue == nil || self.lastOverdue! != count {
                self.lastOverdue = .some(count)
                navigator.overdueChores = count
            }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let overdue = navigator.overdueChores
            for (section, controller) in self.sections {
                controller.tabBarItem.badgeValue = NavigationMenu.badgeText(for: section, overdue: overdue)
                controller.tabBarItem.accessibilityLabel = NavigationMenu.accessibilityLabel(for: section, overdue: overdue)
            }
        }
        // The Profile button's count, and the app icon badge that shows it (`.agents/platforms/apple/badge.md`).
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.defaults.version
            let viewer = UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey)
            let count = ShellAttention.count(store: self.connection.store, viewerUserId: viewer)
            if count != self.environment.attentionCount { self.environment.attentionCount = count }
            let enabled = UserDefaults.standard.object(forKey: AppIconBadgeSync.enabledKey) as? Bool ?? true
            let key = "\(count)|\(enabled)"
            guard key != self.lastIconKey else { return }
            self.lastIconKey = key
            Task { await AppIconBadgeSync.shared.update(count: count) }
        }
        // No network path at all: the offline chip under the header, and the Profile button's badge.
        bag.observe { [weak self] in
            guard let self else { return }
            let isOffline = self.connection.isOffline
            if isOffline != self.environment.isOffline { self.environment.isOffline = isOffline }
            let cap = self.environment.headerEdgeCap ?? 0
            self.offline?.update(isOffline: isOffline, headerEnd: cap, reduceMotion: self.environment.reduceMotion)
        }
        // The session hears the connection's state (a rejected token ends the session).
        bag.observe { [weak self] in
            guard let self else { return }
            let status = self.connection.status
            self.session.connectionStatusChanged(status)
        }
        // Again once connected: a lookup before the socket is up fails, and the cached name stays meanwhile.
        bag.observe { [weak self] in
            guard let self else { return }
            var connected = false
            if case .connected = self.connection.status { connected = true }
            guard connected != self.lastConnected else { return }
            self.lastConnected = connected
            self.profileTask?.cancel()
            self.profileTask = Task { await self.loadProfileName() }
        }
        // Home Assistant creates the phone's tracker on its first location update, so link again once one is accepted.
        bag.observe { [weak self] in
            guard let self else { return }
            let linked = self.session.location?.reporter.lastReportDate != nil
            guard linked != self.lastLinked else { return }
            self.lastLinked = linked
            self.presenceTask?.cancel()
            self.presenceTask = Task { await self.linkPresenceAfterReport() }
        }
        // A notification's page: also on appear, for a tap that launched the app.
        bag.observe { [weak self] in
            guard let self, let request = self.session.push.pendingRequest else { return }
            navigator.open(request.destination, anchor: request.anchor)
            self.session.push.didOpen(request)
        }
        // The location permission step belongs to the Setup flow (`SetupCoordinator`), which ``UKSetupPresenter`` presents;
        // Account's Share Location row still opens the permission screen.
        // Shell state saved with the scene: the stacks are put back for a launch within 30 minutes.
        bag.observe { [weak self] in
            guard let self else { return }
            let routes = navigator.restorableRoutes
            guard self.restored else { return }
            self.saveRoutes(routes)
        }
    }

    // MARK: Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// The leading-edge swipe opens the flyout while the selected section is at its root (deeper, the system's back swipe owns
    /// that edge). Once it recognizes it cancels the touch in the content, so a swipe that starts on a control opens only the flyout.
    @objc private func edgePanned(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        edgeSwipeEnded(translation: recognizer.translation(in: view), edges: recognizer.edges)
    }

    /// A leading-edge swipe ended (its recognizer's state cannot be set, so a hosted test calls this).
    func edgeSwipeEnded(translation raw: CGPoint, edges: UIRectEdge) {
        let flip: CGFloat = edges == .right ? -1 : 1
        navigator.edgeSwipeEnded(startX: 0, translation: CGSize(width: raw.x * flip, height: raw.y))
    }

    // MARK: Tabs

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard let controller = viewController as? UKSectionNavigationController else { return true }
        // Everything goes through the navigator, whose setter also runs for a tap on the selected tab (the second tap).
        // A tab switch is a cut: the content swaps with no transition (`.agents/design/motion.md` §4.1).
        if controller.section != navigator.selection { session.motion.measureCut(.tabSwitch(controller.section.title)) }
        navigator.tabTapped(controller.section)
        if let index = AppSection.allCases.firstIndex(of: navigator.selection), tabBarController.selectedIndex != index {
            UIView.performWithoutAnimation { tabBarController.selectedIndex = index }
        }
        return false
    }

    // MARK: Hiding the content while the flyout covers it

    /// While the flyout is open its scrim covers the content; the content is hidden from VoiceOver too. The flyout is a sibling
    /// outside the tab controller, so it stays reachable.
    fileprivate func setContentHidden(fromAccessibility hidden: Bool) {
        guard tabs.view.accessibilityElementsHidden != hidden else { return }
        tabs.view.accessibilityElementsHidden = hidden
        backdrop.accessibilityElementsHidden = true
    }

    // MARK: Profile and presence

    /// Reads the signed-in user for the profile button (the cached name shows until it arrives) and for the `mobile_app`
    /// registration, which is per Home Assistant user; then offers location once the notification alert is answered.
    private func loadProfileName() async {
        guard let user = try? await connection.currentUser(), !Task.isCancelled else { return }
        if navigator.profileName != user.name { navigator.profileName = user.name }
        // Who is viewing, for the Profile badge and sheet (Your Summary) before the Chores tab has ever been opened.
        UserDefaults.standard.set(user.id, forKey: ChoresModel.viewerDefaultsKey)
        // Whose photo the Profile button draws: the person entity with this user's id.
        session.avatars.setViewer(userID: user.id)
        await session.push.didConnect(userID: user.id, userName: user.name)
        // A phone that reports location follows its signed-in user: its tracker goes on that user's person. An iPad reports but
        // never does (one left at home would mark its person home); ``LocationCoordinator`` decides.
        await session.location?.linkPresence(user: user, api: connection)
        // Then the Setup flow: Notifications, Time Sensitive, Location, whichever are still unseen.
        await session.setup.offerIfNeeded()
    }

    private func linkPresenceAfterReport() async {
        guard let location = session.location, location.linksPresence, location.reporter.lastReportDate != nil,
              session.push.mobileApp.presenceLink?.isLinked != true, let user = try? await connection.currentUser() else { return }
        await location.linkPresence(user: user, api: connection)
    }

    // MARK: Stored state (SceneStorage's counterpart)

    private enum StoreKey {
        static let selection = "selectedTab"
        static let routes = "shellRoutes"
        static let savedAt = "shellRoutesSavedAt"
    }

    private static func storedSelection(in sceneSession: UISceneSession?) -> AppSection {
        (sceneSession?.userInfo?[StoreKey.selection] as? String).flatMap(AppSection.init(rawValue:)) ?? .home
    }

    private func saveSelection(_ section: AppSection) {
        guard restored, let sceneSession = view.window?.windowScene?.session else { return }
        var info = sceneSession.userInfo ?? [:]
        info[StoreKey.selection] = section.rawValue
        sceneSession.userInfo = info
    }

    /// Puts back the pages a launch within 30 minutes of the last one left on screen. A notification's page (which opens after
    /// this) or a stack that is already deeper than its root wins.
    private func restoreRoutes() {
        guard session.push.pendingRequest == nil, navigator.restorableRoutes.isEmpty,
              let info = view.window?.windowScene?.session.userInfo,
              RouteRestore.isFresh(savedAt: info[StoreKey.savedAt] as? Double ?? 0) else { return }
        navigator.restore(RouteRestore.decode(info[StoreKey.routes] as? Data))
    }

    fileprivate func saveRoutes(_ routes: [AppSection: [ShellRoute]]) {
        guard let sceneSession = view.window?.windowScene?.session else { return }
        var info = sceneSession.userInfo ?? [:]
        info[StoreKey.routes] = RouteRestore.encode(routes)
        info[StoreKey.savedAt] = Date().timeIntervalSince1970
        sceneSession.userInfo = info
    }

    /// Leaving the app is the last time the pages were seen; coming back inside the window keeps them.
    func sceneLeftForeground() { saveRoutes(navigator.restorableRoutes) }

    /// Signed out: nothing of the person's last session is put back for the next one.
    func clearStoredState() {
        guard let sceneSession = view.window?.windowScene?.session else { return }
        var info = sceneSession.userInfo ?? [:]
        info[StoreKey.routes] = nil
        info[StoreKey.savedAt] = 0
        sceneSession.userInfo = info
    }

    /// The scene came to the foreground: send a fix (`LocationPermissionPresenter`).
    func sceneBecameActive() {
        // The notification answers again, so the Time Sensitive step and Settings follow a change made in iOS Settings.
        setupPresenter?.sceneBecameActive()
        guard let location = session.location else { return }
        Task { await location.didBecomeActive() }
    }

    /// The app entered the background: the next foreground session sends its Launch update (`LocationPermissionPresenter.handle`).
    func sceneEnteredBackground() {
        session.location?.didEnterBackground()
    }

    private func observeDefaults() {
        let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [defaults] _ in
            MainActor.assumeIsolated { defaults.version &+= 1 }
        }
        observers.append(token)
        // The flyout hides the content from VoiceOver while it is open.
        bag.observe { [weak self] in
            guard let self else { return }
            self.setContentHidden(fromAccessibility: self.navigator.isFlyoutOpen)
        }
    }

    /// The section controllers, for the arrival hold.
    var sectionControllers: [UKSectionNavigationController] { AppSection.allCases.compactMap { sections[$0] } }

    /// The tab bar, for the arrival hold.
    var tabBar: UITabBar { tabs.tabBar }
}

/// A tick the shell bumps when `UserDefaults` changes, so an observation that reads a defaults key (`@AppStorage` in SwiftUI)
/// runs again.
@MainActor
@Observable
final class UKDefaultsTick {
    var version = 0
}

/// Screens the shell shows that belong to another lane's feature, with a default until that lane replaces it.
@MainActor
enum UKShellHooks {
    /// The location permission screen (`LocationPermissionSheet`, the Settings lane's): given the coordinator, the context and a
    /// dismiss action. Replace this closure from the Settings lane's entry file at launch; the default is a placeholder with Close.
    static var locationPermission: (LocationCoordinator, UKContext, @escaping () -> Void) -> UIViewController = { location, _, dismiss in
        // The Household lane's screen (`LocationPermissionSheet`).
        UKLocationPermission.make(location: location, onClose: dismiss)
    }
}
#endif
