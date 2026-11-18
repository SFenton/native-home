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
        guard window != nil, !UKMotion.reduceMotion else {
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

/// The wind compass: 48 ticks, a north marker, cardinal letters and, when the wind has a direction, an arrow that points where the wind blows to
/// with a dot at the side it comes from (`WeatherCompass`). Decorative. It is a `dial` (``WeatherDialSpecs/compass()``) drawn by ``UKDialView``, the
/// app's one dial: the needle turns the short way round and does not animate when Reduce Motion is on.
@MainActor
final class UKWeatherCompassView: UIView {
    private let dial = UKDialView()
    private var sourceDegrees: Double?

    init(sourceDegrees: Double?) {
        self.sourceDegrees = sourceDegrees
        super.init(frame: .zero)
        isAccessibilityElement = false
        addSubview(dial)
        show()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKWeatherCompassView, _) in view.invalidateIntrinsicContentSize() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The dial this compass draws through.
    var face: UKDialView { dial }

    /// Turns the needle to a new source bearing.
    func update(sourceDegrees new: Double?) {
        guard new != sourceDegrees else { return }
        sourceDegrees = new
        show()
    }

    private func show() {
        dial.apply(WeatherDialSpecs.compass(), reading: UKDialReading(value: sourceDegrees), speech: .hidden)
    }

    /// 104 pt, scaled with the footnote size up to 160.
    override var intrinsicContentSize: CGSize { dial.intrinsicContentSize }
    override func sizeThatFits(_ size: CGSize) -> CGSize { dial.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        dial.frame = bounds
    }
}

// MARK: - Pressure gauge

/// The barometer: 49 ticks over a 250 degree arc with the current reading's tick lit (`WeatherPressureGauge`). The value and unit are real text
/// centred in the dial so they scale with Dynamic Type. It is a `dial` (``WeatherDialSpecs/barometer(hasUnit:)``) drawn by ``UKDialView``.
@MainActor
final class UKWeatherPressureGaugeView: UIView, UKGridMeasuring {
    private let dial = UKDialView()

    init(percent: Double, value: String, unit: String?) {
        super.init(frame: .zero)
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(dial)
        dial.apply(WeatherDialSpecs.barometer(hasUnit: unit != nil), reading: UKDialReading(value: percent, lines: [.text(value)] + (unit.map { [.text($0)] } ?? [])),
                   speech: .hidden)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The dial this gauge draws through.
    var face: UKDialView { dial }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { dial.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        dial.frame = bounds
    }
}

// MARK: - Sun arc

/// The daylight arc with the sun at its progress (`WeatherSunArc`). It is an `arc-track` (``WeatherDialSpecs/sunArc()``) drawn by
/// ``UKArcTrackView``.
@MainActor
final class UKWeatherSunArcView: UIView, UKGridMeasuring {
    private let arc = UKArcTrackView()

    init(percent: Double?) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        addSubview(arc)
        arc.apply(WeatherDialSpecs.sunArc(), progress: percent, speech: .hidden)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The arc this view draws through.
    var track: UKArcTrackView { arc }

    /// The arc is as wide as the tile allows, up to 200 pt, and 100:48.
    func gridHeight(forWidth width: CGFloat) -> CGFloat { arc.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { arc.sizeThatFits(CGSize(width: size.width, height: size.height)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        arc.frame = bounds
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
