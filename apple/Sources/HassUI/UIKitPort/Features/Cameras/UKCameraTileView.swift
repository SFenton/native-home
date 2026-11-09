#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One camera card (`CameraTile`): the camera's shared live stream over its latest snapshot, with a small name capsule and nothing
/// else over the picture (direction G; HIG HomeKit: avoid covering camera views). At accessibility text sizes the name sits below
/// the picture. VoiceOver reads "<title> camera", the state (`Live` / `Snapshot`) and the hint "Opens the camera".
///
/// The card is a button; ``onOpen`` runs on a tap with the card as the zoom source.
///
/// ```swift
/// let card = UKCameraTileView(camera: camera, context: context, identifier: "home.camera.\(camera.rtcStreamId)")
/// card.onOpen = { source in open(camera, from: source) }
/// ```
@MainActor
final class UKCameraTileView: UIControl, UKGridMeasuring {
    let camera: HomeConfig.Camera
    /// Runs when the card is tapped, with the card (the zoom transition's source).
    var onOpen: ((UKCameraTileView) -> Void)?

    private let context: UKContext
    private let pool: CameraStreamPool
    private let picture = UIView()
    private let live: UKCameraLiveView
    private let name = UKCameraNameView()
    private let bag = UKObservationBag()
    private var indicator: CameraTile.Indicator?

