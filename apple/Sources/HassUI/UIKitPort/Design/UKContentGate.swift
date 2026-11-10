#if os(iOS)
import HassDesign
import UIKit

/// Waits for a page's content before showing it, the way the web app does (`ContentGate`; pattern `content-gate.md`).
///
/// While loading, the content is laid out but hidden and a centred spinner fades in (after the profile's delay, so a fast
/// load shows no spinner at all). Once `isReady` is true **and** every piece of content that reported itself through
/// ``tracker`` (a ``UKReadinessRequirement``) is ready, or the profile's child timeout passes, the spinner fades out and the
/// content fades in, rising from 4 pt low unless Reduce Motion is on. A gate created ready (data from the disk snapshot) shows
/// its content at once, with no animation. The phases, timings, telemetry and tracker are the SwiftUI gate's own
/// (``ContentGateModel``, ``ReadinessTracker``); this view only draws them.
///
/// ```swift
/// let gate = UKContentGateView(page: "Pantry", isReady: model.isLoaded, timing: .page, label: "Loading Pantry", content: list.view)
/// // later: gate.isReady = model.isLoaded
/// ```
@MainActor
final class UKContentGateView: UIView {
    /// The phases and timings (shared with the SwiftUI gate and the modal reveal).
    var model: ContentGateModel { driver.model }
    /// Content inside the gate reports here (``UKReadinessRequirement``).
    var tracker: ReadinessTracker { driver.model.tracker }
    /// Whether the page's data is loaded; flip it as the data arrives.
    var isReady: Bool {
        get { driver.isReady }
        set { driver.isReady = newValue }
    }

    private let driver: UKContentGateDriver
    private let centre = UILayoutGuide()

