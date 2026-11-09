#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Glyph

/// A condition glyph in multicolor SF Symbol rendering (`WeatherGlyph`). Its ink, not its frame, sits on the leading edge: the
/// symbol is drawn pulled left by the symbol's own empty space, and the view is that much narrower.
@MainActor
final class UKWeatherGlyphView: UIView {
    private let imageView = UIImageView()
    private var condition: String?
    private var night = false
    private let size: CGFloat

    /// - Parameter size: Point size at the default text size; grows with Dynamic Type, up to twice.
    init(condition: String?, night: Bool = false, size: CGFloat) {
        self.size = size
        super.init(frame: .zero)
        isAccessibilityElement = false
        imageView.tintColor = UKWeatherInk.onDark
        imageView.isAccessibilityElement = false
        imageView.contentMode = .topLeft
        addSubview(imageView)
        self.condition = condition
        self.night = night
        redraw()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKWeatherGlyphView, _) in
            view.redraw()
            view.invalidateIntrinsicContentSize()
            view.superview?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(condition: String?, night: Bool) {
        guard condition != self.condition || night != self.night else { return }
        self.condition = condition
        self.night = night
        redraw()
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    private var pointSize: CGFloat { size * min(UIFontMetrics.default.scaledValue(for: 1, compatibleWith: traitCollection), 2) }
    private var symbol: String { WeatherSymbols.condition(condition, night: night) }
    private var inset: CGFloat { WeatherSymbols.leadingInset(of: symbol) * pointSize }

    private func redraw() {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize).applying(UIImage.SymbolConfiguration.preferringMulticolor())
        imageView.image = UIImage(systemName: symbol, withConfiguration: configuration)
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let image = imageView.image?.size ?? .zero
        return CGSize(width: ceil(image.width - inset), height: ceil(image.height))
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let image = imageView.image?.size ?? .zero
        imageView.frame = CGRect(x: -inset, y: 0, width: image.width, height: image.height)
    }
}

// MARK: - Surface

/// The translucent-dark surface behind the sheet's sections and highlight tiles (`weatherSurface`): a darkening wash with a hairline
/// edge. Content goes in ``stack``.
@MainActor
final class UKWeatherSurfaceView: UIView {
    let stack = UIStackView()

    init(padding: CGFloat = HassTokens.Spacing.l, spacing: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.28)
        layer.cornerRadius = HassTokens.Radius.tile
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UKWeatherInk.onDark.withAlphaComponent(0.14).cgColor
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Rail

/// A horizontal gauge: a track, an optional coloured span and an optional marker (`WeatherRail`). Decorative. A change glides unless
/// Reduce Motion is on.
@MainActor
final class UKWeatherRailView: UIView {
    /// What the rail measures; picks the colours.
    enum Tone {
        case aqi, feels, precipitation, temperature, uv, visibility

        /// Gradient stops across the full track.
        var colors: [UIColor] {
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
            switch self {
            case .temperature: return [color(0.36, 0.80, 1.0), color(1.0, 0.85, 0.30), color(1.0, 0.55, 0.20)]
            case .feels: return [color(0.36, 0.80, 1.0), color(0.85, 0.88, 0.92), color(1.0, 0.55, 0.20)]
            case .precipitation: return [color(0.35, 0.70, 1.0), color(0.35, 0.70, 1.0)]
            case .visibility: return [color(0.75, 0.80, 0.86), .white]
            case .uv: return [color(0.30, 0.85, 0.45), color(1.0, 0.85, 0.25), color(1.0, 0.55, 0.20), color(0.95, 0.30, 0.30), color(0.70, 0.40, 0.95)]
            case .aqi: return [color(0.30, 0.85, 0.45), color(1.0, 0.85, 0.25), color(1.0, 0.55, 0.20), color(0.95, 0.30, 0.30), color(0.70, 0.40, 0.95), color(0.65, 0.20, 0.30)]
            }
        }

        /// Scale tones colour the whole track; range tones colour only the span.
        var isScale: Bool { self == .aqi || self == .feels || self == .uv }
    }

    private let tone: Tone
    private var range: WeatherRailRange
    private let track = UIView()
    private let span = UIView()
    private let gradient = CAGradientLayer()
    private let marker = UIView()
    private var didLayout = false

