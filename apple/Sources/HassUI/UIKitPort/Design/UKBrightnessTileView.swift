#if os(iOS)
import HassDesign
import UIKit

/// A dimmable light tile (`BrightnessTile`, pattern: `.agents/patterns/entity-tile.md`) in UIKit, the light dragger of direction G.
///
/// A ``UKGlassTileView`` with the drag laid over its body (the SwiftUI tile's `tileBodyOverlay`, `tileAdjustable`), so discs, chevron,
/// widths and states are the pattern's (`.agents/patterns/action-tiles.md`): an **action tile** (*text, disc*) whose body flips power
/// and whose horizontal drag sets brightness, or, when ``onOpen`` is set, a **navigation tile** with the same `power` disc left of its
/// chevron. The warm lit tile's bright band is the brightness. While dragging, the tile lifts, a "30%" bubble floats over the band's
/// edge and a selection haptic ticks every 10%. A horizontal drag sets brightness from where the finger is across the body and commits
/// on release; a vertical drag is left to the scroll view (the pan only begins on a mostly horizontal movement, and never on a disc).
/// VoiceOver activates the tap and swipes up or down to step brightness by ``BrightnessTile/step``; the disc is its own button when the
/// body opens details. The tile reads as a button speaking its percentage, never a switch.
///
/// Pure UI: callers pass the live percent and receive intents; they send the service calls.
@MainActor
final class UKBrightnessTileView: UIView, UKGridMeasuring, UIGestureRecognizerDelegate {
    // MARK: Inputs

    private(set) var title: String
    private(set) var symbol: String
    private(set) var tint: UIColor
    private(set) var fillTint: UIColor?
    private(set) var percent: Int
    private(set) var isUnavailable: Bool
    /// Asked to turn the light on (`true`) or off.
    var onPower: ((Bool) -> Void)?
    /// Asked to set brightness; 0 means off.
    var onBrightness: ((Int) -> Void)?
    /// When set, the tile is a navigation tile: a tap opens the light's details (a sheet or a page, with the chevron) instead of flipping
    /// power, and the power disc sits left of the chevron.
    var onOpen: (() -> Void)? { didSet { refresh() } }
    /// The tile's accessibility identifier; the disc is `<identifier>.action.power`.
    var identifier: String? { didSet { refresh() } }
    var environment = UKTileEnvironment() { didSet { refresh() } }

    // MARK: Parts

    private let tile: UKGlassTileView
    private let bubble = UKBrightnessBubbleView()
    private var interaction = BrightnessInteraction()
    private var pendingTask: Task<Void, Never>?
    private var lastHapticStep: Int?
    private var isDragging: Bool { interaction.dragPercent != nil }
    private var pan: UIPanGestureRecognizer?

    /// Every state line the tile can show, so the grid sizes it for the longest and a live change never re-spans it.
    private static let stateCandidates = ["Off", "100%", "Unavailable"]

    // MARK: Init

