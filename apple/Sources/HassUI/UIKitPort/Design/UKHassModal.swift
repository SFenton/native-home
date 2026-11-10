#if os(iOS)
import HassDesign
import UIKit

/// A page inside a ``UKHassModalController`` can name its vertical scroller for the sheet-fit measurement. Without it the
/// controller measures the first page-wide, tall-enough scroll view it finds (``SheetFit/isPageScroller(contentWidth:containerWidth:containerHeight:)``).
@MainActor
protocol UKSheetFitting: UIViewController {
    var sheetFitScrollView: UIScrollView? { get }
    /// Whether the page has the standard inline header and nothing pinned above or below its content. A page with a bar of its own
    /// (`modalTabBar`, ``View/hasCustomSheetHeader()``) says false, so its taller chrome never teaches ``SheetChromeMemory``.
    var sheetHeaderIsStandard: Bool { get }
}

extension UKSheetFitting {
    var sheetHeaderIsStandard: Bool { true }
}

/// What a modal is configured with: the parameters of ``HassModal`` and `hassSheet(_:height:appearance:fitKey:)`.
struct UKHassModalOptions {
    /// Inline navigation title, which VoiceOver announces first; nil when the page sets its own.
    var title: String?
    var closeIdentifier = "sheet.close"
    /// Whether the circle-X is shown (a first-run prompt has none; an edit sheet has Cancel and Confirm instead).
    var showsClose = true
    /// Off while the sheet must stay (a sign-out waiting on the server).
    var closeEnabled = true
    /// The system appearance (default), or dark for a sheet over live video or a photo.
    var appearance: HassSheetAppearance = .system
    /// The iPad sheet size: a form sheet (540 pt) or a page sheet. No effect on iPhone.
    var width: HassSheetWidth = .form
    /// Content-fitted (default) or full height.
    var height: HassSheetHeight = .fitted
    /// Presented over the whole screen, with no detents (recipe detail, the Home Assistant settings modal).
    var isFullScreen = false
    /// Identifies this sheet so its measured height is remembered for the next time it opens. Leave the default, the call site,
    /// unless one call site presents content of different heights (one key per camera).
    var fitKey: String
    /// The height of the page's scroll content computed before the sheet opens (the camera viewer: the video's width over its aspect
    /// ratio plus a controls row laid out off screen). The sheet then opens at `chrome.top + predicted + chrome.bottom`
    /// (``SheetChrome``, learned from any fitted sheet and remembered), at its final height on its first presentation too, ahead of
    /// a remembered height. Measurement still corrects a wrong prediction. Pass it only where the content's width is known before
    /// the sheet opens (iPhone and the folded Duo, not a regular-width page sheet).
    var predictedContentHeight: CGFloat?
    /// Close is the only bar item, so the folded Duo keeps it in the sheet's own horizontal bar instead of the vertical one
    /// (`HassModal(closeStaysInBar:)`, `keepsCloseInSheetBar()`; iOS 27.1). The SwiftUI default is true for a plain `HassModal`; a sheet
    /// with Save, Add or other bar actions says false, and this port's default is false, so a call site says true where `HassModal` does.
    var closeStaysInBar = false
    /// How the root page's content appears when the sheet opens: ``UKModalReveal/none`` (there on the first frame, the default) or
    /// ``UKModalReveal/gate(_:)`` (hidden through the slide, then faded in together, with a centred arc only while it is not ready;
    /// `.agents/design/sheet-reveal.md`). Root page only: pushed pages are plain pushes.
    var reveal: UKModalReveal = .none
    /// What VoiceOver says for the reveal's arc; nil is "Loading" and the sheet's title ("Loading Climate"), never a bare "Loading".
    var revealLabel: String?
    /// ``revealLabel`` with its default applied.
    var spokenRevealLabel: String {
        if let revealLabel { return revealLabel }
        if let title, !title.isEmpty { return "Loading \(title)" }
        return "Loading"
    }
    /// Runs instead of dismissing when the presenter owns closing.
    var onClose: (() -> Void)?
    /// Runs once the sheet has gone (closed, swiped down), for the presenter to clear its state.
    var onDismissed: (() -> Void)?

