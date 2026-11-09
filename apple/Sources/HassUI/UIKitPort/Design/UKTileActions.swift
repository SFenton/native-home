#if os(iOS)
import HassDesign
import UIKit

// MARK: - Disc

/// The one round action button of a tile (`TileActionButtonStyle` / `TileActionDisc`, pattern: `.agents/patterns/action-tiles.md`): a 44 pt
/// disc that scales with Dynamic Type up to 1.5x, with a glyph under 45% of its width. It draws the symbol itself so it can swap it for a
/// progress arc while an action is in flight; the symbol replaces itself when the item's state changes (lock to unlock).
///
/// The ink comes from ``TileActionInk`` (the same decision SwiftUI draws): a solid white disc with the family fill as the glyph when on, the
/// dark disc on the lit tile, black at 18% on a filled tile and white at 16% on a dark one. An unavailable item draws no fill and dims its
/// glyph. VoiceOver reads "verb title" ("Unlock Front Door"), a toggle-styled item carries the toggle trait and an On or Off value.
@MainActor
final class UKTileActionDisc: UIControl {
    private(set) var item: TileActionItem
    private var face: TileActionFace
    private var family: ColorFamily?
    private var surface: TileSurface
    private var tileTitle: String
    private let glyph = UIImageView()
    private let pressOverlay = UIView()
    private var spinner: UKArcSpinnerView?
    private var hasConfigured = false
    /// The selection face's disc (``TileSelection``): an empty ring, or a solid white disc with the order or a check, 28 pt inside the 44 pt
    /// target (`TileActionDisc.selectionDisc`).
    private var choiceLayer: UKChoiceDiscView?
    /// Replaces "verb title" as the spoken label (the brightness tile's "Turn Off Kitchen Lights").
    var spokenLabel: String? { didSet { accessibilityLabel = spokenLabel ?? defaultLabel } }
    /// "Unlock Front Door", or the item's own whole label ("Turn Off TV") (`TileActionDisc.label(for:title:)`).
    private var defaultLabel: String { item.label ?? "\(item.verb) \(tileTitle)" }

    init(item: TileActionItem, face: TileActionFace, family: ColorFamily?, surface: TileSurface, title: String, identifier: String?) {
        self.item = item
        self.face = face
        self.family = family
        self.surface = surface
        self.tileTitle = title
        super.init(frame: .zero)
        glyph.contentMode = .center
        glyph.isUserInteractionEnabled = false
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.isHidden = true
        layer.cornerCurve = .continuous
        addSubview(glyph)
        addSubview(pressOverlay)
        accessibilityIdentifier = identifier
        isAccessibilityElement = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) { (view: UKTileActionDisc, _) in
            view.restyle(animated: false, symbolTransition: false)
            view.invalidateIntrinsicContentSize()
            view.superview?.setNeedsLayout()
        }
        restyle(animated: false, symbolTransition: false)
        hasConfigured = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The disc's diameter: 44 pt at the default size, never more than 66.
    static func diameter(traits: UITraitCollection) -> CGFloat {
        TileActionButtonStyle.diameter(scaled: UKFont.scaled(HassTokens.minTarget, relativeTo: .body, traits: traits))
    }

    var diameter: CGFloat { Self.diameter(traits: traitCollection) }

    func configure(item: TileActionItem, face: TileActionFace, family: ColorFamily?, surface: TileSurface, title: String, identifier: String?,
                   animated: Bool) {
        let old = self.item
        self.item = item
        self.face = face
        self.family = family
        self.surface = surface
        self.tileTitle = title
        accessibilityIdentifier = identifier
        restyle(animated: animated && hasConfigured, symbolTransition: animated && hasConfigured && old.symbol != item.symbol)
    }

