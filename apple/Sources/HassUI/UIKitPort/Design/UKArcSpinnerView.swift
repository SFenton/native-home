#if os(iOS)
import HassDesign
import UIKit

/// The app's one loading indicator (`ArcSpinner`): the web's arc, not the system petal spinner. A ring at 22% of its colour with its
/// top quarter at 96% and its right quarter at 72%, turning once every 0.82 s. It takes ``color`` (the text colour around it by
/// default), so it can sit in a tinted button. With Reduce Motion it turns at half speed rather than stopping, because a still arc
/// reads as frozen.
///
/// One linear rotation animation on the render server, started in step with the clock so arcs side by side turn together; no work per
/// frame on the main thread.
@MainActor
final class UKArcSpinnerView: UIView {
    private let size: ArcSpinner.Size
    private let maxScale: CGFloat?
    private let ring = CAShapeLayer()
    private let top = CAShapeLayer()
    private let right = CAShapeLayer()
    private let spinner = CALayer()
    private var observers: UKObserverTokens?

    /// Holds this arc still (a UI test launch: a turning arc keeps XCUITest from ever seeing the app idle); the label still says busy.
    var isPaused = false { didSet { if isPaused != oldValue { syncAnimation() } } }

    /// The colour of the ring and its quarters.
    var color: UIColor = .label { didSet { updateColors() } }

    /// - Parameters:
    ///   - size: How big to draw it.
    ///   - label: What VoiceOver says: "Loading", or the action it stands for ("Sending Open").
    ///   - maxScale: The most the arc may grow with Dynamic Type, as a multiple of its default diameter; nil follows the text.
    init(_ size: ArcSpinner.Size = .page, label: String = "Loading", maxScale: CGFloat? = nil) {
        self.size = size
        self.maxScale = maxScale
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityTraits = .updatesFrequently
        // A status, not a control: the 16 pt inline arc would otherwise fail the audit's hit-area check.
        accessibilityRespondsToUserInteraction = false
        isUserInteractionEnabled = false
        for shape in [ring, top, right] {
            shape.fillColor = nil
            shape.lineCap = .butt
            spinner.addSublayer(shape)
        }
        layer.addSublayer(spinner)
        updateColors()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKArcSpinnerView, _) in
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }
        observers = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.syncAnimation() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var scale: CGFloat {
        ArcSpinner.scale(for: size, textScale: UKFont.scaled(1, relativeTo: .footnote, traits: traitCollection), maxScale: maxScale)
    }

    private var diameter: CGFloat { size.diameter * scale }

    override var intrinsicContentSize: CGSize { CGSize(width: diameter, height: diameter) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    private func updateColors() {
        ring.strokeColor = color.withAlphaComponent(0.22).cgColor
        top.strokeColor = color.withAlphaComponent(0.96).cgColor
        right.strokeColor = color.withAlphaComponent(0.72).cgColor
    }

    override var isHidden: Bool {
        didSet { if isHidden != oldValue { syncAnimation() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lineWidth = size.lineWidth * scale
        let side = min(bounds.width, bounds.height)
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spinner.frame = bounds
        for shape in [ring, top, right] {
            shape.frame = bounds
            shape.lineWidth = lineWidth
        }
        ring.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        // A quarter centred on the top (-90 degrees) and one on the trailing edge (0), like a CSS border side.
        top.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi * 3 / 4, endAngle: -.pi / 4, clockwise: true).cgPath
        right.path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: true).cgPath
        CATransaction.commit()
        syncAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncAnimation()
    }

    /// Spins unless animations are paused (XCUITest idling) or the view is off screen.
    private func syncAnimation() {
        spinner.removeAnimation(forKey: "spin")
        guard window != nil, !isHidden, !isPaused, !UKDesign.animationsPaused, bounds.width > 0 else { return }
        let period = UKDesign.reduceMotion ? ArcSpinner.period * 2 : ArcSpinner.period
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = period
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        // In step with the clock, so every arc on screen turns together (`ArcSpinner.angle(at:)`).
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        animation.timeOffset = phase
        animation.isRemovedOnCompletion = false
        spinner.add(animation, forKey: "spin")
    }
}

/// An indeterminate or determinate `ProgressView` as an arc with its title underneath (`ArcProgressViewStyle`), so a titled spinner
/// ("Loading recipes") keeps its words in the web's arc style. A determinate value keeps the arc too and speaks its percentage.
@MainActor
final class UKArcProgressView: UIView {
    private let spinner: UKArcSpinnerView
    private let titleLabel = UILabel()
    private let surface: TileSurface

    /// The fraction completed, or nil when the wait cannot be quantified.
    var fractionCompleted: Double? { didSet { accessibilityValue = ArcProgressViewStyle.spokenValue(fractionCompleted) } }

    init(title: String, size: ArcSpinner.Size = .page, surface: TileSurface = .page) {
        spinner = UKArcSpinnerView(size)
        self.surface = surface
        super.init(frame: .zero)
        // The title says what is loading, so the arc itself stays silent.
        spinner.isAccessibilityElement = false
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        // `.secondary` measured 3.1:1 over the wallpaper: a page title takes the wallpaper's secondary ink, a sheet's the sheet's.
        titleLabel.textColor = surface == .sheet ? UKInk.secondaryInSheet : UIColor(HassTokens.RGB.Surface.secondaryOnWallpaper)
        titleLabel.isAccessibilityElement = false
        addSubview(spinner)
        addSubview(titleLabel)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .updatesFrequently
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.preferred(.subheadline, traits: traitCollection)
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let arc = spinner.intrinsicContentSize
        let text = titleLabel.sizeThatFits(CGSize(width: size.width.isFinite ? size.width : .greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: max(arc.width, ceil(text.width)), height: arc.height + HassTokens.Spacing.s + ceil(text.height))
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let arc = spinner.intrinsicContentSize
        spinner.frame = CGRect(x: (bounds.width - arc.width) / 2, y: 0, width: arc.width, height: arc.height)
        let text = titleLabel.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        titleLabel.frame = CGRect(x: 0, y: arc.height + HassTokens.Spacing.s, width: bounds.width, height: ceil(text.height))
    }
}

/// The app icon's house and heart as one shape with no tile behind it (`HouseHeartShape`), filled with ``color``. The heart sits in
/// a ring cut out of the house, so the ring shows whatever is behind the view.
@MainActor
final class UKHouseHeartView: UIView {
    private let shape = CAShapeLayer()

    var color: UIColor = .label { didSet { shape.fillColor = color.cgColor } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        shape.fillColor = color.cgColor
        layer.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = HouseHeartShape().path(in: CGRect(origin: .zero, size: bounds.size)).cgPath
        CATransaction.commit()
    }
}
#endif
