#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Style

/// Colours and shapes local to the vacuum surfaces (`VacuumStyle`), as UIKit colours.
enum UKVacuumStyle {
    /// A status tone's glyph colour.
    static func color(_ tone: VacuumTone) -> UIColor { UIColor(VacuumStyle.colorToken(tone)) }
    /// A command button's glyph colour.
    static func color(_ tone: VacuumController.ActionTone) -> UIColor { UIColor(VacuumStyle.colorToken(tone)) }
    /// A selected room: white with dark ink in a dark sheet, `#1C1C1E` in a light one.
    static let selectedFill = UIColor.ukDynamic(light: .ukRGB(HassTokens.Palette.sheetGround), dark: .white)
    /// Ink on ``selectedFill`` and the order badge's disc.
    static let selectedInk = UIColor.ukDynamic(light: .white, dark: .ukRGB(HassTokens.Palette.sheetGround))
    /// The secondary capsule's fill (Pause, Stop, Edit Area): the system's grey control fill.
    static let secondaryFill = UIColor.secondarySystemFill
    /// The glyph of a status tone, in `HassTokens.Ink.secondary`, for rows without a tone.
    static let secondary = UKDesignInk.secondary

    /// The SF Symbol for an MDI name.
    static func symbol(_ mdi: String) -> String { VacuumStyle.symbol(mdi) }
}

// MARK: - Layout helpers

extension UIView {
    /// `view` inside a plain container with `insets` (SwiftUI `.padding`).
    static func ukInset(_ view: UIView, _ insets: UIEdgeInsets) -> UIView {
        let container = UIView()
        container.addSubview(view)
        view.ukPin(to: container, insets: insets)
        return container
    }

    /// `view` inside a container with `horizontal` padding on both sides.
    static func ukInset(_ view: UIView, horizontal: CGFloat, top: CGFloat = 0, bottom: CGFloat = 0) -> UIView {
        ukInset(view, UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal))
    }

    /// The view controller that owns this view.
    var ukOwningController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}

/// A vertical stack of arranged views, spaced like a SwiftUI `VStack(alignment: .leading, spacing:)`.
@MainActor
func ukVStack(_ views: [UIView], spacing: CGFloat = 0) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = spacing
    return stack
}

/// A view that sizes itself by Auto Layout when a parent asks `sizeThatFits` (a flow or grid child).
class UKSelfFittingView: UIView {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let unbounded = size.width >= CGFloat.greatestFiniteMagnitude / 2
        let target = CGSize(width: unbounded ? UIView.layoutFittingCompressedSize.width : size.width, height: UIView.layoutFittingCompressedSize.height)
        return systemLayoutSizeFitting(target, withHorizontalFittingPriority: unbounded ? .fittingSizeLevel : .required, verticalFittingPriority: .fittingSizeLevel)
    }
}

/// Hosts a hand-laid view that measures itself by width (`UKGridMeasuring`) and gives it an Auto Layout height, so grids, flows and
/// section headers can sit in a stack view.
@MainActor
final class UKMeasuredView<Content: UIView & UKGridMeasuring>: UIView {
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = ceil(content.gridHeight(forWidth: bounds.width))
        if abs(heightConstraint.constant - height) > 0.5 { heightConstraint.constant = height }
        content.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }
}

// MARK: - Section

