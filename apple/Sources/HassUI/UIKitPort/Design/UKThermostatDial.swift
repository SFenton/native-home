#if os(iOS)
import HassDesign
import UIKit

// MARK: - Colours

extension UIColor {
    /// A dial tint (`Color(DialTint)`).
    convenience init(dial tint: DialTint) {
        self.init(red: tint.red / 255, green: tint.green / 255, blue: tint.blue / 255, alpha: tint.opacity)
    }

    /// The same colour with its saturation removed (`.saturation(0)` on an inactive dial).
    func ukDesaturated(in traits: UITraitCollection) -> UIColor {
        var white: CGFloat = 0, alpha: CGFloat = 0
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        guard resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        white = 0.299 * red + 0.587 * green + 0.114 * blue
        return UIColor(white: white, alpha: alpha)
    }
}

// MARK: - Dial

/// The shared thermostat dial (`ThermostatDial`; pattern `.agents/patterns/thermostat-dial.md`): the 270 degree ring drawn with
/// `CAShapeLayer`s, a draggable handle per setpoint with its own 64 pt target and haptic detents, tap on the ring to move the
/// nearest handle, and VoiceOver adjustable handles (swipe up and down, or the named actions Raise and Lower).
///
/// Pure UI: set a ``ThermostatDialConfiguration`` and receive setpoint commits through ``onCommit``; map those to
/// `climate.set_temperature`. Dragging shows the new setpoint at once and commits on release. For a dial bound to one climate
/// entity use ``UKClimateThermostatDial``.
///
/// ```swift
/// let dial = UKThermostatDial(configuration, size: .modal) { targets in send(targets) }
/// view.addSubview(dial)      // fills the width up to size.maxSide + 40 and is square; centre it
/// dial.configuration = ThermostatDialConfiguration(entity: box.state, title: "Living Room")   // when the box changes
/// dial.rejection = rejection                                                                  // rolls a refused commit back
/// ```
public final class UKThermostatDial: UIView {
    public typealias Size = ThermostatDial.Size

    public var configuration: ThermostatDialConfiguration {
        didSet { if oldValue != configuration { face.configuration = configuration; refreshLines() } }
    }
    public var size: Size { didSet { widthLimit.constant = size.maxSide + ThermostatDial.gutter * 2 } }
    /// A page on the wallpaper, or the inside of a sheet: decides the supporting text ink.
    public var surface: TileSurface {
        didSet { face.surface = surface; refreshLines() }
    }
    /// The latest commit Home Assistant rejected; the dial drops that edit if it is still showing.
    public var rejection: ThermostatRejection? {
        didSet { if rejection != oldValue, let rejection { face.rollBack(rejection.targets) } }
    }
    public var onCommit: (ThermostatTargets) -> Void {
        get { face.onCommit }
        set { face.onCommit = newValue }
    }

    private let face: UKDialFace
    private let content = UIStackView()
    private let actionLine = UKDialActionLabel()
    private let captionLine = UKDialCaptionView()
    private let lines = UIStackView()
    private let widthLimit: NSLayoutConstraint

