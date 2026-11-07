#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import UIKit

/// The one container that switches a layout-driven page between its content, a skeleton and a state message
/// (`.agents/design/house-config-states.md`, rules 10 to 14; pattern `state-message`).
///
/// A page makes one in `viewDidLoad`, after it installed its scroll view, and keeps it:
///
/// ```swift
/// houseGate = UKHouseLayoutGate(page: self, kind: .home)
/// ```
///
/// **Rule 10, a saved layout always wins.** The state is ``HouseLayoutState/resolve(document:status:role:)``: with a document
/// (this session's or the cache's) it is always content, whatever the store's status says, so a status change never blanks,
/// re-fades or reorders a page that has one. **Rules 11 and 12.** With none the page's content is held back (kept in the view tree,
/// so nothing rebuilds) and a skeleton or a ``UKStateMessageView`` shows in its place, through ``UKStateMessageOverlay`` (leading
/// region on a hinge band). **Motion.** Skeleton or message to content: the skeleton fades out on `quick`, then the content fades in
/// and rises 4 pt over 170 ms (no rise under Reduce Motion). Skeleton to message: `quick` fades. VoiceOver gets `layoutChanged`
/// when a message appears.
///
/// There is no gate (the page is plain content) without a running ``HouseConfigStore`` or a debug-forced state
/// (``HouseLayoutDebug``), so galleries and signed-out screens are untouched.
@MainActor
final class UKHouseLayoutGate {
    private weak var page: UKPageViewController?
    private let kind: HouseSkeletonPlan.Kind
    private let source: HouseConfigSource
    private let store: HouseConfigStore?
    private let forced: HouseLayoutDebug.Forced?
    private let connection: HassConnection?
    private let overlay: UKStateMessageOverlay

    private var skeleton: UKConfigSkeletonView?
    private var userTask: Task<Void, Never>?
    private var retrying = false
    private var renderedBusy = false
    private var renderedRole: HouseLayoutState.Role = .unknown
    private var hasRendered = false

    /// The state on screen.
    private(set) var state: HouseLayoutState = .content
    /// Who is looking; unknown until Home Assistant answers who the user is.
    private(set) var role: HouseLayoutState.Role
    private var user: HassUser?

    /// - Parameters:
    ///   - page: The page; its ``UKPageViewController/contentView`` is what the gate holds back.
    ///   - kind: The skeleton's shape: `.home` or the generic `.page`.
    ///   - source: Where the document is read from; defaults to the context's ``UKContext/houseConfigSource``, else
    ///     ``HouseConfigSource/active``. Tests inject theirs, because the task-local scope does not survive an observation re-run.
    ///   - store: The house config store; defaults to the context's ``UKContext/houseConfigStore``, else the signed-in session's.
    ///   - forced: A debug-forced state; defaults to ``HouseLayoutDebug/current``.
    init(page: UKPageViewController, kind: HouseSkeletonPlan.Kind, source: HouseConfigSource? = nil, store: HouseConfigStore? = nil,
         forced: HouseLayoutDebug.Forced? = HouseLayoutDebug.current, role: HouseLayoutState.Role? = HouseLayoutDebug.currentRole) {
        self.page = page
        self.kind = kind
        self.source = source ?? page.context.houseConfigSource ?? .active
        self.store = store ?? page.context.houseConfigStore ?? page.context.session?.houseConfig
        self.forced = forced
        self.connection = page.context.connection
        self.role = role ?? .unknown
        knownRole = role != nil
        overlay = UKStateMessageOverlay(host: page.view, leadingOnHinge: true)
        guard self.store != nil || forced != nil else { return }
        page.bag.observe { [weak self] in self?.refresh() }
        scheduleDebugSwap()
    }

    /// `FENTON_GALLERY_HOUSECONFIG_SWAP=<seconds>` (debug): a forced state gives way to the document after that long, so the
    /// skeleton-to-content reveal can be watched and measured (`HouseLayoutRevealPerformanceTests`).
    private var forcedReleased = false

