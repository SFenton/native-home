#if os(iOS)
import HassCore
import UIKit

// MARK: - Face

/// The still parts of a dial: the ring of ticks, the one lit tick of a `tick` pointer and the flag, drawn from a ``ServerUIDialLayout/Layout``.
///
/// The view is as big as the dial and a `UIView` draws only inside its bounds, so a tick that reaches past the dial's box (the barometer's top tick
/// runs from y 1.4 to -8.4 in a 140 pt box) is clipped, as it is today. It redraws only when the layout or the look changes.
final class UKDialFaceView: UIView {
    /// What the face draws and with which strokes and inks.
    struct Content: Equatable {
        var layout: ServerUIDialLayout.Layout
        var ticks: ServerUIDial.Ticks?
        var pointer: ServerUIDial.Pointer?
        var flag: ServerUIDial.Flag?
    }

    /// The content now drawn; setting a different one redraws.
    var content: Content? {
        didSet { if content != oldValue { setNeedsDisplay() } }
    }
    /// How many times the face was drawn, for tests that an unchanged reading draws nothing.
    private(set) var drawCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKDialFaceView, _) in view.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func path(_ segments: [ServerUIDialLayout.Segment]) -> UIBezierPath {
        let path = UIBezierPath()
        for segment in segments {
            path.move(to: CGPoint(x: segment.x1, y: segment.y1))
            path.addLine(to: CGPoint(x: segment.x2, y: segment.y2))
        }
        return path
    }

    override func draw(_ rect: CGRect) {
        drawCount += 1
        guard let content else { return }
        let traits = traitCollection
        if let ticks = content.ticks {
            let ring = path(content.layout.ticks)
            ring.lineWidth = CGFloat(ticks.width)
            UKStyledText.color(ticks.ink).resolvedColor(with: traits).setStroke()
            ring.stroke()
        }
        if case .tick(_, _, _, let width, let ink)? = content.pointer, let lit = content.layout.lit {
            let tick = path([lit])
            tick.lineWidth = CGFloat(width)
            // The lit tick has a round cap; the schema has no cap, so every dial draws it so.
            tick.lineCapStyle = .round
            UKStyledText.color(ink).resolvedColor(with: traits).setStroke()
            tick.stroke()
        }
        if let corners = content.layout.flag, let flag = content.flag {
            let shape = UIBezierPath()
            shape.move(to: CGPoint(x: corners[0].x, y: corners[0].y))
            for corner in corners.dropFirst() { shape.addLine(to: CGPoint(x: corner.x, y: corner.y)) }
            shape.close()
            UKStyledText.color(flag.ink).resolvedColor(with: traits).setFill()
            shape.fill()
        }
    }
}
#endif
