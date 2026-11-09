#if os(iOS)
import HassDesign
import HassTelemetry
import UIKit

/// A page body whose sections stay on one side of the hinge while the iPhone Duo is partly folded (Option B of
/// `.agents/design/section-sides.md`; Home's two halves, generalised). In every other pose it is the single column it replaced.
///
/// Every section is a direct subview, laid out by hand from ``FoldColumns``: a pose change only moves frames, so ``UKReflow``'s
/// animation carries each section from its old frame to its new one and nothing is re-parented or re-faded. The top strip (the
/// status rail) spans the page; the leading and trailing sides stack their sections, and the shorter side ends early. A section's
/// side is fixed per page, never balanced by live height, so a section that appears or hides moves only the ones under it.
///
/// Reading order while split is column-major (top, leading, trailing) and the container groups its children for VoiceOver. Right to
/// left mirrors the columns.
@MainActor
final class UKFoldColumns: UIView, UKGridMeasuring {
    /// One section of the page.
    struct Section {
        var view: UIView
        var side: FoldSide
        /// The gap above it in the single column when it differs from the container's spacing.
        var flatGapAbove: CGFloat?
        /// A top section that spans only the leading region (Home's banner).
        var topSpansLeadingOnly = false
        /// Its place among the sections of its side while split (``FoldColumns/Entry/splitRank``).
        var splitRank = 0
        /// The index of the section whose top this one starts level with while split (``FoldColumns/Entry/levelWith``).
        var levelWith: Int?
        /// The pose it takes part in (``FoldColumns/Entry/visibility``). The container lays out only the views of the pose; a page that
        /// uses `.flatOnly` or `.splitOnly` moves the views between hosts itself, in ``onSplitChange``.
        var visibility = FoldVisibility.always
        /// Ignores ``UKFoldColumns/sideInset`` (a rail that runs to the page's edges).
        var fullBleed = false
        /// The side it takes while split at an accessibility text size, where a status rail wraps (``ChipRailMode/wrap``): the top of
        /// the leading column, first in its accessibility group (decision rule 11). Nil keeps ``side``.
        var wrappedSide: FoldSide?

        init(_ view: UIView, side: FoldSide, flatGapAbove: CGFloat? = nil, topSpansLeadingOnly: Bool = false, splitRank: Int = 0,
             levelWith: Int? = nil, visibility: FoldVisibility = .always, fullBleed: Bool = false, wrappedSide: FoldSide? = nil) {
            self.fullBleed = fullBleed
            self.wrappedSide = wrappedSide
            self.visibility = visibility
            self.splitRank = splitRank
            self.levelWith = levelWith
            self.view = view
            self.side = side
            self.flatGapAbove = flatGapAbove
            self.topSpansLeadingOnly = topSpansLeadingOnly
        }
    }

    /// The sections, in flat order.
    private(set) var sections: [Section] = []
    /// The gap between sections.
    var spacing: CGFloat { didSet { setNeedsLayout() } }
    /// Space above and below the sections.
    var insets: UIEdgeInsets { didSet { setNeedsLayout() } }
    /// Space kept clear at both sides of every section, for sections that do not pad themselves.
    var sideInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The widest the single column runs, centred; the columns ignore it.
    var flatMaxWidth: CGFloat = .greatestFiniteMagnitude { didSet { setNeedsLayout() } }
    /// Empty space under the sections (a page that scrolls for the scroll cost probe).
    var extraHeight: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// Called when the page enters or leaves the two-column pose; set before the first layout. A page uses it for what depends on
    /// the pose (a rail that scrolls over the band, a card that narrows).
    var onSplitChange: ((Bool) -> Void)?
    /// The identifier the container carries while split, so a journey can tell the pose from the page.
    var splitIdentifier: String?
    /// The window's hinge in window coordinates while the Duo is partly folded, else nil.
    ///
    /// Written from the page's hinge observer, never from a layout pass: it decides the pose right here (``updateSplit()``), so
    /// `layoutSubviews` only places frames from a decision already taken.
    var hinge: CGRect? { didSet { if hinge != oldValue { updateSplit(); setNeedsLayout() } } }
    /// Whether the page is split now.
    private(set) var isSplit = false
    /// Whether the horizontal size class is regular; a page sets it once its controller exists.
    var isRegular: () -> Bool
    /// The height the page is offered (the scroll view's), which decides "wider than tall"; a page sets it once its scroll view exists.
    var offeredHeight: () -> CGFloat

    /// - Parameters:
    ///   - spacing: The gap between sections.
    ///   - insets: Space above and below the sections.
    ///   - isRegular: Whether the horizontal size class is regular.
    ///   - offeredHeight: The height the page is offered (the scroll view's), which decides "wider than tall".
    init(spacing: CGFloat, insets: UIEdgeInsets = .zero, isRegular: @escaping () -> Bool = { false },
         offeredHeight: @escaping () -> CGFloat = { 0 }) {
        self.spacing = spacing
        self.insets = insets
        self.isRegular = isRegular
        self.offeredHeight = offeredHeight
        super.init(frame: .zero)
        // A text-size change while split reflows the columns (a wrapped rail moves between the top strip and the leading column).
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFoldColumns, _) in
            view.ukSetNeedsLayoutUpward()
            if view.isSplit, view.window != nil { UKMotion.animate(.standard) { view.superview?.layoutIfNeeded() } }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the sections.
    func setSections(_ sections: [Section]) {
        self.sections.forEach { $0.view.removeFromSuperview() }
        self.sections = sections
        for section in sections where section.visibility == .always || (section.visibility == .flatOnly) == !isSplit {
            addSubview(section.view)
        }
        setNeedsLayout()
    }

