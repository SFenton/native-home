#if os(iOS)
import HassDesign
import UIKit

/// The soft placeholder where a tile's value will go until live data lands (`PendingValueBar`): a rounded bar about the width of
/// a short value that breathes between 35% and 100% of a soft white (1.4 s, one repeating animation). It sizes itself to the
/// tile's value line (`footnote`), so the tile does not change height when the value arrives. With Reduce Motion it holds still
/// half way. Hidden from accessibility: the tile's value reads "Loading".
///
/// One repeating opacity animation per bar runs on the render server, so thirty pending tiles cost no main-thread work per frame.
@MainActor
final class UKPendingValueBar: UIView {
    private var observers: UKObserverTokens?

    /// A corner radius for a bar used as a larger placeholder shape (a skeleton's tile or weather module, ``UKConfigSkeletonView``);
    /// nil keeps the capsule of a value bar. The fill and the pulse are the same.
    var fixedCornerRadius: CGFloat? { didSet { if fixedCornerRadius != oldValue { setNeedsLayout() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        backgroundColor = UIColor.white.withAlphaComponent(0.32)
        layer.cornerCurve = .continuous
        observers = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.syncAnimation() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The bar's size follows the footnote text size, so it stays about the width of a short value.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: UKFont.scaled(56, relativeTo: .footnote, traits: traitCollection), height: UKFont.scaled(12, relativeTo: .footnote, traits: traitCollection))
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = fixedCornerRadius.map { min($0, bounds.height / 2) } ?? bounds.height / 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncAnimation()
    }

    override var isHidden: Bool {
        didSet { if isHidden != oldValue { syncAnimation() } }
    }

    private var breathes: Bool { !(UKDesign.animationsPaused || UKDesign.reduceMotion) }

    private func syncAnimation() {
        layer.removeAnimation(forKey: "breathe")
        guard window != nil, !isHidden else { return }
        guard breathes else {
            layer.opacity = 0.65
            return
        }
        layer.opacity = 1
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.35
        animation.toValue = 1
        animation.duration = PendingValueBar.period / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "breathe")
    }
}
#endif
