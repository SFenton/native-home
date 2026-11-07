#if os(iOS)
import HassDesign
import HassTelemetry
import UIKit

/// The inputs of `GlassTile`.
struct UKGlassTileModel {
    var title: String
    var subtitle: String?
    var symbol: String
    /// The glyph and rim colour of a tinted face; nil takes the family's glyph colour.
    var tint: UIColor?
    var family: ColorFamily?
    /// A solid fill the caller owns (a room's colour): white ink and a filled glyph on it, on or off.
    var fillRGB: UInt32?
    var isActive: Bool
    var isUnavailable = false
    /// The error face: a red glyph and red state on a dense ground.
    var isError = false
    /// Toggles get toggle semantics; navigation gets a chevron; read-only tiles are not buttons. A tile built with a ``behavior`` carries
    /// the equivalent kind.
    var kind: GlassTileKind = .toggle
    /// What the body tap does (`TileBehavior`): a `kind:` tile maps to it (toggle, command and selection perform, navigate navigates,
    /// state is inert).
    var behavior: TileBehavior
    /// The tile's action discs (`TileActionItem`).
    var actions: [TileActionItem] = []
    /// Every state line the tile can show (a provider's `stateTextCandidates`), so its minimum width comes from the longest and a live
    /// update never changes it (`tileStateCandidates(_:)`).
    var stateCandidates: [String] = []
    /// Whether the custom accessory (a volume slider) is shown now (`tileAccessoryShown(_:)`).
    var accessoryShown = true
    /// A state wash drawn under the material.
    var wash: UIColor?
    /// 0...1 progress fill from the leading edge, or nil.
    var progress: Double?
    var progressTint: UIColor?
    /// The accessibility identifier of the tile's own control (`tileIdentifier(_:)`).
    var identifier: String?
    /// VoiceOver's value when the subtitle alone is not what to speak (`tileAccessibilityValue(_:)`).
    var spokenValue: String?
    /// VoiceOver's label when the title alone is not what to speak (`tileAccessibilityLabel(_:)`; a room tile adds its cleaning order).
    var spokenLabel: String?
    /// The hint on the body control only (`tileHint(_:)`): a navigation tile with a disc says "Opens <title>" here, never on the disc.
    var bodyHint: String?
    /// Whether the tile announces its own error face (`tileAnnouncesFailure(_:)`).
    var announcesFailure = true
    /// `EntityStore.reapplyGeneration`, read inside the observation: a change of action set in the moments after the whole state is handed
    /// back (a reconnect, a cold launch from the snapshot) applies without motion.
    var reapplyGeneration: Int?

    init(title: String, subtitle: String? = nil, symbol: String, tint: UIColor? = nil, family: ColorFamily? = nil, fillRGB: UInt32? = nil,
         isActive: Bool, isUnavailable: Bool = false, isError: Bool = false, kind: GlassTileKind = .toggle, wash: UIColor? = nil,
         progress: Double? = nil, progressTint: UIColor? = nil, identifier: String? = nil, spokenValue: String? = nil,
         announcesFailure: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.family = family
        self.fillRGB = fillRGB
        self.isActive = isActive
        self.isUnavailable = isUnavailable
        self.isError = isError
        self.kind = kind
        switch kind {
        case .toggle, .command, .selection: behavior = .perform("")
        case .navigate: behavior = .navigate
        case .state: behavior = .inert
        }
        self.wash = wash
        self.progress = progress
        self.progressTint = progressTint
        self.identifier = identifier
        self.spokenValue = spokenValue
        self.announcesFailure = announcesFailure
    }

