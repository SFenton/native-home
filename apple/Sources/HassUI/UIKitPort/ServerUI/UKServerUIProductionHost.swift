#if os(iOS)
import HassCore
import OSLog
import HassDesign
import HassTelemetry
import UIKit

// MARK: - Published product root and compiled recovery boundary

/// Minimal compiled recovery is available before a layout arrives. Product pages always come from the publication Home Assistant serves.
/// A saved layout is adopted in the first layout pass, so a signed-in cold launch never shows the recovery ground when one exists.
@MainActor
final class UKServerUIProductionHost: UIViewController {
    /// Validated for every window before any visible mutation in the shared commit turn.
    struct ApplyPlan {
        let validate: () throws -> Void
        let apply: () throws -> Void
    }

    let sceneID = UUID()
    private let runtime: UKServerUIProductionRuntime
    private let session: AppSession
    private let connection: HassConnection
    private let environment: UKShellEnvironment
    private let bag = UKObservationBag()
    private(set) var renderer: UKServerUIRenderer?
    private var recovery: UIView?
    private var setupPresenter: UKSetupPresenter?
    private var lastConnected = false
    private var lastFailure: String?
    private let status = UILabel()
    private let statusRetry = UIButton(type: .system)
    private let statusPanel = UIStackView()
    private var firstLoadDeadline: Task<Void, Never>?
    private var loadingExpired = false
    private var adoptionFailed = false
    /// Why the saved layout could not attach to this scene: the case and pointer only.
    private var adoptionDiagnostic: String?
    private var adoptionAttempted = false
    private var routeFailure: String?
    /// A Try Again on the boundary is running: its button shows the busy title until the answer returns.
    private var isRetrying = false
    private var layoutWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private static let log = Logger(subsystem: "com.sfenton.home", category: "ServerUI")

    deinit { firstLoadDeadline?.cancel() }

