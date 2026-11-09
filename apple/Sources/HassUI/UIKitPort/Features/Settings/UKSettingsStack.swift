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
    var kind: UKSettingsRowKind = .link { didSet { setNeedsLayout() } }
    var isTransparent = false { didSet { restyle() } }
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
        let vertical = kind == .control ? InsetGroupedMetrics.controlPadding : InsetGroupedMetrics.rowPadding
        topPadding.constant = isTransparent ? 0 : vertical
        bottomPadding.constant = isTransparent ? 0 : -vertical
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

/// A scroll view whose drag takes over from a row that is being pressed (a `UIControl` keeps its touch by default, so a drag that
/// began on a row would not scroll the page).
final class UKStackScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

// MARK: - Driver

/// The settings page as a stack (`InsetGroupedStack`, owner 2026-10-27): a `UIScrollView` over a plain column of section cards,
/// built once when the page opens, so every row is in the accessibility tree from the first frame and nothing is made or sized
/// while scrolling. The same rows, headers and footers as ``UKSettingsListDriver``, diffed by id and signature so a change
/// reconfigures only the rows that changed (a slider being dragged is left alone).
@MainActor
final class UKSettingsStackDriver {
    let style: UKSettingsListDriver.Style
    let scrollView = UKStackScrollView()
    private let column = UIStackView()
    private var sections: [UKSettingsListSection] = []
    private var cells: [String: UKSettingsStackCell] = [:]
    private var signatures: [String: String] = [:]
    private var headerSignatures: [String: String] = [:]
    private var sectionViews: [String: UKSettingsStackSection] = [:]

    init(style: UKSettingsListDriver.Style) {
        self.style = style
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.backgroundColor = .clear
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 0
        column.isLayoutMarginsRelativeArrangement = true
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        updateMargins()
    }

    /// The card's side margin for the window's width class (``InsetGroupedMetrics/margin(regularWidth:)``).
    func updateMargins() {
        let margin = InsetGroupedMetrics.margin(regularWidth: scrollView.traitCollection.horizontalSizeClass == .regular)
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: margin, bottom: InsetGroupedMetrics.sectionTop, trailing: margin)
    }

    func setSections(_ newSections: [UKSettingsListSection], animated: Bool = false) {
        sections = newSections
        updateMargins()
        var liveCells: [String: UKSettingsStackCell] = [:]
        var order: [UIView] = []
        for (index, section) in newSections.enumerated() {
            let followsFooter = index > 0 && newSections[index - 1].footer != nil
            var rowCells: [UKSettingsStackCell] = []
            for (position, row) in section.rows.enumerated() {
                let cell = cells[row.id] ?? UKSettingsStackCell(frame: .zero)
                if cells[row.id] == nil || signatures[row.id] != row.signature {
                    cell.reset()
                    cell.style = style
                    cell.kind = row.kind
                    cell.setAction(row.isEnabled ? row.action : nil)
                    row.configure(cell)
                    // Only the text dims (`.opacity(0.4)` on the label), not the cell's fill and hairline.
                    if !row.isEnabled && row.action != nil { cell.dimContent() }
                    signatures[row.id] = row.signature
                }
                cell.setAction(row.isEnabled ? row.action : nil)
                cell.isFirst = position == 0
                cell.isLast = position == section.rows.count - 1
                cell.aboveIsLink = position > 0 && section.rows[position - 1].kind == .link
                liveCells[row.id] = cell
                rowCells.append(cell)
            }
            let headerSignature: String? = {
                guard case let .view(_, signature, _)? = section.header else { return nil }
                return signature
            }()
            let view = sectionViews[section.id] ?? UKSettingsStackSection(style: style)
            view.update(section: section, rows: rowCells, followsFooter: followsFooter,
                        rebuildHeader: headerSignature != headerSignatures[section.id] || sectionViews[section.id] == nil)
            headerSignatures[section.id] = headerSignature ?? ""
            sectionViews[section.id] = view
            order.append(view)
        }
        for (id, cell) in cells where liveCells[id] == nil { cell.removeFromSuperview(); signatures[id] = nil }
        cells = liveCells
        let alive = Set(newSections.map(\.id))
        for id in sectionViews.keys where !alive.contains(id) { sectionViews[id] = nil }
        if !column.arrangedSubviews.elementsEqual(order, by: ===) {
            for old in column.arrangedSubviews { column.removeArrangedSubview(old); old.removeFromSuperview() }
            order.forEach { column.addArrangedSubview($0) }
        }
    }

    /// Changes a section's footer text where it stands (the Version footer after a copy).
    func updateFooter(sectionID: String, text: String) {
        guard let index = sections.firstIndex(where: { $0.id == sectionID }), sections[index].footer != text else { return }
        sections[index].footer = text
        sectionViews[sectionID]?.setFooter(text, identifier: sections[index].footerIdentifier)
    }
}

