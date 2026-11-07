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
    let model: ContentGateModel
    /// Content inside the gate reports here (``UKReadinessRequirement``).
    var tracker: ReadinessTracker { model.tracker }
    /// Whether the page's data is loaded; flip it as the data arrives.
    var isReady: Bool { didSet { if isReady != oldValue { restart() } } }

    private let content: UIView
    private let label: String
    private let bag = UKObservationBag()
    private var spinner: UKArcSpinnerView?
    private var advanceTask: Task<Void, Never>?
    private var appliedPhase: ContentGateModel.Phase
    private var appliedSpinner = false
    private var hasShownContent: Bool

    /// - Parameters:
    ///   - page: Names the page in telemetry (`ContentReady` signposts).
    ///   - isReady: Whether the page's data is loaded.
    ///   - timing: The first load's timings: ``ContentGateModel/Profile/page`` for a page opening cold, ``ContentGateModel/Profile/results`` (default) for a results region.
    ///   - reloadTiming: Later loads' timings (defaults to `timing`).
    ///   - label: What VoiceOver says for the spinner ("Loading Pantry").
    ///   - content: The page content.
    init(page: String, isReady: Bool, timing: ContentGateModel.Profile = .results, reloadTiming: ContentGateModel.Profile? = nil,
         label: String = "Loading", content: UIView) {
        model = ContentGateModel(page: page, isReady: isReady, firstLoad: timing, reload: reloadTiming)
        self.isReady = isReady
        self.label = label
        self.content = content
        appliedPhase = model.phase
        hasShownContent = isReady
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        applyPhase(animated: false)
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.model.phase
            _ = self.model.spinnerShown
            self.applyPhase(animated: self.window != nil)
        }
        // `.task(id: Input(isReady:, settled:))`: a new advance whenever either input changes.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.tracker.isSettled
            self.restart()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        let rise: CGFloat = phase != .idle && phase != .entering ? UKContentReveal.rise(reduceMotion: reduceMotion) : 0
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
        // The content was hidden from VoiceOver while it loaded: tell it the layout changed so focus lands on the page.
        if phase == .idle, previous != .idle { UIAccessibility.post(notification: .layoutChanged, argument: nil) }
    }

    /// Built only while it shows, so a fast load never runs the arc at all.
    private func ensureSpinner() {
        guard spinner == nil else { return }
        let spinner = UKArcSpinnerView(.page, label: label)
        spinner.accessibilityIdentifier = "contentGate.spinner"
        spinner.alpha = 0
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: centerXAnchor), spinner.centerYAnchor.constraint(equalTo: centerYAnchor)])
        self.spinner = spinner
    }
}

/// The content-gate reveal, shared by every gate (pattern `content-gate.md`, sequence step 3): content is held back (laid out, invisible,
/// not hit, hidden from VoiceOver) and revealed by fading in while rising 4 pt (no rise under Reduce Motion). ``UKContentGateView``
/// and ``UKHouseLayoutGate`` both use it, so the timings (``ContentGateModel/Profile``), the rise and the availability rules live here.
@MainActor
enum UKContentReveal {
    /// How far held-back content sits below its place before it rises (zero under Reduce Motion, which keeps the fade).
    static func rise(reduceMotion: Bool) -> CGFloat { reduceMotion ? 0 : 4 }

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
        content.transform = CGAffineTransform(translationX: 0, y: rise(reduceMotion: UKDesign.reduceMotion))
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