    init(title: String?, fitKey: String = "\(#fileID):\(#line)") {
        self.title = title
        self.fitKey = fitKey
    }
}

/// The container a modal is built from (``HassModal`` + `hassSheet`): a navigation controller with an inline title, the circle-X
/// close and the system grouped ground, presented as a sheet with a visible grabber, in the system appearance while the pages
/// behind stay dark; sized to its content on iPhone (``SheetFit``).
///
/// **Height.** A sheet opens only as tall as it needs (``HassSheetHeight/fitted``, the default): the page's scroll content is
/// measured (``SheetFitModel``, remembered per `fitKey` in ``SheetFitMemory``) and the detent follows it, capped at large and
/// recomputed when the content or Dynamic Type changes. ``HassSheetHeight/full`` is the large detent only, with no grabber: for
/// remotes, any modal with a section tab bar, a sheet that navigates between pages and a sheet over live video.
///
/// **Width (iPad).** ``HassSheetWidth/form`` (540 pt, lists, editors, prompts) or ``HassSheetWidth/page`` (tile grids, dials).
///
/// ```swift
/// var options = UKHassModalOptions(title: "Lighting Mode")
/// options.closeIdentifier = "sizing.close"
/// UKHassModalController(root: page, options: options).present(from: self)
/// ```
/// Pages pushed inside the modal call ``UKHassModal/applyChrome(to:)`` (or push through ``push(_:animated:)``); the page's own
/// `navigationItem` buttons merge with Close the way a SwiftUI `.toolbar` does.
@MainActor
final class UKHassModalController: UINavigationController, UISheetPresentationControllerDelegate, UINavigationControllerDelegate {
    let options: UKHassModalOptions
    /// Receives the measured height of a fitted sheet's content.
    let fit: SheetFitModel

    /// Each page's identity for the fit model: the root's readings set the height, or (``HassSheetHeight/fittedToTopPage``) the page
    /// that appeared last.
    private var pageIDs: [ObjectIdentifier: UUID] = [:]
    private let bag = UKObservationBag()
    private var topPage: UIViewController? { viewControllers.last }
    private var rootAppeared = false
    /// How many times the detent changed since the sheet opened: 0 when the opening height was final (`SheetFitProbe`).
    private var moves = 0
    private var trail = ""
    #if DEBUG
    private var probe: UKSheetFitProbeView?
    #endif
    private var available: CGFloat = LargeDetent.height()
    private var fitHeight: CGFloat = 0
    private var observedScroller: UIScrollView?
    private var contentSizeObservation: NSKeyValueObservation?
    private var appliedDetents = ""
    /// The window the modal was presented from, for ``fillsHeight`` before the modal has a window of its own.
    private weak var presentingWindow: UIWindow?
    private var appliedIdentifiers: [String] = []
    /// The reveal while it runs (``UKModalReveal``); nil when the modal has none, before it attaches and after the content has shown.
    private var reveal: UKSheetRevealController?
    private var revealAttached = false
    private var revealPresented = false
    private let rootReadiness: UKRevealReadiness?
    private let fitDetent = UISheetPresentationController.Detent.Identifier("uk.fit")