    /// - Parameters:
    ///   - page: Names the page in telemetry (`ContentReady` signposts).
    ///   - isReady: Whether the page's data is loaded.
    ///   - timing: The first load's timings: ``ContentGateModel/Profile/page`` for a page opening cold, ``ContentGateModel/Profile/results`` (default) for a results region.
    ///   - reloadTiming: Later loads' timings (defaults to `timing`).
    ///   - label: What VoiceOver says for the spinner ("Loading Pantry").
    ///   - content: The page content.
    init(page: String, isReady: Bool, timing: ContentGateModel.Profile = .results, reloadTiming: ContentGateModel.Profile? = nil,
         label: String = "Loading", content: UIView) {
        let model = ContentGateModel(page: page, isReady: isReady, firstLoad: timing, reload: reloadTiming)
        driver = UKContentGateDriver(model: model, content: content, arcHost: nil, arcCenter: centre, label: label, isReady: isReady)
        super.init(frame: .zero)
        driver.arcHost = self
        addLayoutGuide(centre)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            centre.topAnchor.constraint(equalTo: topAnchor), centre.bottomAnchor.constraint(equalTo: bottomAnchor),
            centre.leadingAnchor.constraint(equalTo: leadingAnchor), centre.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Draws a ``ContentGateModel`` onto a view tree: the one drawing code behind ``UKContentGateView`` (a page's or a region's own
/// gate) and the modal reveal (``UKSheetRevealController``).
///
/// It hides `content` (alpha 0, no hits, hidden from VoiceOver) while the model is not showing it, fades it in over the profile's
/// `contentEnter` (rising `contentRise` pt unless Reduce Motion is on), and builds a ``UKArcSpinnerView`` in `arcHost`, centred on
/// `arcCenter`, only while the model says the arc shows. The arc is laid out the moment it is added, so its first frame is its
/// centred frame and it never travels in from the origin. The driver observes the model and the readiness tracker itself and calls
/// ``ContentGateModel/advance(isReady:reduceMotion:)``; its owner keeps it alive and sets ``isReady``.
@MainActor
final class UKContentGateDriver {
    let model: ContentGateModel
    /// Whether the data is loaded; flip it as it arrives.
    var isReady: Bool { didSet { if isReady != oldValue { restart() } } }
    /// Where the arc is added; the gate view sets itself right after `super.init`.
    weak var arcHost: UIView?
    /// Whether the arc has drawn at all so far (it decides whether the end announces a layout change).
    private(set) var arcWasShown = false
    /// The arc while it exists; nil before it fades in and after it fades out.
    var arc: UKArcSpinnerView? { spinner }

    private let content: UIView
    private let arcCenter: UILayoutGuide
    private let label: String
    private let bag = UKObservationBag()
    private var spinner: UKArcSpinnerView?
    private var advanceTask: Task<Void, Never>?
    private var appliedPhase: ContentGateModel.Phase
    private var appliedSpinner = false
    private var hasShownContent: Bool

    /// - Parameters:
    ///   - model: The phases to draw.
    ///   - content: The view that is hidden, then faded in.
    ///   - arcHost: The view the arc is added to (nil until the owner has one).
    ///   - arcCenter: The arc's centre, a layout guide in `arcHost`'s hierarchy.
    ///   - label: What VoiceOver says for the arc ("Loading Climate").
    ///   - isReady: Whether the data is already there.
    init(model: ContentGateModel, content: UIView, arcHost: UIView?, arcCenter: UILayoutGuide, label: String, isReady: Bool = true) {
        self.model = model
        self.content = content
        self.arcHost = arcHost
        self.arcCenter = arcCenter
        self.label = label
        self.isReady = isReady
        appliedPhase = model.phase
        hasShownContent = model.phase == .idle
        applyPhase(animated: false)
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.model.phase
            _ = self.model.spinnerShown
            self.applyPhase(animated: self.content.window != nil)
        }
        // `.task(id: Input(isReady:, settled:, presented:))`: a new advance whenever any input changes.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.model.tracker.isSettled
            _ = self.model.isPresented
            self.restart()
        }
    }

    /// Stops the gate: no more advances, the arc removed. The content keeps whatever it shows (a reveal cancelled on dismiss).
    func cancel() {
        advanceTask?.cancel()
        advanceTask = nil
        bag.removeAll()
        spinner?.removeFromSuperview()
        spinner = nil
    }

    /// The host finished presenting: tells the model and advances at once, rather than waiting for the observation's next turn.
    func presentationCompleted() {
        model.presentationCompleted()
        restart()
    }

    /// The gate is over (the content has shown): draws the final phase now, so no pending observation is needed, and stops.
    func settle() {
        applyPhase(animated: false)
        cancel()
    }

    private func restart() {
        advanceTask?.cancel()
        let model = model
        let isReady = isReady
        advanceTask = Task { @MainActor in
            await model.advance(isReady: isReady, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        }
    }

    // MARK: Drawing the phase

    private var profile: ContentGateModel.Profile { hasShownContent ? model.reload : model.firstLoad }

    private func applyPhase(animated: Bool) {
        let phase = model.phase
        let spinnerShown = model.spinnerShown
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let contentAlpha: CGFloat = phase == .entering || phase == .idle ? 1 : 0
        let rise: CGFloat = phase != .idle && phase != .entering ? UKContentReveal.rise(reduceMotion: reduceMotion, profile: profile) : 0
        let spinnerAlpha: CGFloat = phase == .loading && spinnerShown ? 1 : 0
        UKContentReveal.setAvailable(content, phase.showsContent)

        if spinnerAlpha > 0 { ensureSpinner() }
        let previous = appliedPhase
        let spinnerChanged = spinnerShown != appliedSpinner
        appliedPhase = phase
        appliedSpinner = spinnerShown
        if phase == .idle { hasShownContent = true }

        let changes = {
            self.content.alpha = contentAlpha
            self.content.transform = CGAffineTransform(translationX: 0, y: rise)
            self.spinner?.alpha = spinnerAlpha
        }
        if animated, phase != previous || spinnerChanged, phase != .loading || spinnerChanged {
            let seconds: Double
            var options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
            switch phase {
            case .entering: seconds = profile.contentEnter.ukSeconds; options.insert(.curveEaseOut)
            case .exiting: seconds = profile.contentExit.ukSeconds; options.insert(.curveEaseOut)
            case .spinnerExiting: seconds = profile.spinnerExit.ukSeconds; options.insert(.curveEaseOut)
            case .loading: seconds = profile.spinnerEnter.ukSeconds; options.insert(.curveEaseIn)
            case .idle: seconds = 0
            }
            UIView.animate(withDuration: seconds, delay: 0, options: options, animations: changes) { [weak self] _ in
                guard let self, let spinner = self.spinner, spinner.alpha == 0, self.appliedPhase != .loading else { return }
                spinner.removeFromSuperview()
                self.spinner = nil
            }
        } else {
            changes()
            if spinnerAlpha == 0, let spinner {
                spinner.removeFromSuperview()
                self.spinner = nil
            }
        }
        // The content was hidden from VoiceOver while the arc was up: tell it the layout changed so focus lands on the page. A
        // reveal that never showed its arc fades in under the sheet's own announcement and says nothing.
        if phase == .idle, previous != .idle, arcWasShown { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
    }

    /// Built only while it shows, so a fast load never runs the arc at all. Laid out at once, without animation, so the first
    /// frame it draws is already centred.
    private func ensureSpinner() {
        guard spinner == nil, let host = arcHost else { return }
        let spinner = UKArcSpinnerView(.page, label: label)
        spinner.accessibilityIdentifier = "contentGate.spinner"
        spinner.alpha = 0
        spinner.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: arcCenter.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: arcCenter.centerYAnchor),
        ])
        UIView.performWithoutAnimation { host.layoutIfNeeded() }
        self.spinner = spinner
        arcWasShown = true
    }
}