/// A titled block in the vacuum sheet (`VacuumSection`): a 15 pt Semibold secondary header over the group it names and an optional
/// footer.
@MainActor
final class UKVacuumSection: UIStackView {
    init(_ title: String, footer: String? = nil, content: [UIView]) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = HassTokens.Spacing.s
        let header = UILabel()
        header.numberOfLines = 0
        header.text = title
        header.textColor = UKDesignInk.secondary
        header.adjustsFontForContentSizeCategory = true
        header.font = UIFont.ukFont(.subheadline, weight: .semibold)
        header.accessibilityTraits = .header
        addArrangedSubview(.ukInset(header, horizontal: HassTokens.Spacing.l))
        content.forEach(addArrangedSubview)
        if let footer { addArrangedSubview(UKVacuumDescription(footer)) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Supporting copy under a group, inset to its text (`VacuumDescription`, the 13 pt footer).
@MainActor
final class UKVacuumDescription: UIView {
    let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)

    init(_ text: String) {
        super.init(frame: .zero)
        label.text = text
        addSubview(label)
        label.ukPin(to: self, insets: UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A card on the sheet's cell colour at the module radius (`vacuumGroup()`).
@MainActor
final class UKVacuumGroupCard: UIView {
    init(_ content: UIView, insets: UIEdgeInsets = UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l)) {
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        addSubview(content)
        content.ukPin(to: self, insets: insets)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Order chip

/// A room's cleaning order: a numeral on a disc (`VacuumOrderBadge`).
@MainActor
final class UKVacuumOrderBadge: UIView {
    private let label = UILabel()
    private var size: NSLayoutConstraint!

    init(order: Int) {
        super.init(frame: .zero)
        size = widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
        backgroundColor = UKVacuumStyle.selectedInk
        label.text = "\(order)"
        label.textColor = UKVacuumStyle.selectedFill
        label.adjustsFontForContentSizeCategory = true
        label.font = .ukFont(.footnote, weight: .bold, monospacedDigit: true)
        label.textAlignment = .center
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
            size, heightAnchor.constraint(greaterThanOrEqualToConstant: 24), heightAnchor.constraint(equalTo: widthAnchor),
        ])
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKVacuumOrderBadge, _) in view.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        size.constant = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 24, compatibleWith: traitCollection)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// A selected room in cleaning order: a capsule with a numbered badge (`VacuumOrderChip`).
@MainActor
final class UKVacuumOrderChip: UKSelfFittingView {
    init(order: Int, title: String) {
        super.init(frame: .zero)
        backgroundColor = UKVacuumStyle.selectedFill
        let label = UILabel.uk(.body, weight: .semibold, ink: UKVacuumStyle.selectedInk)
        label.font = UIFont.ukFont(.subheadline, weight: .semibold)
        label.text = title
        let stack = UIStackView(arrangedSubviews: [UKVacuumOrderBadge(order: order), label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.ukPin(to: self, insets: UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 10))
        isAccessibilityElement = true
        accessibilityLabel = "\(order). \(title)"
        layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - Action button

/// The grey 50 pt capsule for commands that are not the screen's primary action (`VacuumSecondaryButtonStyle`). The label stays in the
/// primary ink; the glyph carries the tone.
@MainActor
final class UKVacuumSecondaryButton: UIControl {
    private let glyph = UIImageView()
    private let label = UILabel.uk(.body, weight: .semibold, ink: UKDesignInk.primary, alignment: .center)
    var onTap: (() -> Void)?

    init(title: String, symbol: String, tint: UIColor, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = UKVacuumStyle.secondaryFill
        layer.cornerCurve = .continuous
        label.font = UIFont.ukFont(.body, weight: .semibold)
        label.text = title
        glyph.tintColor = tint
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UIFont.ukFont(.body, weight: .semibold)))
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        glyph.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [glyph, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = HassTokens.Spacing.s
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: HassTokens.Spacing.l),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -HassTokens.Spacing.l),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UKPrimaryButtonStyle.height),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { onTap?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapWidth.set(label, in: self, reserving: 2 * HassTokens.Spacing.l + glyph.intrinsicContentSize.width + HassTokens.Spacing.s)
        layer.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool { didSet { updateAlpha() } }
    override var isEnabled: Bool { didSet { updateAlpha() } }

    private func updateAlpha() { alpha = isEnabled ? (isHighlighted ? 0.75 : 1) : 0.45 }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? .button : [.button, .notEnabled] }
        set {}
    }
}

/// A command button (`VacuumActionButton`): the screen's one primary capsule for a primary action such as Clean, else a grey 50 pt
/// capsule with a toned glyph. The action's detail shows under it and is always the button's spoken value.
@MainActor
final class UKVacuumActionButton: UIStackView {
    init(action: VacuumController.Action, identifier: String? = nil, showsDetail: Bool = true, perform: @escaping () -> Void) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = HassTokens.Spacing.xs
        let id = identifier ?? "vacuum.action.\(action.kind.rawValue)"
        let button: UIView
        if action.tone == .primary {
            let primary = UKPrimaryButton(action.title, systemImage: UKVacuumStyle.symbol(action.icon)) {
                UKTapFeedback.tap()
                perform()
            }
            primary.isEnabled = !action.isDisabled
            primary.accessibilityIdentifier = id
            primary.accessibilityValue = action.detail ?? ""
            button = primary
        } else {
            let secondary = UKVacuumSecondaryButton(title: action.title, symbol: UKVacuumStyle.symbol(action.icon), tint: UKVacuumStyle.color(action.tone)) {
                UKTapFeedback.tap()
                perform()
            }
            secondary.isEnabled = !action.isDisabled
            secondary.accessibilityIdentifier = id
            secondary.accessibilityValue = action.detail ?? ""
            button = secondary
        }
        addArrangedSubview(button)
        if showsDetail, let detail = action.detail {
            let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            label.text = detail
            label.isAccessibilityElement = false
            addArrangedSubview(.ukInset(label, horizontal: HassTokens.Spacing.l))
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Setting row

/// One select as a pop-up row (`VacuumSettingRow`; direction G, Controls: Choosing one option): the title at the leading edge, the value and
/// a pop-up chevron in the action blue at the trailing edge, for Mode, Fan, Water and Passes alike (owner, 2026-10-28: no segmented
/// controls). The long description is the row's VoiceOver hint. Only the trailing value is the menu's button: a menu hides its source
/// while it is open, so the whole row must not be the label (owner report, 2026-10-13). At accessibility sizes the menu drops under the title.
@MainActor
final class UKVacuumSettingRow: UIView {
    private let setting: VacuumController.Setting
    private let onSelect: (String) -> Void
    private var content: UIView?

    init(setting: VacuumController.Setting, onSelect: @escaping (String) -> Void) {
        self.setting = setting
        self.onSelect = onSelect
        super.init(frame: .zero)
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var symbol: String { UKVacuumStyle.symbol(setting.icon) }

    /// The canonical row with the menu as its accessory (under the text at accessibility sizes); the menu carries the title as its name.
    private func rebuild() {
        content?.removeFromSuperview()
        let row = UKRowView(.init(setting.title, symbol: symbol), accessory: menu(), surface: .sheet)
        row.isTextAccessible = false
        addSubview(row)
        row.ukPin(to: self)
        content = row
    }

    private func menu() -> UIView {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = setting.valueLabel
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.ukFont(.body)
            return attributes
        }
        configuration.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(font: UIFont.ukFont(.footnote, weight: .semibold)))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = HassTokens.Spacing.xs
        configuration.contentInsets = .zero
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.baseForegroundColor = setting.isDisabled ? UKDesignInk.secondary : UKDesignInk.action
        button.configuration = configuration
        button.contentHorizontalAlignment = .trailing
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(options: .displayInline, children: setting.options.map { option in
            UIAction(title: setting.label(for: option), state: option == setting.value ? .on : .off) { [onSelect] _ in onSelect(option) }
        })
        button.isEnabled = !setting.isDisabled
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        // A short value ("1x" and a chevron) is under 44 pt wide: the menu is still a full target (HIG: 44 x 44 pt).
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        button.accessibilityLabel = setting.title
        button.accessibilityValue = setting.valueLabel
        button.accessibilityHint = setting.detail ?? ""
        button.accessibilityIdentifier = "vacuum.setting.\(setting.title)"
        return button
    }
}

// MARK: - Settings group

/// The Cleaning Settings group (`VacuumSettingsGroup`): Mode, Fan, Water and Passes on one card. A row the chosen mode makes meaningless
/// (Water while Mode is Vacuum, Fan while it is Mop) collapses and fades; its hairline goes with it. The card's background, corners and
/// hairlines belong to the group, so they are right at every frame and everything below slides with it. Reduce Motion cross-fades, and a
/// change from a reapply or while the sheet is not on screen applies at once (`VacuumShapeMotion`).
@MainActor
final class UKVacuumSettingsGroup: UIView {
    private struct Entry {
        var row: VacuumCleaningSettingRow
        var view: UKVacuumSettingRow
        var wrapper: UIStackView
        var hairline: UKHairline?
    }

    private let card = UIView()
    private let stack = UIStackView()
    private var entries: [Entry] = []
    private let onSelect: (VacuumController.Setting, String) -> Void

    init(onSelect: @escaping (VacuumController.Setting, String) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        card.backgroundColor = UKDesignSurface.sheetCell
        card.layer.cornerRadius = HassTokens.Radius.module
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        addSubview(card)
        card.ukPin(to: self)
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        stack.ukPin(to: card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `rows`. The same rows with another shown set animate; anything else rebuilds.
    func update(rows: [VacuumCleaningSettingRow], animated: Bool) {
        if entries.map(\.row.id) != rows.map(\.id) {
            build(rows)
            return
        }
        let changed = zip(entries, rows).contains { $0.row.isShown != $1.isShown }
        for (index, row) in rows.enumerated() where entries[index].row != row {
            let shownChanged = entries[index].row.isShown != row.isShown
            entries[index].row = row
            if !shownChanged && entries[index].row.setting != row.setting { build(rows); return }
        }
        guard changed else { return }
        let reduce = UKDesign.reduceMotion
        let apply = { [self] in
            for (index, row) in rows.enumerated() {
                entries[index].wrapper.isHidden = !row.isShown
                entries[index].wrapper.alpha = row.isShown ? 1 : 0
            }
        }
        if animated, window != nil, !reduce {
            UIView.animate(withDuration: MotionTokens.standardDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { [self] in
                apply()
                ukLayoutAncestors()
            }
        } else if animated, window != nil {
            UIView.transition(with: self, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .allowUserInteraction]) { [self] in
                apply()
                ukLayoutAncestors()
            }
        } else {
            apply()
            ukLayoutAncestors()
        }
    }

    private func build(_ rows: [VacuumCleaningSettingRow]) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        entries = rows.enumerated().map { index, row in
            let view = UKVacuumSettingRow(setting: row.setting) { [weak self] in self?.onSelect(row.setting, $0) }
            // Each row owns the hairline above it, so a collapsed row takes its hairline with it.
            let hairline = index == 0 ? nil : UKHairline(inset: .scaledTextInset, surface: .sheet)
            let wrapper = UIStackView(arrangedSubviews: [hairline, view].compactMap { $0 })
            wrapper.axis = .vertical
            wrapper.clipsToBounds = true
            wrapper.isHidden = !row.isShown
            wrapper.alpha = row.isShown ? 1 : 0
            stack.addArrangedSubview(wrapper)
            return Entry(row: row, view: view, wrapper: wrapper, hairline: hairline)
        }
    }

    /// Lays out the chain of ancestors up to the scroll view so the height change animates the content below it.
    private func ukLayoutAncestors() {
        var view: UIView? = self
        while let current = view {
            current.layoutIfNeeded()
            if current is UIScrollView { break }
            view = current.superview
        }
    }
}

// MARK: - Status tiles

/// A grid of tiles of one kind (`DynamicGridLayout` + `.equalHeightTiles()`): `minWidth` scaled with the subheadline, at most
/// `maxColumns`, one column at accessibility sizes when `singleAtAccessibility`.
@MainActor
final class UKVacuumTileGrid: UIView, UKGridMeasuring {
    private let grid: UKDynamicGridView
    private let measured: UKMeasuredView<UKDynamicGridView>
    private let minWidth: CGFloat
    private let maxColumns: Int
    private let singleAtAccessibility: Bool

    init(views: [UIView], minWidth: CGFloat, maxColumns: Int, singleAtAccessibility: Bool = false) {
        self.minWidth = minWidth
        self.maxColumns = maxColumns
        self.singleAtAccessibility = singleAtAccessibility
        grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: minWidth, maxColumns: maxColumns, spacing: HassTokens.Spacing.s, equalRowHeights: true))
        measured = UKMeasuredView(grid)
        super.init(frame: .zero)
        grid.setItems(views.map { UKGridItem($0) })
        addSubview(measured)
        measured.ukPin(to: self)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKVacuumTileGrid, _) in view.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: minWidth, compatibleWith: traitCollection)
        grid.configuration.maxColumns = singleAtAccessibility && traitCollection.ukIsAccessibilitySize ? 1 : maxColumns
        measured.invalidate()
    }

