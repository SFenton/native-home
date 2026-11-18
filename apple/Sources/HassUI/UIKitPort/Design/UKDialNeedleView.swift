#if os(iOS)
import HassCore
import UIKit

// MARK: - Needle

/// The closed needle of a dial, drawn at 0 turn: the head points down (the wind blows toward 180) and the dot sits on top (the source). The dial turns it
/// with a transform about its centre. The shape is ``ServerUIDialLayout/Needle``, the one the Studio draws.
final class UKDialNeedleView: UIView {
    /// The colours of the head, the tail and the dot.
    var inks: (head: UIColor, tail: UIColor, dot: UIColor) = (.white, .white, .white) {
        didSet { setNeedsDisplay() }
    }

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
        func point(_ corner: (x: Double, y: Double)) -> CGPoint { CGPoint(x: x + size * corner.x, y: y + size * corner.y) }
        func shape(_ corners: [(x: Double, y: Double)]) -> UIBezierPath {
            let path = UIBezierPath()
            path.move(to: point(corners[0]))
            for corner in corners.dropFirst() { path.addLine(to: point(corner)) }
            path.close()
            return path
        }
        inks.head.setFill()
        shape(ServerUIDialLayout.Needle.head).fill()
        inks.tail.setFill()
        shape(ServerUIDialLayout.Needle.tail).fill()
        inks.dot.setFill()
        let dot = size * ServerUIDialLayout.Needle.dotSize, centre = point(ServerUIDialLayout.Needle.dotAt)
        UIBezierPath(ovalIn: CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot)).fill()
    }
}
#endif
