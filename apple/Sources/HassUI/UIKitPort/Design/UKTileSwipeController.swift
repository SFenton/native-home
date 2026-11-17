#if os(iOS)
import HassDesign
import UIKit

// MARK: - Swipe to adjust a tile (`sh.tile-swipe@1`)

/// What one swiped tile does: the maths, the words of its bubble and the feel of its drag.
struct UKTileSwipeConfig: Equatable {
    /// The range, the step and the detent.
    var swipe: TileSwipe
    /// The bubble and spoken value, with `{value}` for the number; nil writes the plain number.
    var format: String?
    /// What the bubble reads at the minimum ("Off" on a light), nil for the number.
    var zeroWord: String?
    /// Whether the tile draws its value as a band, at rest and in a drag.
    var showsBand = true
    /// Whether a detent line ticks.
    var ticks = true
    /// What is adjusted, lower case ("brightness"): the hint's noun and the two named actions.
    var label: String

    /// A light's brightness: 0 to 100 by 1, a tick every 10, "Off" at 0.
    static let brightness = UKTileSwipeConfig(swipe: .brightness, format: "{value}%", zeroWord: "Off", showsBand: true, ticks: true, label: "brightness")
}

/// One swipe controller for any glass tile: the pan, the bubble, the lift, the tick, and VoiceOver's increment and decrement
/// (`.agents/patterns/tile-swipe.md`, "Swipe to adjust").
///
/// Tracking is absolute: the band's edge is the finger. While the finger is down the controller moves the host's band and the bubble per sample
/// through ``onFrame`` and does not rebuild the tile (`configure`), writes no state and sends no call; the one call goes out on release through
/// ``onCommit``, and only when the value changed. A touch the system takes sends nothing and the band goes back. The "Not the swipe" rules
/// are the delegate's: a vertical start is the scroll's, an edge start is the edge pan's, a horizontal scroller above wins, a disc's touch is
/// the disc's, and one tile drags at a time.
@MainActor
final class UKTileSwipeController: NSObject, UIGestureRecognizerDelegate {
    // MARK: Inputs

    /// What the tile does.
    let config: UKTileSwipeConfig
    /// The value the tile shows now: the live one, or the optimistic one a release put there.
    var shownValue: () -> Double = { 0 }
    /// A sample: the value under the finger, or `nil` when the drag is over and the tile returns to what it shows.
    var onFrame: (Double?) -> Void = { _ in }
    /// The release: the one call, with the snapped value.
    var onCommit: (Double) -> Void = { _ in }
    /// Asked right after ``onCommit``: whether the commit left an optimistic value behind, so the band can stay at the committed value until the
    /// tile's next `configure`. A consumer that sets none (or refreshes at once) answers no and the frame is released in the same turn.
    var holdsCommittedFrame: () -> Bool = { false }
    /// The commit left a value behind: the tile keeps the band where the finger left it and releases it in its next `configure`.
    var onFrameHold: () -> Void = {}
    /// Whether the tile takes input now (not unavailable, not dimmed by `enabledWhen`).
    var isEnabled: () -> Bool = { true }

    // MARK: Parts

    private weak var host: UIView?
    private let pan = UIPanGestureRecognizer()
    let bubble = UKTileSwipeBubbleView()
    private var lastSample: Double?
    private(set) var dragValue: Double?
    /// Samples taken since the touch began: tests and the cost signpost read it.
    private(set) var sampleCount = 0
    /// The tile that is dragging now; one at a time.
    private static weak var active: UKTileSwipeController?
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?
    private var width: CGFloat = 0
    /// The latest `configure` a republish asked for while the finger was down, run once it lifts.
    private var deferred: (() -> Void)?

    /// Why the last drag was dropped without sending ("resign", "width 170.0 to 171.0", "detach"); tests and diagnostics read it.
    private(set) var lastCancelReason: String?

    /// Whether the finger is down. The tile's republish guard reads it (`hasActiveInteraction`).
    var isDragging: Bool { dragValue != nil }

    // MARK: Init

