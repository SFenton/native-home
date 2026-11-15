#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Scaled metrics

/// `@ScaledMetric(relativeTo:)` for a UIKit view: a design value scaled with Dynamic Type relative to a text style.
enum UKScaled {
    static func value(_ base: CGFloat, relativeTo style: UIFont.TextStyle, traits: UITraitCollection) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: base, compatibleWith: traits)
    }
}

// MARK: - Grid

/// `DynamicGridLayout` for a handful of tiles inside an Auto Layout column: the same columns, spans and hinge band
/// (``UKGridSolver``), solved at every layout (a tile's text can change its height) and reporting its height as its intrinsic
/// content size, so a stack view gives it the room. The minimum column width scales with Dynamic Type relative to a text style,
/// as `HouseholdTileGrid` and `AwaySectionGrid` do with `@ScaledMetric`.
@MainActor
final class UKFlexGridView: UIView {
    private(set) var items: [UKGridItem] = []
    private let minWidth: CGFloat
    private let maxColumns: Int
    private let spacing: CGFloat
    private let scaleStyle: UIFont.TextStyle?
    private let fill: UKGridFill
    private var lastHeight: CGFloat = 0
    private var lastWidth: CGFloat = 0

    /// - Parameters:
    ///   - minWidth: The narrowest column before the grid drops one.
    ///   - scaleStyle: The text style the minimum width scales with; nil keeps it fixed. A section minimum
    ///     (``DynamicGridMetrics/sectionMinWidth`` and up) only grows with it, so text size removes section columns, never adds them.
    ///   - fill: How a short row fills (``UKGridFill``); choice chips and dials pass `.none`.
    init(minWidth: CGFloat, maxColumns: Int, spacing: CGFloat = HassTokens.Spacing.m, scaleStyle: UIFont.TextStyle? = .subheadline,
         fill: UKGridFill = .share) {
        self.fill = fill
        self.minWidth = minWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
        self.scaleStyle = scaleStyle
        super.init(frame: .zero)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKFlexGridView, _) in
            view.setNeedsLayout()
            view.invalidateIntrinsicContentSize()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(hingeChanged), name: UKHinge.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The fold as this grid last applied it: copied one turn after ``UKHinge`` changed, so the reflow runs inside ``UKReflow``'s animation.
    private var band: CGRect? = UKHinge.frame
    private var foldIsPresent = UKHinge.hasFold

    @objc private func hingeChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, band != UKHinge.frame || foldIsPresent != UKHinge.hasFold else { return }
            band = UKHinge.frame
            foldIsPresent = UKHinge.hasFold
            // Up through the hand-laid columns above, which hold the measured height.
            var view: UIView? = self
            while let current = view {
                current.setNeedsLayout()
                view = current.superview
            }
            invalidateIntrinsicContentSize()
        }
    }

    func setItems(_ views: [UIView]) {
        items.forEach { $0.view.removeFromSuperview() }
        items = views.map { UKGridItem($0) }
        items.forEach { addSubview($0.view) }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func solve(width: CGFloat) -> UKGridSolution {
        var scale = scaleStyle.map { UKScaled.value(1, relativeTo: $0, traits: traitCollection) } ?? 1
        if minWidth >= DynamicGridMetrics.sectionMinWidth { scale = max(scale, 1) }
        var configuration = UKGridConfiguration(minCellWidth: minWidth * scale, maxColumns: maxColumns, spacing: spacing, fill: fill)
        // Lying flat (no band) the tracks stay even, symmetric about the page's midpoint; partly folded they divide at the band.
        if foldIsPresent || band != nil, UKHinge.crossesFold(convert(bounds, to: nil), in: window) { configuration.evenColumns = true }
        if let hinge = band {
            if window != nil {
                let frame = convert(bounds, to: nil)
                configuration.hingeBand = HingeAvoidance.band(in: CGRect(x: frame.minX.rounded(), y: 0, width: width.rounded(), height: 0), hinge: hinge)
            }
        }
        return UKGridSolver.solve(width: width, configuration: configuration, spans: items.map(\.span), headers: items.map(\.isHeader)) { index, columnWidth in
            ukMeasuredHeight(self.items[index].view, width: columnWidth)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : minWidth * CGFloat(maxColumns)
        return CGSize(width: width, height: solve(width: width).height)
    }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: lastHeight) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let solution = solve(width: bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, (item, frame)) in zip(items, solution.frames).enumerated() {
            item.view.frame = mirror ? CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
            if let tile = item.view as? UKGlassTileView { tile.gridFullRow = solution.fullRow[index] }
        }
        lastWidth = bounds.width
        if abs(solution.height - lastHeight) > 0.5 {
            lastHeight = solution.height
            invalidateIntrinsicContentSize()
        }
    }
}