    init(root: UIViewController, options: UKHassModalOptions) {
        self.options = options
        rootReadiness = root as? UKRevealReadiness
        let key = options.fitKey
        var onChange: (CGFloat) -> Void = { _ in }
        let predicted = options.predictedContentHeight
        // A prediction (the content's height computed before presentation, plus the chrome) wins over a remembered height.
        let initial = SheetFitStart.height(predictedContent: predicted, remembered: SheetFitMemory.height(for: key))
        fit = SheetFitModel(initial: initial, followsTopPage: options.height == .fittedToTopPage,
                            settleDelay: predicted == nil ? nil : SheetFit.settleDelay) { height in onChange(height) }
        fit.maxSheetHeight = SheetChromeMemory.maxSheetHeight
        fit.systemBottomInset = LargeDetent.systemBottomInset()
        // Every page of a sheet is a `UKPageViewController` (its content is inset by the side safe areas, the folded Duo's rail): a root that is
        // not one is hosted in `UKPageHost`, so nothing can bypass the inset.
        let page = UKPageHost.sheetWrapped(root)
        super.init(rootViewController: page)
        delegate = self
        onChange = { [weak self] height in
            SheetFitMemory.remember(height, for: key)
            self?.fitChanged()
        }
        if let initial = fit.contentHeight { fitHeight = initial }
        UKHassModal.applyChrome(to: page, options: options, dismiss: { [weak self] in self?.close() }, isRoot: true)
        overrideUserInterfaceStyle = options.appearance == .dark ? .dark : (SystemAppearance.current() == .light ? .light : .dark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    #if !FENTON_IOS_SDK_BEFORE_27_1
    /// The folded Duo's vertical bar would pull Close out of the sheet's title bar and leave the title leading aligned: a sheet whose only
    /// bar item is Close keeps its horizontal bar (`toolbarVerticalBehavior(.disabled)`).
    @available(iOS 27.1, *)
    ///
    /// Not where every sheet fills the height (``DuoSheetPolicy``, owner 2026-10-31): with the vertical bar disabled the system puts the
    /// status bar back across the top of the folded outer screen and seats the sheet below it (the camera viewer opened 90 pt short of
    /// the top while every other sheet reached it). Close then sits in the rail like any other sheet's.
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior { options.closeStaysInBar && !fillsHeight ? .disabled : .automatic }

    /// A navigation controller defers to its top page by default; the modal answers for its pages.
    @available(iOS 27.1, *)
    override var childForPreferredVerticalBarBehavior: UIViewController? { nil }
    #endif

    /// Pushes a page, with the modal chrome (ground, inline title).
    func push(_ page: UIViewController, animated: Bool = true) {
        let page = UKPageHost.sheetWrapped(page)
        UKHassModal.applyChrome(to: page, options: options, dismiss: nil, isRoot: false)
        pushViewController(page, animated: animated)
    }

    /// Anything pushed or set that is not a page is hosted as one (``UKPageHost/sheetWrapped(_:)``), whoever pushes it.
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(UKPageHost.sheetWrapped(viewController), animated: animated)
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers.map(UKPageHost.sheetWrapped), animated: animated)
    }

    private func id(for page: UIViewController) -> UUID {
        let key = ObjectIdentifier(page)
        if let existing = pageIDs[key] { return existing }
        let new = UUID()
        pageIDs[key] = new
        return new
    }