    private func restyle(animated: Bool, symbolTransition: Bool) {
        let item = item
        let ink = TileActionInk.resolveTokens(face: face, isOn: item.isOn == true || item.isEmphasized, family: family)
        let appearance = UKDesign.tileAppearance(surface: surface, traits: traitCollection)
        let glyphColor = item.isError ? UIColor.ukRGB(appearance.errorRGB) : UIColor(ink.glyph)
        let unavailable = item.phase == .unavailable
        let discColor = unavailable ? UIColor.clear : UIColor(ink.disc)

        let glyphSize = TileActionButtonStyle.glyphSize(scaled: UKFont.scaled(18, relativeTo: .body, traits: traitCollection), diameter: diameter)
        let image = UIImage(systemName: item.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold))
        if let selection = item.selection {
            restyleChoice(selection, glyphSize: glyphSize, animated: animated)
            return
        }
        choiceLayer?.isHidden = true
        glyph.isHidden = false
        if item.showsProgress {
            if spinner == nil {
                // A status arc tinted to the ink; the disc keeps its own label, so the arc says nothing.
                let arc = UKArcSpinnerView(.inline, label: "", maxScale: 1.5)
                arc.isAccessibilityElement = false
                insertSubview(arc, belowSubview: pressOverlay)
                spinner = arc
            }
            spinner?.color = glyphColor
            spinner?.isHidden = false
            glyph.isHidden = true
        } else {
            spinner?.isHidden = true
            glyph.isHidden = false
            if symbolTransition, !UKDesign.reduceMotion, let image {
                glyph.setSymbolImage(image, contentTransition: .replace)
            } else {
                glyph.image = image
            }
        }

        let work = { [self] in
            backgroundColor = discColor
            glyph.tintColor = glyphColor
            glyph.alpha = unavailable ? 0.5 : 1
            spinner?.alpha = unavailable ? 0.5 : 1
            pressOverlay.backgroundColor = glyphColor.withAlphaComponent(0.22)
        }
        if animated, window != nil, !UKDesign.reduceMotion {
            UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: work)
        } else {
            work()
        }

        isEnabled = item.phase == .ready
        accessibilityLabel = spokenLabel ?? defaultLabel
        accessibilityValue = item.isOn.map { $0 ? "On" : "Off" } ?? ""
        var traits: UIAccessibilityTraits = [.button]
        if item.isOn != nil { traits.insert(.toggleButton) }
        if !isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
        setNeedsLayout()
    }


    /// Draws the selection face's disc instead of the glyph (`TileActionDisc.selectionDisc`, `TileSelectionIndicator`): a ring while not chosen,
    /// a white disc with the check or the order in the family fill while chosen, in the 44 pt target. VoiceOver reads the selected trait,
    /// never "switch", and no value.
    private func restyleChoice(_ selection: TileSelection, glyphSize: CGFloat, animated: Bool) {
        let ink = TileActionInk.resolveTokens(face: face, isOn: selection.isSelected, family: family)
        if choiceLayer == nil {
            let view = UKChoiceDiscView()
            view.isUserInteractionEnabled = false
            insertSubview(view, belowSubview: pressOverlay)
            choiceLayer = view
        }
        let unavailable = item.phase == .unavailable
        glyph.isHidden = true
        backgroundColor = .clear
        let reduced = UKDesign.reduceMotion
        if item.showsProgress {
            if spinner == nil {
                let arc = UKArcSpinnerView(.inline, label: "", maxScale: 1.5)
                arc.isAccessibilityElement = false
                insertSubview(arc, belowSubview: pressOverlay)
                spinner = arc
            }
            spinner?.color = UIColor(ink.glyph)
            spinner?.isHidden = false
            choiceLayer?.isHidden = true
        } else {
            spinner?.isHidden = true
            choiceLayer?.isHidden = false
            choiceLayer?.configure(selection: selection, disc: UIColor(ink.disc), mark: UIColor(ink.glyph),
                                   diameter: UKChoiceDiscView.diameter(traits: traitCollection), animated: animated, reduceMotion: reduced)
        }
        choiceLayer?.alpha = unavailable ? 0.5 : 1
        pressOverlay.backgroundColor = (selection.isSelected ? UIColor(ink.glyph) : UIColor.white).withAlphaComponent(0.22)
        isEnabled = item.phase == .ready
        accessibilityLabel = spokenLabel ?? defaultLabel
        accessibilityValue = ""
        var traits: UIAccessibilityTraits = [.button]
        if selection.isSelected { traits.insert(.selected) }
        if !isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { pressOverlay.isHidden = !isHighlighted } }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        glyph.frame = bounds
        let ring = min(bounds.width, bounds.height, UKChoiceDiscView.diameter(traits: traitCollection))
        let choiceFrame = CGRect(x: (bounds.width - ring) / 2, y: (bounds.height - ring) / 2, width: ring, height: ring)
        choiceLayer?.frame = choiceFrame
        pressOverlay.frame = choiceLayer?.isHidden == false ? choiceFrame : bounds
        pressOverlay.layer.cornerRadius = pressOverlay.frame.width / 2
        if let spinner {
            let size = spinner.sizeThatFits(.zero)
            spinner.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // The whole circle, plus the 44 pt target a smaller disc at a small text size would otherwise miss.
        bounds.insetBy(dx: min(0, (bounds.width - HassTokens.minTarget) / 2), dy: min(0, (bounds.height - HassTokens.minTarget) / 2)).contains(point)
    }
}