// MARK: - Section

/// One section of the stack (`InsetGroupedSectionView`): a header, a card of rows and a footer.
@MainActor
final class UKSettingsStackSection: UIView {
    private let style: UKSettingsListDriver.Style
    private let stack = UIStackView()
    private let card = UIStackView()
    private var headerView: UIView?
    private var footerView: UIView?
    private var footerLabel: UILabel?
    private var topPadding: NSLayoutConstraint!
    private var footerInk: UIColor?

    init(style: UKSettingsListDriver.Style) {
        self.style = style
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.axis = .vertical
        card.alignment = .fill
        card.spacing = 0
        addSubview(stack)
        topPadding = stack.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            topPadding, stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var headerInk: UIColor { style == .wallpaper ? UKInk.onDarkSecondary : UKDesignInk.secondary }

    func update(section: UKSettingsListSection, rows: [UKSettingsStackCell], followsFooter: Bool, rebuildHeader: Bool) {
        topPadding.constant = InsetGroupedMetrics.sectionTop
            + (section.header == nil && !followsFooter ? InsetGroupedMetrics.headerlessExtra : 0)
        footerInk = section.footerInk
        // Header
        if rebuildHeader || (section.header == nil) != (headerView == nil) {
            headerView?.removeFromSuperview()
            headerView = nil
            if let header = section.header {
                let view = makeHeader(header)
                headerView = view
                stack.insertArrangedSubview(view, at: 0)
            }
        }
        // Card
        if card.superview == nil { stack.addArrangedSubview(card) }
        if !card.arrangedSubviews.elementsEqual(rows, by: ===) {
            for old in card.arrangedSubviews { card.removeArrangedSubview(old); old.removeFromSuperview() }
            rows.forEach(card.addArrangedSubview)
        }
        // Footer
        if let footer = section.footer {
            setFooter(footer, identifier: section.footerIdentifier)
        } else if let footerView {
            footerView.removeFromSuperview()
            self.footerView = nil
            footerLabel = nil
        }
    }

    func setFooter(_ text: String, identifier: String?) {
        if footerView == nil {
            let container = UIView()
            let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: InsetGroupedMetrics.footerGap),
                // The gap after a footer is shorter than after a card: the label gives back part of the next section's top.
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: InsetGroupedMetrics.footerOverlap),
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: InsetGroupedMetrics.captionInset),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -InsetGroupedMetrics.captionInset),
            ])
            label.isAccessibilityElement = true
            label.accessibilityTraits = .staticText
            footerView = container
            footerLabel = label
            stack.addArrangedSubview(container)
        }
        footerLabel?.text = text
        // White on the wallpaper (4.5:1 over the photo's mid-grey; the system secondary ink and the 85% white both rendered under
        // 4.1:1 and failed the Settings contrast audit on the notifications footer); the system's secondary ink in a sheet.
        footerLabel?.textColor = footerInk ?? (style == .wallpaper ? UKSettingsInk.wallpaperFooter : UKDesignInk.secondary)
        footerLabel?.accessibilityLabel = text
        footerLabel?.accessibilityIdentifier = identifier
    }

    private func makeHeader(_ header: UKSettingsListSection.Header) -> UIView {
        let container = UIView()
        let content: UIView
        switch header {
        case let .title(title):
            let label = UILabel.uk(.body, weight: .semibold, ink: headerInk)
            label.font = UKFont.rowTitle()
            label.text = title
            label.isAccessibilityElement = true
            label.accessibilityLabel = title
            label.accessibilityTraits = [.header, .staticText]
            content = label
        case let .system(title):
            let label = UILabel.uk(.footnote, ink: style == .wallpaper ? UKDesignSurface.secondaryOnWallpaper : UKDesignInk.secondary)
            label.text = title
            label.isAccessibilityElement = true
            label.accessibilityLabel = title
            label.accessibilityTraits = [.header, .staticText]
            content = label
        case let .view(label, _, build):
            content = build()
            content.isAccessibilityElement = true
            content.accessibilityLabel = label
            content.accessibilityTraits = [.header, .staticText]
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -InsetGroupedMetrics.headerGap),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: InsetGroupedMetrics.captionInset),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -InsetGroupedMetrics.captionInset),
        ])
        return container
    }
}
#endif