    /// A page is about to come on screen: its height is taken now, so the sheet starts resizing with the push (and the pop) as SwiftUI's
    /// does, instead of jumping once the transition has finished.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard options.height == .fittedToTopPage, !options.isFullScreen, rootAppeared else { return }
        viewController.view.layoutIfNeeded()
        fit.setStandardHeader((viewController as? UKSheetFitting)?.sheetHeaderIsStandard ?? true, for: id(for: viewController))
        fit.pageAppeared(id(for: viewController))
        reportFit()
    }

    /// A page came on screen: with ``HassSheetHeight/fittedToTopPage`` it takes the height (at once when it has reported before:
    /// Back to a page measured earlier); otherwise only the first page counts.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        guard options.height != .full, !options.isFullScreen else { return }
        fit.setStandardHeader((viewController as? UKSheetFitting)?.sheetHeaderIsStandard ?? true, for: id(for: viewController))
        fit.pageAppeared(id(for: viewController))
        reportFit()
    }

    func close() {
        if let onClose = options.onClose { onClose() } else { dismiss(animated: true) { [options] in options.onDismissed?() } }
    }

    /// VoiceOver's two-finger scrub (Escape) goes back one page, else closes the sheet, as the swipe down and the Close button do
    /// (modal standard, accessibility). A guarded form (modal in presentation) asks first; a page with a guarded Back leaves it to its button.
    override func accessibilityPerformEscape() -> Bool {
        if viewControllers.count > 1 {
            guard topViewController?.navigationItem.hidesBackButton != true else { return false }
            popViewController(animated: true)
            return true
        }
        if isModalInPresentation {
            onAttemptToDismiss?()
            return onAttemptToDismiss != nil
        }
        close()
        return true
    }

    // MARK: Presenting

    /// Presents the modal from `presenter` with the sheet configured (style, detents, grabber).
    func present(from presenter: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        let regular = presenter.traitCollection.horizontalSizeClass == .regular
        if options.isFullScreen {
            modalPresentationStyle = .fullScreen
        } else if regular {
            modalPresentationStyle = options.width == .page ? .pageSheet : .formSheet
            if options.width == .form {
                UKSheetPlacement.setContentSize(CGSize(width: HassFormSheetSize.width, height: preferredContentSize.height == 0 ? HassFormSheetSize.height : preferredContentSize.height), on: self)
            }
        } else {
            modalPresentationStyle = .pageSheet
        }
        presentingWindow = presenter.view.window
        if fillsHeight, #available(iOS 18.0, *) { preferredTransition = nil }
        configureSheet()
        (presenter.presentedViewController ?? presenter).present(self, animated: animated, completion: completion)
    }

    /// Whether every sheet fills the height now (``DuoSheetPolicy``, owner 2026-10-31): the folded Duo, or landscape beside the
    /// vertical hinge. Read from the sheet's container once it has one, else the window it was presented from.
    private var fillsHeight: Bool {
        UKSheetPlacement.fillsHeight(in: presentationController?.containerView ?? view.window ?? presentingWindow)
    }

    /// Applies the sheet settings (detents, grabber, delegate); ``followPose()`` re-runs it under an open sheet. Internal for tests.
    func configureSheet() {
        guard !options.isFullScreen, let sheet = sheetPresentationController else { return }
        sheet.delegate = self
        // A `.full` sheet has one detent, so a grabber would promise a resize that does not exist (HIG: Sheets); swipe down still dismisses it.
        // Where every sheet fills the height the grabber stays (owner, 2026-10-31).
        sheet.prefersGrabberVisible = options.height != .full || fillsHeight
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        updateDetents(animated: false)
        // After the settings, once: iOS 27 places the sheet against the leading edge on a Duo (``UKSheetPlacement``).
        UKSheetPlacement.place(sheet, in: view.window ?? presentingWindow)
        poseWatch.record(in: view.window ?? presentingWindow)
        #if !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *), options.closeStaysInBar { setNeedsUpdateOfVerticalBarConfiguration() }
        #endif
    }

    private var poseWatch = UKSheetPlacement.PoseWatch()

    /// A fold, an unfold or a rotation changed the full-height rule under the open sheet: the detents and grabber follow, animated.
    private func followPose() {
        guard !options.isFullScreen, let sheet = sheetPresentationController, presentingViewController != nil,
              poseWatch.changed(in: presentationController?.containerView ?? view.window) else { return }
        // Not inside this layout pass: detents change the sheet's frame.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentingViewController != nil else { return }
            sheet.animateChanges { self.configureSheet() }
        }
    }

    /// A presenter's ear for a swipe-down close, kept here because the modal is the sheet's delegate (``configureSheet()`` sets it again
    /// on every re-configure, so a presenter that set itself as delegate would be dropped). Runs after `options.onDismissed`.
    var swipeDismissObserver: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        options.onDismissed?()
        swipeDismissObserver?()
    }

    /// Runs when a swipe-down is refused because the sheet is modal in presentation (a form with unsaved input): the presenter asks
    /// whether to discard (`SheetDismissAttemptObserver`).
    var onAttemptToDismiss: (() -> Void)?

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttemptToDismiss?()
    }

    // MARK: Fit

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = options.appearance == .system ? UKDesignSurface.systemGround : .systemGroupedBackground
        navigationBar.prefersLargeTitles = false
        if #unavailable(iOS 26.0) {
            // No translucent band behind the header: the page's ground runs up under the title.
            let transparent = UINavigationBarAppearance()
            transparent.configureWithTransparentBackground()
            navigationBar.standardAppearance = transparent
            navigationBar.scrollEdgeAppearance = transparent
        }
        guard options.height != .full, !options.isFullScreen else { return }
        #if DEBUG
        // `FENTON_SHEETFIT_PROBE=1`: an element a journey reads to see whether a sheet opened at its final height.
        if ProcessInfo.processInfo.environment["FENTON_SHEETFIT_PROBE"] == "1" {
            let probe = UKSheetFitProbeView()
            probe.value = { [weak self] in
                guard let self else { return "" }
                let initial = self.fit.initialHeight.map { String(Int($0.rounded())) } ?? "none"
                let height = self.fit.contentHeight.map { String(Int($0.rounded())) } ?? "none"
                return "initial=\(initial) height=\(height) moves=\(self.moves) trail=\(self.trail)"
            }
            view.addSubview(probe)
            self.probe = probe
        }
        #endif
        // Any fitted sheet with the standard header teaches the chrome a prediction needs (``SheetChromeMemory``), and the sheet
        // at the large detent is the tallest a sheet gets here: what a later sheet's height is checked against, once it has stood still.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.fit.rootChrome
            _ = self.fit.rootWidth
            _ = self.fit.rootIsCutShort
            SheetChromeMemory.learn(from: self.fit, windowWidth: LargeDetent.window()?.bounds.width)
        }
        bag.observe { [weak self] in
            guard let self, let height = self.fit.largeSheetHeight else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: SheetFit.settleDelay)
                guard let self, self.fit.largeSheetHeight == height else { return }
                SheetChromeMemory.learnMaxSheetHeight(height)
                self.fit.maxSheetHeight = height
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        attachRevealIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UKScrollRate.attachAll(in: view)
        if !revealPresented {
            revealPresented = true
            reveal?.presentationCompleted()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { reveal?.cancel() }
    }

    // MARK: Reveal

    /// The reveal's tracker, so children of the root (images) can hold the fade-in through ``UKReadinessRequirement``; nil without a
    /// reveal or once the content has shown.
    var revealTracker: ReadinessTracker? { reveal?.model.tracker }

    /// Hides the root page's content before the slide starts (``UKModalReveal``). Once, for the root page only.
    private func attachRevealIfNeeded() {
        guard !revealAttached, case .gate(let profile) = options.reveal, let page = viewControllers.first as? UKPageViewController else { return }
        revealAttached = true
        let controller = UKSheetRevealController(
            page: page, profile: profile, label: options.spokenRevealLabel, readiness: rootReadiness, name: options.title ?? "Sheet")
        controller.onFinished = { [weak self] in
            self?.reveal = nil
            self?.reportFit()
        }
        reveal = controller
    }

    /// A rotation or a fold changes the window, the sheet's width and so its content's height: the detent and the iPad form width are
    /// resolved again once the new size is in place (``SheetFit`` re-fits on a size change in SwiftUI through `LargeDetentProbe`).
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.windowChanged() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.horizontalSizeClass != traitCollection.horizontalSizeClass { windowChanged() }
    }

    private func windowChanged() {
        guard !options.isFullScreen, isViewLoaded else { return }
        if options.height == .full {
            // One detent already; only the grabber follows the rule.
            sheetPresentationController?.prefersGrabberVisible = fillsHeight
            return
        }
        available = LargeDetent.height()
        fit.systemBottomInset = LargeDetent.systemBottomInset()
        fit.usesSheetEstimate = traitCollection.horizontalSizeClass == .regular
        appliedDetents = ""
        updateDetents(animated: false)
        view.setNeedsLayout()
        reportFit()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        followPose()
        guard options.height == .fitted, !options.isFullScreen else { return }
        let largest = LargeDetent.height()
        if abs(largest - available) > 0.5 {
            available = largest
            // A rotation or a fold changes the window, and with it the safe area the detent is measured from.
            fit.systemBottomInset = LargeDetent.systemBottomInset()
            updateDetents(animated: true)
        }
        fit.usesSheetEstimate = traitCollection.horizontalSizeClass == .regular
        fit.setSheetHeight(view.bounds.height.rounded())
        if let page = topPage {
            if !rootAppeared, let root = viewControllers.first, page === root {
                rootAppeared = true
                fit.setStandardHeader((root as? UKSheetFitting)?.sheetHeaderIsStandard ?? true, for: id(for: root))
                fit.pageAppeared(id(for: root))
            }
            fit.setSafeInsets(top: page.view.safeAreaInsets.top.rounded(), bottom: page.view.safeAreaInsets.bottom.rounded())
        }
        reportFit()
    }

    /// The scroller the fit reads: the root page's, or with ``HassSheetHeight/fittedToTopPage`` the page on top's.
    private func findScroller() -> (page: UIViewController, scroller: UIScrollView)? {
        guard let page = options.height == .fittedToTopPage ? topPage : viewControllers.first, let scroller = scroller(in: page) else { return nil }
        return (page, scroller)
    }

    private func scroller(in root: UIViewController) -> UIScrollView? {
        if let fitting = root as? UKSheetFitting, let scroller = fitting.sheetFitScrollView { return scroller }
        var queue = [root.view!]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scroll = view as? UIScrollView, SheetFit.isPageScroller(
                contentWidth: scroll.contentSize.width, containerWidth: scroll.bounds.width, containerHeight: scroll.bounds.height) { return scroll }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func reportFit() {
        guard let (page, scroller) = findScroller() else { return }
        if scroller !== observedScroller {
            observedScroller = scroller
            contentSizeObservation = scroller.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportFit() }
            }
        }
        fit.report(SheetFit.Reading(
            content: max(scroller.contentSize.height, reveal?.isLoading == true ? UKSheetRevealController.minimumContentHeight : 0).rounded(),
            viewport: scroller.bounds.height.rounded(),
            topInset: scroller.adjustedContentInset.top.rounded(), bottomInset: scroller.adjustedContentInset.bottom.rounded(),
            width: scroller.bounds.width.rounded()), from: id(for: page))
        syncFitIfMoved()
    }

    private var updatingDetents = false
    private var detentRetryQueued = false

    /// The content height the detents were last made for.
    private var syncedContent: CGFloat?

    /// With ``HassSheetHeight/fittedToTopPage`` the model accepts the top page's height but only calls `onChange` for the root's, so a page
    /// pushed on top (Rooms over Quick Links) would leave the detent at the root's height: apply the model's height when it has moved.
    private func syncFitIfMoved() {
        guard options.height == .fittedToTopPage, let height = fit.contentHeight, height != syncedContent else { return }
        fitChanged()
    }

    private func fitChanged() {
        syncedContent = fit.contentHeight
        if let height = fit.contentHeight { fitHeight = height }
        updateDetents(animated: view.window != nil)
    }

    /// A partial detent on iOS 26.1 draws the system's glass; `hassSheet` sets `presentationBackground(systemGround)`, so the port gives
    /// the detent the same opaque ground (a full-height sheet is opaque already).
    static func opaque(_ detent: UISheetPresentationController.Detent) -> UISheetPresentationController.Detent {
        if #available(iOS 26.1, *), !UKPerfSwitches.isOff(.ukSheetGround),
           let effect = UIColorEffect.perform(NSSelectorFromString("effectWithColor:"), with: UKDesignSurface.systemGround)?.takeUnretainedValue() as? UIVisualEffect {
            detent.backgroundEffect = effect
        }
        return detent
    }

    /// Applies the detents for the measured content: a custom height (smallest, where the sheet opens), plus large for a tall
    /// sheet; `.medium` until the first measurement.
    private func updateDetents(animated: Bool) {
        guard !options.isFullScreen, let sheet = sheetPresentationController else { return }
        // `invalidateDetents` lays the sheet out at once, and that layout reports the new sheet height to the fit model, which asks for
        // detents again: re-entered, a sheet whose height and fit disagreed recursed until the stack ran out (iPad landscape fan sheet,
        // 2026-11-02, a stack overflow in `UIObservationTrackingFeedbackLoopDetected`). A nested request is left to the next layout pass.
        // The request is not dropped: the fit may have moved while the detents were being applied (a transient tall reading, then the
        // settled one), and a sheet left at large under 740 pt of content shows a band of empty ground (iPad Front Door, 2026-11-02).
        // It runs again on the next turn, outside the layout pass.
        guard !updatingDetents else {
            if !detentRetryQueued {
                detentRetryQueued = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.detentRetryQueued = false
                    self.updateDetents(animated: self.view.window != nil)
                }
            }
            view.setNeedsLayout()
            return
        }
        updatingDetents = true
        defer { updatingDetents = false }
        var detents: [UISheetPresentationController.Detent] = []
        var selected: UISheetPresentationController.Detent.Identifier = .large
        var signature = ""
        let fills = fillsHeight
        if fills, #available(iOS 18.0, *), preferredTransition != nil { preferredTransition = nil }
        switch options.height {
        case .full:
            detents = [.large()]
            signature = "full"
        case .fitted where fills, .fittedToTopPage where fills:
            // The folded Duo and landscape beside the hinge: the large detent only, whatever the content measures (``DuoSheetPolicy``).
            // The fit keeps measuring, so the sheet is fitted again when the rule stops applying.
            detents = [Self.opaque(.large())]
            fit.detentIsLarge = true
            signature = "duo-full"
        case .fitted, .fittedToTopPage:
            // `.fittedToTopPage`: the model follows the page on top (``navigationController(_:didShow:animated:)``).
            let detent = SheetFit.detent(contentHeight: fit.contentHeight, availableHeight: available)
            switch detent {
            case .large:
                detents = [Self.opaque(.large())]
            case .provisional:
                detents = [Self.opaque(.medium())]
                selected = .medium
            case let .height(value):
                fitHeight = value
                detents = [Self.opaque(.custom(identifier: fitDetent) { [weak self] context in min(self?.fitHeight ?? value, context.maximumDetentValue) })]
                selected = fitDetent
                if traitCollection.horizontalSizeClass == .regular, options.width == .form {
                    UKSheetPlacement.setContentSize(CGSize(width: HassFormSheetSize.width, height: value), on: self)
                }
            }
            if SheetFit.offersLarge(detent, availableHeight: available) { detents.append(Self.opaque(.large())) }
            fit.detentIsLarge = detent == .large
            signature = "\(detent)|\(detents.count)"
        }
        guard signature != appliedDetents else { return }
        if !appliedDetents.isEmpty { moves += 1; trail += " d:\(signature)@\(Int(available))" }
        appliedDetents = signature
        // The same detents with a new height (the fitted one is a closure over `fitHeight`) are only re-evaluated: replacing them would
        // restart the sheet's state and the resize would jump.
        let ids = detents.map { String(describing: $0.identifier) }
        let sameDetents = ids == appliedIdentifiers
        appliedIdentifiers = ids
        let apply = {
            sheet.prefersGrabberVisible = self.options.height != .full || fills
            if !sameDetents { sheet.detents = detents }
            sheet.selectedDetentIdentifier = selected
            sheet.invalidateDetents()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_DEBUG_SHEET"] == "1" { debugTrackHeight(sheet, label: "\(signature) animated=\(animated)") }
        #endif
        if animated { sheet.animateChanges(apply) } else { apply() }
    }

    #if DEBUG
    private var debugLink: CADisplayLink?
    private var debugHeights: [Int] = []
    private var debugStart = CACurrentMediaTime()

    /// `FENTON_DEBUG_SHEET=1`: logs the sheet's height on each frame for a second after a detent change, to see whether it animates.
    private func debugTrackHeight(_ sheet: UISheetPresentationController, label: String) {
        debugLink?.invalidate()
        debugHeights = []
        debugStart = CACurrentMediaTime()
        NSLog("SHEETPROBE change %@", label)
        let link = CADisplayLink(target: self, selector: #selector(debugTick))
        link.add(to: .main, forMode: .common)
        debugLink = link
    }

    @objc private func debugTick() {
        let layer = sheetPresentationController?.presentedView?.layer
        let height = Int(((layer?.presentation() ?? layer)?.frame.height ?? 0).rounded())
        if debugHeights.last != height { debugHeights.append(height); NSLog("SHEETPROBE h=%d t=%.2f", height, CACurrentMediaTime() - debugStart) }
        if CACurrentMediaTime() - debugStart > 1.2 {
            debugLink?.invalidate()
            NSLog("SHEETPROBE heights %@", debugHeights.map(String.init).joined(separator: ","))
        }
    }
    #endif
}