    init(tone: Tone, range: WeatherRailRange = WeatherRailRange()) {
        self.tone = tone
        self.range = range
        super.init(frame: .zero)
        isAccessibilityElement = false
        track.backgroundColor = UKWeatherInk.onDark.withAlphaComponent(0.22)
        // The gradient rounds itself (no masksToBounds): a clipped container with a sublayer costs an offscreen mask pass per bar.
        gradient.colors = tone.colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        span.layer.addSublayer(gradient)
        marker.backgroundColor = UKWeatherInk.onDark
        marker.layer.borderWidth = 1.5
        marker.layer.borderColor = UIColor.black.withAlphaComponent(0.45).cgColor
        marker.layer.cornerRadius = 6
        for view in [track, span, marker] { view.isUserInteractionEnabled = false; addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: 48, height: 12) }

    /// Moves the span and marker to a new range.
    func update(_ range: WeatherRailRange) {
        guard range != self.range else { return }
        self.range = range
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else {
            applyFrames()
            return
        }
        UIView.animate(withDuration: MotionTokens.standardDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { self.applyFrames() }
    }

    private func clamp(_ value: Double) -> Double { min(100, max(0, value.isFinite ? value : 0)) }

    private func applyFrames() {
        let width = bounds.width
        let start = clamp(tone.isScale ? 0 : range.rangeStartPercent ?? 0)
        let size = tone.isScale ? 100 : min(clamp(range.rangeSizePercent ?? 0), 100 - start)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func x(_ origin: CGFloat, _ length: CGFloat) -> CGFloat { mirror ? width - origin - length : origin }
        track.frame = bounds
        track.layer.cornerRadius = bounds.height / 2
        let spanWidth = width * size / 100
        span.frame = CGRect(x: x(width * start / 100, spanWidth), y: 0, width: spanWidth, height: bounds.height)
        span.alpha = size > 0 ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = span.bounds
        gradient.cornerRadius = bounds.height / 2
        gradient.startPoint = CGPoint(x: mirror ? 1 : 0, y: 0.5)
        gradient.endPoint = CGPoint(x: mirror ? 0 : 1, y: 0.5)
        CATransaction.commit()
        if let value = range.markerPercent, value.isFinite {
            let offset = max(0, min(width - 12, width * clamp(value) / 100 - 6))
            marker.frame = CGRect(x: x(offset, 12), y: (bounds.height - 12) / 2, width: 12, height: 12)
            marker.alpha = 1
        } else {
            marker.alpha = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFrames()
    }
}

// MARK: - Bar chart

/// A small column chart for hourly precipitation chance, accumulation, humidity and cloud cover (`WeatherBarChart`): bars scaled to
/// a "nice" domain, a three-level y axis and a thinned row of hour labels. Decorative for VoiceOver.
@MainActor
final class UKWeatherBarChartView: UIView, UKGridMeasuring {
    private let values: [Double?]
    private let domain: Double
    private let hourLabels: [String]
    private let tint: UIColor
    private let axisLabels: [UILabel]
    private var hourViews: [UILabel] = []
    private var lines: [UIView] = []
    private var bars: [UIView] = []
    private let plotHeight: CGFloat = 76

    init(values: [Double?], domain: Double, axisLabels: (high: String, middle: String, low: String), hourLabels: [String], tint: UIColor) {
        self.values = values
        self.domain = domain
        self.hourLabels = hourLabels
        self.tint = tint
        self.axisLabels = [axisLabels.high, axisLabels.middle, axisLabels.low].map { text in
            let label = UILabel.uk(.caption1, ink: UKWeatherInk.onDarkSecondary, lines: 1, alignment: .right)
            label.text = text
            return label
        }
        super.init(frame: .zero)
        isAccessibilityElement = false
        self.axisLabels.forEach(addSubview)
        for _ in 0..<3 {
            let line = UIView()
            line.backgroundColor = UKWeatherInk.onDark.withAlphaComponent(0.14)
            addSubview(line)
            lines.append(line)
        }
        for value in values {
            let bar = UIView()
            bar.layer.cornerRadius = 2
            bar.layer.cornerCurve = .continuous
            bar.backgroundColor = value == nil ? UKWeatherInk.onDark.withAlphaComponent(0.18) : tint
            addSubview(bar)
            bars.append(bar)
        }
        for text in hourLabels {
            let label = UILabel.uk(.caption1, ink: UKWeatherInk.onDarkSecondary, lines: 1)
            label.text = text
            label.lineBreakMode = .byClipping
            addSubview(label)
            hourViews.append(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func axisWidth() -> CGFloat { ceil(axisLabels.map { $0.sizeThatFits(CGSize(width: 1000, height: 100)).width }.max() ?? 0) }
    private func rowHeight() -> CGFloat { ceil(axisLabels.first?.sizeThatFits(CGSize(width: 1000, height: 100)).height ?? 0) }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { plotHeight + HassTokens.Spacing.xs + rowHeight() }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let axis = axisWidth()
        let plotX = axis + HassTokens.Spacing.xs
        let plotWidth = max(0, bounds.width - plotX)
        func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: mirror ? bounds.width - x - width : x, y: y, width: width, height: height)
        }
        let labelHeight = rowHeight()
        axisLabels[0].frame = frame(0, 0, axis, labelHeight)
        axisLabels[1].frame = frame(0, (plotHeight - labelHeight) / 2, axis, labelHeight)
        axisLabels[2].frame = frame(0, plotHeight - labelHeight, axis, labelHeight)
        let block = plotHeight / 3
        for (index, line) in lines.enumerated() { line.frame = frame(plotX, block * CGFloat(index), plotWidth, 1) }
        let count = max(values.count, 1)
        let column = (plotWidth - 2 * CGFloat(count - 1)) / CGFloat(count)
        for (index, bar) in bars.enumerated() {
            let percent = WeatherPrecipitationTimeline.scaledPercent(values[index], domain: domain)
            let height = values[index] == nil ? 2 : max(percent > 0 ? 2 : 0, plotHeight * percent / 100)
            bar.frame = frame(plotX + CGFloat(index) * (column + 2), plotHeight - height, max(0, column), height)
        }
        let scale = UIFontMetrics(forTextStyle: .caption1).scaledValue(for: 1, compatibleWith: traitCollection)
        let widest = Double(hourLabels.map(\.count).max() ?? 3) * 7.2 * Double(min(scale, 2.5))
        let cadence = WeatherPrecipitationTimeline.labelCadence(count: hourLabels.count, plotWidth: Double(plotWidth), widestLabelWidth: widest)
        let shown = Set(WeatherPrecipitationTimeline.labelIndices(count: hourLabels.count, cadence: cadence))
        for (index, label) in hourViews.enumerated() {
            label.isHidden = !shown.contains(index)
            let size = label.sizeThatFits(CGSize(width: 1000, height: 100))
            label.frame = frame(plotX + CGFloat(index) * (column + 2), plotHeight + HassTokens.Spacing.xs, ceil(size.width), labelHeight)
            label.textAlignment = mirror ? .right : .left
        }
    }
}

// MARK: - Compass

/// The arrow drawn at 0 degrees: the head points down (the wind blows toward 180) and the dot sits on top (the source)
/// (`WindNeedle`).
final class UKWindNeedleView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        let size = min(bounds.width, bounds.height)
        let x = (bounds.width - size) / 2, y = (bounds.height - size) / 2
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x + size * px, y: y + size * py) }
        let head = UIBezierPath()
        head.move(to: point(0.45, 0.50))
        head.addLine(to: point(0.55, 0.50))
        head.addLine(to: point(0.50, 0.74))
        head.close()
        UKWeatherInk.amber.setFill()
        head.fill()
        let tail = UIBezierPath()
        tail.move(to: point(0.45, 0.50))
        tail.addLine(to: point(0.55, 0.50))
        tail.addLine(to: point(0.52, 0.32))
        tail.addLine(to: point(0.48, 0.32))
        tail.close()
        UKWeatherInk.onDark.withAlphaComponent(0.55).setFill()
        tail.fill()
        UKWeatherInk.onDark.setFill()
        let dot = size * 0.07
        UIBezierPath(ovalIn: CGRect(x: point(0.5, 0.29).x - dot / 2, y: point(0.5, 0.29).y - dot / 2, width: dot, height: dot)).fill()
    }
}

