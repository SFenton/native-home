#if os(iOS)
import CoreSpotlight
import HassCore
import HassDesign
import HassTelemetry
import UIKit

/// The root of a window: sign-in or the main tabs, plus scene-phase handling and the launch and arrival motion
/// (`.agents/design/direction-g.md`, "Launch and sign-in motion"). The UIKit counterpart of ``RootView``.
///
/// - A cold launch starts on the plain dark ground the launch screen shows (``SignInStyle/base``), which fades away in 0.2 s: onto
///   the sign-in intro when signed out, onto the disk snapshot when signed in (no intro and no spinner; live values then update in
///   place).
/// - A sign-in lifts the sign-in layer away while Home arrives under it (``HomeArrival``), about 0.9 s in all.
/// - A rejected token ends the session and shows the welcome back sign-in (``AppSession/sessionExpired()``).
final class UKRootViewController: UIViewController {
    private let session: AppSession
    let environment = UKShellEnvironment()
    private let arrival = HomeArrival()
    private let bag = UKObservationBag()
    private var shell: UKShellViewController?
    private var login: UKLoginViewController?
    private var gallery: UIViewController?
    private var launchGround: UIView?
    private var signals: UKDeviceSignals?
    private var keepsSignIn = false
    private var signInLeaves = false
    private var lastSignedIn: Bool?
    private var probes: [AnyObject] = []
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var activatedOnce = false
    #if DEBUG
    private var reuseWatcher: Task<Void, Never>?
    #endif

    init(session: AppSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        UKLayoutCensus.install()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        #if DEBUG
        reuseWatcher?.cancel()
        // The Darwin probes hold this object unretained: a probe posted after it is gone would call into freed memory.
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        #endif
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        // One ground under both layers: the tabs leave at once while the sign-in layer fades in, and without it the frames between
        // showed the window's own background (white in light mode) before the sign-in ground arrived.
        view.backgroundColor = UIColor(rgb: SignInStyle.base)
        environment.arrival = arrival
        observers.append(contentsOf: environment.observeAccessibilitySettings())
        signals = UKDeviceSignals(view: view, environment: environment)
        #if DEBUG
        if let page = UKGalleryRouter.requested() {
            // Debug builds only: fixture-driven controls for UI tests and screenshots.
            embed(page)
            gallery = page
        } else {
            bindSession()
        }
        #else
        bindSession()
        #endif
        installProbes()
        #if DEBUG
        installRotationProbe()
        installGalleryReuse()
        #endif
        installLaunchGround()
        observeScene()
    }