    private func entries() -> [FoldColumns.Entry] {
        let wraps = traitCollection.ukIsAccessibilitySize
        return sections.map {
            let wrapped = wraps ? $0.wrappedSide : nil
            return FoldColumns.Entry(side: wrapped ?? $0.side, isHidden: $0.view.isHidden, flatGapAbove: $0.flatGapAbove,
                                     topSpansLeadingOnly: $0.topSpansLeadingOnly, splitRank: wrapped == nil ? $0.splitRank : -1,
                                     levelWith: $0.levelWith, visibility: $0.visibility, fullBleed: $0.fullBleed)
        }
    }

    /// The column widths while the band divides the page, else nil.
    func geometry(width: CGFloat) -> SplitGeometry? {
        guard hinge != nil else { return nil }
        let originX = window == nil ? 0 : convert(CGPoint.zero, to: nil).x
        let container = HomeColumns.container(from: CGRect(x: originX, y: 0, width: width, height: offeredHeight()))
        return FoldColumns.resolve(container: container, isRegularWidth: isRegular(), hinge: hinge)
    }

    private func layout(width: CGFloat, geometry: SplitGeometry?) -> FoldColumns.Layout {
        FoldColumns.layout(entries: entries(), width: width, geometry: geometry, spacing: spacing,
                           rightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft, sideInset: sideInset, flatMaxWidth: flatMaxWidth) { index, width in
            let view = sections[index].view
            if view is UIStackView {
                return ceil(view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                         withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
            }
            if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
            return ceil(view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        layout(width: width, geometry: geometry(width: width)).height + insets.top + insets.bottom + extraHeight
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    /// Layout passes in which the pose changed: the contract is zero (a pose is decided outside layout). A hosted test reads it with
    /// the layout census on (`FENTON_LAYOUT_CENSUS=1`, `.agents/platforms/apple/uikit-port.md`).
    nonisolated(unsafe) static var splitWritesInLayout = 0

    private var inLayoutPass = false
    private var hasLaidOut = false
    /// Whether a layout pass finished before this one (the first pass sets the initial pose and is not counted).
    private var hasLaidOutEarlier = false
    private var splitUpdatePending = false

    /// Decides whether the page is split from the hinge and the width it is laid out at, and tells the page. Runs where the hinge
    /// or the pose changes (the hinge observer, ``scheduleSplitUpdate()``), outside any layout pass.
    /// - Parameter width: The width to decide for; nil takes the container's own.
    func updateSplit(width: CGFloat? = nil) {
        splitUpdatePending = false
        let split = geometry(width: width ?? bounds.width) != nil
        guard split != isSplit else { return }
        applySplit(split)
        ukSetNeedsLayoutUpward()
    }

    /// One turn later: a layout pass found the decided pose out of date (a size change nobody announced) and asks for a decision.
    private func scheduleSplitUpdate() {
        guard !splitUpdatePending else { return }
        splitUpdatePending = true
        DispatchQueue.main.async { [weak self] in self?.updateSplit() }
    }

    override func layoutSubviews() {
        inLayoutPass = true
        defer { inLayoutPass = false; hasLaidOutEarlier = true }
        super.layoutSubviews()
        let proposed = geometry(width: bounds.width)
        if !hasLaidOut {
            // The first pass of a view that was never laid out sets the initial pose: nothing is on screen to flip, and deferring it
            // would draw one flat frame on a cold launch partly folded.
            hasLaidOut = true
            if (proposed != nil) != isSplit { applySplit(proposed != nil) }
        } else if (proposed != nil) != isSplit {
            scheduleSplitUpdate()
        }
        // Frames follow the decided pose; a stale decision is one turn from being corrected.
        let geometry = isSplit ? proposed : nil
        let split = geometry != nil
        let placed = layout(width: bounds.width, geometry: geometry)
        for ((section, frame), entry) in zip(zip(sections, placed.frames), entries()) where entry.isPlaced(split: split) {
            section.view.frame = frame.offsetBy(dx: 0, dy: insets.top)
        }
        let total = placed.height + insets.top + insets.bottom + extraHeight
        if total != laidOutHeight {
            laidOutHeight = total
            invalidateIntrinsicContentSize()
        }
    }

    private var laidOutHeight: CGFloat = 0

    /// The height the sections need at the current width, for a host that sizes it with Auto Layout (Climate).
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: gridHeight(forWidth: max(bounds.width, 1))) }

    private func applySplit(_ split: Bool) {
        if inLayoutPass && hasLaidOutEarlier { Self.splitWritesInLayout += 1 }
        UKLayoutCensus.note("foldColumns \(isSplit ? "split" : "flat") -> \(split ? "split" : "flat")\(inLayoutPass ? " IN LAYOUT" : "")")
        isSplit = split
        shouldGroupAccessibilityChildren = split
        accessibilityIdentifier = split ? splitIdentifier : nil
        onSplitChange?(split)
        // One `LayoutChange` interval spans the posture reflow, for `XCTOSSignpostMetric` (`.agents/testing/apple/performance.md`).
        if window != nil {
            let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "FoldColumns", split ? "split" : "flat")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Telemetry.end(interval) }
        }
    }

    // MARK: Accessibility

    /// Column-major while split (the top strip, the leading column, then the trailing one); the default order otherwise.
    override var accessibilityElements: [Any]? {
        get {
            guard isSplit else { return nil }
            return FoldColumns.readingOrder(entries: entries()).map { sections[$0].view }
        }
        set {}
    }
}
#endif
