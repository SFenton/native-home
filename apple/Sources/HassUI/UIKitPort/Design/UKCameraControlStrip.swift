#if os(iOS)
import HassDesign
import UIKit

// MARK: - Value/closure camera controls

/// Shared layout for canonical camera buttons and a feedback caption; contains no store or command path.
@MainActor
final class UKCameraControlStripView: UIView {
    enum LayoutAxis { case horizontal, vertical }
    var axis: LayoutAxis = .horizontal { didSet { if axis != oldValue { setNeedsLayout() } } }
    private let buttons: [UKCameraControlButton]
    private let caption: UIView

    init(buttons: [UKCameraControlButton], caption: UIView) {
        self.buttons = buttons
        self.caption = caption
        super.init(frame: .zero)
        accessibilityContainerType = .semanticGroup
        for button in buttons { addSubview(button) }
        addSubview(caption)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func plan(width: CGFloat, axis: LayoutAxis) -> (frames: [CGRect], height: CGFloat) {
        guard !buttons.isEmpty else { return ([], 0) }
        let spacing = HassTokens.Spacing.m
        if axis == .horizontal, !traitCollection.ukIsAccessibilitySize {
            let each = max(0, (width - spacing * CGFloat(buttons.count - 1)) / CGFloat(buttons.count))
            let height = buttons.map { $0.height(forWidth: each) }.max() ?? 0
            return (buttons.indices.map { CGRect(x: CGFloat($0) * (each + spacing), y: 0, width: each, height: height) }, height)
        }
        var y: CGFloat = 0
        let frames = buttons.map { button in
            let height = button.height(forWidth: width)
            defer { y += height + spacing }
            return CGRect(x: 0, y: y, width: width, height: height)
        }
        return (frames, max(0, y - spacing))
    }

    private func captionHeight(width: CGFloat) -> CGFloat {
        caption.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }

    func measuredHeight(forWidth width: CGFloat, axis: LayoutAxis) -> CGFloat {
        let height = captionHeight(width: width)
        return plan(width: width, axis: axis).height + (height > 0 ? HassTokens.Spacing.s + height : 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: measuredHeight(forWidth: size.width, axis: axis))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let plan = plan(width: bounds.width, axis: axis)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (button, frame) in zip(buttons, plan.frames) {
            button.frame = mirror ? CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        let height = captionHeight(width: bounds.width)
        caption.frame = CGRect(x: 0, y: plan.height + (height > 0 ? HassTokens.Spacing.s : 0), width: bounds.width, height: height)
    }
}
#endif