/// Static helpers shared by the modal controller and pushed pages.
@MainActor
enum UKHassModal {
    /// The header treatment and Close of a modal page (`ModalRoot`, `modalChrome()`): the system grouped ground (rows and tiles
    /// on it keep their contrast), an inline title, no large title, the circle-X on the root.
    static func applyChrome(to page: UIViewController, options: UKHassModalOptions, dismiss: (() -> Void)?, isRoot: Bool) {
        if page.view.backgroundColor == nil || page.view.backgroundColor == .clear { page.view.backgroundColor = UKDesignSurface.systemGround }
        page.navigationItem.largeTitleDisplayMode = .never
        if let title = options.title, isRoot { page.navigationItem.title = title }
        if isRoot, options.showsClose, let dismiss, page.navigationItem.rightBarButtonItem == nil {
            page.navigationItem.rightBarButtonItem = UKSheetItems.close(identifier: options.closeIdentifier, isEnabled: options.closeEnabled, action: dismiss)
        }
    }

    /// Hides the system Back so ``UKSheetItems/back(identifier:hasChanges:isEnabled:presenter:action:)`` can guard it
    /// (`hidesSystemBack`). The edge swipe back goes with it.
    static func hidesSystemBack(_ page: UIViewController, _ hidden: Bool = true) {
        page.navigationItem.hidesBackButton = hidden
    }
}
#endif