    public init(_ configuration: ThermostatDialConfiguration, size: Size = .page, surface: TileSurface = .page, rejection: ThermostatRejection? = nil,
                onCommit: @escaping (ThermostatTargets) -> Void) {
        self.configuration = configuration
        self.size = size
        self.surface = surface
        self.rejection = rejection
        face = UKDialFace(configuration: configuration, surface: surface)
        face.onCommit = onCommit
        let inner = UIView()
        widthLimit = inner.widthAnchor.constraint(lessThanOrEqualToConstant: size.maxSide + ThermostatDial.gutter * 2)
        super.init(frame: .zero)
        addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        let fill = inner.widthAnchor.constraint(equalTo: widthAnchor)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            widthLimit, fill,
            inner.centerXAnchor.constraint(equalTo: centerXAnchor),
            inner.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor), inner.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            inner.topAnchor.constraint(equalTo: topAnchor), inner.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content.axis = .vertical
        content.spacing = HassTokens.Spacing.m
        content.alignment = .fill
        inner.addSubview(content)
        content.ukPin(to: inner)
        face.translatesAutoresizingMaskIntoConstraints = false
        face.heightAnchor.constraint(equalTo: face.widthAnchor).isActive = true
        content.addArrangedSubview(face)
        // At accessibility sizes the ring holds the numeral alone; the action and caption lines read below it at their scaled
        // size (HIG Typography: reflow, don't shrink). Hidden from VoiceOver: the readout already speaks both.
        lines.axis = .vertical
        lines.spacing = HassTokens.Spacing.xs
        lines.alignment = .center
        lines.isAccessibilityElement = false
        lines.accessibilityElementsHidden = true
        lines.addArrangedSubview(actionLine)
        lines.addArrangedSubview(captionLine)
        content.addArrangedSubview(lines)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "thermostatDial"
        accessibilityElements = [face]
        face.onDisplay = { [weak self] in self?.refreshLines() }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.refreshLines() }
        refreshLines()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func refreshLines() {
        let showsLines = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        lines.isHidden = !showsLines
        guard showsLines else { return }
        actionLine.update(configuration, surface: surface)
        captionLine.update(configuration, displayed: face.displayed, surface: surface)
    }
}

// MARK: - Text lines

/// The action line ("Heating"), above the numeral.
final class UKDialActionLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UKFont.preferred(.subheadline, bold: true)
        adjustsFontForContentSizeCategory = true
        textAlignment = .center
        numberOfLines = 1
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Supporting text ink. A dial drawn straight on the wallpaper sits on the photo at its brightest, where 72% white measured
    /// 3.8:1 ("Idle"); there it is 92% white. In a sheet it keeps the adaptive secondary ink.
    static func ink(_ surface: TileSurface) -> UIColor {
        surface == .page ? UIColor.white.withAlphaComponent(0.92) : UIColor(HassTokens.RGB.Ink.secondary)
    }

    func update(_ configuration: ThermostatDialConfiguration, surface: TileSurface) {
        text = configuration.actionText
        textColor = Self.ink(surface)
    }
}

/// The caption line (`72.0°F`, or a value dial's "Level 5 • 41% current"), below the numeral.
final class UKDialCaptionView: UIStackView {
    private let icon = UIImageView(image: UIImage(systemName: "thermometer.medium"))
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 4
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.preferred(.footnote, bold: true))
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        addArrangedSubview(icon)
        addArrangedSubview(label)
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    func update(_ configuration: ThermostatDialConfiguration, displayed: ThermostatTargets?, surface: TileSurface) {
        guard let caption = configuration.caption(for: displayed) else {
            isHidden = true
            return
        }
        isHidden = false
        let ink = UKDialActionLabel.ink(surface)
        label.text = caption
        label.textColor = ink
        icon.tintColor = ink
        label.font = UKFont.preferred(.footnote, monospacedDigit: true, bold: true)
        // Value-style captions ("Level 5 • 41% current") run longer than a temperature; two lines keep them whole in a small dial.
        let isValueStyle = configuration.valueStyle != nil
        icon.isHidden = isValueStyle
        label.numberOfLines = isValueStyle ? 2 : 1
    }
}

// MARK: - Face

/// The square the ring, readout and handles are drawn in, and the editing around them.
final class UKDialFace: UIView {
    var configuration: ThermostatDialConfiguration { didSet { refresh(animated: true) } }
    var surface: TileSurface { didSet { readout.update(configuration, displayed: displayed, surface: surface, side: side) } }
    var onCommit: (ThermostatTargets) -> Void = { _ in }
    private(set) var editor = ThermostatDialEditor()

    var displayed: ThermostatTargets? { editor.displayed(configuration) }
    var onDisplay: () -> Void = {}
    var side: CGFloat { max(min(bounds.width, bounds.height) - ThermostatDial.gutter * 2, 0) }

    private let square = UIView()
    private let ring = UKDialRingView()
    private let ringLayers = CALayer()
    private let track = CAShapeLayer()
    private var trailLayers: [String: CAShapeLayer] = [:]
    private let lowArc = CAShapeLayer()
    private let highArc = CAShapeLayer()
    private let marker = CALayer()
    private let readout = UKDialReadout()
    private var handles: [ThermostatTargets.Handle: UKDialHandleView] = [:]
    private var laidOutSide: CGFloat = -1
    private var lastDisplayed: ThermostatTargets?
    private let feedback = UISelectionFeedbackGenerator()
    private var lastColorKey: [AnyHashable] = []

