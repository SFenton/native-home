#if os(iOS)
import HassCore
import UIKit

// MARK: - Arc track

/// A curve with a horizon and a marker at its progress (`sh.arc-track@1`): the weather panel's daylight arc made generic.
///
/// It takes the document's arc (a value: curve, box, inks, widths) and the progress read from it, and places the parts with ``ServerUIArcLayout``,
/// the arithmetic the shared corpus pins. The arc is as wide as the room allows up to its `maxWidth`, sits at the leading edge when it mirrors (the left otherwise), and is as tall as the
/// box's shape gives. Positions scale with the width; line widths, dashes and the marker are points and do not. The curve has a round cap and the
/// horizon a butt cap (the schema has no cap, so every arc draws them so). The marker moves at once: the sun's progress is a slow reading and the
/// contract gives an arc no glide.
///
/// For VoiceOver the arc is hidden, or one element named by the document whose value is its text or the marker's percent (HIG, Accessibility). It
/// mirrors in a right-to-left language unless the document says it does not.
@MainActor
final class UKArcTrackView: UIView, UKGridMeasuring, UKStackMeasuring {
    private(set) var arc: ServerUIArcTrack?
    /// The progress now drawn, in the arc's own scale.
    private(set) var progress: Double?
    /// How many times a progress or an arc changed what was drawn.
    private(set) var drawCount = 0
    /// What was last placed, for tests.
    private(set) var placed: ServerUIArcLayout.Layout?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKArcTrackView, _) in view.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Applying

    /// Draws `arc` with `progress`. Nothing changes when both are what is drawn.
    func apply(_ arc: ServerUIArcTrack, progress: Double?, speech: UKGaugeSpeech) {
        applySpeech(speech, progress: progress, arc: arc)
        let lookChanged = self.arc != arc
        guard lookChanged || progress != self.progress else { return }
        self.arc = arc
        self.progress = progress
        drawCount += 1
        if lookChanged {
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(includingSelf: true)
        }
        setNeedsDisplay()
    }

    private func applySpeech(_ value: UKGaugeSpeech, progress: Double?, arc: ServerUIArcTrack) {
        switch value {
        case .hidden:
            isAccessibilityElement = false
            accessibilityLabel = nil
            accessibilityValue = nil
        case .value(let label, let text):
            isAccessibilityElement = true
            accessibilityTraits = .none
            accessibilityLabel = label
            let percent = arc.marker == nil ? nil : ServerUIArcLayout.progress(progress, scale: arc.scale).map { $0 * 100 }
            accessibilityValue = (text?.isEmpty == false ? text : nil) ?? percent.map { "\(Int($0.rounded()))%" }
        }
    }

    // MARK: Measuring

    private func drawWidth(forAvailable width: CGFloat) -> CGFloat { min(width, CGFloat(arc?.maxWidth ?? .infinity)) }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let arc else { return 0 }
        return drawWidth(forAvailable: width) * CGFloat(arc.box.height / arc.box.width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: drawWidth(forAvailable: size.width), height: gridHeight(forWidth: size.width)) }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: bounds.width > 0 ? gridHeight(forWidth: bounds.width) : UIView.noIntrinsicMetric)
    }
    var stackNaturalWidth: CGFloat { CGFloat(arc?.maxWidth ?? 100) }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { true }

    // MARK: Drawing

    /// Where the arc's left edge was drawn across the view, for tests of the direction.
    private(set) var drawnOrigin: CGFloat = 0

    override func draw(_ rect: CGRect) {
        guard let arc else { return }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let width = drawWidth(forAvailable: bounds.width)
        let layout = ServerUIArcLayout.layoutArc(arc.layoutInput(width: Double(width), value: progress, rtl: rtl))
        placed = layout
        // An arc that mirrors stands at the leading edge of the room it has; one that does not stands where a left-to-right layout puts it.
        let origin = rtl && arc.mirrors ? bounds.width - CGFloat(layout.width) : 0
        drawnOrigin = origin
        func point(_ value: ServerUIArcLayout.Point) -> CGPoint { CGPoint(x: origin + CGFloat(value.x), y: CGFloat(value.y)) }
        let traits = traitCollection
        if let horizon = arc.horizon, let line = layout.horizon {
            let path = UIBezierPath()
            path.move(to: point(line.from))
            path.addLine(to: point(line.to))
            path.lineWidth = CGFloat(horizon.width)
            path.lineCapStyle = .butt
            UKStyledText.color(horizon.ink).resolvedColor(with: traits).setStroke()
            path.stroke()
        }
        let curve = UIBezierPath()
        curve.move(to: point(layout.curve.from))
        curve.addQuadCurve(to: point(layout.curve.to), controlPoint: point(layout.curve.control))
        curve.lineWidth = CGFloat(arc.width)
        curve.lineCapStyle = .round
        if let dash = arc.dash { curve.setLineDash([CGFloat(dash.stroke), CGFloat(dash.gap)], count: 2, phase: 0) }
        UKStyledText.color(arc.ink).resolvedColor(with: traits).setStroke()
        curve.stroke()
        if let marker = arc.marker, let spot = layout.marker {
            let size = CGFloat(marker.size), centre = point(.init(spot.x, spot.y))
            UKStyledText.color(marker.ink).resolvedColor(with: traits).setFill()
            UIBezierPath(ovalIn: CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)).fill()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
}
#endif
