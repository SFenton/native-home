#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A touch recogniser that begins the moment a finger lands and follows it to the end: SwiftUI's `DragGesture(minimumDistance: 0)`.
/// It reports the first touch only, so a second finger (a pinch) does not move the drag.
@MainActor
class UKMapDragRecognizer: UIGestureRecognizer {
    var startLocation: CGPoint = .zero
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, let touch = touches.first else { return }
        tracked = touch
        startLocation = touch.location(in: view)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        self.tracked = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        self.tracked = nil
        state = .cancelled
    }

    override func reset() {
        tracked = nil
    }

    /// The first touch's location in the view.
    var location: CGPoint { tracked?.location(in: view) ?? location(in: view) }
}

/// One of the area editor's three tools: a 44 pt capsule, filled with the action blue while it is the live tool.
@MainActor
final class UKVacuumToolButton: UIControl {
    private let glyph = UIImageView()
    private let label = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary, alignment: .center)
    private var active = false
    var onTap: (() -> Void)?

    init(title: String, symbol: String, identifier: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        layer.cornerCurve = .continuous
        label.text = title
        label.numberOfLines = 0
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.subheadline, weight: .semibold)))
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        glyph.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [glyph, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: HassTokens.Spacing.s),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -HassTokens.Spacing.s),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityIdentifier = identifier
        apply(active: false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, active: Bool, enabled: Bool) {
        label.text = title
        accessibilityLabel = title
        isEnabled = enabled
        apply(active: active, animated: window != nil)
    }

    private func apply(active: Bool, animated: Bool) {
        let changed = active != self.active
        self.active = active
        let change = { [self] in
            backgroundColor = active ? UKDesignInk.actionFill : UKVacuumStyle.secondaryFill
            let ink: UIColor = active ? .white : UKDesignInk.primary
            label.textColor = ink
            glyph.tintColor = ink
        }
        if animated && changed { UKMotion.stateColor(change) } else { change() }
        alpha = isEnabled ? 1 : 0.45
    }

    @objc private func tapped() { onTap?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapWidth.set(label, in: self, reserving: 2 * HassTokens.Spacing.s + glyph.intrinsicContentSize.width + 6)
        layer.cornerRadius = bounds.height / 2
    }

    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.45 } }

    override var accessibilityTraits: UIAccessibilityTraits {
        get {
            var traits: UIAccessibilityTraits = .button
            if active { traits.insert(.selected) }
            if !isEnabled { traits.insert(.notEnabled) }
            return traits
        }
        set {}
    }
}

/// Draws one rectangular cleaning area on the map (`VacuumAreaEditor`).
///
/// Draw mode: drag to draw. Otherwise drag inside the area to move it, drag a corner handle to resize it, or drag elsewhere to pan;
/// pinch zooms 1 to 10 times. VoiceOver gets the same edits as actions on the map.
@MainActor
final class UKVacuumAreaEditorViewController: UKPageViewController, UIGestureRecognizerDelegate {
    /// Zoom factor of one Zoom In or Zoom Out action.
    static let zoomStep = 1.5

    private let controller: VacuumController
    private let mapState: VacuumMapState
    private var drawMode: Bool
    private var viewport = MapViewport.initial { didSet { map.viewport = viewport } }
    private var gesture: MapAreaEdit.Gesture?
    private var pinchStart: ValetudoMapScene.PinchStart?
    private var draft: MapGridRect? { didSet { map.area = area } }

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let toolbar = UIStackView()
    private var drawTool: UKVacuumToolButton!
    private var resetTool: UKVacuumToolButton!
    private var clearTool: UKVacuumToolButton!
    private let unavailable = UKInlineAlertView("Map Unavailable: Home Assistant cannot currently confirm the vacuum's map or position.")
    private let editor = UIStackView()
    private let mapHolder = UIView()
    private let map = UKValetudoMapView()
    private let caption = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private let dimensions = UILabel.uk(.headline, ink: UKDesignInk.primary)
    private let squareMetres = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
    private let outside = UKInlineAlertView("The area must stay inside the rooms shown on the map.")
    private var useButton: UKPrimaryButton!
    private var aspectConstraint: NSLayoutConstraint?
    private var aspect: Double = 0