    init(configuration: ThermostatDialConfiguration, surface: TileSurface) {
        self.configuration = configuration
        self.surface = surface
        super.init(frame: .zero)
        addSubview(square)
        square.addSubview(ring)
        ring.layer.addSublayer(ringLayers)
        ringLayers.shadowColor = UIColor.black.cgColor
        ringLayers.shadowOpacity = 0.18
        ringLayers.shadowRadius = 7
        ringLayers.shadowOffset = CGSize(width: 0, height: 10)
        for layer in [track, lowArc, highArc] {
            layer.fillColor = nil
            layer.lineCap = .round
            ringLayers.addSublayer(layer)
        }
        marker.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        marker.cornerRadius = 9
        marker.borderWidth = 3
        marker.borderColor = UIColor(ThermostatDialPalette.markerRimToken).cgColor
        ringLayers.addSublayer(marker)
        square.addSubview(readout)
        let tap = UITapGestureRecognizer(target: self, action: #selector(ringTapped(_:)))
        ring.addGestureRecognizer(tap)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        feedback.prepare()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self, UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.laidOutSide = -1
            self.setNeedsLayout()
            self.refresh(animated: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(boldChanged), name: UIAccessibility.boldTextStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func boldChanged() { refresh(animated: false) }

    private var geometry: ThermostatDialGeometry { configuration.geometry }
    private var isAccessibilityLayout: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = side
        square.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        ring.frame = square.bounds
        ringLayers.frame = square.bounds
        readout.frame = square.bounds
        if side != laidOutSide {
            laidOutSide = side
            refresh(animated: false)
        }
    }

    // MARK: Drawing

    private func arcPath(side: CGFloat) -> CGPath {
        let radius = side * CGFloat(ThermostatDialGeometry.ringRadiusRatio)
        let start = ThermostatDialGeometry.startDegrees * .pi / 180
        let end = (ThermostatDialGeometry.startDegrees + ThermostatDialGeometry.sweepDegrees) * .pi / 180
        return UIBezierPath(arcCenter: CGPoint(x: side / 2, y: side / 2), radius: radius, startAngle: start, endAngle: end, clockwise: true).cgPath
    }

    /// Shows a stretch of the ring between two values by trimming the full-ring path.
    private func apply(_ layer: CAShapeLayer, from: Double, to: Double, color: UIColor, lineWidth: CGFloat, path: CGPath, hidden: Bool, animateColor: Bool) {
        layer.path = path
        layer.lineWidth = lineWidth
        let start = geometry.fraction(of: from), end = geometry.fraction(of: to)
        layer.strokeStart = CGFloat(start)
        layer.strokeEnd = CGFloat(max(end, start))
        layer.opacity = (hidden || end <= start) ? 0 : 1
        setColor(color, on: layer, keyPath: "strokeColor", animate: animateColor)
    }

    private func setColor(_ color: UIColor, on layer: CALayer, keyPath: String, animate: Bool) {
        let resolved = color.resolvedColor(with: traitCollection).cgColor
        if animate, window != nil { UKMotion.fade(layer, keyPath: keyPath, to: resolved) } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setValue(resolved, forKeyPath: keyPath)
            layer.removeAnimation(forKey: "uk.fade.\(keyPath)")
            CATransaction.commit()
        }
    }

    private func tint(for handle: ThermostatTargets.Handle) -> UIColor {
        configuration.valueStyle.map { UIColor(dial: $0.tint) } ?? UIColor(ThermostatDialPalette.colorToken(for: handle, status: configuration.thermalStatus))
    }

    private var statusTint: UIColor {
        configuration.valueStyle.map { UIColor(dial: $0.tint) } ?? UIColor(ThermostatDialPalette.colorToken(for: configuration.thermalStatus))
    }

    func refresh(animated requested: Bool) {
        guard laidOutSide >= 0 else { return }
        let side = laidOutSide
        let displayed = displayed
        let dragging = editor.activeHandle != nil
        let animated = requested && !dragging && !UIAccessibility.isReduceMotionEnabled && window != nil
        let inactive = configuration.isInactive
        let colorKey = configuration.colorKey
        let colorChanged = colorKey != lastColorKey
        lastColorKey = colorKey
        func tone(_ color: UIColor) -> UIColor { inactive ? color.ukDesaturated(in: traitCollection) : color }

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(MotionTokens.quickDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        let path = arcPath(side: side)
        let lineWidth = side * 24 / 320
        let trackColor = UIColor(HassTokens.RGB.Ink.track(increasedContrast: traitCollection.accessibilityContrast == .high))
        apply(track, from: geometry.min, to: geometry.max, color: tone(trackColor), lineWidth: lineWidth, path: path, hidden: false, animateColor: false)
        // Trails of a value dial.
        let trails = configuration.valueStyle?.trails ?? []
        let showTrails = !configuration.isUnavailable
        for trail in trails where trailLayers[trail.id] == nil {
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.lineCap = .round
            ringLayers.insertSublayer(layer, above: track)
            trailLayers[trail.id] = layer
        }
        for (id, layer) in trailLayers where !trails.contains(where: { $0.id == id }) {
            layer.removeFromSuperlayer()
            trailLayers[id] = nil
        }
        for trail in trails {
            guard let layer = trailLayers[trail.id] else { continue }
            apply(layer, from: trail.from, to: trail.to, color: tone(UIColor(dial: trail.tint)), lineWidth: lineWidth, path: path, hidden: !showTrails, animateColor: animated)
        }
        // Heat and cool arcs of a range.
        if case let .range(low, high)? = displayed, !configuration.isUnavailable {
            apply(lowArc, from: geometry.min, to: low, color: tone(UIColor(ThermostatDialPalette.heatToken)), lineWidth: lineWidth, path: path, hidden: false, animateColor: false)
            apply(highArc, from: high, to: geometry.max, color: tone(UIColor(ThermostatDialPalette.coolToken)), lineWidth: lineWidth, path: path, hidden: false, animateColor: false)
        } else {
            lowArc.opacity = 0
            highArc.opacity = 0
        }
        // The current-temperature marker.
        if !configuration.isUnavailable, let current = configuration.current {
            marker.isHidden = false
            marker.position = geometry.point(for: current, side: side)
            setColor(tone(statusTint), on: marker, keyPath: "backgroundColor", animate: animated && colorChanged)
        } else {
            marker.isHidden = true
        }
        ringLayers.opacity = inactive ? 0.45 : 1
        CATransaction.commit()

        ring.update(configuration: configuration, side: side)
        syncHandles(displayed: displayed, side: side, animated: animated)
        readout.update(configuration, displayed: displayed, surface: surface, side: side)
        onDisplay()
        // One detent per step while dragging.
        if dragging, displayed != lastDisplayed { feedback.selectionChanged() }
        lastDisplayed = displayed
        updateAccessibility(displayed: displayed)
    }

    private func syncHandles(displayed: ThermostatTargets?, side: CGFloat, animated: Bool) {
        let wanted: [ThermostatTargets.Handle] = (configuration.acceptsInput ? displayed?.handles : nil) ?? []
        for (handle, view) in handles where !wanted.contains(handle) {
            view.removeFromSuperview()
            handles[handle] = nil
        }
        for handle in wanted where handles[handle] == nil {
            let view = UKDialHandleView(handle: handle)
            view.onDrag = { [weak self] point in self?.drag(handle, to: point) }
            view.onEnd = { [weak self] point in self?.endDrag(handle, at: point) }
            view.onAdjust = { [weak self] increment in self?.adjust(handle, increment: increment) }
            view.coordinateSpaceView = square
            square.addSubview(view)
            handles[handle] = view
        }
        for handle in wanted {
            guard let view = handles[handle], let displayed else { continue }
            let value = displayed.value(of: handle) ?? geometry.min
            let center = geometry.point(for: value, side: side)
            let move = { view.center = center }
            if animated { UKMotion.animate(.quick, animations: move) } else { move() }
            view.setRim(tint(for: handle), animated: animated)
            view.isDragging = editor.activeHandle == handle
            view.configureAccessibility(label: configuration.accessibilityLabel(for: handle), value: configuration.spokenValue(value))
        }
    }

    private func updateAccessibility(displayed: ThermostatTargets?) {
        let order: [ThermostatTargets.Handle] = [.low, .high, .target]
        accessibilityElements = [readout] + order.compactMap { handles[$0] }
    }

    // MARK: Editing

    @objc private func ringTapped(_ gesture: UITapGestureRecognizer) {
        guard configuration.acceptsInput else { return }
        send(editor.tap(at: gesture.location(in: square), side: side, in: configuration))
        refresh(animated: true)
    }

    private func drag(_ handle: ThermostatTargets.Handle, to point: CGPoint) {
        editor.drag(handle, to: point, side: side, in: configuration)
        refresh(animated: false)
    }

    private func endDrag(_ handle: ThermostatTargets.Handle, at point: CGPoint) {
        let targets = editor.endDrag(handle, at: point, side: side, in: configuration)
        send(targets)
        refresh(animated: false)
    }

    private func adjust(_ handle: ThermostatTargets.Handle, increment: Bool) {
        send(editor.adjust(handle, increment: increment, in: configuration))
        refresh(animated: true)
    }

    func rollBack(_ rejected: ThermostatTargets) {
        editor.rollBack(rejected: rejected)
        refresh(animated: true)
    }

    private func send(_ targets: ThermostatTargets?) {
        if let targets { onCommit(targets) }
    }
}

// MARK: - Ring hit area

/// The 64 pt band around the ring that accepts taps, so touches elsewhere fall through to a scroll view. It draws nothing (the
/// face's layers do); it is hidden from VoiceOver, since the handles and the readout are the accessible parts.
final class UKDialRingView: UIView {
    private var geometry = ThermostatDialGeometry(min: 0, max: 1, step: 1)
    private var side: CGFloat = 0
    private var accepts = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(configuration: ThermostatDialConfiguration, side: CGFloat) {
        geometry = configuration.geometry
        self.side = side
        accepts = configuration.acceptsInput
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        accepts && geometry.isOnRing(point, side: side)
    }
}

// MARK: - Handle

/// One draggable setpoint handle on the dial, with its 64 pt target and its VoiceOver adjustable action.
final class UKDialHandleView: UIView {
    let handle: ThermostatTargets.Handle
    var onDrag: (CGPoint) -> Void = { _ in }
    var onEnd: (CGPoint) -> Void = { _ in }
    var onAdjust: (Bool) -> Void = { _ in }
    weak var coordinateSpaceView: UIView?
    private let knob = UIView()
    private let halo = UIView()
    private var lastPoint = CGPoint.zero

    /// True while this handle is being dragged: it lifts with a larger shadow and a halo.
    var isDragging = false {
        didSet {
            guard isDragging != oldValue else { return }
            halo.isHidden = !isDragging
            knob.layer.shadowOpacity = isDragging ? 0.3 : 0.2
            knob.layer.shadowRadius = isDragging ? 6 : 3
            knob.layer.shadowOffset = CGSize(width: 0, height: isDragging ? 10 : 4)
        }
    }

    init(handle: ThermostatTargets.Handle) {
        self.handle = handle
        super.init(frame: CGRect(x: 0, y: 0, width: ThermostatDialGeometry.hitTarget, height: ThermostatDialGeometry.hitTarget))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        halo.center = center
        halo.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        halo.layer.cornerRadius = 20
        halo.isHidden = true
        halo.isUserInteractionEnabled = false
        addSubview(halo)
        knob.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        knob.center = center
        knob.backgroundColor = .white
        knob.layer.cornerRadius = 12
        knob.layer.borderWidth = 4
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.2
        knob.layer.shadowRadius = 3
        knob.layer.shadowOffset = CGSize(width: 0, height: 4)
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        // `DragGesture(minimumDistance: 0)`: the handle follows the finger from the first touch.
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.minimumPressDuration = 0
        drag.allowableMovement = .greatestFiniteMagnitude
        addGestureRecognizer(drag)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityIdentifier = "thermostatDial.handle.\(handle.rawValue)"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: ThermostatDialConfiguration.raiseActionName) { [weak self] _ in self?.onAdjust(true); return true },
            UIAccessibilityCustomAction(name: ThermostatDialConfiguration.lowerActionName) { [weak self] _ in self?.onAdjust(false); return true },
        ]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setRim(_ color: UIColor, animated: Bool) {
        let resolved = color.resolvedColor(with: traitCollection).cgColor
        if animated { UKMotion.fade(knob.layer, keyPath: "borderColor", to: resolved) } else { knob.layer.borderColor = resolved }
    }

    func configureAccessibility(label: String, value: String) {
        accessibilityLabel = label
        accessibilityValue = value
    }

    override func accessibilityIncrement() { onAdjust(true) }
    override func accessibilityDecrement() { onAdjust(false) }

    @objc private func dragged(_ gesture: UILongPressGestureRecognizer) {
        guard let space = coordinateSpaceView else { return }
        let point = gesture.location(in: space)
        switch gesture.state {
        case .began, .changed:
            lastPoint = point
            onDrag(point)
        case .ended:
            onEnd(point)
        case .cancelled, .failed:
            onEnd(lastPoint)
        default: break
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // The 64 pt circle.
        hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
    }
}

// MARK: - Readout

/// The dial's centre: the action, the large setpoint with its raised unit, and the caption. One accessibility element that speaks
/// the configuration's readout label and value. At accessibility Dynamic Type sizes the ring holds the numeral alone, at its
/// scaled size.
final class UKDialReadout: UIView {
    private let action = UKDialActionLabel()
    private let numeral = UILabel()
    private let caption = UKDialCaptionView()
    private let stack = UIStackView()
    private var widthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        numeral.numberOfLines = 1
        numeral.textAlignment = .center
        numeral.adjustsFontSizeToFitWidth = true
        action.adjustsFontSizeToFitWidth = true
        action.minimumScaleFactor = 0.4
        [action, numeral, caption].forEach(stack.addArrangedSubview)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = stack.widthAnchor.constraint(equalToConstant: 100)
        NSLayoutConstraint.activate([
            widthConstraint, stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "thermostatDial.readout"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The numeral's weight: light, or regular while Bold Text is on, which a fixed-size font does not follow itself.
    static func numeralWeight() -> UIFont.Weight { UIAccessibility.isBoldTextEnabled ? .regular : .light }

    func update(_ configuration: ThermostatDialConfiguration, displayed: ThermostatTargets?, surface: TileSurface, side: CGFloat) {
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        action.isHidden = accessibility
        caption.isHidden = accessibility
        if !accessibility {
            action.update(configuration, surface: surface)
            caption.update(configuration, displayed: displayed, surface: surface)
        }
        action.minimumScaleFactor = 0.4
        numeral.minimumScaleFactor = accessibility ? 0.6 : 0.4
        // Stay inside the ring; the inscribed square of the inner edge is about 0.6 of the side. At accessibility sizes the
        // chord across the ring's middle is wider, so the numeral may use most of the side.
        widthConstraint.constant = max(side * (accessibility ? 0.8 : 0.62), 1)
        let primarySize = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 76)
        let primary = UIFont.monospacedDigitSystemFont(ofSize: primarySize, weight: Self.numeralWeight())
        let text = NSMutableAttributedString(string: configuration.primaryText(for: displayed), attributes: [.font: primary, .foregroundColor: UIColor(HassTokens.RGB.Ink.primary)])
        if let unit = configuration.primaryUnit {
            text.addAttribute(.kern, value: 2, range: NSRange(location: text.length - 1, length: 1))
            // Raised like the SwiftUI alignment guide (0.42 of the numeral size).
            text.append(NSAttributedString(string: unit, attributes: [
                .font: UIFont.systemFont(ofSize: primarySize * 0.32, weight: .bold), .foregroundColor: UIColor(HassTokens.RGB.Ink.primary),
                .baselineOffset: primarySize * 0.42,
            ]))
        }
        numeral.attributedText = text
        accessibilityLabel = configuration.readoutAccessibilityLabel
        accessibilityValue = configuration.readoutAccessibilityValue(for: displayed)
    }
}
#endif