    /// The height at `width`, asked of the grid itself: a grid nested in another grid (a tile row of ``UKVacuumActionTile``s) is measured by
    /// this, not by its Auto Layout height, which is a placeholder until its first layout pass (the Edit Area and Clear Area tiles sat under
    /// Use Rooms, and the Resume and Cancel row was cut short, so the last controls could not be scrolled above the section bar).
    func gridHeight(forWidth width: CGFloat) -> CGFloat { grid.gridHeight(forWidth: width) }

    /// Measures again after a tile changed height.
    func remeasure() {
        grid.invalidateLayout()
        measured.invalidate()
    }
}

/// The Status, Battery and Dock tiles (`VacuumStatusTiles`): equal in width whatever the value, one column at accessibility sizes. They
/// are the shared flat tile (no sheen, press response or chevron) in its stacked arrangement.
@MainActor
final class UKVacuumStatusTiles: UIView {
    init(tiles: [VacuumStatusTile], environment: UKTileEnvironment) {
        super.init(frame: .zero)
        var env = environment
        env.layout = .stackedTop
        let views = tiles.map { tile -> UIView in
            let model = UKGlassTileModel(
                title: tile.caption, subtitle: tile.value, symbol: tile.symbolIsMDI ? VacuumStyle.symbol(tile.symbol) : tile.symbol,
                tint: Self.color(tile.tint), family: .cleaning, isActive: false, behavior: .inert,
                identifier: tile.kind == .status ? "vacuum.status" : "vacuum.status.\(tile.kind.rawValue)", spokenValue: tile.value)
            return UKGlassTileView(model: model, environment: env)
        }
        let grid = UKVacuumTileGrid(views: views, minWidth: 96, maxColumns: 3, singleAtAccessibility: true)
        addSubview(grid)
        grid.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The glyph colour for a tile's tint.
    static func color(_ tint: VacuumStatusTile.Tint) -> UIColor {
        switch tint {
        case let .tone(tone): UKVacuumStyle.color(tone)
        case .primary: UKDesignInk.primary
        case .secondary: UKDesignInk.secondary
        }
    }
}

// MARK: - Action tile

/// A command as the shared action tile (text, then one disc; `VacuumActionTile`): the body and the disc do the same thing. A dim command
/// stays in place with its reason as the VoiceOver value. The explanation, when there is one, is the footer under it (owner, 2026-10-28),
/// never a line inside the tile.
@MainActor
final class UKVacuumActionTile: UIStackView, UKGridMeasuring {
    let tile: UKGlassTileView
    private let tileGrid: UKVacuumTileGrid
    private var footerView: UIView?