    /// - Parameters:
    ///   - identifier: The card's accessibility identifier (`<prefix>.<go2rtc stream id>`).
    ///   - pool: The stream pool; the app's shared one by default.
    init(camera: HomeConfig.Camera, context: UKContext, identifier: String, pool: CameraStreamPool = .shared) {
        self.camera = camera
        self.context = context
        self.pool = pool
        live = UKCameraLiveView(camera: camera, style: .tile, context: context, pool: pool)
        super.init(frame: .zero)
        picture.clipsToBounds = true
        picture.layer.cornerRadius = HassTokens.Radius.tile
        picture.layer.cornerCurve = .continuous
        picture.isUserInteractionEnabled = false
        picture.addSubview(live)
        addSubview(picture)
        name.isUserInteractionEnabled = false
        addSubview(name)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(camera.title) camera"
        accessibilityHint = "Opens the camera"
        accessibilityIdentifier = identifier
        name.configure(title: camera.title)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKCameraTileView, _) in
            view.updateNamePlacement()
            view.setNeedsLayout()
            view.superview?.setNeedsLayout()
        }
        updateNamePlacement()
        let model = pool.model(for: camera)
        let connection = context.connection
        bag.observe { [weak self] in
            guard let self else { return }
            let next = CameraTile.indicator(for: model.state, isOffline: connection?.isOffline ?? false)
            accessibilityValue = CameraTile.statusText(model.state)
            guard next != indicator else { return }
            let animated = indicator != nil && window != nil
            indicator = next
            name.show(next, animated: animated)
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() {
        onOpen?(self)
    }

    /// `.buttonStyle(.plain)` dims the card while it is pressed.
    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? HassTokens.ControlState.pressedOpacity : 1 } }
    }

    private var namesBelow: Bool { traitCollection.ukIsAccessibilitySize }

    private func updateNamePlacement() {
        name.placement = namesBelow ? .below : .overPicture
    }

    // MARK: Layout

    /// Width over height of a card is 1 : 0.78 (`CameraTile.aspectRatio`).
    private func pictureHeight(forWidth width: CGFloat) -> CGFloat { width / CameraTile.aspectRatio }

    private func belowHeight(forWidth width: CGFloat) -> CGFloat {
        guard namesBelow else { return 0 }
        return HassTokens.Spacing.xs + name.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { ceil(pictureHeight(forWidth: width) + belowHeight(forWidth: width)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = pictureHeight(forWidth: bounds.width)
        picture.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        live.frame = picture.bounds
        if namesBelow {
            let size = name.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
            name.frame = CGRect(x: 0, y: height + HassTokens.Spacing.xs, width: bounds.width, height: size.height)
        } else {
            let pad = HassTokens.Spacing.s
            let size = name.sizeThatFits(CGSize(width: max(0, bounds.width - 2 * pad), height: CGFloat.greatestFiniteMagnitude))
            let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
            let x = mirror ? bounds.width - pad - size.width : pad
            name.frame = CGRect(x: x, y: height - pad - size.height, width: size.width, height: size.height)
        }
    }

    /// Hit-test only the card's own frame.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }
}

// MARK: - Name

/// The card's name: an indicator slot (the live dot, the inline arc, or `icloud.slash`) before the camera's title. Over the
/// picture it is a black 75% capsule; below it, plain text in the on-dark ink.
@MainActor
private final class UKCameraNameView: UIView {
    enum Placement { case overPicture, below }

    private let slot = UIView()
    private let dot = UIView()
    private let spinner = UKArcSpinnerView(.inline)
    private let offline = UIImageView(image: UIImage(systemName: "icloud.slash"))
    private let label = UILabel()
    private var indicator: CameraTile.Indicator = .connecting

    var placement: Placement = .overPicture {
        didSet {
            guard placement != oldValue else { return }
            applyPlacement()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        spinner.color = .white
        spinner.isAccessibilityElement = false
        offline.tintColor = UIColor.white.withAlphaComponent(0.85)
        offline.contentMode = .center
        for view in [dot, spinner, offline] { slot.addSubview(view) }
        label.numberOfLines = 0
        addSubview(slot)
        addSubview(label)
        slot.isAccessibilityElement = false
        accessibilityElementsHidden = true
        applyPlacement()
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            label.font = UKFont.footnoteEmphasis(traitCollection)
            offline.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.preferred(.caption2, weight: .semibold, traits: traitCollection))
            setNeedsLayout()
        }
        show(.connecting, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String) { label.text = title }

    private func applyPlacement() {
        switch placement {
        case .overPicture:
            backgroundColor = UIColor.black.withAlphaComponent(0.75)
            label.textColor = .white
        case .below:
            // Beside the wallpaper, whatever the scheme: the on-dark ink.
            backgroundColor = nil
            label.textColor = .white
        }
    }

    /// Cross-fades the slot to `indicator` (0.2 s; the label makes room).
    func show(_ indicator: CameraTile.Indicator, animated: Bool) {
        self.indicator = indicator
        let apply = {
            self.dot.isHidden = indicator != .live
            self.spinner.isHidden = indicator != .connecting
            self.offline.isHidden = indicator != .offline
            self.setNeedsLayout()
            self.superview?.setNeedsLayout()
        }
        if animated {
            UIView.transition(with: slot, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .curveEaseOut, .allowUserInteraction],
                              animations: apply)
        } else {
            apply()
        }
    }

    private var slotSize: CGSize {
        switch indicator {
        case .live: CGSize(width: 8, height: 8)
        case .connecting: spinner.intrinsicContentSize
        case .offline: offline.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        }
    }

    private var insets: UIEdgeInsets {
        switch placement {
        case .overPicture: UIEdgeInsets(top: HassTokens.Spacing.xs, left: HassTokens.Spacing.s, bottom: HassTokens.Spacing.xs, right: HassTokens.Spacing.s)
        case .below: UIEdgeInsets(top: 0, left: HassTokens.Spacing.xs, bottom: 0, right: HassTokens.Spacing.xs)
        }
    }

    /// The label's frame width and height for a given outer width.
    private func metrics(width: CGFloat) -> (label: CGSize, height: CGFloat) {
        let slot = slotSize
        let room = max(1, width - insets.left - insets.right - slot.width - HassTokens.Spacing.xs)
        let text = label.sizeThatFits(CGSize(width: room, height: CGFloat.greatestFiniteMagnitude))
        let labelSize = CGSize(width: min(ceil(text.width), room), height: ceil(text.height))
        return (labelSize, max(labelSize.height, slot.height) + insets.top + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width
        let m = metrics(width: width)
        switch placement {
        case .below:
            return CGSize(width: width, height: m.height)
        case .overPicture:
            let outer = insets.left + insets.right + slotSize.width + HassTokens.Spacing.xs + m.label.width
            return CGSize(width: min(outer, width), height: m.height)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = placement == .overPicture ? bounds.height / 2 : 0
        layer.cornerCurve = .continuous
        let slotSize = slotSize
        let m = metrics(width: bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, x: CGFloat, size: CGSize) {
            view.frame = CGRect(x: mirror ? bounds.width - x - size.width : x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
        place(slot, x: insets.left, size: slotSize)
        for view in [dot, spinner, offline] { view.frame = slot.bounds }
        place(label, x: insets.left + slotSize.width + HassTokens.Spacing.xs, size: m.label)
        label.textAlignment = mirror ? .right : .left
    }
}

// MARK: - Grid section

/// The camera cards on Home and Security (`CameraGrid`: web `columns={2} maxCellWidth={280} maxColumns={4}`, 2 x 2 on iPhone): a
/// "Cameras" section header over a grid of ``UKCameraTileView``s. Both pages show this one grid, and every card on it shows the
/// camera's shared stream from ``CameraStreamPool``.
///
/// ```swift
/// let cameras = UKCameraGridSectionView(context: context, identifierPrefix: "security.camera", bag: bag) { camera, source in open(camera, source) }
/// ```
@MainActor
final class UKCameraGridSectionView: UIView, UKGridMeasuring {
    private let header = UKPageSectionHeaderView("Cameras")
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, fill: .none))
    private(set) var tiles: [UKCameraTileView] = []

    /// The window's hinge (the grid keeps tiles off it).
    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }

    /// - Parameters:
    ///   - identifierPrefix: Prefix of each card's identifier (`<prefix>.<go2rtc stream id>`), so a journey can tell Home's cards
    ///     from Security's while both pages show the same shared streams.
    ///   - bag: The page's bag, for the arrival motion of the cards (the first screenful rises one after another after a sign-in).
    ///   - pool: The stream pool; the app's shared one by default.
    ///   - onOpen: Runs when a card is tapped, with the card as the zoom source.
    init(context: UKContext, identifierPrefix: String = "home.camera", bag: UKObservationBag, pool: CameraStreamPool = .shared,
         onOpen: @escaping (HomeConfig.Camera, UKCameraTileView) -> Void) {
        super.init(frame: .zero)
        grid.followsFold = true
        addSubview(header)
        addSubview(grid)
        tiles = HomeConfig.cameras.map { camera in
            let tile = UKCameraTileView(camera: camera, context: context, identifier: "\(identifierPrefix).\(camera.rtcStreamId)", pool: pool)
            tile.onOpen = { onOpen(camera, $0) }
            return tile
        }
        for (index, tile) in tiles.enumerated() {
            UKArrivalMotion.apply(to: tile, shell: context.shell, kind: .rise, index: index + 1, bag: bag)
        }
        grid.setItems(tiles.map { UKGridItem($0) })
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            // Scales with the name capsule's text, so accessibility sizes step down to fewer, wider cameras.
            grid.configuration.minCellWidth = UKFont.scaled(160, relativeTo: .footnote, traits: traitCollection)
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        header.gridHeight(forWidth: width) + HassTokens.Spacing.s + grid.gridHeight(forWidth: width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight = header.gridHeight(forWidth: bounds.width)
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        grid.frame = CGRect(x: 0, y: headerHeight + HassTokens.Spacing.s, width: bounds.width, height: grid.gridHeight(forWidth: bounds.width))
    }
}
#endif