    /// Attaches the swipe to `host`. A tile inside a horizontal scroller keeps its band, trait and actions but takes no pan, decided as the
    /// touch begins from the ancestor chain, never from the device.
    init(host: UIView, config: UKTileSwipeConfig) {
        self.host = host
        self.config = config
        super.init()
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.name = "UKTileSwipe.pan"
        host.addGestureRecognizer(pan)
        bubble.alpha = 0
        bubble.isUserInteractionEnabled = false
        resignObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel(reason: "resign") }
        }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    /// Detaches the pan and the bubble.
    func detach() {
        cancel(reason: "detach")
        host?.removeGestureRecognizer(pan)
        bubble.removeFromSuperview()
    }

    // MARK: Words

    /// The bubble's text for `value`.
    func text(_ value: Double) -> String { config.swipe.bubbleText(value, format: config.format, zeroWord: config.zeroWord) }

    /// The hint's second sentence: "Swipe up or down to adjust brightness."
    var adjustHint: String { "Swipe up or down to adjust \(config.label)." }

    /// The title-cased noun of the two named actions.
    var actionNoun: String { config.label.prefix(1).uppercased() + config.label.dropFirst() }

    /// Holds a `configure` that arrived during a drag; the latest replaces the one before. Returns whether it was held.
    func hold(_ work: @escaping () -> Void) -> Bool {
        guard isDragging else { return false }
        deferred = work
        return true
    }

    // MARK: Increment and decrement

    /// VoiceOver's increment and decrement, and the two named actions: one detent, clamped, one call.
    func step(up: Bool) {
        guard isEnabled(), !isDragging else { return }
        let shown = shownValue()
        let next = config.swipe.adjusted(shown, up: up)
        if let value = config.swipe.commit(next, shown: shown) { onCommit(value) }
    }

    // MARK: Pan

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let host else { return }
        switch pan.state {
        case .began, .changed:
            width = host.bounds.width
            let x = pan.location(in: host).x
            let value = config.swipe.value(atX: x, width: width, isRightToLeft: host.effectiveUserInterfaceLayoutDirection == .rightToLeft)
            sampleDidChange(value)
        case .ended:
            let value = dragValue
            let shown = shownValue()
            if let value, let commit = config.swipe.commit(value, shown: shown) {
                // A release that sends the value: the call and its pending value come before any redraw, the held `configure` is dropped unrun (the
                // rebuilt model that follows carries the live state under the optimistic value), and the band stays at the committed value.
                endDrag()
                deferred = nil
                onCommit(commit)
                // A consumer that set no value behind the call (or refreshed itself, as a light does) gets the frame back in this turn.
                if holdsCommittedFrame() { onFrameHold() } else { onFrame(nil) }
            } else {
                finish()
            }
        case .cancelled, .failed:
            finish()
        default: break
        }
    }

    private func sampleDidChange(_ value: Double) {
        let starting = dragValue == nil
        if starting {
            Self.active = self
            setLifted(true)
        }
        // One tick at most per sample, never on the first, and never when the system's haptics are off (the generator is silent then).
        if config.ticks, config.swipe.crossesDetent(from: lastSample, to: value) { UKTapFeedback.step() }
        lastSample = value
        dragValue = value
        sampleCount += 1
        onFrame(value)
        placeBubble(value)
    }

    /// Drops the drag without sending: a scroll, an edge swipe, a rotation, a fold or the app leaving the foreground.
    func cancel(reason: String = "cancel") {
        guard isDragging else { return }
        lastCancelReason = reason
        pan.isEnabled = false
        pan.isEnabled = true
        finish()
    }

    /// Ends the drag's own state: no finger, no lift, no bubble. The band and the held `configure` are the caller's.
    @discardableResult
    private func endDrag() -> Bool {
        let wasDragging = isDragging
        dragValue = nil
        lastSample = nil
        if Self.active === self { Self.active = nil }
        setLifted(false)
        return wasDragging
    }

    private func finish() {
        let wasDragging = endDrag()
        if wasDragging {
            onFrame(nil)
            let work = deferred
            deferred = nil
            work?()
        }
    }

    /// A host whose width changed under the finger (a fold, a posture change, a split) drops the drag.
    func hostDidLayout(width newWidth: CGFloat) {
        if isDragging, abs(newWidth - width) > 0.5 { cancel(reason: "width \(width) to \(newWidth)") }
    }

    // MARK: Look

    /// The tile lifts while dragging (only its shadow with Reduce Motion) and the bubble fades in.
    private func setLifted(_ lifted: Bool) {
        guard let host else { return }
        let lift: CGAffineTransform = lifted && !UKDesign.reduceMotion ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        UIView.animate(withDuration: UKDesign.reduceMotion ? 0.2 : UKMotion.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            host.transform = lift
            self.bubble.alpha = lifted ? 1 : 0
        }
        // No shadow pass at rest: a blurred shadow over the tile's material is an offscreen render on every frame.
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = host.layer.shadowOpacity
        shadow.toValue = lifted ? 0.35 : 0
        shadow.duration = UKMotion.quickDuration
        host.layer.shadowColor = UIColor.black.cgColor
        host.layer.shadowRadius = 12
        host.layer.shadowOffset = CGSize(width: 0, height: 6)
        host.layer.shadowOpacity = lifted ? 0.35 : 0
        host.layer.add(shadow, forKey: "swipe.shadow")
        if lifted { host.superview?.bringSubviewToFront(host) }
    }

    /// Puts the bubble over the band's edge, 8 pt above the tile and whole inside its width; near the top of the scroller it comes down only as
    /// far as it must.
    private func placeBubble(_ value: Double) {
        guard let host else { return }
        if bubble.superview == nil { host.addSubview(bubble) }
        host.bringSubviewToFront(bubble)
        let rtl = host.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let metrics = TileSwipeBubble.metrics(isAccessibilitySize: host.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        bubble.show(text(value), metrics: metrics, traits: host.traitCollection)
        let size = bubble.size(maxWidth: host.bounds.width)
        let edge = config.swipe.edge(of: value, width: host.bounds.width, isRightToLeft: rtl)
        let centerX = TileSwipeBubble.centerX(edge: edge, tileWidth: host.bounds.width, bubbleWidth: size.width)
        var centerY = -metrics.lift
        if let scroll = host.ukEnclosingScrollView {
            let frame = host.convert(host.bounds, to: scroll)
            let visibleTop = scroll.contentOffset.y + scroll.adjustedContentInset.top
            centerY += TileSwipeBubble.topShift(tileTop: frame.minY - visibleTop, metrics: metrics)
        }
        // The tile's own lift scales it about its centre; the bubble is a child, so it is placed in the unscaled space.
        bubble.frame = CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Delegate

    /// A start that is mostly horizontal by travel and by velocity (``TileSwipeStart``), with no horizontal scroller above and no other tile dragging. Disabled tiles take no drag.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, isEnabled() else { return false }
        if let active = Self.active, active !== self { return false }
        if host?.ukHasHorizontalScrollerAbove == true { return false }
        // The stroke's own shape and its velocity must both say sideways: a first sample that leans sideways cannot start a swipe on a stroke that
        // has gone up the page at 60 degrees (a diagonal-steep start is the scroll's).
        return TileSwipeStart.isHorizontal(translation: pan.translation(in: pan.view), velocity: pan.velocity(in: pan.view))
    }

    /// A touch that starts on a disc is the disc's.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UKTileActionDisc)
    }

    /// The shell's leading-edge pan, the iPad flyout's and the column edge pans take a touch that starts in their zone, even over a tile.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        other is UIScreenEdgePanGestureRecognizer
    }
}

