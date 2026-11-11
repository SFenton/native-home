#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// What an inventory row asks of its page: open the item editor, ask for a quantity to add to groceries and, where the page deletes,
/// delete (the swipe's Delete, offered to VoiceOver too because a swipe is not discoverable).
struct UKInventoryRowActions {
    var onEdit: () -> Void
    var onShop: () -> Void
    var onDelete: (() -> Void)?
}

/// One inventory card (``InventoryRow``; web `PantryRow`; direction G mockup n6-inventory, redesigned 2026-10-16): the name over its
/// expiry line, then the stock count (above one) in secondary ink, the add-to-groceries cart in the action tint and, when the card
/// opens the item editor, a chevron.
///
/// **Reusing it.** The row draws only its content; the card around it is the caller's (a ``UKInventoryRowCell`` here, a sheet's cell
/// in the Summary sheet's Expired Food tab).
///
/// ```swift
/// let row = UKInventoryRowView(surface: .sheet)
/// row.configure(item: item, model: models.model(for: .allFood), actions: UKInventoryRowActions(onEdit: { open(item) }, onShop: { ask(item) }))
/// // in prepareForReuse: row.reset()
/// ```
/// It binds itself to the page model's shopping state and row errors; `opensEditor` says whether a tap on the row opens the editor (the
/// row installs that tap itself, so the caller wires only `onEdit`). Identifier `inventory.row.<name>`, with `inventory.row.cart`,
/// `inventory.row.edit` and `inventory.row.error` inside.
@MainActor
final class UKInventoryRowView: UKRowView, UIGestureRecognizerDelegate {
    /// A tap on the row opens the editor: multi-batch cards always do, a single batch needs row ids to edit.
    private(set) var opensEditor = false
    private(set) var item: InventoryDisplayItem?

    private var model: InventoryListModel?
    private var actions: UKInventoryRowActions?
    private let bag = UKObservationBag()
    private let nameLabel: UILabel
    private let toneIcon = UIImageView()
    private let subtitleLabel: UILabel
    private let errorLabel = UILabel.uk(.footnote, ink: UKDesignInk.error)
    private let copy = UIStackView()
    private let cart = UKInventoryCartButton()
    private let chevron = UKInventoryChevronButton()
    private let actionsRow = UIStackView()

    /// A page on the module, or the inside of a sheet (the secondary ink follows it).
    override var surface: TileSurface { didSet { if surface != oldValue { render() } } }

    /// The canonical row (``UKRowView``, module metrics): the name, expiry line and error as its text block, the stock count (above one)
    /// as its value, and the cart and the chevron as its accessory. The count wraps within at most half the row (``UKValueLabel``): a
    /// plain wrapping count that refused to shrink left the row's measurement undecided, and some names wrapped a letter a line (owner,
    /// 2026-10-31: tall Expired Food and Food Spaces rows).
    init(surface: TileSurface = .page) {
        let name = UKRowTextLabel.make(.body, ink: UKDesignInk.primary)
        let subtitle = UKRowTextLabel.make(.subheadline, ink: UKDesignInk.secondary)
        nameLabel = name
        subtitleLabel = subtitle
        toneIcon.setContentHuggingPriority(.required, for: .horizontal)
        toneIcon.isAccessibilityElement = false
        toneIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .small)

        let subtitleRow = UIStackView(arrangedSubviews: [toneIcon, subtitle])
        subtitleRow.axis = .horizontal
        subtitleRow.alignment = .firstBaseline
        subtitleRow.spacing = HassTokens.Spacing.xs

        errorLabel.accessibilityIdentifier = "inventory.row.error"
        copy.axis = .vertical
        copy.alignment = .fill
        copy.spacing = 2
        [name, subtitleRow, errorLabel].forEach(copy.addArrangedSubview)
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.isAccessibilityElement = true
        subtitle.isAccessibilityElement = true
        errorLabel.isAccessibilityElement = true