/// The wind compass: 48 ticks, a north marker, cardinal letters and, when the wind has a direction, an arrow that points where the
/// wind blows to with a dot at the side it comes from (`WeatherCompass`). Decorative. The needle turns the short way round and does
/// not animate when Reduce Motion is on.
@MainActor
final class UKWeatherCompassView: UIView {
    private let ticks = UKCompassTicksView()
    private let needle = UKWindNeedleView()
    private var letters: [(UILabel, CGFloat, CGFloat)] = []
    private var sourceDegrees: Double?
    private var angle: Double?

    init(sourceDegrees: Double?) {
        self.sourceDegrees = sourceDegrees
        super.init(frame: .zero)
        isAccessibilityElement = false
        addSubview(ticks)
        for (text, x, y) in [("N", 0.0, -0.58), ("E", 0.58, 0.0), ("W", -0.58, 0.0), ("S", 0.0, 0.58)] {
            if sourceDegrees == nil, text == "E" || text == "W" { continue }
            let label = UILabel()
            label.text = text
            label.textColor = UKWeatherInk.onDark
            label.textAlignment = .center
            addSubview(label)
            letters.append((label, CGFloat(x), CGFloat(y)))
        }
        addSubview(needle)
        needle.isHidden = sourceDegrees == nil
        angle = sourceDegrees
        needle.transform = CGAffineTransform(rotationAngle: CGFloat((angle ?? 0) * .pi / 180))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Turns the needle to a new source bearing.
    func update(sourceDegrees new: Double?) {
        guard new != sourceDegrees else { return }
        sourceDegrees = new
        guard let new else {
            angle = nil
            needle.isHidden = true
            return
        }
        needle.isHidden = false
        // Unwrap so a 350 to 10 change turns 20 degrees, not 340.
        let from = angle ?? new
        let target = from + WeatherPresentation.shortestBearingDelta(from: from, to: new)
        angle = target
        let apply = { self.needle.transform = CGAffineTransform(rotationAngle: CGFloat(target * .pi / 180)) }
        if window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(springDuration: MotionTokens.standardDuration, bounce: 0, options: [.allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        let box = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let radius = side / 2
        ticks.frame = box
        let transform = needle.transform
        needle.transform = .identity
        needle.frame = box
        needle.transform = transform
        let font = UIFont.systemFont(ofSize: max(10, radius * 0.2), weight: .semibold).rounded()
        for (label, x, y) in letters {
            label.font = font
            label.sizeToFit()
            label.center = CGPoint(x: box.midX + radius * x, y: box.midY + radius * y)
        }
    }
}

private extension UIFont {
    /// The rounded design of this font (`design: .rounded`).
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// The compass's ticks and north marker.
private final class UKCompassTicksView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        let radius = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath()
        for index in 1..<48 {
            let long = index % 2 == 0
            let theta = Double(index) * (.pi * 2 / 48) - .pi / 2
            let inner = radius * (long ? 0.80 : 0.85)
            path.move(to: CGPoint(x: center.x + cos(theta) * radius * 0.92, y: center.y + sin(theta) * radius * 0.92))
            path.addLine(to: CGPoint(x: center.x + cos(theta) * inner, y: center.y + sin(theta) * inner))
        }
        path.lineWidth = 1.2
        UIColor.white.withAlphaComponent(0.55).setStroke()
        path.stroke()
        let north = UIBezierPath()
        north.move(to: CGPoint(x: center.x, y: center.y - radius * 0.94))
        north.addLine(to: CGPoint(x: center.x + radius * 0.06, y: center.y - radius * 0.84))
        north.addLine(to: CGPoint(x: center.x - radius * 0.06, y: center.y - radius * 0.84))
        north.close()
        UIColor.white.setFill()
        north.fill()
    }
}

// MARK: - Pressure gauge

/// The barometer: 49 ticks over a 250 degree arc with the current reading's tick lit (`WeatherPressureGauge`). The value and unit
/// are real text centred in the dial so they scale with Dynamic Type.
@MainActor
final class UKWeatherPressureGaugeView: UIView, UKGridMeasuring {
    private let percent: Double
    private let valueLabel = UILabel.uk(.title3, weight: .bold, monospacedDigit: true, ink: UKWeatherInk.onDark, lines: 1, alignment: .center)
    private let unitLabel = UILabel.uk(.caption1, ink: UKWeatherInk.onDarkSecondary, lines: 1, alignment: .center)

    init(percent: Double, value: String, unit: String?) {
        self.percent = percent
        super.init(frame: .zero)
        isAccessibilityElement = false
        backgroundColor = .clear
        valueLabel.text = value
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.adjustsFontSizeToFitWidth = true
        unitLabel.text = unit
        unitLabel.isHidden = unit == nil
        addSubview(valueLabel)
        addSubview(unitLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { width / 1.4 }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: size.width / 1.4) }

    private func tick(_ percent: Double, inner: Double, outer: Double, center: CGPoint, radius: CGFloat) -> UIBezierPath {
        let angle = (145 + min(100, max(0, percent)) / 100 * 250) * .pi / 180
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x + cos(angle) * radius * inner, y: center.y + sin(angle) * radius * inner))
        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * outer, y: center.y + sin(angle) * radius * outer))
        return path
    }

    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: bounds.width / 2, y: bounds.height * 0.56)
        let radius = min(bounds.width, bounds.height * 1.4) / 2
        let ticks = UIBezierPath()
        for index in 0..<49 {
            ticks.append(tick(Double(index) / 48 * 100, inner: 0.78, outer: 0.92, center: center, radius: radius))
        }
        ticks.lineWidth = 1.4
        UIColor.white.withAlphaComponent(0.5).setStroke()
        ticks.stroke()
        let lit = tick(percent, inner: 0.70, outer: 0.98, center: center, radius: radius)
        lit.lineWidth = 3
        lit.lineCapStyle = .round
        UKWeatherInk.amber.setStroke()
        lit.stroke()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let value = valueLabel.sizeThatFits(CGSize(width: bounds.width, height: 200))
        let unit = unitLabel.isHidden ? CGSize.zero : unitLabel.sizeThatFits(CGSize(width: bounds.width, height: 200))
        let total = ceil(value.height) + ceil(unit.height)
        let top = (bounds.height - total) / 2 + 4
        valueLabel.frame = CGRect(x: 0, y: top, width: bounds.width, height: ceil(value.height))
        unitLabel.frame = CGRect(x: 0, y: top + ceil(value.height), width: bounds.width, height: ceil(unit.height))
        setNeedsDisplay()
    }
}