// MARK: - The bubble

/// The capsule that names the value a release will send: a fixed dark capsule with white text in every appearance, never a tile face (like the
/// system's volume HUD). VoiceOver hears the tile's value instead, so the bubble is not an accessibility element.
@MainActor
final class UKTileSwipeBubbleView: UIView {
    private let label = UILabel()
    private(set) var metrics = TileSwipeBubble.regular

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "tile.swipe.bubble"
        backgroundColor = .ukRGB(HassTokens.Palette.sheetCell)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 1
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The words and the sizes for the text size of `traits`. At most xxLarge at regular sizes and the first accessibility size above them.
    func show(_ text: String, metrics: TileSwipeBubble.Metrics, traits: UITraitCollection) {
        self.metrics = metrics
        let category = traits.preferredContentSizeCategory
        let capped = category.isAccessibilityCategory
            ? (category > .accessibilityMedium ? UITraitCollection(preferredContentSizeCategory: .accessibilityMedium) : traits)
            : (category > .extraExtraLarge ? UITraitCollection(preferredContentSizeCategory: .extraExtraLarge) : traits)
        label.font = UKFont.rowTitle(capped, monospacedDigit: true)
        label.text = text
        layer.cornerRadius = metrics.height / 2
        accessibilityLabel = nil
        setNeedsLayout()
    }

    /// The capsule's size for the shown text, growing to `maxWidth` and no further.
    func size(maxWidth: CGFloat) -> CGSize {
        let textWidth = ceil(label.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: metrics.height)).width)
        return CGSize(width: TileSwipeBubble.width(textWidth: textWidth, tileWidth: maxWidth, metrics: metrics), height: metrics.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: min(metrics.horizontalPadding, bounds.width / 4), dy: 0)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
    }
}

// MARK: - Ancestors

extension UIView {
    /// The nearest scroll view above this view.
    var ukEnclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }

    /// Whether a scroll view above this view scrolls sideways (a paged row, `ukPagesByViewport`, a chip rail): it wins, and the tile takes no pan.
    var ukHasHorizontalScrollerAbove: Bool {
        var view = superview
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled,
               scroll.contentSize.width > scroll.bounds.width + 1 || (scroll.isPagingEnabled && scroll.alwaysBounceHorizontal) {
                return true
            }
            view = current.superview
        }
        return false
    }
}
#endif
