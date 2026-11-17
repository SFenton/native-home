#if os(iOS)
import HassDesign
import UIKit

// MARK: - Row background

/// A row's share of its section's module card (``ModuleRowBackground``): the density's tint with the module's 26 pt corners on
/// the first row's top and the last row's bottom, so the rows read as one inset card; the sheet's cell colour in a sheet.
final class UKModuleRowBackgroundView: UIView {
    private let wash = UIView()
    private var density = ModuleDensity.thin
    private var surface = TileSurface.page

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        wash.backgroundColor = UKDesignInk.action
        wash.alpha = 0
        wash.isUserInteractionEnabled = false
        wash.layer.cornerCurve = .continuous
        wash.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wash)
        NSLayoutConstraint.activate([
            wash.topAnchor.constraint(equalTo: topAnchor), wash.bottomAnchor.constraint(equalTo: bottomAnchor),
            wash.leadingAnchor.constraint(equalTo: leadingAnchor), wash.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func transparencyChanged() { applyFill() }

    /// - Parameter animated: the card's corners change as part of an animated list update (a first or last row left): the radius animates
    ///   (``setCorners(_:radius:animated:)``). Off screen, or under Reduce Motion, they change at once.
    func configure(density: ModuleDensity, surface: TileSurface, isFirst: Bool, isLast: Bool, selected: Bool, animated: Bool = false) {
        self.density = density
        self.surface = surface
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        setCorners(corners, radius: corners.isEmpty ? 0 : HassTokens.Radius.module, animated: animated && window != nil && !UKMotion.reduceMotion)
        applyFill()
        let target: CGFloat = selected ? 0.18 : 0
        if wash.alpha != target {
            if window == nil { wash.alpha = target } else { UKMotion.state { self.wash.alpha = target } }
        }
    }

    /// Sets the corners. `maskedCorners` is discrete, so a change cannot interpolate; the radius can. Gaining corners from square sets the
    /// mask and grows the radius from 0, and losing them shrinks the radius and drops the mask when it lands. A change that keeps some
    /// rounded corners and moves others (a first row that becomes the only row) cross-dissolves, because one radius cannot be both.
    private func setCorners(_ corners: CACornerMask, radius: CGFloat, animated: Bool) {
        let oldCorners = layer.maskedCorners
        let oldRadius = layer.cornerRadius
        guard corners != oldCorners || radius != oldRadius else { return }
        func apply(_ mask: CACornerMask, _ value: CGFloat) {
            layer.maskedCorners = mask
            layer.cornerRadius = value
            wash.layer.maskedCorners = mask
            wash.layer.cornerRadius = value
        }
        guard animated else { apply(corners, radius); return }
        if oldRadius == 0 || oldCorners.isEmpty {
            apply(corners, 0)
            UKMotion.animate(.standard) { apply(corners, radius) }
        } else if radius == 0 || corners.isEmpty {
            UKMotion.animate(.standard, animations: { apply(oldCorners, 0) }, completion: { _ in apply(corners, radius) })
        } else {
            UIView.transition(with: self, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                apply(corners, radius)
            }
        }
    }

    private func applyFill() {
        backgroundColor = surface == .sheet
            ? UKDesignSurface.sheetCell
            : UKDesignSurface.moduleTint(density, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
    }
}

extension Array {
    /// The element at `index`, or nil when out of range.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