    init(runtime: UKServerUIProductionRuntime, session: AppSession, connection: HassConnection,
         environment: UKShellEnvironment) {
        self.runtime = runtime
        self.session = session
        self.connection = connection
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
        runtime.attach(self, id: sceneID)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        setupPresenter = UKSetupPresenter(setup: session.setup, host: self)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textColor = .label
        status.backgroundColor = .secondarySystemBackground
        status.accessibilityIdentifier = "server-ui.production.status"
        status.isHidden = true
        statusRetry.accessibilityIdentifier = "server-ui.production.refresh"
        statusRetry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        statusRetry.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let text = self.runtime.store?.current?.document.bootstrap?.recovery.loadingTitle { Announcer.announce(text) }
            Task { await self.runtime.retry() }
        }, for: .touchUpInside)
        statusPanel.axis = .vertical
        [status, statusRetry].forEach(statusPanel.addArrangedSubview)
        statusPanel.isHidden = true
        statusPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusPanel)
        NSLayoutConstraint.activate([
            statusPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            statusPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            statusPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        // Only the store's state re-runs it: the boundary is rebuilt as views, and UIKit mutates what that reads on every layout
        // pass, which inside the tracking scope rebuilt it every frame (the accessibility tree churned, the audit saw
        // element-less "no description" issues).
        bag.observe(track: { [weak self] in
            guard let self else { return }
            _ = self.runtime.store?.status
            _ = self.runtime.store?.remote
            _ = self.runtime.store?.rejection
            _ = self.runtime.store?.current
            _ = self.runtime.providerFailure
        }, apply: { [weak self] in self?.showStatus() })
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.session.houseConfig?.current
            self.runtime.refreshProviders()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.runtime.store?.current
            _ = self.renderer?.navigation.snapshot
            self.openPendingDestination()
            // A navigation or a new publication is when an open interaction has most likely ended.
            self.runtime.interactionMayHaveEnded()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            // A permission explanation or system alert ending lets a deferred layout commit.
            if !self.session.setup.blocksPublication { self.runtime.interactionMayHaveEnded() }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let status = self.connection.status
            let connected: Bool
            if case .connected = status { connected = true } else { connected = false }
            let justConnected = connected && !self.lastConnected
            self.lastConnected = connected
            self.session.connectionStatusChanged(status)
            if justConnected {
                Task { [weak self] in
                    guard let self else { return }
                    await self.runtime.reconnected()
                    if self.renderer != nil, self.session.isCurrentConnection(self.connection) { await self.session.setup.offerIfNeeded() }
                }
            }
        }
        guard runtime.store != nil, renderer == nil else { return }
        firstLoadDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
            guard let self, self.renderer == nil else { return }
            self.loadingExpired = true
            self.showStatus()
        }
    }

    /// Whether the window has a size to draw a backdrop for.
    var hasGeometry: Bool { view.bounds.width > 0 && view.bounds.height > 0 }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adoptSavedPublicationIfNeeded()
        if hasGeometry { runtime.layoutChanged(id: sceneID) }
    }

    /// The restored last-good publication goes on screen in the first layout pass that has a size, before the first frame is drawn.
    /// The backdrop's blur finishes after it; the layout itself never waits on the network or the blur.
    private func adoptSavedPublicationIfNeeded() {
        guard !adoptionAttempted, renderer == nil, view.bounds.width > 0, view.bounds.height > 0,
              let store = runtime.store, let publication = store.current, let prepared = store.prepared else { return }
        adoptionAttempted = true
        do {
            try apply(publication, prepared: prepared, requireBackdropImage: false)
        } catch {
            adoptionFailed = true
            adoptionDiagnostic = "adoption: " + ServerUIRejectionDiagnostic.describe(error)
            Self.log.error("Saved publication could not attach: \(self.adoptionDiagnostic ?? "", privacy: .public)")
            showStatus()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setForeground(view.window?.windowScene?.activationState == .foregroundActive)
        setupPresenter?.refresh()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            firstLoadDeadline?.cancel()
            runtime.detach(id: sceneID)
        }
    }

    func setForeground(_ active: Bool) {
        runtime.setForeground(active, id: sceneID)
        if active { setupPresenter?.sceneBecameActive() }
    }

    func validate(_ publication: ServerUICompositionPublication) throws {
        let supplied = runtime.providers.supplementalProviders(for: publication)
        let settings = try runtime.providers.settings(for: publication, sceneID: sceneID)
        try renderer?.validateUpdate(publication, collections: runtime.providers.presentationCollections(settings, for: publication),
                                     records: runtime.providers.records(for: publication, sceneID: sceneID),
                                     settingsProviders: settings,
                                     bedroomProviders: supplied.bedrooms,
                                     remoteProviders: supplied.remotes, canEditBedroom: runtime.providers.canEditBedroom)
    }

    func preferredBlurPercent(fallback: Int) -> Int { runtime.providers.preferredBlurPercent(fallback: fallback) }

    func apply(_ publication: ServerUICompositionPublication, prepared: UKServerUIProductionRuntime.Prepared,
               requireBackdropImage: Bool = true) throws {
        let plan = try prepareApply(publication, prepared: prepared, requireBackdropImage: requireBackdropImage)
        try plan.validate()
        try plan.apply()
    }

    /// Builds the actual detached renderer during preparation, before the publication is durably written.
    /// - Parameter requireBackdropImage: `false` for a saved layout adopted at launch, whose blur renders after the first frame.
    func prepareApply(_ publication: ServerUICompositionPublication, prepared: UKServerUIProductionRuntime.Prepared,
                      requireBackdropImage: Bool = true) throws -> ApplyPlan {
        let next: UKServerUIRenderer
        let previous = renderer
        let size = view.bounds.size
        let scale = traitCollection.displayScale
        let backdrop = requireBackdropImage ? try prepared.readyBackdrop(for: self) : try prepared.adoptionBackdrop(for: self)
        let preparedBlurPercent = backdrop.blur.percent
        let records = try runtime.providers.records(for: publication, sceneID: sceneID)
        let settings = try runtime.providers.settings(for: publication, sceneID: sceneID, blur: backdrop.blur)
        let collections = try runtime.providers.presentationCollections(settings, for: publication, sceneID: sceneID)
        let (bedrooms, remotes) = runtime.providers.supplementalProviders(for: publication)
        let canEditBedroom = runtime.providers.canEditBedroom
        if let renderer {
            try renderer.validateUpdate(publication, collections: collections, records: records, settingsProviders: settings,
                                        bedroomProviders: bedrooms, remoteProviders: remotes,
                                        canEditBedroom: canEditBedroom)
            next = renderer
        } else {
            for case let preferences as UKServerUIPreferencesProvider in settings.values {
                preferences.adoptBlur(backdrop.blur)
            }
            var context = UKContext(store: connection.store, caller: runtime.providers.caller)
            context.connection = connection
            context.session = session
            context.push = session.push
            context.location = session.location
            context.motion = session.motion
            context.shell = environment
            next = try UKServerUIRenderer(publication: publication, context: context, backdrop: backdrop,
                collections: collections, records: records,
                bedroomProviders: bedrooms, remoteProviders: remotes,
                deviceResponder: runtime.providers.caller, scheduleStorage: runtime.providers.caller,
                canEditBedroom: canEditBedroom,
                roomResidentId: { [weak providers = runtime.providers] in providers?.roomResidentID },
                accountProvider: runtime.providers, settingsProviders: settings, shellHeader: runtime.providers.shellHeader)
            next.loadViewIfNeeded()
            next.view.frame = CGRect(origin: .zero, size: size)
            next.view.setNeedsLayout()
            next.view.layoutIfNeeded()
        }
        return ApplyPlan(validate: { [weak self] in
            guard let self, self.session.isCurrentConnection(self.connection),
                  self.renderer === previous, self.view.bounds.size == size,
                  self.traitCollection.displayScale == scale else {
                throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document")
            }
            if requireBackdropImage { _ = try prepared.readyBackdrop(for: self) }
            guard backdrop.blur.percent == preparedBlurPercent else {
                throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/theme/background")
            }
            if previous != nil {
                try next.validateUpdate(publication, collections: collections, records: records, settingsProviders: settings,
                                        bedroomProviders: bedrooms, remoteProviders: remotes,
                                        canEditBedroom: canEditBedroom)
            }
        }, apply: { [weak self] in
            guard let self else { throw CancellationError() }
            if renderer != nil {
                try next.apply(publication: publication, backdrop: backdrop, collections: collections, records: records,
                               settingsProviders: settings, bedroomProviders: bedrooms, remoteProviders: remotes,
                               canEditBedroom: canEditBedroom)
            } else {
                addChild(next)
                next.view.frame = view.bounds
                next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.insertSubview(next.view, at: 0)
                next.didMove(toParent: self)
                renderer = next
                joinArrival(next)
                firstLoadDeadline?.cancel()
                resumeLayoutWaiters()
                Telemetry.endTracked(Telemetry.Name.snapshotShown)
                Task { [weak self] in
                    guard let self, self.session.isCurrentConnection(self.connection) else { return }
                    if self.lastConnected { await self.session.setup.offerIfNeeded() }
                }
            }
            runtime.providers.adoptPreferences(sceneID: sceneID, blur: backdrop.blur)
            recovery?.removeFromSuperview()
            recovery = nil
            view.bringSubviewToFront(statusPanel)
            openPendingDestination()
        })
    }

    private func openPendingDestination() {
        guard let request = session.push.pendingRequest, let renderer else { return }
        do {
            try renderer.openSystemRoute(request.route)
            session.push.didOpen(request)
            routeFailure = nil
        } catch {
            routeFailure = "This destination is not available yet. Finish the current interaction or refresh the layout."
        }
        showStatus()
    }

    /// Holds the root's arrival until the layout is on screen or `timeout` passes, so the sign-in layer does not lift onto the
    /// recovery ground when a layout is about to arrive. Returns at once when there is nothing to wait for.
    func awaitFirstLayout(timeout: Duration) async {
        guard renderer == nil, runtime.store?.remote == .waiting || runtime.store?.remote == .published else { return }
        let id = UUID()
        await withCheckedContinuation { continuation in
            layoutWaiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.layoutWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    private func resumeLayoutWaiters() {
        let waiting = layoutWaiters
        layoutWaiters = [:]
        waiting.values.forEach { $0.resume() }
    }

    /// The renderer joins Home's arrival after a sign-in: while it is held back every surface (everything but the backdrop,
    /// which times itself) rises in staggered by the same 60 ms steps the compiled pages used. At any other time this does nothing.
    private func joinArrival(_ renderer: UKServerUIRenderer) {
        guard let arrival = environment.arrival, arrival.isActive, !arrival.isRevealed else { return }
        var index = 1
        for child in renderer.view.subviews where !(child is UKBackdropView) && !child.isHidden && child.alpha == 1 {
            UKArrivalMotion.apply(to: child, shell: environment, kind: .rise, index: index, bag: bag)
            index += 1
        }
    }

    private func showStatus() {
        let state = runtime.store?.status ?? .idle
        if renderer != nil {
            let copy = runtime.store?.current?.document.bootstrap?.recovery
            let message: String?
            switch state {
            case .failure:
                message = copy.map { "\($0.unavailableTitle). \($0.unavailableMessage)" }
                    ?? "The new layout could not be applied. Your previous layout is still available."
            default: message = runtime.providerFailure
                ? "The updated house configuration cannot be applied yet. Finish the current interaction and try again."
                : routeFailure
            }
            status.text = message
            status.isHidden = message == nil
            statusPanel.isHidden = message == nil
            statusRetry.setTitle(copy?.retryLabel ?? BoundaryCopy.tryAgain, for: .normal)
            if let message, message != lastFailure { Announcer.announce(message) }
            lastFailure = message
            return
        }
        recovery?.removeFromSuperview()
        let remote = runtime.store?.remote ?? .waiting
        let boundary = Boundary(remote: remote, status: state, storeMissing: runtime.store == nil,
                                expired: loadingExpired, adoptionFailed: adoptionFailed)
        if boundary.isFinal { resumeLayoutWaiters() }
        let main = UKStateMessageView(symbol: boundary.symbol,
            title: boundary.title, message: boundary.message, actionTitle: boundary.canRetry ? BoundaryCopy.tryAgain : nil,
            actionIdentifier: "server-ui.production.retry", action: !boundary.canRetry ? nil : { [weak self] in
                self?.retryFromBoundary()
            }, actionBusyTitle: isRetrying ? BoundaryCopy.tryingAgain : nil, identifier: "server-ui.production.recovery")
        let clear = UIButton(type: .system)
        clear.setTitle(BoundaryCopy.clear, for: .normal)
        clear.accessibilityIdentifier = "server-ui.production.clear"
        clear.addAction(UIAction { [weak self] _ in self?.confirmCacheReset() }, for: .touchUpInside)
        clear.isHidden = !boundary.offersClear
        let signOut = UIButton(type: .system)
        signOut.setTitle(BoundaryCopy.signOut, for: .normal)
        signOut.accessibilityIdentifier = "server-ui.production.signOut"
        signOut.addAction(UIAction { [weak self] _ in self?.confirmSignOut() }, for: .touchUpInside)
        for button in [clear, signOut] {
            // Dynamic Type (HIG, Typography > Dynamic Type): the system button's title is a fixed 15 pt on one line. It follows the
            // text size like the page's text and wraps and centres at the largest sizes instead of being cut off, as the sign-in
            // screen's "Use a different account" button does (the iPad audit at AX5 reported Sign Out as unsupported).
            button.titleLabel?.font = .ukFont(.body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        var arranged: [UIView] = [main, clear, signOut]
        #if DEBUG
        // The journey attaches this: the rejection's case and pointer, never a value, so a device run says why it is showing.
        let diagnostic = UILabel()
        diagnostic.font = .ukFont(.caption2)
        diagnostic.adjustsFontForContentSizeCategory = true
        diagnostic.numberOfLines = 0
        diagnostic.textAlignment = .center
        diagnostic.textColor = .secondaryLabel
        diagnostic.accessibilityIdentifier = "server-ui.production.diagnostic"
        diagnostic.text = runtime.store?.rejection ?? adoptionDiagnostic
            ?? "no rejection; remote=\(remote), status=\(state), expired=\(loadingExpired)"
        arranged.append(diagnostic)
        #endif
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        // On a window with a hinge band the whole column (state, Clear, Sign Out) sits in the leading region; lying flat and
        // everywhere else it is centred (`HingeAvoidance`, as `UKStateMessageOverlay(leadingOnHinge:)` does).
        let region = UKHingeClearingView(content: scroll, leadingOnly: true)
        region.translatesAutoresizingMaskIntoConstraints = false
        region.accessibilityIdentifier = "server-ui.production.recoveryRegion"
        view.insertSubview(region, at: 0)
        NSLayoutConstraint.activate([
            region.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            region.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            region.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            region.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        recovery = region
    }

    /// Asks Home Assistant for the layout again; the button shows the busy title until the answer returns.
    private func retryFromBoundary() {
        guard !isRetrying else { return }
        isRetrying = true
        showStatus()
        Task { [weak self] in
            await self?.runtime.retry()
            self?.isRetrying = false
            if self?.renderer == nil { self?.showStatus() }
        }
    }

    private func confirmCacheReset() {
        let spec = BoundaryCopy.clearAlert
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: spec.cancel.title, style: .cancel))
        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .destructive) { [weak self] _ in
            Task { await self?.runtime.resetRejectedCache() }
        })
        present(alert, animated: true)
    }

    private func confirmSignOut() {
        let spec = AlertCopy.signOut
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: spec.cancel.title, style: .cancel))
        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .destructive) { [weak self] _ in
            self?.signOutConfirmed()
        })
        present(alert, animated: true)
    }

    private func signOutConfirmed() {
        Task { [weak self] in
            guard let self else { return }
            do { try await self.session.confirmedSignOut() }
            catch {
                let spec = AlertCopy.signOutFailed(device: .current)
                let failure = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                failure.addAction(UIAlertAction(title: spec.cancel.title, style: .cancel))
                failure.addAction(UIAlertAction(title: spec.confirm.title, style: .default) { [weak self] _ in
                    self?.signOutConfirmed()
                })
                self.present(failure, animated: true)
            }
        }
    }
}
#endif
