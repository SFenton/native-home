#if os(iOS)
import HassDesign
import HassTelemetry
import UIKit

// MARK: - Scroll gate

/// Tells the tickers inside a scroll view when it is moving, so they pause (`pausesTickersWhileScrolling()`). Install with
/// ``UIScrollView/ukPausesTickersWhileScrolling()``; it observes the scroll view's offset and needs no delegate.
@MainActor
final class UKTickerScrollGate: NSObject {
    static let didChange = Notification.Name("UKTickerScrollGateDidChange")
    private static var gateKey: UInt8 = 0

    private(set) var isScrolling = false {
        didSet { if isScrolling != oldValue { NotificationCenter.default.post(name: Self.didChange, object: self) } }
    }
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var idleTimer: Timer?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.moved() }
        }
    }

    /// The gate of the nearest scroll view above `view`, if any installed one.
    static func nearest(above view: UIView) -> UKTickerScrollGate? {
        var current = view.superview
        while let candidate = current {
            if let scroll = candidate as? UIScrollView, let gate = objc_getAssociatedObject(scroll, &gateKey) as? UKTickerScrollGate { return gate }
            current = candidate.superview
        }
        return nil
    }

    static func install(on scrollView: UIScrollView) {
        guard objc_getAssociatedObject(scrollView, &gateKey) == nil else { return }
        objc_setAssociatedObject(scrollView, &gateKey, UKTickerScrollGate(scrollView: scrollView), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private func moved() {
        isScrolling = true
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard let scrollView else { isScrolling = false; return }
        if scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking { moved() } else { isScrolling = false }
    }
}

extension UIScrollView {
    /// Tells the tickers inside this scroll view when it is moving, so they pause.
    func ukPausesTickersWhileScrolling() {
        UKTickerScrollGate.install(on: self)
    }
}

// MARK: - Ticker

/// One line of text that scrolls like a ticker when it is wider than the room it has (`TickerLabel`, pattern: `.agents/patterns/ticker.md`).
///
/// The label takes the width it is offered. If its natural width is wider, it plays ``MotionTokens/Ticker/passes`` passes of
/// ``TickerPlan`` (hold, travel at 30 pt/s, hold, return) after it appears or its text changes, with a soft fade at each edge, then rests
/// at the start. It runs only while it overflows, the app is active, the view is on screen and its page is not scrolling, and not at all
/// under Reduce Motion (then ``wraps`` decides whether the text wraps or is cut). The ticker text is hidden from accessibility: the
/// caller names the content some other way.
///
/// One display link drives the offset, and only while the ticker runs, so a page of resting labels costs nothing.
@MainActor
final class UKTickerLabel: UIView {
    // MARK: Inputs

    var text: String { didSet { if text != oldValue { textChanged() } } }
    /// The label's font (`.headline` by default); rebuilt when Dynamic Type changes.
    var textStyle: UIFont.TextStyle { didSet { updateFont() } }
    var weight: UIFont.Weight? { didSet { updateFont() } }
    /// Monospaced digits (`.monospacedDigit()`), for a tile's state line.
    var monospacedDigit = false { didSet { updateFont() } }
    var textColor: UIColor = .label { didSet { for label in [staticLabel, movingLabel] { label.textColor = textColor } } }
    /// Wrap onto as many lines as the text needs instead of ticking (accessibility sizes, Reduce Motion).
    var wraps: Bool { didSet { updateMode() } }
    /// Where the label cannot grow (a navigation bar): when it must hold still it is cut with an ellipsis on one line.
    var truncatesWhenStill: Bool { didSet { updateMode() } }
    /// An accessibility identifier for an invisible element that reports the ticker's state to UI tests, added only when
    /// `FENTON_TICKER_PROBE=1` is in the environment.
    var probe: String? { didSet { updateProbe() } }

    /// Whether this launch adds the probe elements.
    static let probeEnabled = TickerLabel.probeEnabled
    /// Whether the label's section is on screen; a ticker holds still behind another tab (`tickerIsOnScreen`).
    var isSectionOnScreen = true { didSet { sync() } }

    // MARK: State

    private let staticLabel = UILabel()
    private let movingLabel = UILabel()
    private let clip = UIView()
    private let fade = CAGradientLayer()
    private let probeView = UIView()
    private var plan = TickerPlan(textWidth: 0, columnWidth: 0)
    private var clock = TickerClock()
    private var link: CADisplayLink?
    private var interval: Telemetry.Interval?
    private var gate: UKTickerScrollGate?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObservers: UKObserverTokens?
    private var isScrolling: Bool { gate?.isScrolling ?? false }

    init(_ text: String, textStyle: UIFont.TextStyle = .headline, weight: UIFont.Weight? = nil, wraps: Bool = false,
         truncatesWhenStill: Bool = false, probe: String? = nil) {
        self.text = text
        self.textStyle = textStyle
        self.weight = weight
        self.wraps = wraps
        self.truncatesWhenStill = truncatesWhenStill
        self.probe = probe
        super.init(frame: .zero)
        isAccessibilityElement = false
        clipsToBounds = true
        for label in [staticLabel, movingLabel] {
            label.text = text
            label.textColor = textColor
            label.isAccessibilityElement = false
        }
        movingLabel.numberOfLines = 1
        movingLabel.lineBreakMode = .byClipping
        clip.addSubview(movingLabel)
        clip.layer.mask = fade
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        addSubview(staticLabel)
        addSubview(clip)
        probeView.isUserInteractionEnabled = false
        probeView.isAccessibilityElement = true
        updateFont()
        updateMode()
        updateProbe()
        accessibilityObservers = NotificationCenter.default.ukObserveAccessibility { [weak self] in
            self?.updateMode()
            self?.sync()
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKTickerLabel, _) in view.updateFont() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        MainActor.assumeIsolated {
            link?.invalidate()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    // MARK: Mode

    private var reduceMotion: Bool { UKDesign.reduceMotion }
    private var isTicking: Bool { !(wraps || reduceMotion) }

    private func updateFont() {
        let font = UKFont.preferred(textStyle, weight: weight, monospacedDigit: monospacedDigit, traits: traitCollection)
        staticLabel.font = font
        movingLabel.font = font
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func updateMode() {
        updateVisibility()
        if truncatesWhenStill, !isTicking {
            staticLabel.numberOfLines = 1
            staticLabel.lineBreakMode = .byTruncatingTail
        } else {
            staticLabel.numberOfLines = 0
            staticLabel.lineBreakMode = .byWordWrapping
        }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        sync()
    }

    /// The moving label and its edge-fade mask (an offscreen pass) exist only while the text overflows; text that fits is a plain
    /// label, as in SwiftUI's `TickerLabel`.
    private func updateVisibility() {
        let moves = isTicking && plan.overflows
        staticLabel.isHidden = moves
        clip.isHidden = !moves
    }

    private func textChanged() {
        staticLabel.text = text
        movingLabel.text = text
        pause(cause: "restart")
        clock.restart()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        sync()
    }

    // MARK: Layout

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if isTicking {
            return CGSize(width: size.width, height: ceil(movingLabel.font.lineHeight))
        }
        let fitted = staticLabel.sizeThatFits(CGSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fitted.height))
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: sizeThatFits(CGSize(width: max(bounds.width, 1), height: 0)).height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        staticLabel.frame = bounds
        clip.frame = bounds
        let natural = movingLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height))
        movingLabel.frame = CGRect(x: -currentOffset, y: 0, width: ceil(natural.width), height: bounds.height)
        var next = plan
        next.columnWidth = bounds.width
        next.textWidth = ceil(natural.width)
        if next != plan {
            plan = next
            updateVisibility()
            sync()
        }
        updateFade(offset: currentOffset)
        positionProbe()
    }

    private var currentOffset: CGFloat { isTicking ? plan.offset(at: clock.elapsed(at: .now)) : 0 }

    /// A mask that is clear in the middle and fades each edge over ``MotionTokens/Ticker/fadeWidth``, the leading edge only once the
    /// text has moved (at rest the first letter stays solid, aligned with the glyph above), the trailing edge only while there is more
    /// text to the right.
    private func updateFade(offset: CGFloat) {
        let width = max(plan.columnWidth, 1)
        let fadeWidth = MotionTokens.Ticker.fadeWidth
        let leading = plan.overflows ? min(fadeWidth, offset) : 0
        let trailing = plan.overflows ? min(fadeWidth, max(plan.travel - offset, 0)) : 0
        let start = leading / width
        let end = 1 - trailing / width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.colors = [UIColor.black.withAlphaComponent(leading > 0 ? 0 : 1).cgColor, UIColor.black.cgColor, UIColor.black.cgColor,
                       UIColor.black.withAlphaComponent(trailing > 0 ? 0 : 1).cgColor]
        fade.locations = [0, NSNumber(value: max(start, 0)), NSNumber(value: min(end, 1)), 1]
        CATransaction.commit()
    }

    // MARK: Running

    /// Whether the label may run now.
    private var shouldRun: Bool {
        isTicking && plan.overflows && window != nil && !isHidden && isSectionOnScreen
            && window?.windowScene?.activationState == .foregroundActive && !isScrolling && !plan.isFinished(at: clock.elapsed(at: .now))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if window != nil {
            gate = UKTickerScrollGate.nearest(above: self)
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UKTickerScrollGate.didChange, object: gate, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            })
            for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sync() }
                })
            }
        } else {
            gate = nil
            pause(cause: "disappear")
        }
        sync()
    }

    /// Starts or pauses the clock to match ``shouldRun``.
    private func sync() {
        if plan.overflows, !clock.isRunning, shouldRun {
            clock.resume(at: .now)
            interval = Telemetry.begin(Telemetry.Name.tickerRun, page: "Ticker", "run")
            startLink()
        } else if !shouldRun, clock.isRunning {
            pause(cause: plan.isFinished(at: clock.elapsed(at: .now)) ? "finished" : "paused")
        }
        updateProbe()
    }

    private func pause(cause: String) {
        link?.invalidate()
        link = nil
        guard clock.isRunning else { return }
        clock.pause(at: .now)
        if let interval { _ = Telemetry.end(interval, detail: cause) }
        interval = nil
        applyOffset()
    }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: UKTickerLinkTarget { [weak self] in self?.tick() }, selector: #selector(UKTickerLinkTarget.fire))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func tick() {
        if plan.isFinished(at: clock.elapsed(at: .now)) || !shouldRun {
            // The last pass ended: stop the clock so the label rests at the start.
            let finished = plan.isFinished(at: clock.elapsed(at: .now))
            pause(cause: finished ? "finished" : "paused")
            applyOffset()
            updateProbe()
            return
        }
        applyOffset()
    }

    private func applyOffset() {
        let offset = currentOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movingLabel.frame.origin.x = -offset
        CATransaction.commit()
        updateFade(offset: offset)
    }

    // MARK: Probe

    private func updateProbe() {
        guard Self.probeEnabled, let probe else {
            probeView.removeFromSuperview()
            return
        }
        if probeView.superview == nil { addSubview(probeView) }
        let lineHeight = staticLabel.font.lineHeight
        let height = staticLabel.sizeThatFits(CGSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)).height
        // A ticking label is one line however long its text (the SwiftUI ticker reports the column it scrolls in).
        let lines = isTicking ? 1 : (lineHeight > 0 ? Int((height / lineHeight).rounded()) : 0)
        probeView.accessibilityLabel = "overflow=\(plan.overflows ? 1 : 0) running=\(clock.isRunning ? 1 : 0) "
            + "finished=\(plan.isFinished(at: clock.elapsed(at: .now)) ? 1 : 0) wraps=\(wraps || reduceMotion ? 1 : 0) lines=\(lines)"
        probeView.accessibilityIdentifier = probe
    }

    private func positionProbe() {
        probeView.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        if probeView.superview != nil { bringSubviewToFront(probeView) }
    }
}

/// Keeps a display link from retaining its owner.
private final class UKTickerLinkTarget: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @MainActor @objc func fire() { handler() }
}
#endif