    /// A tile whose controls are action items (`GlassTile(…, behavior:, actions:, perform:)`, pattern: `.agents/patterns/action-tiles.md`).
    init(title: String, subtitle: String? = nil, symbol: String, tint: UIColor? = nil, family: ColorFamily? = nil, fillRGB: UInt32? = nil,
         isActive: Bool, isUnavailable: Bool = false, isError: Bool = false, behavior: TileBehavior, actions: [TileActionItem] = [],
         wash: UIColor? = nil, progress: Double? = nil, progressTint: UIColor? = nil, identifier: String? = nil, spokenValue: String? = nil,
         announcesFailure: Bool = true) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint, family: family, fillRGB: fillRGB, isActive: isActive,
                  isUnavailable: isUnavailable, isError: isError, kind: .command, wash: wash, progress: progress, progressTint: progressTint,
                  identifier: identifier, spokenValue: spokenValue, announcesFailure: announcesFailure)
        self.behavior = behavior
        self.actions = actions
        switch behavior {
        case let .perform(id):
            let primary = actions.first { $0.id == id }
            if let selection = primary?.selection {
                // The selection face: the tile fills when chosen, and VoiceOver reads "selected", never "switch".
                kind = .selection(isSelected: selection.isSelected)
                self.isActive = selection.isSelected
            } else {
                kind = primary?.isOn != nil ? .toggle : .command
            }
        case .navigate: kind = .navigate
        case .inert: kind = .state
        }
    }

    /// A read-only tile: flat, not a button.
    var isInert: Bool { behavior == .inert }
    /// The tile has action discs of its own.
    var usesItems: Bool { !actions.isEmpty }

    /// Gives a tile whose body flips an action's state command semantics: a button that speaks its value, not a switch
    /// (`tileCommandSemantics()`: a dimmable light reads "40%", not "on").
    mutating func useCommandSemantics() { if kind == .toggle { kind = .command } }

    /// The face's content with the accessory's room reserved.
    func faceContent(trailingInset: CGFloat, bottomInset: CGFloat, hidesGlyph: Bool = false, textFit: TileTextFit = .natural) -> UKTileFaceContent {
        UKTileFaceContent(
            title: title, subtitle: subtitle, symbol: symbol, tint: tint, family: family, fillRGB: fillRGB, isActive: isActive,
            isUnavailable: isUnavailable && !isInert, isError: isError, showsChevron: behavior == .navigate, level: progress,
            levelTint: progressTint, wash: wash, trailingInset: trailingInset, bottomInset: bottomInset, hidesGlyph: hidesGlyph, isFlat: isInert,
            textFit: textFit, probeIdentifier: identifier)
    }

    /// What VoiceOver reads for the value (`GlassTile.accessibilityValue`).
    func accessibilityValue(valuesPending: Bool) -> String {
        // The first sign-in, before any value has arrived: the soft bar says nothing, so the tile does.
        if valuesPending, subtitle != nil || kind == .toggle { return "Loading" }
        if let spokenValue { return spokenValue }
        if isUnavailable { return "Unavailable" }
        if isError { return subtitle ?? "Error" }
        // A tile built from action items speaks its state line; the toggle semantics live on the discs.
        if kind == .toggle { return usesItems ? (subtitle ?? (isActive ? "On" : "Off")) : (isActive ? "On" : "Off") }
        return subtitle ?? ""
    }

    /// The state line as its own text element reads: a line break (two-line tiles) reads as a pause, and the audit finds no raw break in a label.
    var spokenSubtitle: String? {
        subtitle?.split(whereSeparator: \.isNewline).joined(separator: ", ")
    }
}

/// The shared entity tile (`GlassTile`, pattern: `.agents/patterns/entity-tile.md`) in UIKit.
///
/// Pure UI: callers pass a model and an action, never a store. Bind it to an entity by reading the ``EntityBox`` inside a
/// ``UKObservationBag`` and calling ``configure(_:environment:animated:action:perform:)`` with the result:
///
/// ```swift
/// bag.observe { [weak tile] in
///     let light = store.entity("light.kitchen")
///     tile?.configure(UKGlassTileModel(title: "Kitchen", subtitle: light.isActive ? "On" : "Off", symbol: "lightbulb",
///                                      family: .lights, isActive: light.isActive), action: { toggle() })
/// }
/// ```
///
/// Two ways to give a tile controls of its own, both outside the tile's own control so a tap on a disc never also taps the body:
///
/// - **Action items** (`TileActionItem`, ``UKTileActionStrip``): the one 44 pt disc, placed by `TileActionPlacement`. Up to two trail,
///   vertically centred and clear of the chevron; three or more, accessibility text sizes and a custom accessory go below the text. A body
///   that performs an action carries the state glyph on its first disc and draws no leading glyph of its own. Their room is declared from
///   content, never measured by laying out.
/// - **A custom accessory** (``setAccessory(_:)``, a view): the legacy rail, measured, vertically centred on the trailing edge, or below the
///   text at accessibility sizes. With items it is the volume slider under the discs.
///
/// A tile with items or state candidates declares its minimum width (``gridMinimumWidth``, `TileMinimumWidth`) and is drawn for the room the
/// grid gave it: one line when it fits, else a ticker with the discs still trailing down to the 96 pt text floor, else a ticker with the strip
/// below (the three `ViewThatFits` variants of `GlassTile`). A read-only tile (`TileBehavior.inert`) is flat: no sheen, rim, chevron or press.
@MainActor
final class UKGlassTileView: UIControl, UKGridMeasuring {
    // MARK: State

    private(set) var model: UKGlassTileModel
    private(set) var environment = UKTileEnvironment()
    /// Runs when the tile's body is tapped (after the tap haptic).
    var action: (() -> Void)?
    /// Runs with the item's id for a disc tap, or a body tap that performs that action, once any confirmation was answered.
    var onPerform: ((TileActionItem.ID) -> Void)?
    /// VoiceOver's swipe up (`true`) and down on the body (`tileAdjustable(_:)`): a light's brightness steps. Nil: the tile is not adjustable.
    var onAdjust: ((Bool) -> Void)?
    /// The face, for views that wrap a tile.
    let face: UKGlassTileFaceView
    private(set) var accessory: UIView?
    /// The grid resolved this tile to a whole row (`tileSpansFullRow`, computed from the grid by ``UKDynamicGridView``). Gates animation only.
    var gridFullRow = false
    /// Tells the tile it spans its row (a section's lead tile); the grid's own computation is the other way.
    var spansFullRow = false
    private var hasConfigured = false
    private var bodyElement: UKTileAccessibilityElement?
    /// The state line as a static text beside the body, so a text query finds it as it finds SwiftUI's.
    private var subtitleElement: UIAccessibilityElement?
    private let strip = UKTileActionStrip()
    private var stripConfiguredFor: [TileActionItem]?
    private var motion = ActionSetMotion()

