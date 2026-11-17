#if os(iOS)
import Accessibility
import HassCore
import UIKit

// MARK: - Chart

/// One series as bars, a line or a line over a filled area, on an axis with thinned labels (`sh.chart@1`), drawn with Core Animation layers.
///
/// It is values only (``UKChartContent``, ``UKChartSpeech``): the binder reads the entities and the document and hands over one value. A new value
/// is a change of the layers' paths and of the label texts in place: the layers, the labels and the view stay, nothing is rebuilt, and nothing
/// moves unless the plot's size does. A chart does not animate (the Studio's chart has no `animates`), so there is no Reduce Motion path to
/// honour, and a scrolling page writes nothing per frame: the paths change only when ``apply(_:speech:)`` gets a different value or the width
/// changes.
///
/// For VoiceOver the chart is one element named by its label. Its value is always the series read out and it always carries an
/// `AXChartDescriptor`, so the Audio Graph plays the data, whether or not the document writes `a11y.value` (HIG, Charting data, Best practices). The axis, the marks and the labels are not read separately.
/// Axis levels, the unknown stub and the labels follow the appearance, so a chart in a light sheet reads as well as one on the dark page.
@MainActor
final class UKChartView: UIView, UKGridMeasuring, UKStackMeasuring, @preconcurrency AXChart {
    /// The audio graph of the series, always set with the speech.
    var accessibilityChartDescriptor: AXChartDescriptor?

    /// The value drawn now.
    private(set) var content: UKChartContent?
    /// How many times a value was drawn (a different value), for tests that a tick which changes nothing draws nothing.
    private(set) var drawCount = 0
    /// How many times the label views were created or removed, for tests that a new value of the same count rebuilds none.
    private(set) var labelBuildCount = 0

    private let plot = UIView()
    private let gridLayer = CAShapeLayer()
    private let barsLayer = CAShapeLayer()
    private let stubsLayer = CAShapeLayer()
    private let areaLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let dotsLayer = CAShapeLayer()
    private let emptyLabel = UILabel.uk(.body, ink: UKDesignInk.secondary, lines: 0, alignment: .natural)
    private var levelLabels: [UILabel] = []
    private var pointLabels: [UILabel] = []
    /// What the chart tells an assistive technology now.
    private(set) var speech: UKChartSpeech?

    /// Points between the axis labels and the plot, and between the plot and the labels under it.
    private let spacing: CGFloat = 4
    /// The padding above and below the empty text.
    private let emptyPadding: CGFloat = 12

    // MARK: Inspection (tests)