// MARK: - Choice disc

/// The selection tile's mark (`TileSelectionIndicator`): a ring while not chosen, a white disc with the checkmark (single choice) or the
/// 1-based order (ordered choice) in the family fill while chosen. 28 pt at the default size, scaling with text to 1.5x, inside the 44 pt
/// target.
///
/// **Motion** (the approved mockup): choosing fills the ring white and scales the check in from 50% (`quick`); a number that changes
/// rolls. Under Reduce Motion nothing scales or rolls: the fill and the mark cross-fade (`stateReduced`).
@MainActor
final class UKChoiceDiscView: UIView {
    private let ring = UIView()
    private let fill = UIView()
    private let label = UILabel()
    private let check = UIImageView()
    private var selection: TileSelection?

    /// The ring's opacity on the dark ground, which keeps it above 3:1 (WCAG 1.4.11).
    private static let ringOpacity: CGFloat = 0.85
    /// The ring and the chosen disc at the default size, and the ring's stroke (`TileSelectionIndicator`, which HassDesign keeps internal).
    private static let baseDiameter: CGFloat = 28
    private static let ringWidth: CGFloat = 2

    /// The indicator's diameter: 28 pt, scaling with text but never more than 1.5x (`TileSelectionIndicator.diameter(scaled:)`).
    static func diameter(traits: UITraitCollection) -> CGFloat {
        min(max(UKFont.scaled(Self.baseDiameter, relativeTo: .body, traits: traits), Self.baseDiameter), Self.baseDiameter * 1.5)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for layer in [ring, fill] { layer.layer.cornerCurve = .continuous; layer.isUserInteractionEnabled = false }
        ring.layer.borderWidth = Self.ringWidth
        ring.layer.borderColor = UIColor.white.withAlphaComponent(Self.ringOpacity).cgColor
        label.textAlignment = .center
        check.contentMode = .center
        addSubview(ring)
        addSubview(fill)
        addSubview(label)
        addSubview(check)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(selection: TileSelection, disc: UIColor, mark: UIColor, diameter: CGFloat, animated: Bool, reduceMotion: Bool) {
        let previous = self.selection
        self.selection = selection
        let chosen = selection.isSelected
        let size = (diameter * 0.54).rounded()
        if let position = selection.position {
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            let rounded = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            label.font = UIFont(descriptor: rounded.fontDescriptor.addingAttributes([.featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType, UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]]),
                                size: size)
            label.text = "\(position)"
        }
        label.textColor = mark
        check.tintColor = mark
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .bold))
        fill.backgroundColor = disc
        let showsNumber = chosen && selection.position != nil
        let showsCheck = chosen && selection.position == nil
        let apply = { [self] in
            ring.alpha = chosen ? 0 : 1
            fill.alpha = chosen ? 1 : 0
            label.alpha = showsNumber ? 1 : 0
            check.alpha = showsCheck ? 1 : 0
        }
        let changed = previous != nil && previous != selection
        if animated, changed, window != nil {
            if reduceMotion {
                UIView.animate(withDuration: MotionTokens.stateReducedDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: apply)
            } else {
                // The mark scales in from 50%; a changed number rolls (a vertical cross-dissolve).
                if chosen, previous?.isSelected != true {
                    (showsNumber ? label : check).transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                }
                UIView.animate(withDuration: UKMotion.quickDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    apply()
                    self.label.transform = .identity
                    self.check.transform = .identity
                }
                if showsNumber, previous?.position != nil { UIView.transition(with: label, duration: UKMotion.quickDuration, options: [.transitionFlipFromTop, .allowUserInteraction], animations: nil) }
            }
        } else {
            apply()
            label.transform = .identity
            check.transform = .identity
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for layer in [ring, fill] {
            layer.frame = bounds
            layer.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
        label.frame = bounds
        check.frame = bounds
    }
}

