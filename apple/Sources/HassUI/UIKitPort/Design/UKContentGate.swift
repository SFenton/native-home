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
    var model: ContentGateModel { driver.model }
    /// Content inside the gate reports here (``UKReadinessRequirement``).
    var tracker: ReadinessTracker { model.tracker }
    /// Whether the page's data is loaded; flip it as the data arrives.
    var isReady: Bool {
        get { driver.isReady }
        set { driver.isReady = newValue }
    }
    private let driver: UKContentGateDriver

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
        driver = UKContentGateDriver(model: model, isReady: isReady, content: content, label: label)
        super.init(frame: .zero)
        driver.arcHost = self
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Shared phase drawing

/// Drives the shared loading phases on a region or the root content of a modal, without owning the sheet's chrome.
@MainActor
final class UKContentGateDriver {
    let model: ContentGateModel
    var isReady: Bool { didSet { if isReady != oldValue { restart() } } }
    weak var arcHost: UIView?
    var onFinished: (() -> Void)?

    private let arcCenter: UILayoutGuide?
    private let content: UIView
    private let label: String
    private let bag = UKObservationBag()
    private var spinner: UKArcSpinnerView?
    private var advanceTask: Task<Void, Never>?
    private var appliedPhase: ContentGateModel.Phase
    private var appliedSpinner = false
    private var hasShownContent: Bool
    private var arcWasShown = false

    init(model: ContentGateModel, isReady: Bool, content: UIView, arcHost: UIView? = nil,
         arcCenter: UILayoutGuide? = nil, label: String) {
        self.model = model
        self.isReady = isReady
        self.content = content
        self.arcHost = arcHost
        self.arcCenter = arcCenter
        self.label = label
        appliedPhase = model.phase
        hasShownContent = model.phase == .idle
        applyPhase(animated: false)
        bag.observe { [weak self] in
            guard let self else { return }
            self.applyPhase(animated: self.content.window != nil)
        }
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.model.tracker.isSettled
            self.restart()
        }
    }

    /// Follow a provider's typed readiness only for the lifetime of this gate.
    func observeReadiness(_ read: @escaping () -> Bool) {
        bag.observe { [weak self] in self?.isReady = read() }
    }

    func presentationCompleted() {
        model.presentationCompleted()
        restart()
    }

    func cancel() {
        advanceTask?.cancel()
        bag.removeAll()
        spinner?.removeFromSuperview()
        spinner = nil
    }

    private func restart() {
        advanceTask?.cancel()
        let model = model
        let isReady = isReady
        advanceTask = Task { @MainActor in
            await model.advance(isReady: isReady, reduceMotion: UKMotion.reduceMotion)
        }
    }

    // MARK: Drawing the phase

    private var profile: ContentGateModel.Profile { hasShownContent ? model.reload : model.firstLoad }

    private func applyPhase(animated: Bool) {
        let phase = model.phase
        let spinnerShown = model.spinnerShown
        let reduceMotion = UKMotion.reduceMotion
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
        // The content was hidden from VoiceOver while it loaded: tell it the layout changed so focus lands on the page.
        if phase == .idle, previous != .idle {
            if arcWasShown || !model.firstLoad.waitsForPresentation {
                UIAccessibility.post(notification: .layoutChanged, argument: nil)
            }
            onFinished?()
        }
    }

    /// Built only while it shows, so a fast load never runs the arc at all.
    private func ensureSpinner() {
        guard spinner == nil, let arcHost else { return }
        let spinner = UKArcSpinnerView(.page, label: label)
        spinner.accessibilityIdentifier = "contentGate.spinner"
        spinner.alpha = 0
        spinner.translatesAutoresizingMaskIntoConstraints = false
        arcHost.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: arcCenter?.centerXAnchor ?? arcHost.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: arcCenter?.centerYAnchor ?? arcHost.centerYAnchor),
        ])
        UIView.performWithoutAnimation { arcHost.layoutIfNeeded() }
        arcWasShown = true
        self.spinner = spinner
    }
}

/// The content-gate reveal, shared by every gate (pattern `content-gate.md`, sequence step 3): content is held back (laid out, invisible,
/// not hit, hidden from VoiceOver) and revealed by fading in while rising 4 pt (no rise under Reduce Motion). ``UKContentGateView``
/// uses it, so the timings (``ContentGateModel/Profile``), the rise and the availability rules live here.
@MainActor
enum UKContentReveal {
    /// How far held-back content sits below its place before it rises (zero under Reduce Motion, which keeps the fade).
    static func rise(reduceMotion: Bool, profile: ContentGateModel.Profile = .page) -> CGFloat {
        reduceMotion ? 0 : profile.contentRise
    }

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

#endif