        // The cart and the chevron: two 44 pt targets with a gap between them (HIG, Accessibility: space between targets).
        actionsRow.axis = .horizontal
        actionsRow.alignment = .center
        actionsRow.spacing = HassTokens.Spacing.s
        actionsRow.addArrangedSubview(cart)
        actionsRow.addArrangedSubview(chevron)
        actionsRow.setContentHuggingPriority(.required, for: .horizontal)
        actionsRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        var content = UKRowContent("", style: .module)
        content.verticalPadding = HassTokens.Spacing.s
        content.minHeight = 64
        super.init(content, accessory: actionsRow, textView: copy, surface: surface)
        accessoryTrailingInset = HassTokens.Spacing.xs
        isTextAccessible = false
        cart.accessibilityIdentifier = "inventory.row.cart"
        cart.addAction(UIAction { [weak self] _ in self?.actions?.onShop() }, for: .touchUpInside)
        chevron.accessibilityIdentifier = "inventory.row.edit"
        chevron.addAction(UIAction { [weak self] _ in self?.actions?.onEdit() }, for: .touchUpInside)
        // A touch convenience: the whole row opens the editor. Assistive technologies reach it through the chevron's "Edit <name>"
        // button, so the gesture adds no element of its own.
        accessibilityContainerType = .semanticGroup
        // A recognizer on the row rather than the list's selection: with the search field up, the first touch on a scroll view's cell
        // went to the keyboard's dismissal and never selected (owner, 2026-10-30: only the chevron opened the item).
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The name, expiry line and error while they show, then the cart and the chevron.
    override var accessibilityElements: [Any]? {
        get {
            var elements: [Any] = [nameLabel, subtitleLabel]
            if !errorLabel.isHidden { elements.append(errorLabel) }
            elements.append(cart)
            if !chevron.isHidden { elements.append(chevron) }
            return elements
        }
        set {}
    }

