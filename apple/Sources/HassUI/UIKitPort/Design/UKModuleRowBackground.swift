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

    func configure(density: ModuleDensity, surface: TileSurface, isFirst: Bool, isLast: Bool, selected: Bool) {
        self.density = density
        self.surface = surface
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        let radius: CGFloat = corners.isEmpty ? 0 : HassTokens.Radius.module
        layer.maskedCorners = corners
        layer.cornerRadius = radius
        wash.layer.maskedCorners = corners
        wash.layer.cornerRadius = radius
        applyFill()
        let target: CGFloat = selected ? 0.18 : 0
        if wash.alpha != target {
            if window == nil { wash.alpha = target } else { UKMotion.state { self.wash.alpha = target } }
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