    init(title: String, subtitle: String? = nil, symbol: String, identifier: String, spec: TileActionSpec? = nil, isFilled: Bool = false,
         isUnavailable: Bool = false, spokenValue: String? = nil, footer: String? = nil, environment: UKTileEnvironment, perform: @escaping () -> Void) {
        let spec = spec ?? TileActionSpec(id: "do", verb: title, symbol: symbol, phase: isUnavailable ? .unavailable : .ready, feedback: .momentary)
        let model = UKGlassTileModel(
            title: title, subtitle: subtitle, symbol: symbol, family: .cleaning, isActive: isFilled, isUnavailable: spec.phase == .unavailable,
            behavior: .perform(spec.id), actions: [TileActionItem(spec)], identifier: identifier,
            spokenValue: (spokenValue?.isEmpty == false) ? spokenValue : nil)
        tile = UKGlassTileView(model: model, environment: environment) { perform() }
        tile.onPerform = { _ in perform() }
        tileGrid = UKVacuumTileGrid(views: [tile], minWidth: 150, maxColumns: 1)
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        spacing = HassTokens.Spacing.xs
        // A grid of one measures the tile at the width it is given, as SwiftUI's full-width tile does.
        addArrangedSubview(tileGrid)
        if let footer {
            let description = UKVacuumDescription(footer)
            footerView = description
            addArrangedSubview(description)
        }
    }