    /// The cart and the chevron are plain controls (not `UIButton`), which UIKit does not shield from a superview's tap recognizer: the cart's
    /// touch was cancelled and the row opened the editor instead of the quantity prompt.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view?.isDescendant(of: cart) ?? false) && !(touch.view?.isDescendant(of: chevron) ?? false)
    }

    /// A tap on the row's text or empty space: puts the keyboard away, then opens the editor.
    @objc private func rowTapped() {
        guard opensEditor else { return }
        window?.endEditing(true)
        actions?.onEdit()
    }

    // MARK: Configure

    /// Shows `item` and follows `model`'s shopping state and row errors.
    func configure(item: InventoryDisplayItem, model: InventoryListModel, actions: UKInventoryRowActions) {
        self.item = item
        self.model = model
        self.actions = actions
        bag.removeAll()
        accessibilityIdentifier = "inventory.row.\(item.name)"
        bag.observe { [weak self] in self?.render() }
    }

    func performEdit() { actions?.onEdit() }

    /// A reused cell stops following its last item.
    func reset() {
        bag.removeAll()
        item = nil
        model = nil
    }

    private func render() {
        guard let item, let model else { return }
        let batches = model.batches(for: item).count
        let multiBatch = batches > 1
        let expiry = InventoryCatalog.expiryInfo(item.soonestExpiry(model.calendar), calendar: model.calendar)
        // The expiry alone: the stock count is the trailing number, so the line never grows long enough to push the actions
        // under the text (owner design pass, 2026-10-16).
        let subtitle = InventoryCatalog.rowSubtitle(expiry, quantity: nil, batchCount: batches)
        let deletable = model.deletableRows(of: item) != nil
        // Multi-batch cards always open the editor; a single batch needs row ids to edit.
        opensEditor = multiBatch || deletable
        let tone = multiBatch ? nil : expiry.tone
        let state = model.shopping[item.id, default: .idle]
        let error = model.rowErrors[item.id]

        nameLabel.text = item.name
        subtitleLabel.text = subtitle
        let ink = Self.color(tone, surface: surface)
        subtitleLabel.textColor = ink
        toneIcon.isHidden = tone == nil
        toneIcon.tintColor = ink
        if let tone { toneIcon.image = UIImage(systemName: tone == .expired ? "exclamationmark.triangle.fill" : "clock.fill") }
        errorLabel.text = error
        errorLabel.isHidden = error == nil
        var content = rowContent
        content.value = item.shownQuantity.map { InventoryFormat.quantity($0) }
        update(content, accessory: actionsRow)
        (nameLabel as? UKRowTextLabel)?.frameView = copy
        (subtitleLabel as? UKRowTextLabel)?.frameView = copy
        errorLabel.isAccessibilityElement = error != nil
        // The name and its count are one spoken text, found by either (the SwiftUI row combines them); the name stays its identifier.
        nameLabel.accessibilityLabel = Self.accessibilityText(item: item, subtitle: subtitle, tone: tone, error: error)
        nameLabel.accessibilityIdentifier = item.name
        subtitleLabel.accessibilityLabel = subtitle
        // The swipe's Delete (single-batch, deletable cards) as a VoiceOver action on the name, where a swipe is not discoverable.
        let canDelete = deletable && !multiBatch && actions?.onDelete != nil
        nameLabel.accessibilityCustomActions = canDelete
            ? [UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in self?.actions?.onDelete?(); return true }] : nil

        cart.show(state, name: item.name)
        chevron.isHidden = !opensEditor
        chevron.show(name: item.name, multiBatch: multiBatch, ink: UKDesignSurface.secondary(on: surface))
    }

    /// Expiry tone colours (``InventoryTone``): G's orange (soon) and red (expired), from the tokens that keep 4.5:1 on the dense
    /// module and in sheets; a glyph carries the tone too, so colour isn't the only cue.
    static func color(_ tone: ExpiryInfo.Tone?, surface: TileSurface) -> UIColor {
        switch tone {
        case .expired: UKDesignInk.error
        case .soon: UKDesignInk.warning
        case nil: UKDesignSurface.secondary(on: surface)
        }
    }

    /// "Honey, Quantity 3, Expires in 2 days, Expiring soon": the row's one spoken line for its text.
    static func accessibilityText(item: InventoryDisplayItem, subtitle: String, tone: ExpiryInfo.Tone?, error: String?) -> String {
        var parts = [item.name]
        if let quantity = item.shownQuantity { parts.append("Quantity \(InventoryFormat.quantity(quantity))") }
        parts.append(subtitle)
        if tone == .soon { parts.append("Expiring soon") }
        if let error { parts.append(error) }
        return parts.joined(separator: ", ")
    }
}

/// A text of the row that VoiceOver and UI tests find by its own words, framed as the whole text block (a hit area of a line's height is
/// too small to interact with; the block is what the row's text offers).
final class UKRowTextLabel: UILabel {
    weak var frameView: UIView?

    static func make(_ style: UIFont.TextStyle, ink: UIColor) -> UILabel {
        let label = UKRowTextLabel()
        label.font = .ukFont(style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = ink
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    override var accessibilityFrame: CGRect {
        get {
            guard let frameView else { return super.accessibilityFrame }
            return UIAccessibility.convertToScreenCoordinates(frameView.bounds, in: frameView)
        }
        set {}
    }
}

// MARK: - Buttons

/// The cart in the action tint (a quiet bare symbol), an arc while adding, a check once added; a 44 pt target (scaled with the text).
final class UKInventoryCartButton: UIControl {
    private let icon = UIImageView()
    private let arc = UKArcSpinnerView(.compact, label: "Adding to Groceries")
    private var size: NSLayoutConstraint!
    private var tall: NSLayoutConstraint!
    private var current: InventoryListModel.ShoppingState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        arc.color = UKDesignInk.primary
        arc.isUserInteractionEnabled = false
        arc.isAccessibilityElement = false
        arc.isHidden = true
        [icon, arc].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        translatesAutoresizingMaskIntoConstraints = false
        size = widthAnchor.constraint(equalToConstant: 44)
        tall = heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([size, tall])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isAccessibilityElement = true
        accessibilityTraits = .button
        rescale()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKInventoryCartButton, _) in self.rescale() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let side = UIFontMetrics(forTextStyle: .body).scaledValue(for: 44, compatibleWith: traitCollection)
        size.constant = side
        tall.constant = side
    }