    init(controller: VacuumController, mapState: VacuumMapState) {
        self.controller = controller
        self.mapState = mapState
        drawMode = controller.areaSelection == nil
        super.init(sheetTitle: nil)
        title = "\(controller.vacuum.title) Cleaning Area"
        navigationItem.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var area: MapGridRect? { draft ?? controller.areaSelection }
    private var minimumCells: Double { mapState.scene?.minimumAreaCells(controller.vacuum) ?? 5 }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.alwaysBounceVertical = false
        install(scrollView: scroll)
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = HassTokens.Spacing.l
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let width = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * HassTokens.Spacing.l)
        width.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 760), width,
        ])
        buildToolbar()
        buildEditor()
        buildSummary()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKVacuumAreaEditorViewController, _) in
            page.toolbar.axis = page.traitCollection.ukIsAccessibilitySize ? .vertical : .horizontal
            page.toolbar.distribution = page.traitCollection.ukIsAccessibilitySize ? .fill : .fillEqually
        }
        bag.observe { [weak self] in self?.render() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.isScrollEnabled = !isDragging
    }

    private var isDragging = false

    // MARK: Toolbar

    private func buildToolbar() {
        toolbar.axis = traitCollection.ukIsAccessibilitySize ? .vertical : .horizontal
        toolbar.distribution = traitCollection.ukIsAccessibilitySize ? .fill : .fillEqually
        toolbar.spacing = HassTokens.Spacing.s
        drawTool = UKVacuumToolButton(title: "Draw", symbol: "rectangle.dashed", identifier: "vacuum.area.draw") { [weak self] in self?.drawTapped() }
        resetTool = UKVacuumToolButton(title: "Reset View", symbol: "arrow.up.left.and.arrow.down.right", identifier: "vacuum.area.reset") { [weak self] in
            self?.viewport = .initial
        }
        clearTool = UKVacuumToolButton(title: "Clear", symbol: "trash", identifier: "vacuum.area.clear") { [weak self] in
            self?.controller.areaSelection = nil
            self?.drawMode = true
            self?.render()
        }
        [drawTool, resetTool, clearTool].forEach(toolbar.addArrangedSubview)
        content.addArrangedSubview(toolbar)
        content.addArrangedSubview(unavailable)
    }

    private func drawTapped() {
        controller.areaSelection = nil
        if UIAccessibility.isVoiceOverRunning, let scene = mapState.scene {
            controller.areaSelection = MapAreaEdit.voiceOverStart(scene.interactionGeometry, minimum: minimumCells)
            drawMode = false
        } else {
            drawMode = true
        }
        render()
    }

    // MARK: Map

    private func buildEditor() {
        editor.axis = .vertical
        editor.alignment = .fill
        editor.spacing = HassTokens.Spacing.s
        mapHolder.layer.cornerRadius = HassTokens.Radius.tile
        mapHolder.layer.cornerCurve = .continuous
        mapHolder.clipsToBounds = true
        map.translatesAutoresizingMaskIntoConstraints = false
        mapHolder.addSubview(map)
        let fill = map.widthAnchor.constraint(equalTo: mapHolder.widthAnchor)
        fill.priority = UILayoutPriority(500)
        NSLayoutConstraint.activate([
            map.centerXAnchor.constraint(equalTo: mapHolder.centerXAnchor),
            map.topAnchor.constraint(equalTo: mapHolder.topAnchor), map.bottomAnchor.constraint(equalTo: mapHolder.bottomAnchor),
            map.widthAnchor.constraint(lessThanOrEqualTo: mapHolder.widthAnchor),
            map.heightAnchor.constraint(lessThanOrEqualToConstant: 520), fill,
        ])
        map.isAccessibilityElement = true
        map.accessibilityLabel = "\(controller.vacuum.title) cleaning area editor"
        map.accessibilityIdentifier = "vacuum.area.map"
        let drag = UKMapDragRecognizer(target: self, action: #selector(dragged(_:)))
        drag.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        map.addGestureRecognizer(drag)
        map.addGestureRecognizer(pinch)
        caption.accessibilityTraits = .staticText
        editor.addArrangedSubview(mapHolder)
        editor.addArrangedSubview(caption)
        content.addArrangedSubview(editor)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func dragged(_ recognizer: UKMapDragRecognizer) {
        switch recognizer.state {
        case .began:
            isDragging = true
            scroll.isScrollEnabled = false
            fallthrough
        case .changed:
            guard mapState.isReady, pinchStart == nil, let scene = mapState.scene else { return }
            let (job, step) = scene.drag(gesture, from: recognizer.startLocation, to: recognizer.location, size: map.bounds.size, viewport: viewport,
                                         drawMode: drawMode, area: controller.areaSelection, minimum: minimumCells)
            gesture = job
            if let next = step.draft { draft = next }
            if let next = step.viewport { viewport = next }
            refreshSummary()
        case .ended:
            finishDrag(commit: true)
        default:
            finishDrag(commit: false)
        }
    }

    private func finishDrag(commit: Bool) {
        isDragging = false
        scroll.isScrollEnabled = true
        if commit, let draft {
            controller.areaSelection = draft
            drawMode = false
        }
        draft = nil
        gesture = nil
        render()
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard let scene = mapState.scene else { return }
        switch recognizer.state {
        case .began:
            pinchStart = scene.pinchStart(at: recognizer.location(in: map), size: map.bounds.size, viewport: viewport)
            gesture = nil
            draft = nil
        case .changed:
            if pinchStart == nil { pinchStart = scene.pinchStart(at: recognizer.location(in: map), size: map.bounds.size, viewport: viewport) }
            if let start = pinchStart { viewport = scene.pinched(start, magnification: recognizer.scale, size: map.bounds.size) }
        default:
            pinchStart = nil
        }
    }

    /// The pinch's alternative (no visible buttons): Switch Control and Voice Control list these too.
    private func accessibilityActions() -> [UIAccessibilityCustomAction] {
        guard let scene = mapState.scene else { return [] }
        let size = map.bounds.size
        var actions = [
            UIAccessibilityCustomAction(name: "Zoom In") { [weak self] _ in
                guard let self else { return false }
                self.viewport = scene.zoomed(self.viewport, by: Self.zoomStep, size: size)
                return true
            },
            UIAccessibilityCustomAction(name: "Zoom Out") { [weak self] _ in
                guard let self else { return false }
                self.viewport = scene.zoomed(self.viewport, by: 1 / Self.zoomStep, size: size)
                return true
            },
            UIAccessibilityCustomAction(name: "Reset Zoom") { [weak self] _ in
                self?.viewport = .initial
                return true
            },
        ]
        if let rect = controller.areaSelection {
            for nudge in MapAreaEdit.Nudge.allCases {
                actions.append(UIAccessibilityCustomAction(name: nudge.title) { [weak self] _ in
                    guard let self else { return false }
                    self.controller.areaSelection = MapAreaEdit.nudge(rect, nudge, interaction: scene.interactionGeometry, minimum: self.minimumCells)
                    return true
                })
            }
        }
        return actions
    }

    // MARK: Summary

    private func buildSummary() {
        let heading = ukVStack([dimensions, squareMetres], spacing: 2)
        heading.isAccessibilityElement = true
        dimensions.accessibilityIdentifier = "vacuum.area.dimensions"
        heading.accessibilityIdentifier = nil
        let button = UKPrimaryButton("Draw an Area to Continue", systemImage: UKVacuumStyle.symbol("mdi:check")) { [weak self] in
            UKTapFeedback.tap()
            self?.navigationController?.popViewController(animated: true)
        }
        button.accessibilityIdentifier = "vacuum.area.use"
        useButton = button
        let summary = ukVStack([
            heading,
            UKVacuumDescription("Drag to draw an area, drag inside it to move it, and drag any round corner handle to resize it. Pinch to zoom."),
            outside, button,
        ], spacing: HassTokens.Spacing.m)
        summaryHeading = heading
        content.addArrangedSubview(summary)
    }

    private var summaryHeading: UIStackView?

    private var dimensionsText: String? {
        guard let area, let scene = mapState.scene else { return nil }
        return VacuumFormat.areaSize(area, pixelSize: scene.interactionGeometry.pixelSize)
    }

    private var squareMetresText: String? {
        guard let area, let scene = mapState.scene else { return nil }
        let size = area.dimensionsCm(pixelSize: scene.interactionGeometry.pixelSize)
        return "\((size.width * size.height / 10_000).formatted(.number.precision(.fractionLength(2)).grouping(.never))) m² selected"
    }

    private func refreshSummary() {
        dimensions.text = dimensionsText ?? "No area selected"
        squareMetres.text = squareMetresText ?? "Draw a rectangle to continue."
        summaryHeading?.accessibilityLabel = [dimensions.text, squareMetres.text].compactMap { $0 }.joined(separator: ", ")
        map.accessibilityValue = dimensionsText ?? "No area selected"
        map.area = area
        outside.isHidden = mapState.allows(controller.areaSelection)
    }

    // MARK: Render

    private func render() {
        let ready = mapState.isReady
        let selection = controller.areaSelection
        drawTool.configure(title: selection == nil ? "Draw" : "Redraw", active: drawMode, enabled: ready)
        resetTool.configure(title: "Reset View", active: false, enabled: ready)
        clearTool.configure(title: "Clear", active: false, enabled: ready && selection != nil)
        if let scene = mapState.scene {
            unavailable.isHidden = true
            editor.isHidden = false
            let ratio = max(scene.aspectRatio, 0.6)
            if aspectConstraint == nil || aspect != ratio {
                aspectConstraint?.isActive = false
                let constraint = map.widthAnchor.constraint(equalTo: map.heightAnchor, multiplier: ratio)
                constraint.isActive = true
                aspectConstraint = constraint
                aspect = ratio
            }
            map.scene = scene
            map.showsHandles = !drawMode
            caption.text = drawMode ? "Drag on the map to draw the cleaning area."
                : area != nil ? "Drag the area to move it or use any round corner handle to resize it." : "Choose Draw, then drag on the map."
            map.accessibilityCustomActions = accessibilityActions()
        } else {
            unavailable.isHidden = false
            editor.isHidden = true
        }
        refreshSummary()
        useButton.title = selection == nil ? "Draw an Area to Continue" : "Use This Area"
        useButton.isEnabled = !(selection == nil || !ready)
    }
}
#endif
