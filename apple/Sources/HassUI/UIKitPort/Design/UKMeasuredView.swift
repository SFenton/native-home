#if os(iOS)
import HassDesign
import UIKit

// MARK: - Fit cache

/// The height a container measured, kept for the width, content size category and Bold Text setting it was measured at, so a scroll view that asks on every
/// frame (`UKPageScrollView.layoutSubviews`) gets an answer and does no layout. The owner calls ``invalidate()`` from
/// `invalidateIntrinsicContentSize()`, which `ukRemeasureContainers` reaches from any child whose content changed, and from
/// ``ukInvalidateFits(in:)`` when a page reports a change.
struct UKFitCache {
    private var entry: (width: CGFloat, category: UIContentSizeCategory, weight: UILegibilityWeight, height: CGFloat)?
    private var generation = 0
    /// How many times the owner measured for real (a hit does not count); tests read it to prove a scroll does not measure.
    private(set) var fits = 0

    /// The kept height, when it was measured at `width` in `category` and nothing has invalidated it since.
    func height(forWidth width: CGFloat, category: UIContentSizeCategory, weight: UILegibilityWeight = .unspecified) -> CGFloat? {
        guard let entry, entry.width == width, entry.category == category, entry.weight == weight else { return nil }
        return entry.height
    }

    /// The token to give ``store(_:width:category:since:)`` after a measurement.
    var token: Int { generation }

    /// Keeps `height`, unless something invalidated the cache while it was being measured.
    mutating func store(_ height: CGFloat, width: CGFloat, category: UIContentSizeCategory, weight: UILegibilityWeight = .unspecified,
                        since token: Int) {
        fits += 1
        if token == generation { entry = (width, category, weight, height) }
    }

    /// Drops the kept height: the content or its size changed.
    mutating func invalidate() {
        generation += 1
        entry = nil
    }
}

/// A container that keeps its measured height (``UKFitCache``) and can be told to forget it.
@MainActor
protocol UKFitCaching: AnyObject {
    /// Drops the kept height: the content changed in a way no child reported.
    func invalidateFit()
}

/// Drops the kept height of every ``UKFitCaching`` view in `view`'s subtree. A page calls it when its content changed
/// (``UKPageScrollView/contentChanged(animated:)``), once per change, never per frame.
@MainActor
func ukInvalidateFits(in view: UIView) {
    (view as? UKFitCaching)?.invalidateFit()
    for child in view.subviews { ukInvalidateFits(in: child) }
}

// MARK: - Measured host

/// A view that can be told the width it will get before its first layout pass, so the height it gives Auto Layout is already right.
@MainActor
protocol UKWidthPreparing: AnyObject {
    /// Measures the hosted content at `width` and stores the result as the Auto Layout height.
    func prepare(forWidth width: CGFloat)
}

/// Hosts a hand-laid view that measures itself by width (``UKGridMeasuring``) and gives it an Auto Layout height, so grids, flows,
/// tiles and section headers can sit in a stack view (the one mechanism for a hand-laid view in a stack; add no other).
///
/// The height constraint is refreshed in `layoutSubviews`, so a system-fitting call made before the first layout would read the
/// placeholder 1 pt. A container that measures by system fitting (``UKServerUIFittingView``, a stack that is itself
/// ``UKGridMeasuring``) calls ``ukPrepareMeasuredViews(in:width:)`` first, which runs ``prepare(forWidth:)`` on every host below it.
/// The host also forwards ``UKGridMeasuring/gridMinimumWidth`` so a tile inside it takes the tracks it needs.
@MainActor
final class UKMeasuredView<Content: UIView & UKGridMeasuring>: UIView, UKGridMeasuring, UKWidthPreparing, UKSurfaceStyled {
    let content: Content
    private var heightConstraint: NSLayoutConstraint!

    init(_ content: Content) {
        self.content = content
        super.init(frame: .zero)
        heightConstraint = heightAnchor.constraint(equalToConstant: 1)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
        addSubview(content)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKMeasuredView<Content>, _) in view.invalidate() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Measures again at the current width.
    func invalidate() { setNeedsLayout() }

    var gridMinimumWidth: CGFloat { content.gridMinimumWidth }

    /// Passes a list's surface on to the hosted row, so a hosted row styles like a bare one.
    var surface: TileSurface = .page {
        didSet { (content as? UKSurfaceStyled)?.surface = surface }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { ceil(content.gridHeight(forWidth: width)) }

    func prepare(forWidth width: CGFloat) {
        guard width > 1 else { return }
        setHeight(gridHeight(forWidth: width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = gridHeight(forWidth: bounds.width)
        setHeight(height)
        content.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }

    private func setHeight(_ height: CGFloat) {
        if abs(heightConstraint.constant - height) > 0.5 { heightConstraint.constant = height }
    }
}

/// Runs ``UKWidthPreparing/prepare(forWidth:)`` on every measured host below `view`, so a system-fitting call that follows reads their
/// real heights, not the first-pass placeholder. The width is the container's own: a host with side insets is corrected by its next layout.
@MainActor
func ukPrepareMeasuredViews(in view: UIView, width: CGFloat) {
    for child in view.subviews where !child.isHidden {
        if let host = child as? UKWidthPreparing { host.prepare(forWidth: width) } else { ukPrepareMeasuredViews(in: child, width: width) }
    }
}

/// The view to arrange in a stack for `row`: the row itself when Auto Layout already gives it a height (a stack, a control, a pinned
/// fitting host), a ``UKMeasuredView`` around it when it only measures by width. A hand-laid row put in a stack bare is 0 pt tall
/// (a bedroom tile) or a hairline (a settings link) and draws over its neighbours.
@MainActor
func ukStackRow(_ row: UIView) -> UIView {
    switch row {
    case is UKServerUIFittingView, is UKServerUISettingsAtom, is UIStackView, is UKRowButton, is UKRowView, is UKWidthPreparing: return row
    case let measuring as any (UIView & UKGridMeasuring): return ukMeasuredHost(measuring)
    default: return row
    }
}

@MainActor
private func ukMeasuredHost<T: UIView & UKGridMeasuring>(_ content: T) -> UIView { UKMeasuredView<T>(content) }
#endif