#if os(iOS) && DEBUG
/// The probe's accessibility element (`SheetFitProbe`): its value is composed when it is read.
final class UKSheetFitProbeView: UIView {
    var value: () -> String = { "" }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        isAccessibilityElement = true
        accessibilityIdentifier = "sheet.fit.probe"
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var accessibilityValue: String? {
        get { value() + " geo=[" + geometry() + "]" }
        set {}
    }

    /// Every ancestor's transform up to the window, in the notation `JourneyTestCase.sheetScale` reads (` t=a/d`, ` lt=m11/m22`): a
    /// sheet is drawn scaled by the system (an iPhone's at 0.96), and accessibility frames are in that scaled space.
    private func geometry() -> String {
        var parts: [String] = []
        var view: UIView? = self
        var depth = 0
        while let current = view, !(current is UIWindow), depth < 14 {
            var text = "\(type(of: current))"
            let t = current.transform
            if !t.isIdentity { text += " t=\(String(format: "%.3f", t.a))/\(String(format: "%.3f", t.d))" }
            let layer = current.layer.transform
            if !CATransform3DIsIdentity(layer) { text += " lt=\(String(format: "%.3f", layer.m11))/\(String(format: "%.3f", layer.m22))" }
            parts.append(text)
            view = current.superview
            depth += 1
        }
        return parts.joined(separator: " | ")
    }
}
#endif
