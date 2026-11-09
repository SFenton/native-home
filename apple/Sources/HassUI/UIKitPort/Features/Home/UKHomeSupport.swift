#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Where the Home page hands off to screens the Security lane owns. They default to the real implementations; a test may replace them.
@MainActor
enum UKHomeHooks {
    /// Presents the camera viewer a tapped camera card opens (``UKCameraViewer``, `CameraViewer`), growing out of `source`.
    static var cameraViewer: (HomeConfig.Camera, UIViewController, UKContext, UIView?) -> Void = { camera, presenter, context, source in
        UKCameraViewer.present(camera, from: presenter, context: context, source: source)
    }
    /// The page the Security chip opens: the alarm controls (`SecuritySystemSheet`).
    static var securitySystemSheet: (UKContext, any HassServiceCalling) -> UIViewController = { context, caller in
        UKSecuritySystemViewController(context: context, caller: caller)
    }
}

/// Ink colours the Home page and the weather views draw with, from the SwiftUI tokens.
enum UKWeatherInk {
    /// `HassTokens.Ink.onDark`.
    static let onDark = UIColor(HassTokens.RGB.Ink.onDark)
    /// `HassTokens.Ink.onDarkSecondary`.
    static let onDarkSecondary = UKInk.onDarkSecondary
    /// The blue of a raindrop and precipitation bars.
    static let drop = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1)
    /// The needle and the pressure tick.
    static let amber = UIColor(red: 1.0, green: 0.82, blue: 0.30, alpha: 1)
}

/// Measures a view that lays itself out with Auto Layout (the notification banner) for a hand-laid column: its height at a width,
/// and hidden when the child is. The column reads `gridHeight(forWidth:)`.
@MainActor
final class UKFittingBox: UIView, UKGridMeasuring {
    let child: UIView
    var insets: UIEdgeInsets
    /// Called when the child shows or hides, so the page lays out again.
    var onVisibilityChange: (() -> Void)?
    private var observation: NSKeyValueObservation?

    init(_ child: UIView, insets: UIEdgeInsets = .zero) {
        self.child = child
        self.insets = insets
        super.init(frame: .zero)
        addSubview(child)
        isHidden = child.isHidden
        observation = child.observe(\.isHidden, options: [.new]) { [weak self] child, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isHidden != child.isHidden {
                    self.isHidden = child.isHidden
                    self.onVisibilityChange?()
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard !child.isHidden else { return 0 }
        let inner = max(1, width - insets.left - insets.right)
        let fitted = child.systemLayoutSizeFitting(CGSize(width: inner, height: UIView.layoutFittingCompressedSize.height),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return ceil(fitted.height) + insets.top + insets.bottom
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        child.frame = bounds.inset(by: insets)
    }
}

/// Puts a hand-laid view (a grid, the hourly carousel) into an Auto Layout stack: the host's intrinsic height is the child's height at
/// the host's width, and it asks for a new layout when that changes.
@MainActor
final class UKAutoSizingHost: UIView {
    let child: UIView & UKGridMeasuring
    private var lastHeight: CGFloat = -1

    init(_ child: UIView & UKGridMeasuring) {
        self.child = child
        super.init(frame: .zero)
        addSubview(child)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var width: CGFloat { bounds.width > 0 ? bounds.width : 320 }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: ceil(child.gridHeight(forWidth: width))) }

    override func layoutSubviews() {
        super.layoutSubviews()
        child.frame = bounds
        let height = ceil(child.gridHeight(forWidth: bounds.width))
        if height != lastHeight {
            lastHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    /// Asks for a new height after the child's content changed.
    func contentChanged() {
        lastHeight = -1
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

/// A one-pixel-class line of the given colour (a separator the SwiftUI view draws as a `Rectangle` of height 1).
final class UKLineView: UIView {
    init(color: UIColor, height: CGFloat = 1) {
        super.init(frame: .zero)
        backgroundColor = color
        isAccessibilityElement = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UIView {
    /// Asks every ancestor, up to the window, to lay out again: the way a height change deep in a
    /// column reaches the column (nothing here uses Auto Layout between the page and its cards).
    func ukSetNeedsLayoutUpward() {
        var view: UIView? = self
        while let current = view {
            current.setNeedsLayout()
            view = current.superview
        }
    }
}

/// A view that reports its height from `sizeThatFits` to `systemLayoutSizeFitting`, so a paging row of hand-laid cells can measure them.
class UKMeasuredCell: UIView {
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        sizeThatFits(CGSize(width: targetSize.width, height: .greatestFiniteMagnitude))
    }
}
#endif