/// The content-gate reveal, shared by every gate (pattern `content-gate.md`, sequence step 3): content is held back (laid out, invisible,
/// not hit, hidden from VoiceOver) and revealed by fading in while rising 4 pt (no rise under Reduce Motion). ``UKContentGateView``
/// and ``UKHouseLayoutGate`` both use it, so the timings (``ContentGateModel/Profile``), the rise and the availability rules live here.
@MainActor
enum UKContentReveal {
    /// How far held-back content sits below its place before it rises (the profile's `contentRise`; zero under Reduce Motion, which keeps the fade).
    static func rise(reduceMotion: Bool, profile: ContentGateModel.Profile = .page) -> CGFloat { reduceMotion ? 0 : profile.contentRise }

    /// Makes `content` reachable (hit testing, VoiceOver) or not.
    static func setAvailable(_ content: UIView, _ available: Bool) {
        content.isUserInteractionEnabled = available
        content.accessibilityElementsHidden = !available
    }

    /// Holds `content` back at once: invisible and unreachable, still laid out.
    static func hold(_ content: UIView) {
        content.layer.removeAllAnimations()
        content.alpha = 0
        content.transform = .identity
        setAvailable(content, false)
    }

    /// Shows `content`; animated, it fades in over the profile's `contentEnter` (the page profile's 170 ms) rising 4 pt, after `delay`.
    /// - Parameters:
    ///   - content: The held-back content.
    ///   - animated: False shows it at once (a reopen, a cache that was already there).
    ///   - delay: How long to wait first, for a layer fading out above it.
    ///   - profile: The timings; ``ContentGateModel/Profile/page`` by default.
    ///   - completion: Called when it is fully shown.
    static func reveal(_ content: UIView, animated: Bool, delay: TimeInterval = 0, profile: ContentGateModel.Profile = .page,
                       completion: (() -> Void)? = nil) {
        setAvailable(content, true)
        guard animated else {
            content.alpha = 1
            content.transform = .identity
            completion?()
            return
        }
        content.transform = CGAffineTransform(translationX: 0, y: rise(reduceMotion: UKDesign.reduceMotion, profile: profile))
        UIView.animate(withDuration: profile.contentEnter.ukSeconds, delay: delay, options: [.curveEaseOut, .allowUserInteraction], animations: {
            content.alpha = 1
            content.transform = .identity
        }, completion: { _ in completion?() })
    }
}

extension Duration {
    /// The duration in seconds, for UIKit animations.
    var ukSeconds: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// Holds the enclosing ``UKContentGateView`` (if any) until `isReady` (`contentReadiness(_:isReady:)`), so its spinner gives way
/// only once this content can draw. Leaving the screen counts as ready: call ``end()`` (or let it deinit with its owner).
///
/// ```swift
/// final class UKCachedImageView: UIImageView {
///     private var readiness: UKReadinessRequirement?
///     func attach(to tracker: ReadinessTracker?) { readiness = UKReadinessRequirement("image:\(url)", tracker: tracker, isReady: false) }
///     func loaded() { readiness?.isReady = true }
///     override func removeFromSuperview() { readiness?.end(); super.removeFromSuperview() }
/// }
/// ```
@MainActor
final class UKReadinessRequirement {
    let id: String
    private weak var tracker: ReadinessTracker?
    var isReady: Bool { didSet { tracker?.set(id, ready: isReady) } }

    init(_ id: String, tracker: ReadinessTracker?, isReady: Bool) {
        self.id = id
        self.tracker = tracker
        self.isReady = isReady
        tracker?.set(id, ready: isReady)
    }

    /// The content left the screen: it no longer holds the gate.
    func end() { tracker?.set(id, ready: true) }
}
#endif