    /// The tile's height at `width`, with its footer under it (see ``UKVacuumTileGrid/gridHeight(forWidth:)``).
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        var height = tileGrid.gridHeight(forWidth: width)
        if let footerView {
            height += spacing + footerView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        return ceil(height)
    }

    /// A tile for a vacuum command. The description is the VoiceOver value (and the footer under a dock tile).
    convenience init(_ command: VacuumCommandTile, environment: UKTileEnvironment, perform: @escaping () -> Void) {
        self.init(title: command.action.title, subtitle: command.subtitle, symbol: command.spec.symbol,
                  identifier: "vacuum.action.\(command.action.kind.rawValue)", spec: command.spec, isFilled: command.isFilled,
                  spokenValue: command.action.detail, footer: command.footer, environment: environment, perform: perform)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A set of action tiles side by side (Pause and Stop, Edit Area and Clear Area), stacked at accessibility sizes (`VacuumTileRow`).
@MainActor
func ukVacuumTileRow(_ tiles: [UIView]) -> UIView {
    UKVacuumTileGrid(views: tiles, minWidth: 150, maxColumns: 2)
}

// MARK: - Choice tile

/// A Rooms or Auto-Clean tile (`VacuumChoiceTileView`; the selection tile, `.agents/design/action-navigation-tiles.md`, rollout A): chosen is
/// the filled face with the numbered order disc (Rooms) or a check (Auto-Clean), unchosen is dark with an empty ring. It is one element to
/// VoiceOver, selected when chosen, with the order in its label.
@MainActor
final class UKVacuumChoiceTile: UIView {
    let tile: UKGlassTileView
    private let identifier: String
    private var perform: () -> Void

    init(tile model: VacuumChoiceTile, identifier: String, environment: UKTileEnvironment, perform: @escaping () -> Void) {
        self.identifier = identifier
        self.perform = perform
        tile = UKGlassTileView(model: Self.model(model, identifier: identifier), environment: environment)
        super.init(frame: .zero)
        addSubview(tile)
        tile.ukPin(to: self)
        tile.action = { [weak self] in self?.perform() }
        tile.onPerform = { [weak self] _ in self?.perform() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ model: VacuumChoiceTile, perform: @escaping () -> Void) {
        self.perform = perform
        tile.configure(Self.model(model, identifier: identifier))
    }

    private static func model(_ tile: VacuumChoiceTile, identifier: String) -> UKGlassTileModel {
        let id = "choose"
        let item = TileActionItem(id: id, verb: tile.isChosen ? "Deselect" : "Select", symbol: tile.isChosen ? "checkmark" : "circle",
                                  phase: tile.isUnavailable ? .unavailable : .ready, feedback: .optimistic,
                                  selection: tile.order.map { .ordered(position: $0) } ?? .single(isSelected: tile.isChosen))
        var model = UKGlassTileModel(title: tile.title, subtitle: tile.subtitle, symbol: VacuumStyle.symbol(tile.icon), family: .cleaning,
                                     isActive: tile.isChosen, isUnavailable: tile.isUnavailable, behavior: .perform(id), actions: [item],
                                     identifier: identifier, spokenValue: tile.accessibilityValue)
        model.spokenLabel = tile.accessibilityLabel
        return model
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { tile.sizeThatFits(size) }
}

extension UKVacuumChoiceTile: UKGridMeasuring {
    func gridHeight(forWidth width: CGFloat) -> CGFloat { tile.gridHeight(forWidth: width) }
    var gridMinimumWidth: CGFloat { tile.gridMinimumWidth }
}
#endif
