#if os(iOS)
import HassDesign
import UIKit

/// Keeps content off the iPhone Duo's hinge band (`HingeAvoidance`; `.agents/patterns/hinge-avoidance.md`, decided 2026-10-24).
///
/// The hinge arrives in window coordinates; a view measures its own frame in the same space and the helpers answer in the
/// container's local coordinates (``HingeAvoidance`` holds the geometry; only a vertical hinge is a band, so iPad and iPhone never
/// change). Two layout views:
/// - ``UKHingeAvoidingView`` keeps a single object that cannot split (an alarm card, a dial, a sign-in form) centred, and moves it
///   to the centre of the leading region only when the hinge crosses its centred frame.
/// - ``UKHingeClearingView`` keeps a page sheet's form clear of the hinge by using the wider side of it.
///
/// Both read the hinge from ``UKHinge/frame``, which the shell publishes (`readsWindowHinge()` in the SwiftUI app) and which is nil
/// on devices without one.
@MainActor
public enum UKHinge {
    /// The hinge in window coordinates, or nil. Set by the shell when the window's hinge changes; posts ``didChange``.
    public static var frame: CGRect? {
        didSet {
            if frame != oldValue { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }

    /// A vertical hinge exists in either pose (``WindowFold/isVertical``: landscape, partly folded or flat); ``frame`` is the band, set
    /// only while partly folded. A lying-flat Duo has no band but its grids keep an even number of tracks (symmetric about the page's
    /// midpoint). Unfolded portrait (a horizontal hinge) is false, so its grids keep their own column counts. Posts ``didChange`` too.
    public static var hasFold = false {
        didSet {
            if hasFold != oldValue { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }

    /// Publishes the window's fold: ``hasFold`` first, then the band.
    public static func publish(_ fold: WindowFold) {
        hasFold = fold.isVertical
        frame = fold.band
    }

    public static let didChange = Notification.Name("UKHinge.didChange")

    /// Whether the fold passes through a view whose frame in the window is `frame`: the hinge band's middle while partly folded, else the
    /// window's midpoint (lying flat). A grid keeps an even number of tracks only then. A grid in a pane that sits wholly on one side
    /// of the fold (the Settings split's trailing page) is not divided by it and fills its column (owner, 2026-11-01: Vacation Mode
    /// ended 200 pt short of the pane's edge). Without a window the answer is yes, as the grid's first measurement always was.
    static func crossesFold(_ frame: CGRect, in window: UIWindow?) -> Bool {
        guard let window else { return true }
        let middle = Self.frame?.midX ?? window.bounds.midX
        return frame.minX + 1 < middle && middle < frame.maxX - 1
    }
}

/// Centres its child and moves it off the hinge only when the hinge crosses it (`avoidsHinge()`). A no-op without a hinge.
///
/// ```swift
/// let host = UKHingeAvoidingView(child: dial)       // the child sizes itself by its own constraints inside the host's width
/// ```
public final class UKHingeAvoidingView: UIView {
    public let child: UIView
    private var childX: NSLayoutConstraint!
    private var childWidth: NSLayoutConstraint!

    public init(child: UIView) {
        self.child = child
        super.init(frame: .zero)
        addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        childX = child.leadingAnchor.constraint(equalTo: leadingAnchor)
        childWidth = child.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([childX, childWidth, child.topAnchor.constraint(equalTo: topAnchor), child.bottomAnchor.constraint(equalTo: bottomAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(hingeChanged), name: UKHinge.didChange, object: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func hingeChanged() { setNeedsLayout() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        // The width the child takes when offered the whole container; the band decides from that, not from a width the move
        // itself would change.
        childWidth.isActive = false
        let natural = child.systemLayoutSizeFitting(CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel).width
        childWidth.isActive = true
        let objectWidth = min(natural > 0 ? natural : bounds.width, bounds.width)
        let container = convert(bounds, to: nil)
        // Position and width only: the height follows the placement and must not feed back.
        let band = HingeAvoidance.band(in: CGRect(x: container.minX.rounded(), y: 0, width: container.width.rounded(), height: 0), hinge: UKHinge.frame)
        let place = HingeAvoidance.placement(objectWidth: objectWidth, containerWidth: bounds.width, band: band)
        if childX.constant != place.x || childWidth.constant != place.width {
            childX.constant = place.x
            childWidth.constant = place.width
            super.layoutSubviews()
        }
    }
}

/// Keeps a page sheet's form clear of the hinge by using the wider side of it (`clearsHinge()`; a sheet can be sized but not
/// offset, so the content takes the inset). A no-op wherever no vertical hinge crosses the sheet.
public final class UKHingeClearingView: UIView {
    public let content: UIView
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    /// Takes the leading region of a band instead of its wider side, and lets touches through where the content takes none (a state
    /// message: it sits in the leading region, never across the band).
    private let leadingOnly: Bool
    /// False makes the view a plain full-size host (no hinge handling).
    private let active: Bool

    public init(content: UIView, leadingOnly: Bool = false, active: Bool = true) {
        self.content = content
        self.leadingOnly = leadingOnly
        self.active = active
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        leading = content.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailing = content.trailingAnchor.constraint(equalTo: trailingAnchor)
        NSLayoutConstraint.activate([leading, trailing, content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)])
        NotificationCenter.default.addObserver(self, selector: #selector(hingeChanged), name: UKHinge.didChange, object: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    @objc private func hingeChanged() { setNeedsLayout() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard active else { return }
        let container = convert(bounds, to: nil)
        let frame = CGRect(x: container.minX.rounded(), y: 0, width: container.width.rounded(), height: 0)
        let band = HingeAvoidance.band(in: frame, hinge: UKHinge.frame)
        let region = leadingOnly
            ? (x: CGFloat(0), width: max(band?.lowerBound ?? frame.width, 0))
            : HingeAvoidance.clearRegion(containerWidth: frame.width, band: band)
        let lead = band == nil ? 0 : region.x
        let trail = band == nil ? 0 : max(frame.width - region.x - region.width, 0)
        if leading.constant != lead || trailing.constant != -trail {
            leading.constant = lead
            trailing.constant = -trail
            super.layoutSubviews()
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return leadingOnly && hit === self ? nil : hit
    }
}
#endif