    init(title: String, symbol: String = "lightbulb", tint: UIColor, fillTint: UIColor? = nil, percent: Int, isUnavailable: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.fillTint = fillTint
        self.percent = percent
        self.isUnavailable = isUnavailable
        tile = UKGlassTileView(model: UKGlassTileModel(title: title, symbol: symbol, isActive: false))
        super.init(frame: .zero)
        isAccessibilityElement = false
        addSubview(tile)
        bubble.alpha = 0
        bubble.isUserInteractionEnabled = false
        addSubview(bubble)
        tile.action = { [weak self] in self?.handleTap() }
        tile.onPerform = { [weak self] _ in self?.flip() }
        tile.onAdjust = { [weak self] up in self?.adjust(by: up ? BrightnessTile.step : -BrightnessTile.step) }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        // A drag that began never also taps: the pan cancels the tile's touch.
        tile.addGestureRecognizer(pan)
        self.pan = pan
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { MainActor.assumeIsolated { pendingTask?.cancel() } }

    // MARK: Update

    /// Shows the live state. Any live report replaces the optimistic value (web `useOptimisticState`).
    func update(title: String? = nil, symbol: String? = nil, tint: UIColor? = nil, fillTint: UIColor?, percent: Int, isUnavailable: Bool) {
        if let title { self.title = title }
        if let symbol { self.symbol = symbol }
        if let tint { self.tint = tint }
        self.fillTint = fillTint
        if percent != self.percent { interaction.pendingPercent = nil }
        self.percent = percent
        self.isUnavailable = isUnavailable
        refresh()
    }

    /// The tile's one action: a `power` disc, toggle-styled, optimistic. A tile that opens details and is unavailable has none; an action
    /// tile keeps it, dimmed in place. It is the item `PowerToggleActions.entity` yields, field for field
    /// (`BrightnessTile.powerItem(percent:isUnavailable:)`, internal to HassDesign).
    private func items(shown: Int) -> [TileActionItem] {
        if onOpen != nil, isUnavailable { return [] }
        return [TileActionItem(id: BrightnessTile.powerId, verb: shown > 0 ? "Turn Off" : "Turn On", symbol: "power", isOn: shown > 0,
                               phase: isUnavailable ? .unavailable : .ready, feedback: .optimistic)]
    }

    private func refresh() {
        let shown = interaction.shown(live: percent)
        let status = BrightnessTile.status(percent: shown, isUnavailable: isUnavailable)
        var model = UKGlassTileModel(
            title: title, subtitle: status, symbol: symbol, tint: tint, family: .lights, isActive: shown > 0 && !isUnavailable,
            isUnavailable: isUnavailable, isError: false, behavior: onOpen == nil ? .perform(BrightnessTile.powerId) : .navigate,
            actions: items(shown: shown), progress: isUnavailable ? nil : Double(shown) / 100, progressTint: fillTint, identifier: identifier)
        model.stateCandidates = Self.stateCandidates
        // A button speaking its percentage and adjustable, never a switch (the power disc carries the on/off state).
        model.useCommandSemantics()
        model.bodyHint = BrightnessTile.hint(percent: shown, isUnavailable: isUnavailable, opensDetails: onOpen != nil)
        tile.onAdjust = isUnavailable ? nil : { [weak self] up in self?.adjust(by: up ? BrightnessTile.step : -BrightnessTile.step) }
        tile.configure(model, environment: environment, animated: true)
        pan?.isEnabled = !isUnavailable
        bubble.percent = shown
        setNeedsLayout()
    }

    // MARK: Intents

    /// A tap: open details when the caller asked for that, else flip power.
    private func handleTap() {
        if let onOpen { onOpen() } else { flip() }
    }

    fileprivate func flip() {
        send(interaction.flip(live: percent, isUnavailable: isUnavailable))
    }

    fileprivate func adjust(by delta: Int) {
        send(interaction.adjust(by: delta, live: percent, isUnavailable: isUnavailable))
    }

    /// Passes `intent` to the caller and drops the optimistic value after ``BrightnessTile/pendingTimeout``.
    private func send(_ intent: BrightnessInteraction.Intent?) {
        guard let intent else { return }
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrightnessTile.pendingTimeout)
            guard !Task.isCancelled, let self else { return }
            interaction.pendingPercent = nil
            refresh()
        }
        switch intent {
        case let .power(on): onPower?(on)
        case let .brightness(value): onBrightness?(value)
        }
        refresh()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let x = pan.location(in: tile).x
        let width = tile.bounds.width
        switch pan.state {
        case .began, .changed:
            let moved = pan.translation(in: tile)
            let wasDragging = isDragging
            interaction.dragChanged(translation: CGSize(width: moved.x, height: moved.y), x: x, width: width)
            if isDragging != wasDragging { setDragging(isDragging) }
            let step = BrightnessTile.hapticStep(interaction.dragPercent)
            if lastHapticStep != nil, step != nil, step != lastHapticStep { UKTapFeedback.step() }
            lastHapticStep = step
            refresh()
        case .ended:
            send(interaction.dragEnded(x: x, width: width, live: percent))
            endDrag()
        case .cancelled, .failed:
            interaction.dragCancelled()
            endDrag()
        default: break
        }
    }

    private func endDrag() {
        lastHapticStep = nil
        setDragging(false)
        refresh()
    }

    /// The tile lifts while dragging (only its shadow with Reduce Motion), and the bubble fades in.
    private func setDragging(_ dragging: Bool) {
        let lift: CGAffineTransform = dragging && !UKDesign.reduceMotion ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        UIView.animate(withDuration: UKDesign.reduceMotion ? 0.2 : UKMotion.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.tile.transform = lift
            self.bubble.alpha = dragging ? 1 : 0
        }
        // No shadow pass at rest: a blurred shadow over the tile's material is an offscreen render on every frame.
        let shadow = CABasicAnimation(keyPath: "shadowOpacity")
        shadow.fromValue = tile.layer.shadowOpacity
        shadow.toValue = dragging ? 0.35 : 0
        shadow.duration = UKMotion.quickDuration
        tile.layer.shadowColor = UIColor.black.cgColor
        tile.layer.shadowRadius = 12
        tile.layer.shadowOffset = CGSize(width: 0, height: 6)
        tile.layer.shadowOpacity = dragging ? 0.35 : 0
        tile.layer.add(shadow, forKey: "shadow")
        if dragging { superview?.bringSubviewToFront(self) }
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }

    /// The drag lies under the discs: a touch that starts on one is the disc's.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UKTileActionDisc)
    }

    // MARK: Layout

    var gridMinimumWidth: CGFloat { tile.gridMinimumWidth }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile.gridHeight(forWidth: width) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { tile.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.transform = .identity
        tile.frame = bounds
        let center = BrightnessTile.bubbleCenter(percent: interaction.shown(live: percent), width: bounds.width)
        bubble.frame = CGRect(x: center - BrightnessBubble.width / 2, y: -BrightnessBubble.lift - BrightnessBubble.height / 2,
                              width: BrightnessBubble.width, height: BrightnessBubble.height)
        if isDragging, !UKDesign.reduceMotion { tile.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) }
    }
}

/// The "30%" bubble that floats over the band's edge while dragging: a fixed dark capsule with white text in every appearance (like
/// the system's volume HUD). VoiceOver hears the tile's value instead.
@MainActor
final class UKBrightnessBubbleView: UIView {
    private let label = UILabel()

    var percent: Int = 0 { didSet { label.text = "\(percent)%" } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        backgroundColor = .ukRGB(HassTokens.Palette.sheetCell)
        layer.cornerRadius = BrightnessBubble.height / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        label.textColor = .white
        label.textAlignment = .center
        // At most xxLarge: the bubble is a fixed size.
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            let capped = traitCollection.preferredContentSizeCategory > .extraExtraLarge
                ? UITraitCollection(preferredContentSizeCategory: .extraExtraLarge) : traitCollection
            label.font = UKFont.rowTitle(capped, monospacedDigit: true)
        }
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}
#endif