    /// The tile's state while its action set changes shape. Local to the tile and written only by a change of shape.
    private struct ActionSetMotion {
        /// The old controls, still drawn while they fade out or while scrolling holds the change back.
        var held: (actions: [TileActionItem], hasAccessory: Bool)?
        var isDeferred = false
        var discOpacity: CGFloat = 1
        var epoch = 0
        var seenGeneration: Int?
        var reappliedAt: ContinuousClock.Instant?
        var scrollToken: NSObjectProtocol?
        var outgoing: UIView?
    }

    // MARK: Init

    init(model: UKGlassTileModel, environment: UKTileEnvironment = UKTileEnvironment(), action: (() -> Void)? = nil) {
        self.model = model
        self.environment = environment
        self.action = action
        face = UKGlassTileFaceView(content: model.faceContent(trailingInset: 0, bottomInset: 0))
        super.init(frame: .zero)
        face.isUserInteractionEnabled = false
        addSubview(face)
        addSubview(strip)
        strip.isHidden = true
        strip.onPerform = { [weak self] id in self?.request(id) }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKGlassTileView, _) in
            view.setNeedsLayout()
            view.apply(animated: false)
            view.ukHeightMayHaveChanged()
        }
        motion.seenGeneration = model.reapplyGeneration
        apply(animated: false)
        hasConfigured = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Configure

    /// Shows `model`. State changes cross-fade; a tile that turns to its error face plays the error haptic and announces it once. A change of
    /// the controls' shape (`TileActionSetTransition`) animates the tile's height when it spans its row.
    /// - Parameter animated: False for a reused cell taking another tile's state, which must not cross-fade.
    func configure(_ model: UKGlassTileModel, environment: UKTileEnvironment? = nil, animated: Bool = true, action: (() -> Void)? = nil,
                   perform: ((TileActionItem.ID) -> Void)? = nil) {
        let old = self.model
        let oldShape = TileActionShape(motion.held?.actions ?? old.actions, hasAccessory: motion.held?.hasAccessory ?? hasAccessory(for: old))
        self.model = model
        if let environment { self.environment = environment }
        if let action { self.action = action }
        if let perform { self.onPerform = perform }
        // The reapply first, so a change that arrives with it reads it.
        if let generation = model.reapplyGeneration, generation != motion.seenGeneration {
            if motion.seenGeneration != nil { motion.reappliedAt = .now }
            motion.seenGeneration = generation
        }
        let newShape = TileActionShape(model.actions, hasAccessory: hasAccessory(for: model))
        if oldShape != newShape {
            if hasConfigured, animated {
                actionSetChanged(from: motion.held ?? (actions: old.actions, hasAccessory: hasAccessory(for: old)), shape: oldShape, to: newShape)
            } else {
                endActionSetChange()
            }
        }
        apply(animated: hasConfigured && animated)
        // A change of shape that did not animate moved the tile's height at once: the grids around it measure again.
        if oldShape != newShape, hasConfigured, motion.held == nil, motion.outgoing == nil, !motionIsPlaying { ukHeightMayHaveChanged() }
        if hasConfigured, animated, model.isError, !old.isError {
            UKTapFeedback.failure()
            if model.announcesFailure { announceFailure([model.title, model.subtitle].compactMap { $0 }.joined(separator: ", ")) }
        }
    }

    /// Sets the custom accessory (nil removes it): the legacy rail, or the volume slider under the discs. Its controls are their own
    /// accessibility elements beside the tile.
    func setAccessory(_ view: UIView?) {
        accessory?.removeFromSuperview()
        accessory = view
        if let view { addSubview(view) }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        apply(animated: false)
    }

    private func hasAccessory(for model: UKGlassTileModel) -> Bool { accessory != nil && model.accessoryShown }

    /// A change of shape is animating (or held for scrolling): the animation relays out the grids itself.
    private var motionIsPlaying: Bool { motion.discOpacity != 1 || motion.isDeferred }

    // MARK: Resolved placement

    private enum Fit: Equatable { case natural, tickerTrailing, tickerBelow }

    /// A tile that declares its minimum width is sized from its content: it has controls of its own, or a provider told it the states it
    /// can show. Other tiles keep wrapping text and take the span they were given.
    private var isContentAware: Bool { model.usesItems || !model.stateCandidates.isEmpty }

    /// The controls the layout uses now: the old ones while a change of shape is still playing out.
    private var shownActions: [TileActionItem] { motion.held?.actions ?? model.actions }
    private var hasAccessory: Bool { motion.held?.hasAccessory ?? hasAccessory(for: model) }
    private var usesItems: Bool { !shownActions.isEmpty }
    private var isInert: Bool { model.isInert }
    private var accessibilitySize: Bool { traitCollection.ukIsAccessibilitySize }
    private var discIsHidden: Bool { TileActionPlacement.discIsAccessibilityHidden(behavior: model.behavior, items: shownActions) }

    private func slot(fit: Fit) -> TileActionSlot {
        let slot = TileActionPlacement.slot(count: shownActions.count, behavior: model.behavior, accessibilitySize: accessibilitySize,
                                            fitsTrailing: fit != .tickerBelow)
        return slot == .trailing && hasAccessory ? .below : slot
    }

    private var diameter: CGFloat { UKTileActionDisc.diameter(traits: traitCollection) }

    /// The least width of a tile that shows its text on one line beside its controls (`TileMinimumWidth`), 0 for a tile that declared none.
    /// It assumes the discs trail whenever the count and text size allow, so it never depends on the width it helps decide.
    var gridMinimumWidth: CGFloat { isContentAware ? width(textFloorOnly: false) : 0 }

    private var floorWidth: CGFloat { width(textFloorOnly: true) }

    private func width(textFloorOnly: Bool) -> CGFloat {
        let slot = slot(fit: .natural)
        let layout = environment.layout.resolved(accessibilitySize: accessibilitySize)
        let carries = TileActionPlacement.carriesGlyph(behavior: model.behavior, slot: slot)
        let glyphColumn = layout == .row && !carries ? GlassTileFace.rowGlyphWidth + HassTokens.Spacing.m : 0
        let strip = slot == .trailing ? TileActionButtonStyle.stripWidth(count: shownActions.count, diameter: diameter) + HassTokens.Spacing.s : 0
        let chevron = model.behavior == .navigate ? GlassTileFace.chevronReserve : 0
        if textFloorOnly { return TileMinimumWidth.width(text: TileMinimumWidth.textFloor, glyphColumn: glyphColumn, chevron: chevron, strip: strip) }
        let titleWidth = UKTileTextMeasure.width(model.title, state: false, traits: traitCollection)
        let states = model.stateCandidates.isEmpty ? [model.subtitle].compactMap { $0 } : model.stateCandidates
        let stateWidth = states.map { UKTileTextMeasure.width($0, state: true, traits: traitCollection) }.max() ?? 0
        return TileMinimumWidth.width(text: max(titleWidth, stateWidth), glyphColumn: glyphColumn, chevron: chevron, strip: strip)
    }

    /// How the tile is drawn for the room it was given, in the order `ViewThatFits` tries them.
    private func fit(forWidth available: CGFloat) -> Fit {
        guard isContentAware else { return .natural }
        if available + 0.5 >= gridMinimumWidth { return .natural }
        if available + 0.5 >= floorWidth { return .tickerTrailing }
        return .tickerBelow
    }

    private struct Placement {
        var fit: Fit
        var slot: TileActionSlot
        var trailingInset: CGFloat = 0
        var bottomInset: CGFloat = 0
        var accessorySize: CGSize = .zero
        var hidesGlyph = false
        var textFit: TileTextFit = .natural
    }

    private func accessorySize(width: CGFloat) -> CGSize {
        guard let accessory, hasAccessory else { return .zero }
        if accessory is UKTileVolumeSlider { return accessory.sizeThatFits(CGSize(width: max(0, width - 2 * HassTokens.Spacing.m), height: 0)) }
        return accessory.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    private func placement(width: CGFloat) -> Placement {
        let fit = fit(forWidth: width)
        var placement = Placement(fit: fit, slot: slot(fit: fit))
        placement.textFit = !isContentAware ? .natural : (fit == .natural ? .oneLine : .ticker)
        placement.hidesGlyph = TileActionPlacement.carriesGlyph(behavior: model.behavior, slot: placement.slot)
        placement.accessorySize = accessorySize(width: width)
        let s = HassTokens.Spacing.s
        if usesItems {
            switch placement.slot {
            case .trailing:
                placement.trailingInset = TileActionButtonStyle.stripWidth(count: shownActions.count, diameter: diameter) + s
            case .below:
                let accessoryHeight = hasAccessory && placement.accessorySize.height > 0 ? placement.accessorySize.height + s : 0
                placement.bottomInset = diameter + accessoryHeight + s
            case .none: break
            }
        } else if accessory != nil, hasAccessory {
            // The legacy rail.
            let size = placement.accessorySize
            placement.trailingInset = accessibilitySize || size.width == 0 ? 0 : size.width + s
            placement.bottomInset = accessibilitySize && size.height > 0 ? size.height + s : 0
        }
        return placement
    }

    private var layoutWidth: CGFloat { bounds.width > 0 ? bounds.width : 170 }

    private func faceContent(_ placement: Placement) -> UKTileFaceContent {
        model.faceContent(trailingInset: placement.trailingInset, bottomInset: placement.bottomInset, hidesGlyph: placement.hidesGlyph,
                          textFit: placement.textFit)
    }

    /// The ground the discs sit on, from the same face the tile draws.
    private var actionFace: TileActionFace {
        switch TileFaceStyle.resolve(family: model.family, isActive: model.isActive, isError: model.isError,
                                     isUnavailable: model.isUnavailable && !isInert, solidFill: model.fillRGB) {
        case .lit: .lit
        case .filled, .colored: .filled
        case .off, .tinted, .error: .dark
        }
    }

    /// Whether a body that performs an action is waiting on Home Assistant or cannot run: the body is disabled with its disc. A navigation
    /// body stays enabled while one of its discs is in flight, so the sheet still opens.
    private var bodyBlocked: Bool {
        guard case let .perform(id) = model.behavior else { return false }
        if shownActions.contains(where: { $0.phase == .inFlight }) { return true }
        return shownActions.first(where: { $0.id == id }).map { $0.phase != .ready } ?? false
    }

    private func apply(animated: Bool) {
        // A state tile is not a button: never dimmed as disabled.
        isEnabled = isInert ? true : !(model.isUnavailable || bodyBlocked)
        face.isEnabled = isEnabled
        let placement = placement(width: layoutWidth)
        let content = faceContent(placement)
        face.apply(content, environment: environment, animated: animated)
        configureStrip(animated: animated)
        configureAccessibility()
        setNeedsLayout()
    }

    private func configureStrip(animated: Bool) {
        let items = shownActions
        strip.isHidden = items.isEmpty
        guard !items.isEmpty else {
            if stripConfiguredFor != nil { strip.configure(items: [], title: model.title, tileIdentifier: model.identifier, face: actionFace, family: model.family,
                                                           surface: environment.surface, animated: false) }
            stripConfiguredFor = nil
            return
        }
        strip.configure(items: items, title: model.title, tileIdentifier: model.identifier, face: actionFace, family: model.family,
                        surface: environment.surface, animated: animated)
        stripConfiguredFor = items
    }

    // MARK: Press feedback

    /// Presses like a plain button but never fades the label when disabled: a locked tile still carries its state, so its text must
    /// keep 4.5:1 (`GlassTileButtonStyle`).
    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { face.alpha = isHighlighted ? HassTokens.ControlState.pressedOpacity : 1 } }
    }

    @objc private func tapped() {
        if model.kind.playsTapFeedback { UKTapFeedback.tap() }
        // A body that performs an action runs the item it names (the primary of the set); the others open or run the tile's own action.
        if case let .perform(id) = model.behavior, model.usesItems {
            // The body's action goes through the same question as its disc.
            if TileActionConfirmation.required(forPerforming: id, in: shownActions) != nil { request(id) } else { onPerform?(id) }
        } else {
            action?()
        }
    }

    // MARK: Confirmation

    /// An action waiting on its question: the action as it was when asked about, so the answer applies to that and nothing else.
    private struct ConfirmationRequest {
        var item: TileActionItem
        var confirmation: TileActionConfirmation
    }

    /// A disc tap (or a body tap that performs the same action): asks first when the action carries a confirmation, else performs
    /// (`GlassTile.request(_:)`).
    private func request(_ id: TileActionItem.ID) {
        guard let item = shownActions.first(where: { $0.id == id }), let confirmation = TileActionConfirmation.required(forPerforming: id, in: shownActions),
              let presenter = ukOwningViewController
        else { onPerform?(id); return }
        let ask = ConfirmationRequest(item: item, confirmation: confirmation)
        let alert = UIAlertController(title: confirmation.title, message: confirmation.message,
                                      preferredStyle: confirmation.style == .dialog ? .actionSheet : .alert)
        let confirmIdentifier = TileActionConfirmation.confirmIdentifier(model.identifier)
        let cancelIdentifier = TileActionConfirmation.cancelIdentifier(model.identifier)
        let confirm = UIAlertAction(title: confirmation.confirmVerb, style: confirmation.isDestructive ? .destructive : .default) { [weak self] _ in
            self?.confirmed(ask)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(confirm)
        // A plain confirming button is the bold default; a destructive one never is (`.agents/patterns/alerts.md`).
        if !confirmation.isDestructive { alert.preferredAction = confirm }
        if confirmation.style == .dialog, let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = bounds
        }
        presenter.ukPresent(alert, identifiers: [confirmation.confirmVerb: confirmIdentifier, "Cancel": cancelIdentifier])
    }

    /// The person confirmed: runs the action only if it is still the one that was asked about. The state under the question can move
    /// before the answer (a panel disarmed elsewhere, a bed turned off): a changed action is dropped, never run in place of the old
    /// (`TileActionConfirmation.holds(for:in:)`).
    private func confirmed(_ ask: ConfirmationRequest) {
        guard let now = shownActions.first(where: { $0.id == ask.item.id }), now.isOn == ask.item.isOn, now.verb == ask.item.verb,
              TileActionConfirmation.required(forPerforming: ask.item.id, in: shownActions) == ask.confirmation
        else { return }
        onPerform?(ask.item.id)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The controls first: a tap on a disc never also taps the body.
        if motion.discOpacity == 1 {
            for view in [strip, accessory].compactMap({ $0 }) where !view.isHidden && view.frame.contains(point) {
                if let hit = view.hitTest(convert(point, to: view), with: event) { return hit }
            }
        }
        // A read-only tile is not a button: touches pass through it.
        if isInert { return nil }
        return super.hitTest(point, with: event)
    }

    // MARK: Layout

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : layoutWidth
        let placement = placement(width: width)
        let content = faceContent(placement)
        if face.content != content { face.apply(content, environment: environment, animated: false) }
        return face.sizeThatFits(CGSize(width: width, height: size.height))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: gridHeight(forWidth: layoutWidth)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let placement = placement(width: bounds.width)
        let content = faceContent(placement)
        if face.content != content { face.apply(content, environment: environment, animated: false) }
        face.frame = bounds
        let pad = HassTokens.Spacing.m
        let s = HassTokens.Spacing.s
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ rect: CGRect) {
            view.frame = mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        strip.alpha = motion.discOpacity
        accessory?.alpha = motion.discOpacity
        accessory?.isHidden = !hasAccessory
        var controls = CGRect.null
        if usesItems {
            let stripSize = strip.sizeThatFits(.zero)
            if placement.slot == .below {
                var bottom = bounds.height - pad
                if let accessory, hasAccessory {
                    let frame = CGRect(x: pad, y: bottom - placement.accessorySize.height, width: bounds.width - 2 * pad, height: placement.accessorySize.height)
                    accessory.isHidden = false
                    place(accessory, frame)
                    controls = controls.union(accessory.frame)
                    bottom = frame.minY - s
                }
                // Centred under the text.
                strip.frame = CGRect(x: (bounds.width - stripSize.width) / 2, y: bottom - stripSize.height, width: stripSize.width, height: stripSize.height)
            } else {
                accessory?.isHidden = true
                let reserve = pad + (model.behavior == .navigate ? GlassTileFace.chevronReserve : 0)
                place(strip, CGRect(x: bounds.width - reserve - stripSize.width, y: (bounds.height - stripSize.height) / 2,
                                    width: stripSize.width, height: stripSize.height))
            }
            controls = controls.union(strip.frame)
        } else if let accessory {
            accessory.isHidden = !hasAccessory
            let size = placement.accessorySize
            if hasAccessory {
                let x: CGFloat, y: CGFloat
                if accessibilitySize {
                    x = pad
                    y = bounds.height - pad - size.height
                } else {
                    let reserve = pad + (model.behavior == .navigate ? GlassTileFace.chevronReserve : 0)
                    x = bounds.width - reserve - size.width
                    y = (bounds.height - size.height) / 2
                }
                place(accessory, CGRect(x: x, y: y, width: size.width, height: size.height))
                controls = accessory.frame
            }
        }
        // The face lays its text out after this pass; the subtitle element is framed from where the text is, so lay it out first (a state line
        // that arrived after the first pass was otherwise exposed with an empty frame and the audit read its text as inaccessible).
        face.layoutIfNeeded()
        layoutAccessibilityFrames(controls: controls, below: placement.slot == .below || (!usesItems && accessibilitySize))
    }

    /// The tile's own element covers what the controls do not, so the controls stay hittable.
    private func layoutAccessibilityFrames(controls: CGRect, below: Bool) {
        subtitleElement?.accessibilityFrameInContainerSpace = face.subtitleFrame
        guard let bodyElement else { return }
        // The tile's own element covers what the controls do not, so the controls stay hittable.
        if controls.isNull {
            bodyElement.accessibilityFrameInContainerSpace = bounds
        } else if below {
            bodyElement.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, controls.minY))
        } else if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            bodyElement.accessibilityFrameInContainerSpace = CGRect(x: controls.maxX, y: 0, width: max(0, bounds.width - controls.maxX), height: bounds.height)
        } else {
            bodyElement.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: max(0, controls.minX), height: bounds.height)
        }
    }

    // MARK: Changing the action set

    private var pageIsScrolling: Bool { UKTickerScrollGate.nearest(above: self)?.isScrolling ?? false }

    /// Whether the whole state was just handed back (a reconnect, a cold launch from the snapshot).
    private var isReapplying: Bool {
        TileActionSetTransition.isReapply(elapsedSinceReapply: motion.reappliedAt.map { ContinuousClock.now - $0 })
    }

    private var isFullRow: Bool { spansFullRow || gridFullRow }

    /// The controls changed: ``TileActionSetTransition`` decides, this applies it.
    private func actionSetChanged(from: (actions: [TileActionItem], hasAccessory: Bool), shape: TileActionShape, to new: TileActionShape) {
        motion.epoch += 1
        motion.outgoing?.removeFromSuperview()
        motion.outgoing = nil
        let decision = TileActionSetTransition.decide(old: shape, new: new, isFullRow: isFullRow, isScrolling: pageIsScrolling,
                                                      isReapply: isReapplying, reduceMotion: UKDesign.reduceMotion)
        applyTransition(decision, from: from)
    }

    private func endActionSetChange() {
        motion.epoch += 1
        motion.held = nil
        motion.isDeferred = false
        motion.discOpacity = 1
        motion.outgoing?.removeFromSuperview()
        motion.outgoing = nil
        removeScrollObserver()
    }

    private func removeScrollObserver() {
        if let token = motion.scrollToken { NotificationCenter.default.removeObserver(token) }
        motion.scrollToken = nil
    }

    private func applyTransition(_ decision: TileActionSetTransition, from: (actions: [TileActionItem], hasAccessory: Bool)) {
        switch decision {
        case .none:
            endActionSetChange()
        case .deferred:
            motion.held = from
            motion.isDeferred = true
            motion.discOpacity = 1
            removeScrollObserver()
            motion.scrollToken = NotificationCenter.default.addObserver(forName: UKTickerScrollGate.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrollingMayHaveEnded() }
            }
        case .animate: play(from: from, reduced: false)
        case .crossFade: play(from: from, reduced: true)
        }
    }

    /// Scrolling stopped: decide the held change again.
    private func scrollingMayHaveEnded() {
        guard motion.isDeferred, !pageIsScrolling else { return }
        removeScrollObserver()
        guard let from = motion.held else { motion.isDeferred = false; return }
        let decision = TileActionSetTransition.decide(
            old: TileActionShape(from.actions, hasAccessory: from.hasAccessory), new: TileActionShape(model.actions, hasAccessory: hasAccessory(for: model)),
            isFullRow: isFullRow, isScrolling: false, isReapply: isReapplying, reduceMotion: UKDesign.reduceMotion)
        applyTransition(decision, from: from)
    }

    /// Relays out for the new controls, taking the grids around the tile with it.
    private func relayout() {
        apply(animated: false)
        ukHeightMayHaveChanged()
        window?.layoutIfNeeded()
    }

    /// The change: old discs fade out (`quick`), the height animates (`standard`), new discs fade in (`quick`). Reduce Motion swaps at once and
    /// cross-fades the new discs in over 0.2 s, with no height animation. One `LayoutChange` signpost spans it (`page: TileActionSet`) for
    /// `XCTOSSignpostMetric` (`tools/ios_motionperf.sh`).
    private func play(from: (actions: [TileActionItem], hasAccessory: Bool), reduced: Bool) {
        motion.held = from
        motion.isDeferred = false
        let epoch = motion.epoch
        let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "TileActionSet", reduced ? "reduced" : "animated")
        func finish() { NextFrame.perform { Telemetry.end(interval) } }
        func current() -> Bool { motion.epoch == epoch }
        if reduced {
            // One cross-fade: the new layout at once (no height animation), the old discs out and the new in together.
            let old = [strip, accessory].compactMap { $0 }.filter { !$0.isHidden }.compactMap { $0.snapshotView(afterScreenUpdates: false) }
            let holder = UIView(frame: bounds)
            holder.isUserInteractionEnabled = false
            holder.isAccessibilityElement = false
            for (snapshot, source) in zip(old, [strip, accessory].compactMap { $0 }.filter { !$0.isHidden }) { snapshot.frame = source.frame; holder.addSubview(snapshot) }
            addSubview(holder)
            motion.outgoing = holder
            motion.held = nil
            motion.discOpacity = 0
            relayout()
            UIView.animate(withDuration: MotionTokens.stateReducedDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { [self] in
                holder.alpha = 0
                motion.discOpacity = 1
                strip.alpha = 1
                accessory?.alpha = 1
            } completion: { [weak self] _ in
                guard let self, current() else { return }
                holder.removeFromSuperview()
                motion.outgoing = nil
                motion.discOpacity = 1
                setNeedsLayout()
                finish()
            }
            return
        }
        UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { [self] in
            motion.discOpacity = 0
            strip.alpha = 0
            accessory?.alpha = 0
        } completion: { [weak self] _ in
            guard let self, current() else { return }
            UIView.animate(withDuration: MotionTokens.standardDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { [self] in
                motion.held = nil
                relayout()
            } completion: { [weak self] _ in
                guard let self, current() else { return }
                UIView.animate(withDuration: MotionTokens.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { [self] in
                    motion.discOpacity = 1
                    strip.alpha = 1
                    accessory?.alpha = 1
                } completion: { _ in finish() }
            }
        }
    }

    // MARK: Accessibility

    /// Label and value go on the tile's own control (not the whole tile), so identifiers and disabled state do not split between
    /// elements. A tile with controls is a container of the tile element, each disc and the accessory.
    private var exposesSubtitle: Bool { !isInert && !environment.valuesPending && !(model.subtitle ?? "").isEmpty }
    private var exposesControls: Bool { (usesItems && !discIsHidden) || (accessory != nil && hasAccessory) || exposesSubtitle }

    private func configureAccessibility() {
        let value = model.accessibilityValue(valuesPending: environment.valuesPending)
        let traits = Self.traits(for: model, blocked: bodyBlocked)
        // A tile that is a container of elements leaves its own identity to them, so a query finds the body once.
        let single = !exposesControls
        accessibilityLabel = model.spokenLabel ?? model.title
        accessibilityValue = value
        // Only a single-element tile carries the identifier itself; a container would otherwise match a query before its button, so it
        // carries `<id>.tile` instead: tests read the tile's whole bounds from it. An identifier is not spoken and a container that is not
        // an element is no VoiceOver stop, so this changes nothing for people.
        accessibilityIdentifier = single ? model.identifier : model.identifier.map { $0 + ".tile" }
        accessibilityTraits = single ? traits.union(onAdjust == nil ? [] : .adjustable) : (traits.contains(.notEnabled) ? [.notEnabled] : [])
        accessibilityHint = spokenHint
        if exposesControls {
            let element = bodyElement ?? UKTileAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = model.spokenLabel ?? model.title
            element.accessibilityValue = value
            element.accessibilityIdentifier = model.identifier
            element.accessibilityTraits = onAdjust == nil ? traits : traits.union(.adjustable)
            element.accessibilityHint = accessibilityHint
            element.onAdjust = onAdjust
            element.activate = { [weak self] in
                guard let self, !isInert, isEnabled else { return false }
                tapped()
                return true
            }
            bodyElement = element
        } else {
            bodyElement = nil
        }
        if exposesSubtitle {
            let element = subtitleElement ?? UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = model.spokenSubtitle
            element.accessibilityTraits = .staticText
            subtitleElement = element
        } else {
            subtitleElement = nil
        }
    }

    /// The body's hint: the caller's, else for a tile whose one disc is hidden (it repeats the body) what a double-tap does, worded as that
    /// disc would be ("Cancel Hot Flash Mode"); nil otherwise.
    private var spokenHint: String? {
        if let hint = model.bodyHint, !hint.isEmpty { return hint }
        guard discIsHidden, let item = shownActions.first else { return nil }
        return item.label ?? "\(item.verb) \(model.title)"
    }

    private static func traits(for model: UKGlassTileModel, blocked: Bool) -> UIAccessibilityTraits {
        var traits: UIAccessibilityTraits = []
        switch model.kind {
        case .state: traits = [.staticText]
        case .toggle: traits = [.button, .toggleButton]
        case let .selection(isSelected): traits = isSelected ? [.button, .selected] : [.button]
        case .navigate, .command: traits = [.button]
        }
        if (model.isUnavailable || blocked), !model.isInert { traits.insert(.notEnabled) }
        return traits
    }

    override var isAccessibilityElement: Bool {
        get { !exposesControls }
        set {}
    }

    override var accessibilityElements: [Any]? {
        get {
            guard exposesControls, let bodyElement else { return nil }
            var elements: [Any] = [bodyElement]
            if let subtitleElement { elements.append(subtitleElement) }
            if usesItems, !discIsHidden { elements += strip.discs }
            if let accessory, hasAccessory {
                // An accessory that is a row of controls exposes each control.
                let controls = accessory.isAccessibilityElement ? [] : accessory.subviews.filter(\.isAccessibilityElement)
                elements += controls.isEmpty ? [accessory] : controls
            }
            return elements
        }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        guard !isInert, isEnabled else { return false }
        tapped()
        return true
    }

    override func accessibilityIncrement() { if isEnabled { onAdjust?(true) } }
    override func accessibilityDecrement() { if isEnabled { onAdjust?(false) } }
}

/// The tile's own element when it has controls beside it.
final class UKTileAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    var onAdjust: ((Bool) -> Void)?

    override func accessibilityActivate() -> Bool { activate?() ?? false }
    override func accessibilityIncrement() { onAdjust?(true) }
    override func accessibilityDecrement() { onAdjust?(false) }
}

// MARK: - Text measure

/// The natural single-line width of a tile's text, for the tile's declared minimum width (`TileTextMeasure`): measured with the font of the
/// tile's text style at the trait collection's Dynamic Type size, never by laying a view out. Cached by text, style and size.
@MainActor
enum UKTileTextMeasure {
    private struct Key: Hashable {
        var text: String
        var state: Bool
        var category: String
    }

    private static var cache: [Key: CGFloat] = [:]

    /// The width of `text` on one line, rounded up to a whole point; `state` is the footnote state line, else the bold subheadline title.
    static func width(_ text: String, state: Bool, traits: UITraitCollection) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = Key(text: text, state: state, category: traits.preferredContentSizeCategory.rawValue)
        if let width = cache[key] { return width }
        if cache.count > 4_000 { cache.removeAll(keepingCapacity: true) }
        let font = state ? UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits) : UKFont.tileTitle(traits)
        let width = ((text as NSString).size(withAttributes: [.font: font]).width).rounded(.up)
        cache[key] = width
        return width
    }
}
#endif