    func show(_ state: InventoryListModel.ShoppingState, name: String) {
        let configuration = UIImage.SymbolConfiguration(font: .ukFont(.body))
        switch state {
        case .idle:
            icon.image = UIImage(systemName: "cart.badge.plus", withConfiguration: configuration)
            icon.tintColor = UKDesignInk.action
            icon.isHidden = false
            arc.isHidden = true
            accessibilityLabel = "Add \(name) to shopping list"
        case .adding:
            icon.isHidden = true
            arc.isHidden = false
            accessibilityLabel = "Adding \(name) to shopping list"
        case .added:
            icon.image = UIImage(systemName: "checkmark", withConfiguration: configuration)
            icon.tintColor = UKDesignInk.success
            icon.isHidden = false
            arc.isHidden = true
            accessibilityLabel = "Added \(name) to shopping list"
        }
        isEnabled = state == .idle
        current = state
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.5 : 1 } }
    }
}

/// The chevron that opens the item editor: the row's accessible way into it ("Edit <name>"), a 44 pt target.
final class UKInventoryChevronButton: UIControl {
    private let icon = UIImageView()
    private var size: NSLayoutConstraint!
    private var tall: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        icon.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        icon.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        translatesAutoresizingMaskIntoConstraints = false
        size = widthAnchor.constraint(equalToConstant: 44)
        tall = heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([size, tall])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isAccessibilityElement = true
        accessibilityTraits = .button
        rescale()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKInventoryChevronButton, _) in self.rescale() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let side = UIFontMetrics(forTextStyle: .body).scaledValue(for: 44, compatibleWith: traitCollection)
        size.constant = side
        tall.constant = side
    }

    func show(name: String, multiBatch: Bool, ink: UIColor) {
        icon.image = UIImage(systemName: "chevron.forward", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.rowTitle(traitCollection)))
        icon.tintColor = ink
        accessibilityLabel = "Edit \(name)"
        accessibilityHint = multiBatch ? "Opens each expiration batch" : "Opens the item editor"
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.5 : 1 } }
    }
}

// MARK: - Cell

/// An inventory row as a list cell: the row's share of its section's dense module (the first row's top corners and the last row's
/// bottom corners rounded, the selected wash in a split), a hairline above every row but the first, and the row.
final class UKInventoryRowCell: UICollectionViewListCell {
    private let card = UKModuleRowBackgroundView()
    private let row = UKInventoryRowView()
    private var hairline: UKHairline?
    private var surfaceShown: TileSurface = .page

    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyUpdatesBackgroundConfiguration = false
        automaticallyUpdatesContentConfiguration = false
        backgroundConfiguration = .clear()
        backgroundView = card
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var opensEditor: Bool { row.opensEditor }


    func configure(item: InventoryDisplayItem, model: InventoryListModel, isFirst: Bool, isLast: Bool, selected: Bool, surface: TileSurface,
                   actions: UKInventoryRowActions, animatedCorners: Bool = false) {
        card.configure(density: .dense, surface: surface, isFirst: isFirst, isLast: isLast, selected: selected, animated: animatedCorners)
        row.surface = surface
        row.configure(item: item, model: model, actions: actions)
        hairline?.removeFromSuperview()
        hairline = nil
        if !isFirst {
            let line = UKHairline(inset: .fixed(HassTokens.Spacing.l), surface: surface)
            line.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(line)
            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: contentView.topAnchor),
                line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            hairline = line
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        row.reset()
    }

    /// Measured at the width the layout proposes (``UIKit/UICollectionViewCell/ukFitted(_:)``): a row sized before the list had its width wrapped
    /// one word a line (owner, 2026-10-30, Summary sheet Expired Food and Food Spaces rows).
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(layoutAttributes)
    }
}
#endif
