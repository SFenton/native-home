#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Presentations

/// The three tabs' content as views for the detail's vertical stack.
@MainActor
enum UKRecipeTabs {
    // MARK: General

    /// Hero image, facts, equipment and the source link (``RecipeGeneralTab``; web `GeneralTab`).
    static func general(_ detail: RecipeDetail, fallbackImageURL: URL?) -> [UIView] {
        var views: [UIView] = []
        let facts = RecipeFormatting.facts(detail)
        views.append(UKRecipeHeroImage(url: detail.primaryImageURL ?? detail.thumbnailURL, fallbackURL: fallbackImageURL ?? detail.thumbnailURL))
        if !facts.isEmpty {
            views.append(UKModuleListView(.thin, hasGlyphs: true, surface: .sheet, rows: facts.map { UKRecipeFactRow(fact: $0) }))
        }
        if detail.capabilities.general == .none {
            views.append(UKRecipeNotice("Servings, time, difficulty, and equipment are not available in the cached Cookidoo metadata."))
        } else {
            views.append(contentsOf: [factList("Devices", detail.general.devices), factList("Optional Devices", detail.general.optionalDevices),
                                      factList("Additional Equipment", detail.general.equipment)].compactMap { $0 })
        }
        if let url = detail.source.canonicalURL {
            let link = UKRecipeLinkRow(title: detail.source.isCookidoo ? "Open in Cookidoo" : "Open Source Recipe", url: url)
            link.accessibilityIdentifier = "recipe.openSource"
            views.append(UKModuleListView(.thin, hasGlyphs: true, surface: .sheet, rows: [link]))
        }
        return views
    }

    /// A titled inset list of names (devices, equipment); nothing when empty.
    private static func factList(_ title: String, _ items: [String]) -> UIView? {
        guard !items.isEmpty else { return nil }
        let rows = items.map { UKRecipeTextRow(text: $0) as UIView }
        return titled(title, quiet: false, list: UKModuleListView(.thin, hasGlyphs: false, surface: .sheet, rows: rows))
    }

    /// A header over an inset list: the header is inset with the rows' text (``RecipeSectionHeader``).
    static func titled(_ title: String, quiet: Bool, list: UIView) -> UIView {
        let header = UKRecipeSectionHeaderLabel(title, isQuiet: quiet)
        let column = UIStackView(arrangedSubviews: [UKRecipeInset(header, horizontal: HassTokens.Spacing.l), list])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        return column
    }

    // MARK: Ingredients

    /// Ingredient checklist with inventory state, and the grocery action (``RecipeIngredientsTab``; web `IngredientsTab`).
    static func ingredients(_ detail: RecipeDetail, model: RecipeDetailModel) -> [UIView] {
        var views: [UIView] = []
        if detail.capabilities.ingredients != .none, detail.ingredientsTruncated {
            views.append(UKRecipeNotice("This ingredient list is truncated."))
        }
        if detail.capabilities.ingredients == .none || detail.ingredients.isEmpty {
            views.append(UKStateMessageView(symbol: "list.bullet", title: "No Ingredients Available",
                                            message: "Ingredient details are not available for this recipe.", identifier: "recipe.ingredients.empty"))
        } else {
            let checklist = detail.capabilities.ingredients == .checklist
            for section in RecipeFormatting.ingredientSections(detail) {
                let rows = section.ingredients.map { UKIngredientRow(detail: detail, ingredient: $0, checklist: checklist) as UIView }
                let list = UKModuleListView(.thin, hasGlyphs: checklist, surface: .sheet, rows: rows)
                if let heading = section.heading {
                    views.append(titled(heading, quiet: section.headingIsGenerated, list: list))
                } else {
                    views.append(list)
                }
            }
        }
        views.append(UKGroceryActionView(model: model))
        return views
    }

    // MARK: Instructions

    /// Numbered steps in groups, each an inset list under its header, or the Cookidoo link (``RecipeInstructionsTab``).
    static func instructions(_ detail: RecipeDetail) -> [UIView] {
        if detail.capabilities.instructions == .externalLink {
            if let url = detail.instructions.fallbackURL ?? detail.source.canonicalURL {
                return [UKExternalLinkPanel(url: url)]
            }
            return [UKStateMessageView(symbol: "link", title: "Instructions Link Unavailable", message: "The external instruction link is not available.",
                                       identifier: "recipe.instructions.linkUnavailable")]
        }
        if detail.capabilities.instructions == .local, detail.instructions.available {
            var views: [UIView] = []
            if detail.instructions.truncated { views.append(UKRecipeNotice("These instructions are truncated.")) }
            for (index, group) in detail.instructions.groups.enumerated() {
                let list = UKModuleListView(.thin, hasGlyphs: false, surface: .sheet, rows: group.steps.map { UKRecipeStepRow(step: $0) as UIView })
                if let heading = RecipeFormatting.sectionHeading(group.label, index: index, count: detail.instructions.groups.count) {
                    views.append(titled(heading.label, quiet: heading.generated, list: list))
                } else {
                    views.append(list)
                }
            }
            return views
        }
        return [UKStateMessageView(symbol: "list.number", title: "No Instructions Available", message: "Instructions are not available for this recipe.",
                                   identifier: "recipe.instructions.empty")]
    }
}