// MARK: - Sun arc

/// The daylight arc with the sun at its progress (`WeatherSunArc`).
final class UKWeatherSunArcView: UIView, UKGridMeasuring {
    private let percent: Double?

    init(percent: Double?) {
        self.percent = percent
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The arc is as wide as the tile allows, up to 200 pt, and 100:48.
    func gridHeight(forWidth width: CGFloat) -> CGFloat { min(width, 200) * 48 / 100 }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: min(size.width, 200), height: gridHeight(forWidth: size.width)) }

    override func draw(_ rect: CGRect) {
        let drawWidth = min(bounds.width, 200)
        let scaleX = drawWidth / 100, scaleY = drawWidth * 48 / 100 / 48
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * scaleX, y: y * scaleY) }
        let horizon = UIBezierPath()
        horizon.move(to: point(4, 40))
        horizon.addLine(to: point(96, 40))
        horizon.lineWidth = 1
        UIColor.white.withAlphaComponent(0.35).setStroke()
        horizon.stroke()
        let arc = UIBezierPath()
        arc.move(to: point(8, 40))
        arc.addQuadCurve(to: point(92, 40), controlPoint: point(50, 4))
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        arc.setLineDash([3, 4], count: 2, phase: 0)
        UIColor.white.withAlphaComponent(0.6).setStroke()
        arc.stroke()
        if let percent {
            let marker = WeatherPresentation.sunArcMarker(percent: percent)
            let center = point(marker.x, marker.y)
            UIColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)).fill()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
}

