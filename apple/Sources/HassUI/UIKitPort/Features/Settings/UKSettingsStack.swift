#if os(iOS)
import HassDesign
import UIKit

// MARK: - Cell

/// One row of the settings stack (`InsetGroupedRow`): the caller's row on the module tint (rounded on the card's first and last row),
/// a hairline above it unless it is first, and a wash while it is pressed (`GroupedRowButtonStyle`). The cell owns the row's padding,
/// so a tap anywhere on it activates it.
@MainActor
final class UKSettingsStackCell: UIControl, UKSettingsRowCell {
    var style: UKSettingsListDriver.Style = .wallpaper { didSet { restyle() } }
    var kind: UKSettingsRowKind = .link { didSet { applyPadding() } }
    var isTransparent = false { didSet { restyle(); applyPadding() } }
    /// Whether the row above is a glyph row (its hairline starts at the text).
    var aboveIsLink = false { didSet { updateSeparator() } }
    var isFirst = true { didSet { restyle(); updateSeparator() } }
    var isLast = true { didSet { restyle() } }

    var contentConfiguration: UIContentConfiguration? {
        didSet {
            guard var current = contentConfiguration else { return }
            // The row pads itself: a list cell's own margins would add to it.
            if var list = current as? UIListContentConfiguration {
                list.directionalLayoutMargins = NSDirectionalEdgeInsets.zero
                current = list
            }
            let view = current.makeContentView()
            placeContent(view, minHeight: 0)
        }
    }

    /// The system's accessories (a disclosure chevron) are drawn by the row itself in the stack; trailing views come through
    /// ``addTrailing(_:)``.
    var accessories: [UICellAccessory] = []

    func addTrailing(_ view: UIView) {
        trailing.addArrangedSubview(view)
        trailing.isHidden = false
    }

    private let fill = UIView()
    private let wash = UIView()
    private let separator = UIView()
    private let host = UIStackView()
    private let trailing = UIStackView()
    private var hosted: UIView?
    private var minHeightConstraint: NSLayoutConstraint?
    private var topPadding: NSLayoutConstraint!
    private var bottomPadding: NSLayoutConstraint!
    private var separatorLeading: NSLayoutConstraint!
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for view in [fill, wash] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer.cornerCurve = .continuous
            addSubview(view)
            view.ukPin(to: self)
        }
        wash.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        wash.alpha = 0
        separator.backgroundColor = UKDesignSurface.separator
        separator.isUserInteractionEnabled = false
        separator.isAccessibilityElement = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        host.axis = .horizontal
        host.alignment = .center
        host.spacing = HassTokens.Spacing.s
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.isHidden = true
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        topPadding = host.topAnchor.constraint(equalTo: topAnchor)
        bottomPadding = host.bottomAnchor.constraint(equalTo: bottomAnchor)
        separatorLeading = separator.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            topPadding, bottomPadding,
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InsetGroupedMetrics.leadingInset),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InsetGroupedMetrics.trailingInset),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separatorLeading,
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InsetGroupedMetrics.separatorTrailing),
        ])
        host.addArrangedSubview(trailing)
        applyPadding()
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: UKSettingsStackCell, _) in cell.updateSeparator() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A row with an action is one target: a touch anywhere on it, whatever it holds, is the row's.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return onTap != nil && hit != nil ? self : hit
    }

    override var isHighlighted: Bool {
        didSet { if onTap != nil, !isTransparent { wash.alpha = isHighlighted ? 1 : 0 } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A system list content view keeps the wrap it measured at the width it first had. A cell laid out while its column was still
        // taking its width (the split opening, a fold) would keep a title one word a line in a column 420 pt wide
        // (owner, 2026-11-01); the row measures again whenever its own width changes.
        let width = bounds.width.rounded()
        if width > 1, width != measuredWidth {
            measuredWidth = width
            hosted?.invalidateIntrinsicContentSize()
            invalidateIntrinsicContentSize()
        }
    }

    private var measuredWidth: CGFloat = 0

    /// The row's vertical padding, written to its constraints when the kind or transparency changes, never during layout: a fit taken
    /// before the first layout (the column measuring its holder) then already counts it. Set in `layoutSubviews`, a link measured 30 pt
    /// short and the stack squashed its rows.
    private func applyPadding() {
        let vertical = kind == .control ? InsetGroupedMetrics.controlPadding : InsetGroupedMetrics.rowPadding
        topPadding.constant = isTransparent ? 0 : vertical
        bottomPadding.constant = isTransparent ? 0 : -vertical
    }

    private func restyle() {
        let radius = HassTokens.Radius.module
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        for view in [fill, wash] {
            view.layer.cornerRadius = corners.isEmpty ? 0 : radius
            view.layer.maskedCorners = corners
        }
        if isTransparent {
            fill.backgroundColor = .clear
        } else {
            switch style {
            case .wallpaper: fill.backgroundColor = UKDesignSurface.moduleTint(.thin, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
            case .sheet: fill.backgroundColor = UKDesignSurface.sheetCell
            }
        }
    }

    private func updateSeparator() {
        separator.isHidden = isFirst || isTransparent
        let glyphInset = aboveIsLink && !traitCollection.ukIsAccessibilitySize
        separatorLeading.constant = glyphInset
            ? InsetGroupedMetrics.leadingInset + InsetGroupedMetrics.glyphColumn + HassTokens.Spacing.m
            : InsetGroupedMetrics.leadingInset
    }

    /// Clears what the last row left.
    func reset() {
        contentConfiguration = nil
        accessories = []
        trailing.arrangedSubviews.forEach { $0.removeFromSuperview() }
        trailing.isHidden = true
        hosted?.removeFromSuperview()
        hosted = nil
        minHeightConstraint?.isActive = false
        minHeightConstraint = nil
        isAccessibilityElement = false
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityHint = nil
        accessibilityIdentifier = nil
        accessibilityTraits = []
        accessibilityElements = nil
        alpha = 1
        isTransparent = false
    }

    func showRow(_ view: UIView, insets: NSDirectionalEdgeInsets, minHeight: CGFloat) {
        placeContent(view, minHeight: minHeight)
        // A transparent row (a notice) is the view itself, edge to edge.
        if isTransparent { setNeedsLayout() }
    }

    private func placeContent(_ view: UIView, minHeight: CGFloat) {
        hosted?.removeFromSuperview()
        minHeightConstraint?.isActive = false
        hosted = view
        view.translatesAutoresizingMaskIntoConstraints = false
        host.insertArrangedSubview(view, at: 0)
        if minHeight > 0 {
            let constraint = view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight)
            constraint.isActive = true
            minHeightConstraint = constraint
        }
        // A tap lands on the cell (the control), whatever it holds.
        if onTap != nil { view.isUserInteractionEnabled = false }
    }

    func makeRowElement(label: String, value: String?, hint: String?, traits: UIAccessibilityTraits, identifier: String?) {
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityValue = value
        accessibilityHint = hint
        accessibilityTraits = traits
        accessibilityIdentifier = identifier
    }

    func dimContent() { hosted?.alpha = 0.4 }

    /// The row has an action: its content stops taking touches, so the whole cell is the target.
    func setAction(_ action: (() -> Void)?) {
        onTap = action
        hosted?.isUserInteractionEnabled = action == nil
    }
}

// MARK: - Scroll view

#endif