    /// The paths of the known bars, the stubs, the area and the line, and the visible label texts under the plot.
    var barPath: CGPath? { barsLayer.path }
    var stubPath: CGPath? { stubsLayer.path }
    var areaPath: CGPath? { areaLayer.path }
    var linePath: CGPath? { lineLayer.path }
    var dotPath: CGPath? { dotsLayer.path }
    /// The colour the marks are drawn in now (resolved for the view's appearance).
    var markColor: CGColor? { content?.mark == .bar ? barsLayer.fillColor : lineLayer.strokeColor }
    /// The plot's frame inside the view.
    var plotFrame: CGRect { plot.frame }
    /// The texts of the labels under the plot that show now.
    var shownPointLabels: [String] { pointLabels.filter { !$0.isHidden }.compactMap(\.text) }
    /// The texts of the axis levels, top to bottom.
    var axisTexts: [String] { levelLabels.compactMap(\.text) }
    /// The empty text, when it shows.
    var shownEmptyText: String? { emptyLabel.isHidden ? nil : emptyLabel.text }
    /// The identity of the plot's layers, for tests that an update keeps them.
    var layerIdentity: [ObjectIdentifier] { [gridLayer, barsLayer, stubsLayer, areaLayer, lineLayer, dotsLayer].map(ObjectIdentifier.init) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        plot.isUserInteractionEnabled = false
        addSubview(plot)
        for layer in [gridLayer, areaLayer, barsLayer, stubsLayer, lineLayer, dotsLayer] {
            plot.layer.addSublayer(layer)
        }
        syncContentsScale()
        lineLayer.fillColor = nil
        lineLayer.lineCap = .round
        lineLayer.lineJoin = .round
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKChartView, _) in view.setNeedsLayout() }
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: UKChartView, _) in view.syncContentsScale() }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKChartView, _) in
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
            view.ukRemeasureContainers(includingSelf: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Gives the plot's layers the view's display scale, so marks stay sharp when the view moves to another screen.
    private func syncContentsScale() {
        let scale = traitCollection.displayScale
        guard scale > 0 else { return }
        for layer in [gridLayer, areaLayer, barsLayer, stubsLayer, lineLayer, dotsLayer] { layer.contentsScale = scale }
    }

    // MARK: Applying a value

    /// Draws `value` and tells assistive technologies `speech`. The same value and speech change nothing.
    func apply(_ value: UKChartContent, speech: UKChartSpeech) {
        let contentChanged = value != content
        guard contentChanged || speech != self.speech else { return }
        self.speech = speech
        isAccessibilityElement = true
        accessibilityLabel = speech.label
        accessibilityValue = speech.series
        accessibilityTraits = .image
        accessibilityChartDescriptor = Self.descriptor(value, speech: speech)
        guard contentChanged else { return }
        let sizeChanged = content.map { $0.height != value.height || $0.hasData != value.hasData || $0.labels != value.labels
            || $0.emptyText != value.emptyText } ?? true
        content = value
        drawCount += 1
        syncLabels(for: value)
        if sizeChanged {
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(includingSelf: true)
        }
        setNeedsLayout()
    }

    /// The audio graph of a series: the labels along a category axis, the values on a numeric one, and a line for a line or an area.
    static func descriptor(_ content: UKChartContent, speech: UKChartSpeech) -> AXChartDescriptor {
        // Categories must be distinct for the graph, so a repeated or empty label gets its position.
        var seen = Set<String>()
        let categories = content.points.enumerated().map { index, point -> String in
            let name = point.label.isEmpty ? "\(index + 1)" : point.label
            return seen.insert(name).inserted ? name : "\(name) (\(index + 1))"
        }
        let top = max(content.top, content.base + 1)
        let step = (top - content.base) / Double(max(content.gridLines, 1))
        let xAxis = AXCategoricalDataAxisDescriptor(title: speech.label, categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(
            title: speech.label, range: content.base...top, gridlinePositions: (0...max(content.gridLines, 1)).map { content.base + step * Double($0) },
            valueDescriptionProvider: speech.describe)
        let points = zip(categories, content.points).map { category, point in
            AXDataPoint(x: category, y: point.value.flatMap { $0.isFinite ? $0 : nil }, additionalValues: [],
                        label: point.value.map { speech.describe($0) } ?? content.emptyText)
        }
        let series = AXDataSeriesDescriptor(name: speech.label, isContinuous: content.mark != .bar, dataPoints: points)
        return AXChartDescriptor(title: speech.label, summary: speech.series, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }

    /// Makes as many labels as the value needs, reusing the ones that are there, and sets their texts and inks.
    private func syncLabels(for value: UKChartContent) {
        let labelInk = value.labelInk ?? UKDesignInk.secondary
        func fit(_ labels: inout [UILabel], count: Int, alignment: NSTextAlignment) {
            while labels.count < count {
                let label = UILabel.uk(.caption1, monospacedDigit: true, ink: labelInk, lines: 1, alignment: alignment)
                label.lineBreakMode = .byClipping
                label.isAccessibilityElement = false
                addSubview(label)
                labels.append(label)
                labelBuildCount += 1
            }
            while labels.count > count {
                labels.removeLast().removeFromSuperview()
                labelBuildCount += 1
            }
            for label in labels { label.textColor = labelInk }
        }
        fit(&levelLabels, count: value.hasData ? (value.levelTexts?.count ?? 0) : 0, alignment: .right)
        for (label, text) in zip(levelLabels, value.levelTexts ?? []) { label.text = text }
        fit(&pointLabels, count: value.hasData && value.labels != .none ? value.points.count : 0, alignment: .left)
        for (label, point) in zip(pointLabels, value.points) { label.text = point.label }
        emptyLabel.text = value.emptyText
        emptyLabel.isHidden = value.hasData
        plot.isHidden = !value.hasData
    }

    // MARK: Measuring

    /// A label's line at the text size this view is shown at: the base height at the standard size, scaled by the view's own category (the labels follow
    /// their own traits, so a measure from the app-wide size would lag a window that sets its own).
    private func labelHeight() -> CGFloat {
        let base = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).lineHeight
        return ceil(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: base, compatibleWith: traitCollection))
    }

    private func measuredHeight(width: CGFloat) -> CGFloat {
        guard let content else { return 0 }
        guard content.hasData else {
            let text = content.emptyText as NSString
            let bounds = text.boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
                                           attributes: [.font: emptyLabel.font as Any], context: nil)
            return ceil(bounds.height) + emptyPadding * 2
        }
        return content.height + (content.labels == .none ? 0 : spacing + labelHeight())
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { measuredHeight(width: width) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight(width: bounds.width)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: measuredHeight(width: size.width)) }

    var stackNaturalWidth: CGFloat { 120 }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { true }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let content else { return }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let width = bounds.width
        if !content.hasData {
            emptyLabel.frame = CGRect(x: 0, y: emptyPadding, width: width, height: max(0, bounds.height - emptyPadding * 2))
            return
        }
        let lineHeight = labelHeight()
        // The axis column: as wide as its widest label, with a gap before the plot.
        let axisWidth = ceil(levelLabels.map { $0.sizeThatFits(CGSize(width: 1000, height: lineHeight)).width }.max() ?? 0)
        let plotX = axisWidth > 0 ? axisWidth + spacing : 0
        let plotWidth = max(0, width - plotX)
        let plotSize = CGSize(width: plotWidth, height: content.height)
        func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rtl ? width - x - w : x, y: y, width: w, height: h)
        }
        plot.frame = frame(plotX, 0, plotWidth, content.height)
        for (index, label) in levelLabels.enumerated() {
            let count = max(levelLabels.count - 1, 1)
            label.frame = frame(0, CGFloat(index) * (content.height - lineHeight) / CGFloat(count), axisWidth, lineHeight)
            label.textAlignment = rtl ? .left : .right
        }
        draw(content, in: plotSize, rtl: rtl)
        layoutPointLabels(content, plotX: plotX, plotWidth: plotWidth, lineHeight: lineHeight, frame: frame, rtl: rtl)
    }

    private func layoutPointLabels(_ content: UKChartContent, plotX: CGFloat, plotWidth: CGFloat, lineHeight: CGFloat,
                                   frame: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect, rtl: Bool) {
        guard content.labels != .none, !pointLabels.isEmpty else { return }
        let sizes = pointLabels.map { ceil($0.sizeThatFits(CGSize(width: 1000, height: lineHeight)).width) }
        let cadence = content.labels == .all ? 1
            : ServerUIChartMath.labelCadence(count: pointLabels.count, plotWidth: Double(plotWidth), widestLabelWidth: Double(sizes.max() ?? 0))
        let shown = Set(ServerUIChartMath.labelIndices(count: pointLabels.count, cadence: cadence))
        let slot = plotWidth / CGFloat(max(pointLabels.count, 1))
        for (index, label) in pointLabels.enumerated() {
            label.isHidden = !shown.contains(index)
            let x = content.mark == .bar ? plotX + CGFloat(index) * slot : plotX + (CGFloat(index) + 0.5) * slot - sizes[index] / 2
            label.frame = frame(x, content.height + spacing, sizes[index], lineHeight)
            label.textAlignment = rtl ? .right : .left
        }
    }

    /// Writes the paths and colours of the layers for `content` in a plot of `size`. No action runs: a change is not animated.
    private func draw(_ content: UKChartContent, in size: CGSize, rtl: Bool) {
        let traits = traitCollection
        func cg(_ color: UIColor) -> CGColor { color.resolvedColor(with: traits).cgColor }
        func mirrored(_ x: CGFloat, _ width: CGFloat = 0) -> CGFloat { rtl ? size.width - x - width : x }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for layer in [gridLayer, areaLayer, barsLayer, stubsLayer, lineLayer, dotsLayer] { layer.frame = CGRect(origin: .zero, size: size) }

        let grid = UIBezierPath()
        for index in 0..<max(content.gridLines, 0) {
            grid.append(UIBezierPath(rect: CGRect(x: 0, y: size.height * CGFloat(index) / CGFloat(content.gridLines), width: size.width, height: 1)))
        }
        gridLayer.path = grid.cgPath
        gridLayer.fillColor = cg(content.gridInk ?? UKDesignSurface.separator)

        let values = content.points.map(\.value)
        let tint = cg(content.tint)
        if content.mark == .bar {
            let marks = ServerUIChartMath.barMarks(values, top: content.top, base: content.base, width: Double(size.width), height: Double(size.height),
                                                   gap: Double(content.gap), minimum: Double(content.minimum))
            let known = UIBezierPath(), unknown = UIBezierPath()
            for mark in marks {
                let rect = CGRect(x: mirrored(CGFloat(mark.x), CGFloat(mark.width)), y: size.height - CGFloat(mark.height),
                                  width: CGFloat(mark.width), height: CGFloat(mark.height))
                guard rect.width > 0, rect.height > 0 else { continue }
                let rounded = UIBezierPath(roundedRect: rect, cornerRadius: min(content.radius, rect.width / 2, rect.height / 2))
                if mark.unknown { unknown.append(rounded) } else { known.append(rounded) }
            }
            barsLayer.path = known.cgPath
            stubsLayer.path = unknown.cgPath
            areaLayer.path = nil
            lineLayer.path = nil
            dotsLayer.path = nil
        } else {
            barsLayer.path = nil
            stubsLayer.path = nil
            let marks = ServerUIChartMath.pointMarks(values, top: content.top, base: content.base, width: Double(size.width), height: Double(size.height))
            // A line breaks where a value is unknown: one run of points for each stretch of known values.
            var runs: [[CGPoint]] = []
            for mark in marks {
                guard let y = mark.y else { runs.append([]); continue }
                if runs.isEmpty { runs.append([]) }
                runs[runs.count - 1].append(CGPoint(x: mirrored(CGFloat(mark.x)), y: CGFloat(y)))
            }
            let drawn = runs.filter { !$0.isEmpty }
            let line = UIBezierPath(), area = UIBezierPath(), dots = UIBezierPath()
            for run in drawn {
                line.move(to: run[0])
                run.dropFirst().forEach(line.addLine(to:))
                area.move(to: run[0])
                run.dropFirst().forEach(area.addLine(to:))
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: size.height))
                area.addLine(to: CGPoint(x: run[0].x, y: size.height))
                area.close()
                if content.dots {
                    let radius = max(2, content.lineWidth * 1.25)
                    for point in run { dots.append(UIBezierPath(arcCenter: point, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)) }
                }
            }
            lineLayer.path = line.cgPath
            lineLayer.strokeColor = tint
            lineLayer.lineWidth = content.lineWidth
            areaLayer.path = content.mark == .area ? area.cgPath : nil
            areaLayer.fillColor = tint
            areaLayer.opacity = 0.3
            dotsLayer.path = dots.cgPath
        }
        barsLayer.fillColor = tint
        dotsLayer.fillColor = tint
        stubsLayer.fillColor = cg(content.unknownInk ?? UIColor.label.withAlphaComponent(0.18))
    }
}
#endif