// MARK: - Tile

/// A highlight tile: a small title with an icon, then the tile's content (`WeatherTile`). Read as one element with the web's
/// aria-label, e.g. `Feels Like 75°F`.
@MainActor
final class UKWeatherTileView: UIView, UKGridMeasuring {
    let surface = UKWeatherSurfaceView(padding: HassTokens.Spacing.m, spacing: HassTokens.Spacing.s)

    init(title: String, symbol: String, label: String, identifier: String, value: String?, content: UIView) {
        super.init(frame: .zero)
        let icon = UIImageView()
        icon.tintColor = UKWeatherInk.onDarkSecondary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let caption = UILabel.uk(.footnote, weight: .semibold, ink: UKWeatherInk.onDarkSecondary)
        caption.text = title
        let header = UIStackView(arrangedSubviews: [icon, caption])
        header.axis = .horizontal
        header.alignment = .firstBaseline
        header.spacing = HassTokens.Spacing.xs
        ukOnContentSizeChange { [weak self, weak icon] in
            icon?.image = UKFont.symbol(symbol, style: .footnote, weight: .semibold, traits: self?.traitCollection)
        }
        surface.stack.addArrangedSubview(header)
        surface.stack.addArrangedSubview(content)
        surface.translatesAutoresizingMaskIntoConstraints = true
        addSubview(surface)
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityValue = value ?? ""
        accessibilityIdentifier = identifier
        [icon, caption, header, content].forEach { $0.isAccessibilityElement = false }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(surface.systemLayoutSizeFitting(CGSize(width: max(1, width), height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
    }
}
#endif
