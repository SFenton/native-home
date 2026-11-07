#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The condition-aware gradient behind the weather sheet (`WeatherBackdrop`, web `WeatherAtmosphere`). Every scene is dark enough for
/// white text at 4.5:1 or better. Decoration (stars, cloud banks, rain, snow) is drawn at low opacity and only animates when Reduce
/// Motion is off; with Reduce Transparency on, it is left out and the gradient stays solid.
@MainActor
final class UKWeatherBackdropView: UIView {
    private let gradient = CAGradientLayer()
    private let decoration = UKWeatherDecorationView()
    private(set) var scene: WeatherScene
    private var tokens: UKObserverTokens?

    init(scene: WeatherScene) {
        self.scene = scene
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        addSubview(decoration)
        apply()
        tokens = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.apply() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(scene new: WeatherScene) {
        guard new != scene else { return }
        scene = new
        apply()
    }

    private func apply() {
        let colors = WeatherBackdrop.colors(for: scene)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [UIColor(colors.top).cgColor, UIColor(colors.bottom).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        CATransaction.commit()
        decoration.isHidden = UIAccessibility.isReduceTransparencyEnabled
        decoration.configure(scene: scene, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// The sheet's base colour, for the ground behind the page.
    var baseColor: UIColor { UIColor(WeatherBackdrop.colorTokens(for: scene).bottom) }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        decoration.frame = bounds
    }
}

/// Low-opacity scene decoration (`WeatherDecoration`). Rain and snow fall as five static shape layers (one per fall speed) that a
/// repeating `CABasicAnimation` slides down at 24 frames a second: the render server moves them with no main-thread work and no
/// path rebuilt per frame (the display-link version rewrote one path 24 times a second, which the render server re-rasterized, and
/// was 700 ms of idle render server CPU per 8 s). The animation runs only while the view is on screen, the app is active and
/// motion is allowed.
@MainActor
final class UKWeatherDecorationView: UIView {
    private var scene: WeatherScene = .neutral
    private var animated = true
    private var layers: [CAShapeLayer] = []
    private var builtFor: String?
    private var observers: UKObserverTokens?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        clipsToBounds = true
        observers = UKObserverTokens([UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncAnimation() }
            }
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(scene: WeatherScene, animated: Bool) {
        self.scene = scene
        self.animated = animated
        setNeedsDisplay()
        rebuild()
    }

    private var fallingSpec: (count: Int, slant: Double, length: Double, opacity: Double)? {
        switch scene {
        case .rain, .storm: (36, 0.18, 26, 0.16)
        case .snow: (30, 0.04, 5, 0.30)
        default: nil
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncAnimation()
    }

    private static let speedClasses = 5

    /// Builds the five layers for the current scene and size: every streak's start is where the old phase 0 put it.
    private func rebuild() {
        let size = bounds.size
        guard let spec = fallingSpec, size.width > 0, size.height > 0 else {
            layers.forEach { $0.removeFromSuperlayer() }
            layers = []
            builtFor = nil
            return
        }
        let key = "\(scene)|\(size.width)|\(size.height)"
        guard key != builtFor else { return }
        builtFor = key
        layers.forEach { $0.removeFromSuperlayer() }
        layers = []
        let travel = size.height + spec.length
        let paths = (0..<Self.speedClasses).map { _ in CGMutablePath() }
        for index in 0..<spec.count {
            let seed = Double(index) * 0.618033988
            let x = seed.truncatingRemainder(dividingBy: 1) * size.width
            let progress = (seed * 3).truncatingRemainder(dividingBy: 1)
            let y = progress * travel - spec.length
            // The streak and its copy one fall above it, so the slide wraps without a gap.
            for offset in [travel, 0] as [Double] {
                paths[index % Self.speedClasses].move(to: CGPoint(x: x, y: y + offset))
                paths[index % Self.speedClasses].addLine(to: CGPoint(x: x + spec.length * spec.slant, y: y + offset + spec.length))
            }
        }
        for (index, path) in paths.enumerated() {
            let layer = CAShapeLayer()
            layer.anchorPoint = .zero
            layer.bounds = CGRect(x: 0, y: 0, width: size.width, height: 2 * travel)
            layer.position = CGPoint(x: 0, y: -travel)
            layer.path = path
            layer.fillColor = nil
            layer.lineCap = .butt
            layer.strokeColor = UIColor.white.withAlphaComponent(spec.opacity).cgColor
            layer.lineWidth = spec.length > 10 ? 1 : 2.5
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull()]
            self.layer.addSublayer(layer)
            layers.append(layer)
            _ = index
        }
        syncAnimation()
    }

    private func syncAnimation() {
        let shouldRun = fallingSpec != nil && animated && window != nil && UIApplication.shared.applicationState == .active && !UKDesign.animationsPaused
        for (index, layer) in layers.enumerated() {
            guard shouldRun, let spec = fallingSpec else {
                layer.removeAnimation(forKey: "fall")
                continue
            }
            if layer.animation(forKey: "fall") != nil { continue }
            let travel = bounds.height + spec.length
            let speed = 0.12 + Double(index) * 0.03
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = -travel
            fall.toValue = 0
            fall.duration = 1 / speed
            fall.repeatCount = .infinity
            fall.timingFunction = CAMediaTimingFunction(name: .linear)
            fall.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            fall.isRemovedOnCompletion = false
            layer.add(fall, forKey: "fall")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuild()
    }

    // MARK: Still decoration

    private struct Star { var x: Double; var y: Double; var size: Double; var opacity: Double }

    private static let stars: [Star] = (0..<34).map { index in
        let x = (Double(index) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let y = (Double(index) * 0.3247179572 + 0.17).truncatingRemainder(dividingBy: 1)
        return Star(x: x, y: y, size: index % 7 == 0 ? 2.4 : index % 3 == 0 ? 1.8 : 1.2, opacity: index % 7 == 0 ? 0.5 : 0.24 + Double(index % 4) * 0.04)
    }

    private static let banks: [(x: Double, y: Double, width: Double)] = [
        (-0.1, 0.08, 0.7), (0.4, 0.22, 0.8), (-0.05, 0.42, 0.65), (0.5, 0.6, 0.7), (0.0, 0.78, 0.75),
    ]

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let size = bounds.size
        switch scene {
        case .night:
            for star in Self.stars {
                context.setFillColor(UIColor.white.withAlphaComponent(star.opacity).cgColor)
                context.fillEllipse(in: CGRect(x: star.x * size.width, y: star.y * size.height * 0.7, width: star.size, height: star.size))
            }
        case .clouds, .fog, .wind, .neutral, .exceptional:
            for (index, bank) in Self.banks.enumerated() {
                let rect = CGRect(x: bank.x * size.width, y: bank.y * size.height, width: size.width * bank.width, height: size.height * 0.16)
                let opacity = scene == .fog ? 0.07 : 0.045 + Double(index % 2) * 0.015
                UIColor.white.withAlphaComponent(opacity).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
            }
        case .sunny:
            context.saveGState()
            context.addEllipse(in: CGRect(x: size.width * 0.55, y: -size.height * 0.12, width: size.width * 0.9, height: size.width * 0.9))
            context.clip()
            let colors = [UIColor.white.withAlphaComponent(0.16).cgColor, UIColor.clear.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: size.width, y: 0), startRadius: 0,
                                           endCenter: CGPoint(x: size.width, y: 0), endRadius: size.width * 0.5, options: [])
            }
            context.restoreGState()
        case .rain, .storm, .snow:
            break
        }
    }
}
#endif
