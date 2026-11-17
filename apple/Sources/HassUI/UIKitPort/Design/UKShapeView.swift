#if os(iOS)
import HassCore
import UIKit

// MARK: - Shape

/// A capsule, a rectangle or a circle of one colour (`sh.stack@1`). It is decoration: a drawn line or bar that VoiceOver skips.
///
/// The size is the one the document gives, in points; the colour follows the appearance and keeps its opacity.
@MainActor
final class UKShapeView: UIView, UKStackMeasuring {
    private(set) var definition: ServerUIShapePart?
    /// The drawn form, at its authored size on the leading edge of whatever the page gives this view.
    private let fill = UIView()
    /// The frame of the drawn form.
    var drawnFrame: CGRect { fill.frame }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        fill.layer.cornerCurve = .continuous
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws `value`.
    func apply(_ value: ServerUIShapePart) {
        definition = value
        fill.backgroundColor = UKStyledText.color(value.fill)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        definition.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = intrinsicContentSize
        let width = min(size.width, bounds.width)
        fill.frame = CGRect(x: effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - width : 0, y: 0, width: width, height: min(size.height, bounds.height))
        switch definition?.form {
        case .capsule?, .circle?: fill.layer.cornerRadius = min(fill.bounds.width, fill.bounds.height) / 2
        case .rect?, nil: fill.layer.cornerRadius = 0
        }
    }

    var stackNaturalWidth: CGFloat { intrinsicContentSize.width }
    var stackFillsWidth: Bool { false }
    var stackShrinks: Bool { false }
}

extension UKShapeView: UKGridMeasuring {
    func gridHeight(forWidth width: CGFloat) -> CGFloat { intrinsicContentSize.height }
}
#endif
