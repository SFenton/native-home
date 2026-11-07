#if os(iOS)
import HassDesign
import UIKit

/// A shape drawn on Liquid Glass (iOS 26 and later) or a thin material (before): the UIKit counterpart of
/// `navigationGlass(in:)` and the floating bar's `BarGlass`.
///
/// Put the control's content in ``contentView``. ``init(shape:tint:isInteractive:material:)`` picks the look:
/// - `navigationGlass`: no tint, not interactive, `ultraThinMaterial` below iOS 26 (`.agents/design/direction-g.md`, Layers).
/// - `BarGlass`: an optional tint (the primary action's blue, an applied filter's light fill), interactive, `ultraThinMaterial`
///   with the tint laid over at 88% below iOS 26.
///
/// A tint change cross-fades with ``UKMotion/Token/state`` (`stateColorTransition`).
public final class UKGlassView: UIView {
    /// The glass's outline.
    public enum Shape: Equatable {
        case capsule
        case circle
        case rounded(CGFloat)
    }

    /// Opacity of the tint over the thin material when there is no glass.
    static let fallbackTintOpacity: CGFloat = 0.88

    public let shape: Shape
    public let isInteractive: Bool
    private let effectView = UIVisualEffectView(effect: nil)
    private let tintOverlay = UIView()
    private let usesGlass: Bool
    private let fallbackStyle: UIBlurEffect.Style
    public private(set) var tint: UIColor?

    /// The view for the glass's content.
    public var contentView: UIView { effectView.contentView }

    public init(shape: Shape = .capsule, tint: UIColor? = nil, isInteractive: Bool = false, material: UIBlurEffect.Style = .systemUltraThinMaterial) {
        self.shape = shape
        self.isInteractive = isInteractive
        self.tint = tint
        self.fallbackStyle = material
        if #available(iOS 26, *) { usesGlass = true } else { usesGlass = false }
        super.init(frame: .zero)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor), effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor), effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        if usesGlass {
            if !UKPerfSwitches.isOff(.ukGlass) { applyGlass() }
            if #available(iOS 26, *) {
                switch shape {
                case .capsule, .circle: effectView.cornerConfiguration = .capsule()
                case let .rounded(radius): effectView.cornerConfiguration = .corners(radius: .fixed(radius))
                }
            }
        } else {
            effectView.effect = UIBlurEffect(style: material)
            effectView.layer.masksToBounds = true
            effectView.layer.cornerCurve = .continuous
            tintOverlay.isUserInteractionEnabled = false
            tintOverlay.backgroundColor = tint?.withAlphaComponent(Self.fallbackTintOpacity)
            effectView.contentView.insertSubview(tintOverlay, at: 0)
            tintOverlay.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tintOverlay.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                tintOverlay.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
                tintOverlay.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                tintOverlay.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            ])
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func applyGlass() {
        if #available(iOS 26, *), !UKPerfSwitches.isOff(.ukGlass) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = tint
            glass.isInteractive = isInteractive
            effectView.effect = glass
        }
    }

    /// Changes the tint, cross-fading it with the state timing.
    public func setTint(_ newTint: UIColor?, animated: Bool = true) {
        guard newTint != tint else { return }
        tint = newTint
        let apply = { [self] in
            if usesGlass { applyGlass() } else { tintOverlay.backgroundColor = newTint?.withAlphaComponent(Self.fallbackTintOpacity) }
        }
        if animated, window != nil { UKMotion.stateColor(apply) } else { apply() }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !usesGlass else { return }
        switch shape {
        case .capsule, .circle: effectView.layer.cornerRadius = bounds.height / 2
        case let .rounded(radius): effectView.layer.cornerRadius = radius
        }
    }
}

/// A view with a ``UKGlassView`` behind its content: the shape of `.navigationGlass(in:)`. Add content to ``contentView``.
public final class UKNavigationGlassView: UIView {
    public let glass: UKGlassView
    public var contentView: UIView { glass.contentView }

    public init(shape: UKGlassView.Shape = .capsule) {
        glass = UKGlassView(shape: shape)
        super.init(frame: .zero)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

extension UIView {
    /// Pins this view to all four edges of `other`.
    func ukPin(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
        ])
    }
}
#endif
