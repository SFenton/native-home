#if os(iOS)
import HassDesign
import UIKit

/// What a layout-driven page draws while its house layout has not arrived and there is no saved copy: the page's own shape in
/// ``UKPendingValueBar``'s fill and pulse (0.35 to 1 over 1.4 s; a still 65% under Reduce Motion; never a shimmer or a spinner),
/// `.agents/design/house-config-states.md` rule 11.
///
/// The whole skeleton is one accessibility element, "Getting your home from Home Assistant"; the shapes are hidden. The shapes come
/// from ``HouseSkeletonPlan``. Home on a partly folded Duo uses fold columns (the rail on top, the module leading, the tiles
/// trailing) by the hinge band, found like every hinge-aware view does.
///
/// ```swift
/// let skeleton = UKConfigSkeletonView(.home)      // identifier home.skeleton
/// host.addSubview(skeleton)                       // pinned to the free space under the header
/// ```
@MainActor
final class UKConfigSkeletonView: UIView {
    let kind: HouseSkeletonPlan.Kind
    private var bars: [UKPendingValueBar] = []
    private var plan: HouseSkeletonPlan?
    private var planKey: PlanKey?

    private struct PlanKey: Equatable {
        let width: CGFloat
        let band: ClosedRange<CGFloat>?
        let chipHeight: CGFloat
    }

    init(_ kind: HouseSkeletonPlan.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = HouseConfigCopy.skeletonLabel
        accessibilityTraits = .staticText
        accessibilityIdentifier = kind == .home ? "home.skeleton" : "page.skeleton"
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(hingeChanged), name: UKHinge.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func hingeChanged() { setNeedsLayout() }

    /// The plan for the skeleton's current width, hinge and text size.
    func currentPlan() -> HouseSkeletonPlan {
        let container = convert(bounds, to: nil)
        let band = kind == .home
            ? HingeAvoidance.band(in: CGRect(x: container.minX.rounded(), y: 0, width: container.width.rounded(), height: 0), hinge: UKHinge.frame)
            : nil
        let chipHeight = UKFont.scaled(56, relativeTo: .body, traits: traitCollection)
        let key = PlanKey(width: bounds.width, band: band, chipHeight: chipHeight)
        if let plan, key == planKey { return plan }
        let made = HouseSkeletonPlan.make(kind, width: bounds.width, band: band, chipHeight: chipHeight)
        plan = made
        planKey = key
        return made
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let plan = currentPlan()
        while bars.count < plan.shapes.count {
            let bar = UKPendingValueBar()
            addSubview(bar)
            bars.append(bar)
        }
        for (index, bar) in bars.enumerated() {
            guard index < plan.shapes.count else {
                bar.isHidden = true
                continue
            }
            let shape = plan.shapes[index]
            bar.isHidden = false
            bar.frame = shape.frame
            switch shape.role {
            case .chip, .bar: bar.fixedCornerRadius = nil
            case .module: bar.fixedCornerRadius = 24
            case .tile: bar.fixedCornerRadius = 20
            }
        }
    }
}
#endif