// MARK: - Strip

/// The discs of a tile laid in a row (`TileActionStrip`): trailing and vertically centred, or below the text (the tile places the strip).
/// Every tap plays the tap haptic and nothing later (no success haptic); identifiers are `<tile-id>.action.<item.id>`. Discs are reused by
/// item id, so a symbol that changes with state replaces itself instead of the disc being remade.
@MainActor
final class UKTileActionStrip: UIView {
    private(set) var discs: [UKTileActionDisc] = []
    private(set) var items: [TileActionItem] = []
    /// Runs with the tapped item's id.
    var onPerform: ((TileActionItem.ID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(items: [TileActionItem], title: String, tileIdentifier: String?, face: TileActionFace, family: ColorFamily?,
                   surface: TileSurface, animated: Bool) {
        let existing = Dictionary(discs.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [UKTileActionDisc] = []
        for item in items {
            let identifier = [tileIdentifier, "action", item.id].compactMap { $0 }.joined(separator: ".")
            if let disc = existing[item.id] {
                disc.configure(item: item, face: face, family: family, surface: surface, title: title, identifier: identifier, animated: animated)
                next.append(disc)
            } else {
                let disc = UKTileActionDisc(item: item, face: face, family: family, surface: surface, title: title, identifier: identifier)
                let id = item.id
                disc.addAction(UIAction { [weak self] _ in
                    UKTapFeedback.tap()
                    self?.onPerform?(id)
                }, for: .touchUpInside)
                addSubview(disc)
                next.append(disc)
            }
        }
        for disc in discs where !next.contains(where: { $0 === disc }) { disc.removeFromSuperview() }
        discs = next
        self.items = items
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var diameter: CGFloat { UKTileActionDisc.diameter(traits: traitCollection) }

    /// The strip's width for `count` discs at `traits`.
    static func width(count: Int, traits: UITraitCollection) -> CGFloat {
        TileActionButtonStyle.stripWidth(count: count, diameter: UKTileActionDisc.diameter(traits: traits))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: TileActionButtonStyle.stripWidth(count: discs.count, diameter: diameter), height: discs.isEmpty ? 0 : diameter)
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = diameter
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var x: CGFloat = 0
        for disc in discs {
            let origin = mirror ? bounds.width - x - diameter : x
            disc.frame = CGRect(x: origin, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
            x += diameter + TileActionButtonStyle.gap
        }
    }
}

// MARK: - Volume slider

/// A volume slider for a tile's custom slot (`TileVolumeSlider`, pattern: `.agents/patterns/action-tiles.md`): presentational, no store.
///
/// A horizontal pan sets the level from where the finger is across the track and a vertical drag is left to the scroll view. The level is
/// written once, on release, through ``onCommit`` (a drag never sends a service call per frame). VoiceOver reads "Volume title" with the
/// level in percent and adjusts by ``TileVolumeSlider/step``, each step writing once.
@MainActor
final class UKTileVolumeSlider: UIView, UIGestureRecognizerDelegate {
    var title: String { didSet { accessibilityLabel = "Volume \(title)" } }
    /// The level the caller shows, 0...100 (live, or its optimistic value).
    private(set) var percent: Int
    /// Dims and ignores input (the speaker is off or unavailable).
    var isDisabled: Bool { didSet { refresh() } }
    /// Asked to set the level, once per release or per VoiceOver step.
    var onCommit: ((Int) -> Void)?

    private let track = CALayer()
    private let fill = CALayer()
    private var dragPercent: Double?
    private var pendingPercent: Int?
    private var dragAxisHorizontal: Bool?
    private var pendingTask: Task<Void, Never>?
    private var lastHapticStep: Int?

    /// The slim capsule's height inside the 44 pt target.
    static let trackHeight = TileVolumeSlider.trackHeight

    init(title: String, percent: Int, isDisabled: Bool = false, identifier: String? = nil, onCommit: ((Int) -> Void)? = nil) {
        self.title = title
        self.percent = percent
        self.isDisabled = isDisabled
        self.onCommit = onCommit
        super.init(frame: .zero)
        track.backgroundColor = UIColor.white.withAlphaComponent(0.22).cgColor
        fill.backgroundColor = UIColor.white.cgColor
        layer.addSublayer(track)
        layer.addSublayer(fill)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Volume \(title)"
        accessibilityIdentifier = identifier
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { MainActor.assumeIsolated { pendingTask?.cancel() } }

    /// Shows the live level. Any live report replaces the level shown meanwhile.
    func update(percent: Int, isDisabled: Bool) {
        if percent != self.percent { pendingPercent = nil }
        self.percent = percent
        self.isDisabled = isDisabled
        refresh()
    }

    private var shown: Int {
        if let dragPercent { return Int(dragPercent.rounded()) }
        return pendingPercent ?? percent
    }

    private func refresh() {
        alpha = isDisabled ? 0.5 : 1
        accessibilityValue = TileVolumeSlider.spokenValue(percent: shown)
        layoutFill(animated: window != nil && dragPercent == nil)
    }

    private var targetHeight: CGFloat { UKFont.scaled(HassTokens.minTarget, relativeTo: .body, traits: traitCollection) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: targetHeight) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: targetHeight) }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height = Self.trackHeight
        track.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        track.cornerRadius = height / 2
        fill.cornerRadius = height / 2
        CATransaction.commit()
        layoutFill(animated: false)
    }

    private func layoutFill(animated: Bool) {
        let height = Self.trackHeight
        let width = max(height, bounds.width * CGFloat(shown) / 100)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let frame = CGRect(x: mirror ? bounds.width - width : 0, y: (bounds.height - height) / 2, width: width, height: height)
        UKMotion.quick(animated: animated) { fill.frame = frame }
    }

    // MARK: Interaction

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard !isDisabled, let pan = recognizer as? UIPanGestureRecognizer else { return !isDisabled }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }

    private func location(of pan: UIPanGestureRecognizer) -> CGFloat {
        let x = pan.location(in: self).x
        return effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - x : x
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let x = location(of: pan)
        switch pan.state {
        case .began, .changed:
            let moved = pan.translation(in: self)
            if dragAxisHorizontal == nil { dragAxisHorizontal = abs(moved.x) >= abs(moved.y) }
            guard dragAxisHorizontal == true else { return }
            dragPercent = TileVolumeSlider.percent(atX: x, width: bounds.width)
            let step = BrightnessTile.hapticStep(dragPercent)
            if lastHapticStep != nil, step != nil, step != lastHapticStep { UKTapFeedback.step() }
            lastHapticStep = step
            refresh()
        case .ended:
            defer { dragAxisHorizontal = nil; lastHapticStep = nil }
            guard dragAxisHorizontal == true, dragPercent != nil else { return }
            dragPercent = nil
            commit(Int(TileVolumeSlider.percent(atX: x, width: bounds.width).rounded()))
        default:
            dragAxisHorizontal = nil
            dragPercent = nil
            lastHapticStep = nil
            refresh()
        }
    }

    /// Passes a committed level to the caller and drops the shown level after ``BrightnessTile/pendingTimeout``.
    private func commit(_ value: Int) {
        defer { refresh() }
        guard value != shown else { return }
        pendingPercent = value
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrightnessTile.pendingTimeout)
            guard !Task.isCancelled, let self else { return }
            pendingPercent = nil
            refresh()
        }
        onCommit?(value)
    }

    override func accessibilityIncrement() {
        guard !isDisabled else { return }
        commit(TileVolumeSlider.stepped(shown, by: TileVolumeSlider.step))
    }

    override func accessibilityDecrement() {
        guard !isDisabled else { return }
        commit(TileVolumeSlider.stepped(shown, by: -TileVolumeSlider.step))
    }
}
#endif