// MARK: - Pieces

/// A view inset horizontally inside a column.
final class UKRecipeInset: UIView {
    init(_ child: UIView, horizontal: CGFloat = 0, vertical: CGFloat = 0) {
        super.init(frame: .zero)
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: topAnchor, constant: vertical), child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal), child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A header over an inset list in the recipe sheets (``RecipeSectionHeader``): 15 Semibold in the readable secondary ink, no
/// uppercasing; generated headings ("Section 2", "Other Ingredients") are regular weight.
final class UKRecipeSectionHeaderLabel: UILabel {
    init(_ title: String, isQuiet: Bool = false) {
        super.init(frame: .zero)
        text = title
        font = .ukFont(.subheadline, weight: isQuiet ? .regular : .semibold)
        adjustsFontForContentSizeCategory = true
        textColor = UKDesignInk.secondary
        numberOfLines = 0
        accessibilityTraits = [.header, .staticText]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The recipe's photo in a 26 pt card, 16:10, on the sheet's cell colour (``RecipeGeneralTab``).
final class UKRecipeHeroImage: UIView {
    init(url: URL?, fallbackURL: URL?) {
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let image = UKRemoteImageView(url: url, fallbackURL: fallbackURL, placeholderSymbol: "fork.knife")
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: topAnchor), image.bottomAnchor.constraint(equalTo: bottomAnchor),
            image.leadingAnchor.constraint(equalTo: leadingAnchor), image.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: 10.0 / 16.0),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A quiet status line (``Notice``; web `.notice` with `role="status"`).
final class UKRecipeNotice: UIView {
    init(_ text: String) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.footnote))))
        icon.tintColor = UKDesignInk.secondary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
        label.text = text
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = HassTokens.Spacing.xs + 2
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One fact on the General tab: glyph, label and the value trailing in secondary ink (``RecipeFactRow``), a module row. At
/// accessibility sizes the value moves under the label, so both wrap whole words. One element: the label, with the value.
final class UKRecipeFactRow: UKRowView {
    init(fact: RecipeFormatting.Fact) {
        var content = UKRowContent(fact.label, value: fact.value, symbol: fact.symbol, glyph: UKDesignInk.secondary)
        content.spokenValue = fact.spokenValue ?? fact.value
        super.init(content, surface: .sheet)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A row of plain text on an inset list (a device name): 52 pt at least.
final class UKRecipeTextRow: UKRowView {
    init(text: String) {
        var content = UKRowContent(text)
        content.verticalPadding = HassTokens.Spacing.m
        content.minHeight = RecipeRowMetrics.minHeight
        super.init(content, surface: .sheet)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A list row that opens a web page ("Open in Cookidoo"), in the action tint (``RecipeLinkRow``).
final class UKRecipeLinkRow: UKRowButton {
    init(title: String, url: URL) {
        var content = UKRowContent(title, symbol: "arrow.up.right.square", glyph: UKDesignInk.action)
        content.titleInk = UKDesignInk.action
        content.verticalPadding = HassTokens.Spacing.m
        content.minHeight = RecipeRowMetrics.minHeight
        super.init(UKRowView(content, surface: .sheet), onTap: { UIApplication.shared.open(url) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.button, .link] }
        set {}
    }
}

/// One numbered instruction step (``RecipeStepRow``).
final class UKRecipeStepRow: UIView, UKSurfaceStyled {
    var surface: TileSurface = .sheet

    init(step: RecipeDetail.Step) {
        super.init(frame: .zero)
        let number = UKValueLabel(.body, weight: .semibold, ink: UKDesignInk.secondary, monospacedDigit: true)
        number.text = "\(step.number)."
        number.widthReference = self
        number.maxShare = 0.25
        let text = UILabel.uk(.body, ink: UKDesignInk.primary)
        text.text = step.text
        let row = UIStackView(arrangedSubviews: [number, text])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.m), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.m),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.l), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HassTokens.Spacing.l),
            heightAnchor.constraint(greaterThanOrEqualToConstant: RecipeRowMetrics.minHeight),
        ])
        // The step's words are their own element, so they read (and are found) as the step's text.
        number.isAccessibilityElement = true
        number.accessibilityLabel = "Step \(step.number)"
        text.isAccessibilityElement = true
        text.accessibilityLabel = step.text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One ingredient: status mark, title with amount, chips, source text and match (``IngredientRow``; web `CheckboxRow`). The canonical
