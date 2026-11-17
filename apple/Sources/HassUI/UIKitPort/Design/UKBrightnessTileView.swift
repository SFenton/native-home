#if os(iOS)
import HassDesign
import UIKit

/// A dimmable light tile (`BrightnessTile`, pattern: `.agents/patterns/entity-tile.md`) in UIKit, the light dragger of direction G.
///
/// A ``UKGlassTileView`` with the drag laid over its body (the SwiftUI tile's `tileBodyOverlay`, `tileAdjustable`), so discs, chevron,
/// widths and states are the pattern's (`.agents/patterns/action-tiles.md`): an **action tile** (*text, disc*) whose body flips power
/// and whose horizontal drag sets brightness, or, when ``onOpen`` is set, a **navigation tile** with the same `power` disc left of its
/// chevron. The warm lit tile's bright band is the brightness. A tile that swipes (``swipe``) lets a horizontal drag set brightness from where
/// the finger is across the body, through ``UKTileSwipeController`` (the lift, the "30%" bubble, a selection tick at each detent, one call on
/// release); a tile without a swipe has no pan, no adjustable trait and no adjust hint (`sh.tile-swipe@1`, off by default on a light group
/// tile). VoiceOver activates the tap and, when the tile swipes, swipes up or down to step brightness by one detent; the disc is its own
/// button when the body opens details. The tile reads as a button speaking its percentage, never a switch.
///
/// Pure UI: callers pass the live percent and receive intents; they send the service calls.
@MainActor
final class UKBrightnessTileView: UIView, UKGridMeasuring {
    // MARK: Inputs

    private(set) var title: String
    private(set) var symbol: String
    private(set) var tint: UIColor
    private(set) var fillTint: UIColor?
    private(set) var percent: Int
    private(set) var isUnavailable: Bool
    private var isFailed = false
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
    private var interaction = BrightnessInteraction()
    private var pendingTask: Task<Void, Never>?
    private var isDragging: Bool { swipeController?.isDragging == true }
    /// A publication must not replace a drag or its local brightness feedback.
    var hasActiveInteraction: Bool { isDragging || interaction.pendingPercent != nil }
    private var swipeController: UKTileSwipeController?
    /// The swipe this tile takes. Today's callers (a room's lights, a custom light sheet, the gallery) swipe brightness by tens; a light group
    /// tile passes what its document authored, which is nil, and so no swipe, when `swipe` is absent (`sh.tile-swipe@1`).
    var swipe: UKTileSwipeConfig? = .brightness { didSet { if swipe != oldValue { installSwipe() } } }
    /// The words the state line says (`sh.state-words@1`).
    var words = UKLightWords() { didSet { if words != oldValue { refresh() } } }

    /// Every state line the tile can show, so the grid sizes it for the longest and a live change never re-spans it.
    private var stateCandidates: [String] { words.candidates + ["Didn't Respond"] }

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
        tile.action = { [weak self] in self?.handleTap() }
        tile.onPerform = { [weak self] _ in self?.flip() }
        installSwipe()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { MainActor.assumeIsolated { pendingTask?.cancel() } }

    // MARK: Update

    /// Shows the live state. Any live report replaces the optimistic value (web `useOptimisticState`).
    func update(title: String? = nil, symbol: String? = nil, tint: UIColor? = nil, fillTint: UIColor?, percent: Int, isUnavailable: Bool,
                isFailed: Bool = false) {
        if let title { self.title = title }
        if let symbol { self.symbol = symbol }
        if let tint { self.tint = tint }
        self.fillTint = fillTint
        if percent != self.percent { interaction.pendingPercent = nil }
        self.percent = percent
        self.isUnavailable = isUnavailable
        self.isFailed = isFailed
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
        let status = words.status(percent: shown, isUnavailable: isUnavailable)
        var model = UKGlassTileModel(
            title: title, subtitle: isFailed ? "Didn't Respond" : status, symbol: symbol, tint: tint, family: .lights, isActive: shown > 0 && !isUnavailable,
            isUnavailable: isUnavailable, isError: isFailed, behavior: onOpen == nil ? .perform(BrightnessTile.powerId) : .navigate,
            actions: items(shown: shown), progress: isUnavailable || swipe?.showsBand == false ? nil : Double(shown) / 100, progressTint: fillTint,
            identifier: identifier)
        model.stateCandidates = stateCandidates
        // A button speaking its percentage and adjustable, never a switch (the power disc carries the on/off state).
        model.useCommandSemantics()
        model.bodyHint = BrightnessTile.hint(percent: shown, isUnavailable: isUnavailable, opensDetails: onOpen != nil, adjusts: false)
        tile.onAdjust = isUnavailable || swipeController == nil ? nil : { [weak self] up in self?.swipeController?.step(up: up) }
        let configure = { [self] in tile.configure(model, environment: environment, animated: true) }
        // A drag holds its tile: the latest model waits for the finger to lift (C8).
        if swipeController?.hold(configure) != true { configure() }
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

    /// The swipe's one call: set brightness to `value`.
    fileprivate func commit(_ value: Double) {
        let shown = interaction.shown(live: percent)
        send(interaction.adjust(by: Int(value.rounded()) - shown, live: percent, isUnavailable: isUnavailable))
    }

    /// Replaces the swipe controller for the current ``swipe``.
    private func installSwipe() {
        swipeController?.detach()
        swipeController = nil
        tile.swipe = nil
        guard let swipe else { refresh(); return }
        let controller = UKTileSwipeController(host: tile, config: swipe)
        controller.shownValue = { [weak self] in self.map { Double($0.interaction.shown(live: $0.percent)) } ?? 0 }
        controller.isEnabled = { [weak self] in self.map { !$0.isUnavailable } ?? false }
        controller.onCommit = { [weak self] in self?.commit($0) }
        controller.onFrame = { [weak self] value in
            guard let self else { return }
            guard let value else { tile.showSwipeFrame(level: nil); return }
            // The drag shows the light's own words and lit face as it passes zero, with no `configure`.
            let drag = Int(value.rounded())
            tile.showSwipeFrame(level: value / 100, subtitle: words.status(percent: drag, isUnavailable: false), isActive: drag > 0,
                                usesBand: swipe.showsBand)
        }
        swipeController = controller
        tile.swipe = controller
        refresh()
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

    // MARK: Layout

    var gridMinimumWidth: CGFloat { tile.gridMinimumWidth }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile.gridHeight(forWidth: width) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { tile.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isDragging { tile.transform = .identity }
        // Bounds and centre, not `frame`: a lifted tile (the swipe's 1.03 scale) would take a smaller `bounds` from a frame set under its transform.
        tile.bounds = CGRect(origin: .zero, size: bounds.size)
        tile.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

#endif