/// A child's height at `width`: a tile or other measuring view answers for itself, an Auto Layout view is fitted.
@MainActor
func ukMeasuredHeight(_ view: UIView, width: CGFloat) -> CGFloat {
    if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
    return ceil(view.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
}

// MARK: - Column

extension UIStackView {
    /// A vertical column of full-width views (`VStack(alignment: .leading, spacing:)`).
    static func ukColumn(_ views: [UIView] = [], spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = spacing
        return stack
    }
}

extension UIEdgeInsets {
    /// The same inset on every side.
    static func ukAll(_ value: CGFloat) -> UIEdgeInsets { UIEdgeInsets(top: value, left: value, bottom: value, right: value) }
}

/// A view with a fixed padding around a child (`.padding(_:)`), sized by the child.
@MainActor
final class UKHouseholdPaddedView: UIView {
    init(_ child: UIView, insets: UIEdgeInsets) {
        super.init(frame: .zero)
        addSubview(child)
        child.ukPin(to: self, insets: insets)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A scroll view of one column, centred and capped at a readable width (`ScrollView { VStack { … }.padding().frame(maxWidth:) }`).
@MainActor
final class UKColumnContainer {
    let scrollView = UIScrollView()
    let column: UIStackView

    /// - Parameters:
    ///   - spacing: Between the column's children.
    ///   - margins: Around the column (`.padding()` is 16 on every side).
    ///   - maxWidth: The widest the padded column gets (840 on the household pages); nil fills the width.
    ///   - clearsHinge: Uses the wider side of the unfolded Duo's hinge (`clearsHinge()`).
    init(spacing: CGFloat, margins: NSDirectionalEdgeInsets, maxWidth: CGFloat? = 840, clearsHinge: Bool = false) {
        column = UIStackView.ukColumn(spacing: spacing)
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = margins
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(holder)
        let centring = UIView()
        centring.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        let outer: UIView = clearsHinge ? UKHingeClearingView(content: centring) : centring
        holder.addSubview(outer)
        outer.ukPin(to: holder)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        var constraints = [
            holder.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            holder.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            holder.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            column.topAnchor.constraint(equalTo: centring.topAnchor),
            column.bottomAnchor.constraint(equalTo: centring.bottomAnchor),
            column.centerXAnchor.constraint(equalTo: centring.centerXAnchor),
        ]
        let fill = column.widthAnchor.constraint(equalTo: centring.widthAnchor)
        fill.priority = UILayoutPriority(999)
        constraints.append(fill)
        if let maxWidth {
            constraints.append(column.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth))
        } else {
            constraints.append(column.widthAnchor.constraint(equalTo: centring.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    convenience init(spacing: CGFloat, padding: CGFloat = UKPageMetrics.side, maxWidth: CGFloat? = 840, clearsHinge: Bool = false) {
        self.init(spacing: spacing, margins: NSDirectionalEdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding),
                  maxWidth: maxWidth, clearsHinge: clearsHinge)
    }
}

// MARK: - Sections

/// The household tile tints (`HassTokens.Tint.settingsSwitch`, `.settingsControl`) and the away pages' colours (`AwayTint`).
enum UKHouseholdTint {
    static let settingsSwitch = UIColor(HassTokens.RGB.Tint.settingsSwitch)
    static let settingsControl = UIColor(HassTokens.RGB.Tint.settingsControl)
    static let vacation = UIColor(AwayTint.vacationToken)
    static let pending = UIColor(AwayTint.pendingToken)
    static let soloTrip = UIColor(AwayTint.soloTripToken)
}

// MARK: - Page base

/// A scroll view of padded content for a household sheet: it names its scroller for the sheet-fit measurement, so a fitted
/// sheet opens as tall as its tiles (``SheetFitModel``).
@MainActor
final class UKHouseholdSheetContentController: UKPageViewController, UKSheetFitting {
    private let scroll: UIScrollView
    private let content: UIView
    /// The bindings of the views in `content`, kept alive with the sheet.
    private let kept: UKObservationBag

    var sheetFitScrollView: UIScrollView? { scroll }

    /// - Parameters:
    ///   - content: What the scroll view holds, sized by its own constraints (padding included).
    ///   - bag: The bindings of the views in `content`; the sheet keeps them alive.
    init(content: UIView, bag: UKObservationBag = UKObservationBag()) {
        self.content = content
        kept = bag
        scroll = UIScrollView()
        super.init(sheetTitle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.alwaysBounceVertical = false
        install(scrollView: scroll)
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }
}

/// Makes the controller that presents a sheet the one that shows alerts and further sheets: the nearest presented controller.
extension UIViewController {
    var ukTopPresented: UIViewController {
        var top = self
        while let next = top.presentedViewController { top = next }
        return top
    }
}
#endif