/// row with the mark leading (top aligned) and the title, chips and notes as its text view.
final class UKIngredientRow: UKRowView {
    convenience init(detail: RecipeDetail, ingredient: RecipeDetail.Ingredient, checklist: Bool) {
        self.init(presentation: RecipeIngredientPresentation(detail: detail, ingredient: ingredient, checklist: checklist))
    }

    init(presentation: RecipeIngredientPresentation) {
        let title = UILabel.uk(.body, ink: UKDesignInk.primary)
        title.text = presentation.title
        var parts: [UIView] = [title]
        if !presentation.chips.isEmpty { parts.append(UKChipFlow(chips: presentation.chips)) }
        if let source = presentation.source {
            let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            label.text = source
            parts.append(label)
        }
        if let match = presentation.match {
            let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            label.text = match
            parts.append(label)
        }
        let column = UIStackView(arrangedSubviews: parts)
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = HassTokens.Spacing.s
        var content = UKRowContent(presentation.title)
        if let mark = presentation.mark {
            content.symbol = mark
            content.glyph = presentation.onHand ? UKDesignInk.success : UKDesignInk.secondary
            content.alignsLeadingToTop = true
        }
        content.verticalPadding = HassTokens.Spacing.m
        content.minHeight = RecipeRowMetrics.minHeight
        content.spokenValue = presentation.spokenValue
        content.identifier = presentation.identifier
        super.init(content, textView: column, surface: .sheet)
        isTextAccessible = false
        isAccessibilityElement = true
        accessibilityLabel = presentation.title
        accessibilityValue = content.spokenValue
        accessibilityIdentifier = content.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The row's mark: a filled check when on hand, a question mark when EverShelf is unsure of the match, else an empty circle.
    static func mark(_ ingredient: RecipeDetail.Ingredient, onHand: Bool) -> String { IngredientRow.mark(ingredient, onHand: onHand) }
}

/// Small capsules that wrap onto new lines (``ChipFlow``). Its height follows its width, so it keeps a height constraint current.
final class UKChipFlow: UIView {
    private let chips: [UILabel]
    private var flowHeight: NSLayoutConstraint?

    init(chips texts: [String]) {
        chips = texts.map { text in
            let label = UKChipLabel()
            label.text = text
            return label
        }
        super.init(frame: .zero)
        chips.forEach(addSubview)
        translatesAutoresizingMaskIntoConstraints = false
        let height = heightAnchor.constraint(equalToConstant: 24)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        flowHeight = height
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let sizes = chips.map { $0.sizeThatFits(unbounded) }
        let solved = UKFlowSolver.frames(sizes: sizes, width: bounds.width, spacing: HassTokens.Spacing.s,
                                         rightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft) { index, width in
            self.chips[index].sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
        }
        for (chip, frame) in zip(chips, solved.frames) { chip.frame = frame }
        if let flowHeight, abs(flowHeight.constant - solved.height) > 0.5 {
            flowHeight.constant = solved.height
            DispatchQueue.main.async { [weak self] in self?.superview?.setNeedsLayout() }
        }
    }
}

/// One capsule of a ``UKChipFlow``: footnote text in secondary ink on the fill, 8 pt across and 4 pt down.
final class UKChipLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .ukFont(.footnote)
        adjustsFontForContentSizeCategory = true
        textColor = UKDesignInk.secondary
        backgroundColor = .secondarySystemFill
        numberOfLines = 0
        clipsToBounds = true
        layer.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var insets: UIEdgeInsets { UIEdgeInsets(top: HassTokens.Spacing.xs, left: HassTokens.Spacing.s, bottom: HassTokens.Spacing.xs, right: HassTokens.Spacing.s) }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = super.sizeThatFits(CGSize(width: max(1, size.width - insets.left - insets.right), height: size.height))
        return CGSize(width: ceil(inner.width + insets.left + insets.right), height: ceil(inner.height + insets.top + insets.bottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// "Instructions are on Cookidoo" with its one primary action (``RecipeInstructionsTab``, ``ExternalLinkButton``).
final class UKExternalLinkPanel: UIView {
    init(url: URL) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: "arrow.up.right.square", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.largeTitle))))
        icon.tintColor = UKDesignInk.secondary
        icon.isAccessibilityElement = false
        let title = UILabel.uk(.headline, ink: UKDesignInk.primary, alignment: .center)
        title.text = "Instructions are on Cookidoo"
        let detail = UILabel.uk(.subheadline, ink: UKDesignInk.secondary, alignment: .center)
        detail.text = "Official Cookidoo step text stays on Cookidoo and is not stored or shown here."
        let button = UKPrimaryButton("Open in Cookidoo", systemImage: "arrow.up.right.square") { UIApplication.shared.open(url) }
        button.accessibilityIdentifier = "recipe.openCookidoo"
        button.accessibilityTraits.insert(.link)
        let column = UIStackView(arrangedSubviews: [icon, title, detail, button])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = HassTokens.Spacing.m
        button.translatesAutoresizingMaskIntoConstraints = false
        button.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        button.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// "Add to Grocery List", the sheet's one primary button, with its description (or the reason it is disabled), progress and result