    private func scheduleDebugSwap() {
        #if DEBUG
        guard forced != nil, let seconds = ProcessInfo.processInfo.environment["FENTON_GALLERY_HOUSECONFIG_SWAP"].flatMap(Double.init) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.forcedReleased = true
            self?.refresh()
        }
        #endif
    }

    private var knownRole: Bool

    deinit { userTask?.cancel() }

    // MARK: - State

    /// What the facades have and how the store stands, or the debug-forced state.
    private func inputs() -> (hasDocument: Bool, status: HouseConfigStore.Status) {
        if forcedReleased { return (true, .ready) }
        if let forced { return (forced.hasDocument, forced.status) }
        return (source.read { _ in true } ?? false, store?.status ?? .idle)
    }

    private func refresh() {
        guard let page else { return }
        let (hasDocument, status) = inputs()
        var next = HouseLayoutState.resolve(hasDocument: hasDocument, status: status, role: role)
        if retrying {
            // Try Again keeps the message up, with a busy button, while the store asks again.
            if next == .skeleton { next = .message(.timedOut, showsAction: true) } else { retrying = false }
        }
        if case .message = next { loadRoleIfNeeded() }
        let busy = retrying
        guard next != state || busy != renderedBusy || role != renderedRole || !hasRendered else { return }
        let previous = state
        let animated = hasRendered && page.view.window != nil
        let roleChanged = role != renderedRole
        state = next
        renderedBusy = busy
        renderedRole = role
        hasRendered = true
        render(previous: previous, animated: animated, busy: busy, roleChanged: roleChanged)
    }

    private func loadRoleIfNeeded() {
        guard !knownRole, role == .unknown, userTask == nil, let connection else { return }
        userTask = Task { [weak self] in
            let loaded = try? await connection.currentUser()
            guard !Task.isCancelled, let self else { return }
            user = loaded
            userTask = nil
            if let loaded {
                role = HouseLayoutState.Role(loaded)
                refresh()
            }
        }
    }

    // MARK: - Rendering

    private func render(previous: HouseLayoutState, animated: Bool, busy: Bool, roleChanged: Bool) {
        guard let page else { return }
        switch state {
        case .content:
            let showMotion = animated && previous != .content
            removeLayers(animated: showMotion)
            revealContent(of: page, animated: showMotion)
        case .skeleton:
            holdContentBack(of: page)
            overlay.show(nil)
            showSkeleton(in: page, animated: animated && previous != .skeleton)
        case let .message(messageKind, showsAction):
            holdContentBack(of: page)
            let fromSkeleton = previous == .skeleton && animated
            // The role arriving swaps the text and the button in place, on `quick`.
            showMessage(messageKind, showsAction: showsAction, busy: busy, fadeIn: fromSkeleton || (roleChanged && animated))
            if previous != state {
                UIAccessibility.post(notification: .layoutChanged, argument: overlay.shown)
            }
            hideSkeleton(animated: fromSkeleton)
        }
    }

    private func holdContentBack(of page: UKPageViewController) { UKContentReveal.hold(page.contentView) }

    private func revealContent(of page: UKPageViewController, animated: Bool) {
        // The layers fade out first (`quick`); then the content fades in and rises 4 pt (the shared content-gate reveal).
        let interval = animated ? Telemetry.begin(Telemetry.Name.layoutChange, page: "HouseLayout", "reveal") : nil
        UKContentReveal.reveal(page.contentView, animated: animated, delay: UKMotion.quickDuration) {
            if let interval { _ = Telemetry.end(interval) }
        }
    }

    private func removeLayers(animated: Bool) {
        let layers = [skeleton, overlay.container].compactMap { $0 }
        let skeleton = skeleton
        self.skeleton = nil
        let message = overlay.container
        guard animated else {
            skeleton?.removeFromSuperview()
            overlay.show(nil)
            return
        }
        let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "HouseLayout", "layersOut")
        UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: [.curveEaseOut], animations: {
            layers.forEach { $0.alpha = 0 }
        }, completion: { [overlay] _ in
            _ = Telemetry.end(interval)
            skeleton?.removeFromSuperview()
            if overlay.container === message { overlay.show(nil) }
        })
    }

    private func showSkeleton(in page: UKPageViewController, animated: Bool) {
        if skeleton == nil {
            let view = UKConfigSkeletonView(kind)
            view.translatesAutoresizingMaskIntoConstraints = false
            page.view.addSubview(view)
            let host = page.view!
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor), view.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
            skeleton = view
        }
        guard let skeleton else { return }
        skeleton.layer.removeAllAnimations()
        skeleton.alpha = 1
        if animated {
            skeleton.alpha = 0
            UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: .curveEaseOut) { skeleton.alpha = 1 }
        }
    }

    private func hideSkeleton(animated: Bool) {
        guard let old = skeleton else { return }
        skeleton = nil
        guard animated else { return old.removeFromSuperview() }
        UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: .curveEaseOut, animations: { old.alpha = 0 },
                       completion: { _ in old.removeFromSuperview() })
    }

    private func showMessage(_ messageKind: HouseLayoutState.Kind, showsAction: Bool, busy: Bool, fadeIn: Bool) {
        let entry = HouseConfigCopy.entry(messageKind)
        let view = UKStateMessageView(
            symbol: entry.symbol, title: entry.title, message: entry.message(for: role),
            actionTitle: showsAction ? entry.actionTitle : nil, actionIdentifier: "houseConfig.action",
            action: showsAction ? { [weak self] in self?.perform(entry.action) } : nil,
            actionBusyTitle: busy ? HouseConfigCopy.tryAgainBusy : nil, identifier: "houseConfig.state")
        overlay.show(view)
        guard fadeIn, let container = overlay.container else { return }
        container.alpha = 0
        let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "HouseLayout", "messageIn")
        UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: .curveEaseOut, animations: { container.alpha = 1 },
                       completion: { _ in _ = Telemetry.end(interval) })
    }

    // MARK: - Actions

    private func perform(_ action: HouseConfigCopy.Action?) {
        switch action {
        case let .open(webPage)?:
            guard let page else { return }
            UKHomeAssistantSettings.present(context: page.context, from: page, user: user, initialPage: webPage)
        case .tryAgain?:
            retrying = true
            store?.resubscribeIfNeeded()
            refresh()
        case nil:
            break
        }
    }
}
#endif