    #if DEBUG
    /// App reuse for UI tests (`FENTON_UITEST_REUSE=<request directory>`, `.agents/testing/apple/app-reuse.md`): watches the request
    /// file, and on each reset drops the gallery (with every sheet and alert over it), then builds it again from the new
    /// `FENTON_GALLERY*` variables exactly as a launch would. The `uitest.generation` element carries the count a journey waits on.
    /// Inert, and absent from the tree, in every other launch.
    private func installGalleryReuse() {
        guard GalleryReset.isEnabled() else { return }
        let marker = UKProbeElementView(identifier: "uitest.generation", label: "\(GalleryReset.shared.generation)")
        view.addSubview(marker)
        NSLayoutConstraint.activate([marker.leadingAnchor.constraint(equalTo: view.leadingAnchor), marker.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        probes.append(marker)
        reuseWatcher = Task { await GalleryReset.shared.watchRequests() }
        bag.observe { [weak self, weak marker] in
            let reset = GalleryReset.shared
            let isBlank = reset.isBlank
            let generation = reset.generation
            guard let self else { return }
            if isBlank {
                self.dismissEverythingPresented()
                if let old = self.gallery { self.remove(old); self.gallery = nil }
            } else if self.gallery == nil, let page = UKGalleryRouter.requested() {
                self.embed(page)
                self.gallery = page
                self.view.subviews.compactMap { $0 as? UKProbeElementView }.forEach { self.view.bringSubviewToFront($0) }
            }
            marker?.show("\(generation)")
        }
    }

    /// Sheets and alerts over the gallery leave without animation, so the next gallery can present its own at once.
    private func dismissEverythingPresented() {
        var top: UIViewController? = view.window?.rootViewController ?? self
        while let presented = top?.presentedViewController { top = presented }
        while let controller = top, controller !== (view.window?.rootViewController ?? self), controller.presentingViewController != nil {
            let below = controller.presentingViewController
            controller.dismiss(animated: false)
            top = below
        }
        presentedViewController?.dismiss(animated: false)
    }

    /// `xcrun simctl spawn <udid> notifyutil -p uk.debug.landscape|uk.debug.portrait`: asks the window scene for the orientation, which
    /// is the window rotation a person's turn of the device causes (a rotation probe for layout loops; a debug build only).
    private func installRotationProbe() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        for name in ["uk.debug.landscape", "uk.debug.portrait"] {
            CFNotificationCenterAddObserver(center, me, { _, observer, name, _, _ in
                guard let observer, let name = name?.rawValue as String? else { return }
                let root = Unmanaged<UKRootViewController>.fromOpaque(observer).takeUnretainedValue()
                MainActor.assumeIsolated {
                    let mask: UIInterfaceOrientationMask = name == "uk.debug.landscape" ? .landscapeLeft : .portrait
                    root.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { NSLog("ROTATE error %@", String(describing: $0)) }
                }
            }, name as CFString, nil, .deliverImmediately)
        }
    }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UKLayoutCensus.bump("root")
        signals?.refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !activatedOnce else { return }
        activatedOnce = true
        firstFrame()
        Task {
            // Telemetry (`.agents/patterns/telemetry.md`): MetricKit's daily reports, and the image cache kept under its disk budget.
            MetricKitCollector.shared.start()
            await Task.detached(priority: .background) { ImagePipeline.shared.trimDisk() }.value
        }
        #if DEBUG
        // `FENTON_DUMP_VIEWS=<seconds>` prints the window's view hierarchy once, for layout debugging against the SwiftUI app.
        if let seconds = ProcessInfo.processInfo.environment["FENTON_DUMP_VIEWS"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let window = self?.view.window else { return }
                let text = (window.perform(Selector(("recursiveDescription")))?.takeUnretainedValue() as? String) ?? "unavailable"
                // The simulator shares the host's file system.
                try? text.write(toFile: ProcessInfo.processInfo.environment["FENTON_DUMP_FILE"] ?? "/tmp/uikit-viewdump.txt", atomically: true, encoding: .utf8)
            }
        }
        // Journeys cannot tap a Spotlight result inside the app: `FENTON_OPEN_SPOTLIGHT=<item id>` hands the same activity the
        // system would to the same handler.
        if let identifier = ProcessInfo.processInfo.environment["FENTON_OPEN_SPOTLIGHT"] {
            let activity = NSUserActivity(activityType: CSSearchableItemActionType)
            activity.userInfo = [CSSearchableItemActivityIdentifier: identifier]
            session.push.open(spotlightUserInfo: activity.userInfo)
        }
        #endif
    }

    override var childForStatusBarStyle: UIViewController? { shell ?? login ?? gallery }

    // MARK: Children

    private func embed(_ child: UIViewController, below: UIView? = nil, above: UIView? = nil) {
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let below {
            view.insertSubview(child.view, belowSubview: below)
        } else if let above {
            view.insertSubview(child.view, aboveSubview: above)
        } else {
            view.insertSubview(child.view, at: 0)
        }
        child.didMove(toParent: self)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func remove(_ child: UIViewController) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: Session

    private func bindSession() {
        bag.observe { [weak self] in
            guard let self else { return }
            // Read inside the observation so a change to any of them runs this again.
            _ = self.session.isSignedIn
            _ = self.session.expiredAccount
            self.syncPhase()
        }
    }

    /// Makes the children match the session: the tabs while signed in, the sign-in layer while signed out and while it lifts away.
    private func syncPhase() {
        let signedIn = session.isSignedIn
        if case let .signedIn(connection, _) = session.phase {
            if shell == nil {
                let tabs = UKShellViewController(session: session, connection: connection, environment: environment)
                // The tabs under the sign-in layer; with no sign-in layer they take the window.
                if let login { embed(tabs, below: login.view) } else { embed(tabs) }
                shell = tabs
                Task { await session.backdrop?.refresh() }
            }
        } else if let shell {
            // Signed out: nothing of the person's last session is put back for the next one, and the tabs leave at once.
            shell.clearStoredState()
            remove(shell)
            self.shell = nil
        }
        if !signedIn || keepsSignIn {
            if login == nil || (!signedIn && lastSignedIn == true) { showLogin(fadeIn: lastSignedIn == true) }
        } else if let login, !keepsSignIn {
            remove(login)
            self.login = nil
        }
        lastSignedIn = signedIn
        let isSignedIn = signedIn
        shell?.view.isHidden = false
        login?.view.isUserInteractionEnabled = !isSignedIn
        login?.view.accessibilityElementsHidden = isSignedIn
        if let launchGround { view.bringSubviewToFront(launchGround) }
        view.subviews.compactMap { $0 as? UKProbeElementView }.forEach { view.bringSubviewToFront($0) }
    }

    private func showLogin(fadeIn: Bool) {
        if let login { remove(login) }
        let model = LoginModel(mode: session.expiredAccount.map { .welcomeBack($0) } ?? .fresh)
        let screen = UKLoginViewController(
            model: model, playsIntro: AppRoot.playsIntro(played: session.motion.hasPlayed(.intro)), environment: environment,
            onIntroPlayed: { [session] in session.motion.markPlayed(.intro) },
            onUseDifferentAccount: { [session] in session.forgetExpiredAccount() },
            onSignedIn: { [weak self] server, tokens in try self?.signedIn(server, tokens) })
        embed(screen, above: shell?.view)
        login = screen
        if fadeIn {
            // The sign-in layer fades in over the ground (`MotionTokens.crossFade`).
            screen.view.alpha = 0
            UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: .curveEaseInOut) { screen.view.alpha = 1 }
        }
    }

    // MARK: Motion

    /// The first frame is up: end the launch interval and let the launch ground go.
    private func firstFrame() {
        Task { @MainActor in
            await Task.yield()
            Telemetry.endTracked(Telemetry.Name.launch)
            // Signed out there is no snapshot to show.
            if !session.isSignedIn { Telemetry.cancelTracked(Telemetry.Name.snapshotShown) }
            if let ground = launchGround {
                UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: .curveEaseOut, animations: { ground.alpha = 0 },
                               completion: { _ in ground.removeFromSuperview() })
                launchGround = nil
            }
            // The intro (signed out) or the snapshot (signed in) is on screen now: that is what a launch cost run measures.
            if LaunchCostProbe.isEnabled { Task { await LaunchCostProbe.measureWindow(session.isSignedIn ? "snapshot" : "intro") } }
        }
    }

    private func installLaunchGround() {
        let ground = UIView(frame: view.bounds)
        ground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ground.backgroundColor = UIColor(rgb: SignInStyle.base)
        ground.isUserInteractionEnabled = false
        ground.accessibilityElementsHidden = true
        view.addSubview(ground)
        launchGround = ground
    }

    /// Tokens arrived: hold Home's elements back, start the session under the sign-in layer, then lift the layer away while the
    /// backdrop settles and the header, chips, cards and tab bar come in (about 0.9 s; Reduce Motion cross-fades).
    func signedIn(_ server: HassServer, _ tokens: AuthTokens) throws {
        Telemetry.cancelTracked(Telemetry.Name.snapshotShown)
        // The arrival plays once per session (reset at sign-out); any other sign-in just swaps the screens.
        guard !session.motion.hasPlayed(.signInArrival) else {
            Telemetry.cancelTracked(Telemetry.Name.arrival)
            try session.didSignIn(server: server, tokens: tokens)
            syncPhase()
            Announcer.screenChanged(announcing: AppRoot.arrivalAnnouncement)
            return
        }
        // Building Home behind the sign-in layer is one long turn of its own; the arrival motion is measured after it.
        LaunchCostProbe.begin("arrival-build")
        arrival.begin()
        keepsSignIn = true
        signInLeaves = false
        do {
            try session.didSignIn(server: server, tokens: tokens)
            syncPhase()
        } catch {
            arrival.finish()
            keepsSignIn = false
            throw error
        }
        session.motion.markPlayed(.signInArrival)
        let reduceMotion = environment.reduceMotion
        Task { @MainActor in
            // Home's views are built, held back; now they and the layer move.
            try? await Task.sleep(for: .milliseconds(60))
            LaunchCostProbe.finish()
            LaunchCostProbe.begin("arrival")
            self.liftSignIn(reduceMotion: reduceMotion)
            self.arrival.reveal()
            // The staggered items have no one completion; the arrival's own length bounds them.
            try? await Task.sleep(for: HomeArrival.duration)
            self.arrival.finish()
            // The sign-in layer is hidden from VoiceOver and Home is built: move focus there and say where it is.
            Announcer.screenChanged(announcing: AppRoot.arrivalAnnouncement)
            Telemetry.endTracked(Telemetry.Name.arrival)
            LaunchCostProbe.finish()
        }
    }

    /// The sign-in layer goes when its own lift ends, not after a guessed delay: it rises 18 pt, shrinks to 97% and fades
    /// (`MotionTokens.Arrival.lift`, easeOut 0.4 s); Reduce Motion cross-fades only.
    private func liftSignIn(reduceMotion: Bool) {
        guard let login else {
            keepsSignIn = false
            return
        }
        let done: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.keepsSignIn = false
            self.signInLeaves = false
            if self.login === login, self.session.isSignedIn {
                self.remove(login)
                self.login = nil
            }
        }
        if reduceMotion {
            UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: .curveEaseInOut, animations: { login.view.alpha = 0 }, completion: done)
        } else {
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseOut, animations: {
                login.view.alpha = 0
                login.view.transform = CGAffineTransform(translationX: 0, y: MotionTokens.Arrival.liftDistance)
                    .scaledBy(x: MotionTokens.Arrival.liftScale, y: MotionTokens.Arrival.liftScale)
            }, completion: done)
        }
    }

    // MARK: Scene phase

    /// `lifecycle.didBecomeActive/didEnterBackground` and the shell's saves follow the scene (`@Environment(\.scenePhase)`).
    private func observeScene() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            let sceneID = (note.object as? UIScene).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, self.isOurScene(sceneID) else { return }
                if case let .signedIn(_, lifecycle) = self.session.phase { lifecycle.didBecomeActive() }
                // Back in the foreground: a house layout that never arrived is asked for again.
                self.session.houseConfig?.resubscribeIfNeeded()
                self.shell?.sceneBecameActive()
            }
        })
        observers.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] note in
            let sceneID = (note.object as? UIScene).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, self.isOurScene(sceneID) else { return }
                self.shell?.sceneLeftForeground()
            }
        })
        observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] note in
            let sceneID = (note.object as? UIScene).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, self.isOurScene(sceneID) else { return }
                if case let .signedIn(_, lifecycle) = self.session.phase { lifecycle.didEnterBackground() }
                self.shell?.sceneLeftForeground()
                self.shell?.sceneEnteredBackground()
            }
        })
    }

    private func isOurScene(_ id: ObjectIdentifier?) -> Bool {
        guard let id, let scene = view.window?.windowScene else { return false }
        return id == ObjectIdentifier(scene)
    }

    // MARK: Probes

    /// The diagnostics overlays: invisible 2 pt elements in the corners that journeys and `tools/ios_*.sh` read.
    private func installProbes() {
        func add(_ probe: UKProbeElementView, corner: (UIView) -> [NSLayoutConstraint]) {
            view.addSubview(probe)
            NSLayoutConstraint.activate(corner(probe))
        }
        #if DEBUG
        if UKResourceCensusProbe.isEnabled {
            let probe = UKResourceCensusProbe()
            probes.append(probe)
            add(probe.element) { [view] in [$0.leadingAnchor.constraint(equalTo: view!.leadingAnchor), $0.topAnchor.constraint(equalTo: view!.topAnchor)] }
        }
        // What each appearance source says (`FENTON_APPEARANCE_DEBUG=1`), for the system-appearance journeys.
        if UKAppearanceProbe.isEnabled {
            let probe = UKAppearanceProbe()
            probes.append(probe)
            add(probe.element) { [view] in [$0.leadingAnchor.constraint(equalTo: view!.leadingAnchor), $0.bottomAnchor.constraint(equalTo: view!.bottomAnchor, constant: -2)] }
        }
        #endif
        // Scroll cost runs (`FENTON_SCROLLCOST=1`, any build).
        if UKScrollCostProbe.isEnabled {
            let probe = UKScrollCostProbe()
            probes.append(probe)
            add(probe.element) { [view] in [$0.trailingAnchor.constraint(equalTo: view!.trailingAnchor), $0.topAnchor.constraint(equalTo: view!.topAnchor)] }
        }
        // Navigation cost runs (`FENTON_NAVPERF=1`).
        if UKNavigationPerfProbe.isEnabled {
            let probe = UKNavigationPerfProbe()
            probes.append(probe)
            add(probe.element) { [view] in [$0.leadingAnchor.constraint(equalTo: view!.leadingAnchor), $0.topAnchor.constraint(equalTo: view!.topAnchor, constant: 2)] }
        }
        // Launch cost runs (`FENTON_LAUNCHCOST=1`, any build).
        if UKLaunchCostProbe.isEnabled {
            let probe = UKLaunchCostProbe()
            probes.append(probe)
            add(probe.element) { [view] in [$0.trailingAnchor.constraint(equalTo: view!.trailingAnchor), $0.bottomAnchor.constraint(equalTo: view!.bottomAnchor)] }
        }
    }
}
#endif