/// (``GroceryAction``; web `RecipeGroceryAction`).
final class UKGroceryActionView: UIView {
    private let model: RecipeDetailModel
    private let column = UIStackView()
    private let bag = UKObservationBag()
    private var shown: RecipeDetailModel.Grocery?
    private var button: UKPrimaryButton?

    init(model: RecipeDetailModel) {
        self.model = model
        super.init(frame: .zero)
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = HassTokens.Spacing.s
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        bag.observe { [weak self] in
            guard let self else { return }
            self.update(state: self.model.grocery, reason: self.model.groceryDisabledReason)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func footnote(_ text: String, identifier: String) -> UILabel {
        let label = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
        label.text = text
        label.accessibilityIdentifier = identifier
        return label
    }

    private func update(state: RecipeDetailModel.Grocery, reason: String?) {
        let hadState = shown != nil
        // The button swaps for the confirmation with a cross-fade (`MotionTokens.state`).
        let rebuild = { [self] in
            for view in column.arrangedSubviews { column.removeArrangedSubview(view); view.removeFromSuperview() }
            button = nil
            switch state {
            case let .added(message):
                let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.headline))))
                check.tintColor = UKDesignInk.success
                check.isAccessibilityElement = false
                let text = UILabel.uk(.headline, ink: UKDesignInk.primary)
                text.text = "Added to Grocery List"
                let row = UIStackView(arrangedSubviews: [UIView(), check, text, UIView()])
                row.axis = .horizontal
                row.alignment = .center
                row.spacing = HassTokens.Spacing.s
                row.arrangedSubviews[0].widthAnchor.constraint(equalTo: row.arrangedSubviews[3].widthAnchor).isActive = true
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
                row.isAccessibilityElement = true
                row.accessibilityLabel = "Added to Grocery List"
                row.accessibilityIdentifier = "recipe.grocery.added"
                column.addArrangedSubview(row)
                column.addArrangedSubview(footnote(message, identifier: "recipe.grocery.message"))
            default:
                let add = UKPrimaryButton(GroceryAction.title, systemImage: "cart.badge.plus", isBusy: state == .adding) { [weak self] in
                    self?.model.addMissingToGroceries()
                }
                add.isEnabled = reason == nil
                add.accessibilityIdentifier = "recipe.grocery.add"
                button = add
                column.addArrangedSubview(add)
                if let reason {
                    column.addArrangedSubview(footnote(reason, identifier: "recipe.grocery.reason"))
                } else {
                    column.addArrangedSubview(footnote(GroceryAction.explanation, identifier: "recipe.grocery.description"))
                }
                if case let .failed(message) = state {
                    let alert = UKInlineAlertView(message, severity: .error)
                    alert.accessibilityIdentifier = "recipe.grocery.error"
                    column.addArrangedSubview(alert)
                }
            }
        }
        if hadState, window != nil, shown != state {
            UIView.transition(with: self, duration: UIAccessibility.isReduceMotionEnabled ? 0.2 : MotionTokens.stateDuration,
                              options: [.transitionCrossDissolve, .allowUserInteraction], animations: rebuild)
        } else {
            rebuild()
        }
        if hadState, shown != state {
            switch state {
            case let .added(message): UIAccessibility.post(notification: .announcement, argument: "Added to grocery list. \(message)")
            case let .failed(message): UIAccessibility.post(notification: .announcement, argument: message)
            default: break
            }
        }
        shown = state
    }
}
#endif
