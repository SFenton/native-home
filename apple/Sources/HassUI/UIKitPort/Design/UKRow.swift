#if os(iOS)
import HassDesign
import UIKit

// MARK: - Style

/// The metrics of a row: the SwiftUI app has two (``ModuleRow`` on a module or sheet list, ``SettingsLinkRow`` in the inset grouped
/// stack) and a row picks one, so a list lines up with its hairlines whatever it holds. Everything else about a row (its slots, how its
/// text wraps, how it reflows at accessibility sizes, its accessibility element) is the same in both.
enum UKRowStyle {
    /// ``ModuleRow``: 16 pt side padding, 52 pt (60 pt with a subtitle), a 24 pt glyph column at body size and a 14 pt gap, so
    /// hairlines start at ``ModuleRowMetrics/textInset``.
    case module
    /// ``SettingsLinkRow``: the cell supplies the side inset, 44 pt minimum, a 34 pt column for a title3 icon or an app icon and a 12 pt
    /// gap; at accessibility sizes the icon sits above the text.
    case grouped
    /// A row in a `Form` cell (the cell supplies the 16 pt margin and 7 pt of padding): 44 pt minimum, a 28 pt body glyph column, 12 pt gap.
    case form

    var sidePadding: CGFloat { self == .module ? HassTokens.Spacing.l : 0 }
    var verticalPadding: CGFloat { self == .module ? HassTokens.Spacing.s : HassTokens.Spacing.xs }
    var minHeight: CGFloat { self == .module ? ModuleRowMetrics.height : HassTokens.minTarget }
    var minHeightWithSubtitle: CGFloat { self == .module ? ModuleRowMetrics.heightWithSubtitle : HassTokens.minTarget }
    var leadingColumn: CGFloat {
        switch self {
        case .module: ModuleRowMetrics.glyphWidth
        case .grouped: 34
        case .form: 28
        }
    }
    var gap: CGFloat { self == .module ? ModuleRowMetrics.gap : HassTokens.Spacing.m }
    var glyphStyle: UIFont.TextStyle { self == .grouped ? .title3 : .body }
    var subtitleStyle: UIFont.TextStyle { self == .grouped ? .subheadline : .footnote }
    var valueStyle: UIFont.TextStyle { self == .grouped ? .subheadline : .body }
    var monospacedSubtitle: Bool { self != .grouped }
    var leadingAboveTextAtAccessibilitySizes: Bool { self == .grouped }
}

// MARK: - Content

/// What a ``UKRowView`` shows: the slots of the one canonical row.
///
/// - Leading: a `symbol`, a `check` (the check variant), or any `leadingView` (an avatar, an app icon) in the glyph column.
/// - Text: `title`, an optional `subtitle` and an optional trailing `value`; the value sits beside the text while both fit and drops
///   under it when they do not (`ViewThatFits`), and at accessibility sizes.
/// - Trailing: the row's accessory view, then a chevron when the row opens something.
struct UKRowContent: Equatable {
    /// The check variant's state: a circle the size of the title.
    struct Check: Equatable {
        var isChecked: Bool
        var checkedTint: UIColor
        var uncheckedTint: UIColor
        /// Dims only the glyph (the row cannot change; the title keeps its contrast).
        var dimmed = false
    }

    var title: String
    var subtitle: String?
    /// A trailing text (a Home/Away state, a build, a stock count).
    var value: String?
    var symbol: String?
    /// The symbol's colour, or nil for the row's secondary ink.
    var glyph: UIColor?
    /// Dims only the glyph.
    var glyphOpacity: CGFloat = 1
    /// Any view in the glyph column instead of a symbol (an avatar, an app icon). It keeps its own size.
    var leadingView: UIView?
    var check: Check?
    /// Overrides the surface's title ink (an action-tinted row).
    var titleInk: UIColor?
    /// Overrides the regular title weight (a bold action).
    var titleWeight: UIFont.Weight?
    /// Overrides the subtitle's secondary ink.
    var subtitleInk: UIColor?
    var valueInk: UIColor?
    /// The subtitle reads an entity's state, so it gives way to a ``UKPendingValueBar`` while `valuesPending`.
    var subtitleIsValue = false
    /// Draws a trailing chevron: the row opens something.
    var showsChevron = false
    /// The accessibility identifier of the row's text element.
    var identifier: String?
    var style: UKRowStyle = .module
    /// Overrides the style's padding above and below the text (the check rows use 11 pt).
    var verticalPadding: CGFloat?
    /// Overrides the style's minimum height (a 44 pt row in a card).
    var minHeight: CGFloat?
    /// Aligns the leading slot with the first line of a tall text block instead of centring it (an ingredient's mark).
    var alignsLeadingToTop = false
    /// What VoiceOver reads as the value when it is not the value text.
    var spokenValue: String?
    /// What VoiceOver reads as the label when it is more than the title and subtitle (SwiftUI `.accessibilityElement(children: .combine)`).
    var spokenLabel: String?
    /// Centres the leading slot and the text as one group, with no accessory, value or chevron: a centred action ("Sign Out"). Give it
    /// ``titleInk`` for the destructive red and a ``leadingView`` for a busy arc. It does not stack at accessibility sizes; it wraps.
    var isCentered = false
    /// Overrides the style's side padding (a row on a card of its own, 12 pt in).
    var horizontalPadding: CGFloat?
    /// Overrides the style's subtitle text style (a sheet's detail lines are subheadline).
    var subtitleStyle: UIFont.TextStyle?
    /// Overrides the style's glyph text style (a title3 glyph on a sheet row).
    var glyphStyle: UIFont.TextStyle?
    /// Overrides the regular value weight (a measurement in semibold).
    var valueWeight: UIFont.Weight?
    /// What VoiceOver reads after the label.
    var hint: String?

    init(_ title: String, subtitle: String? = nil, value: String? = nil, symbol: String? = nil, glyph: UIColor? = nil,
         subtitleInk: UIColor? = nil, glyphOpacity: CGFloat = 1, subtitleIsValue: Bool = false, showsChevron: Bool = false,
         style: UKRowStyle = .module) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.symbol = symbol
        self.glyph = glyph
        self.subtitleInk = subtitleInk
        self.glyphOpacity = glyphOpacity
        self.subtitleIsValue = subtitleIsValue
        self.showsChevron = showsChevron
        self.style = style
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.value == rhs.value && lhs.symbol == rhs.symbol
            && lhs.glyph == rhs.glyph && lhs.glyphOpacity == rhs.glyphOpacity && lhs.leadingView === rhs.leadingView
            && lhs.check == rhs.check && lhs.titleInk == rhs.titleInk && lhs.titleWeight == rhs.titleWeight && lhs.subtitleInk == rhs.subtitleInk
            && lhs.valueInk == rhs.valueInk && lhs.subtitleIsValue == rhs.subtitleIsValue && lhs.showsChevron == rhs.showsChevron
            && lhs.identifier == rhs.identifier && lhs.style == rhs.style && lhs.verticalPadding == rhs.verticalPadding && lhs.minHeight == rhs.minHeight && lhs.alignsLeadingToTop == rhs.alignsLeadingToTop && lhs.spokenValue == rhs.spokenValue && lhs.spokenLabel == rhs.spokenLabel
            && lhs.isCentered == rhs.isCentered && lhs.horizontalPadding == rhs.horizontalPadding && lhs.subtitleStyle == rhs.subtitleStyle
            && lhs.glyphStyle == rhs.glyphStyle && lhs.valueWeight == rhs.valueWeight && lhs.hint == rhs.hint
    }

    var hasLeading: Bool { symbol != nil || leadingView != nil || check != nil }
}

// MARK: - Centred action

extension UKRowContent {
    /// A centred action row (`SignOutRow`): the title in `ink` (the danger red for a destructive one), centred, with an inline arc and
    /// `busyTitle` in its place while the action waits on the server. Pass it to ``UKRowView`` or ``UKRowButton``; build it again only
    /// when `isBusy` changes.
    @MainActor
    static func centeredAction(_ title: String, ink: UIColor, busyTitle: String? = nil, isBusy: Bool = false,
                               style: UKRowStyle = .form) -> UKRowContent {
        var content = UKRowContent(isBusy ? (busyTitle ?? title) : title, style: style)
        content.titleInk = ink
        content.isCentered = true
        if isBusy {
            let spinner = UKArcSpinnerView(.inline, label: busyTitle ?? title)
            spinner.color = ink
            spinner.isAccessibilityElement = false
            content.leadingView = spinner
        }
        return content
    }
}

// MARK: - Row

/// The one row (``ModuleRow``, ``SettingsLinkRow``, ``CheckRow``; `.agents/patterns/rows.md`): slots for a leading glyph, check or
/// avatar, the text (title, subtitle, value) and a trailing accessory or chevron. Every list row in the port is this view, in a
/// module list, a form cell, a settings cell or a sheet; a feature row that needs something special (a stepper, a slider, a menu) puts
/// it in the accessory slot or a `textView` and keeps this layout.
///
/// - Metrics: ``UKRowStyle``. 44 pt target at least, 52 / 60 pt in the module style.
/// - Wrapping: the labels wrap at the row's own width less what sits beside them (``UKWrapWidth``, read in `layoutSubviews`), never
///   from their own width.
/// - Accessibility sizes: the accessory (and the value) move under the text; in the grouped style the icon sits above it.
/// - VoiceOver: the text is one element named "Title, subtitle" (value as its value), then the accessory's own controls. A row with a
///   ``tapTarget`` makes that the element instead, behind everything left of the accessory.
///
/// ```swift
/// let row = UKRowView(.init("Front Door", subtitle: "Locked", symbol: "lock"), accessory: statusLabel)
/// ```
class UKRowView: UIView, UKSurfaceStyled {
    var surface: TileSurface = .page { didSet { restyle() } }
    /// No state has arrived yet (``UKContext/valuesPending``).
    var valuesPending = false { didSet { updateSubtitle() } }
    private(set) var rowContent: UKRowContent
    private(set) var accessory: UIView?
    /// A card behind the row (a row on a form's ground rather than in a module).
    var drawsCard = false { didSet { updateCard() } }
    /// The card's fill (a sheet's cell colour); the grouped ground by default.
    var cardColor: UIColor? { didSet { updateCard() } }
    /// The margin after the accessory (``CheckRowMetrics``); the style's side padding by default.
    var accessoryTrailingInset: CGFloat? { didSet { updatePadding() } }
    /// The control behind everything left of the accessory (a check toggle, a row button). Callers set its accessibility label, value,
    /// hint and traits.
    private(set) var tapTarget: UIControl?
    /// Whether VoiceOver visits the text. False when the accessory is the element (a switch, a stepper, a field) and carries the name.
    var isTextAccessible = true { didSet { textStack.isAccessibilityElement = isTextAccessible } }
    /// The accessory takes the room the text leaves instead of its own width (a text field beside its label).
    var expandsAccessory = false { didSet { arrange() } }
    /// A view in place of the title and subtitle (a todo item's title and due line).
    private(set) var textView: UIView?
    /// The traits of the text element (static text unless the row is only drawing).
    var textTraits: UIAccessibilityTraits = .staticText { didSet { textStack.accessibilityTraits = textTraits } }

    /// A view under the whole row, edge to edge inside the side padding (a slider under its title and value). The row's text, value and
    /// accessory stay on the line above it.
    private(set) var bodyView: UIView?
    private var bodyConstraints: [NSLayoutConstraint] = []
    private var highlightObservation: NSKeyValueObservation?
    private let centerSpacers = (leading: UIView(), trailing: UIView())

    private let glyphView = UIImageView()
    private let titleLabel = UILabel.uk(.body, ink: .white)
    private let subtitleLabel = UILabel.uk(.footnote, monospacedDigit: true, ink: .white)
    private let valueLabel = UKValueLabel(.body, ink: .white)
    private let pendingBar = UKPendingValueBar()
    private let textStack = UIStackView()
    private let leadingStack = UIStackView()
    private let chevronView = UIImageView()
    private let root = UIStackView()
    private var rootPadding: [NSLayoutConstraint] = []
    private var tapTrailing: NSLayoutConstraint?
    private var glyphWidth: NSLayoutConstraint!
    private var minHeight: NSLayoutConstraint!
    private var valueStacked = false

    init(_ content: UKRowContent, accessory: UIView? = nil, textView: UIView? = nil, surface: TileSurface = .page) {
        rowContent = content
        self.accessory = accessory
        self.textView = textView
        self.surface = surface
        super.init(frame: .zero)
        build()
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.rescale() }
        rescale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows new content in place (a state changed): colours cross-fade, nothing relayouts unless the structure changed.
    func update(_ content: UKRowContent, accessory newAccessory: UIView? = nil) {
        let old = rowContent
        let structure = old.hasLeading != content.hasLeading || old.showsChevron != content.showsChevron
            || (old.subtitle == nil) != (content.subtitle == nil) || (old.value == nil) != (content.value == nil)
            || old.style != content.style || old.leadingView !== content.leadingView || old.isCentered != content.isCentered
            || old.horizontalPadding != content.horizontalPadding
        rowContent = content
        if newAccessory !== accessory {
            accessory?.removeFromSuperview()
            accessory = newAccessory
            arrange()
        } else if structure {
            arrange()
        }
        restyle()
    }

    /// Puts a control after the text (nil removes it) and sets the margin after it.
    func setAccessory(_ view: UIView?, trailingInset: CGFloat? = nil) {
        accessoryTrailingInset = trailingInset
        guard accessory !== view else { return }
        accessory?.removeFromSuperview()
        accessory = view
        arrange()
    }

    /// Puts a view under the row's line (nil removes it): a slider, a progress bar, a second control line. It takes the row's side
    /// padding and the style's vertical padding, and the row's minimum height applies to the line above it.
    func setBody(_ view: UIView?) {
        guard bodyView !== view else { return }
        NSLayoutConstraint.deactivate(bodyConstraints)
        bodyConstraints = []
        bodyView?.removeFromSuperview()
        bodyView = view
        if let view {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        updatePadding()
    }

    /// Shows the check state of the check variant. A change on screen cross-fades the glyph's colour (``UKMotion/stateColor(_:)``).
    func setChecked(_ checked: Bool, checkedTint: UIColor, uncheckedTint: UIColor, dimmed: Bool = false, animated: Bool = true) {
        let wasChecked = rowContent.check?.isChecked
        rowContent.check = .init(isChecked: checked, checkedTint: checkedTint, uncheckedTint: uncheckedTint, dimmed: dimmed)
        if rowContent.symbol != nil { rowContent.symbol = nil }
        if glyphView.superview == nil || leadingStack.arrangedSubviews.first !== glyphHolder { arrange() }
        let apply = { [self] in
            glyphView.image = UIImage(systemName: CheckRowMetrics.symbol(checked: checked))
            glyphView.tintColor = checked ? checkedTint : uncheckedTint
            glyphView.alpha = dimmed ? CGFloat(CheckRowMetrics.dimmedGlyphOpacity) : 1
        }
        if animated, let wasChecked, wasChecked != checked, window != nil { UKMotion.stateColor { apply() } } else { apply() }
    }

    /// Installs the control behind the row's text. It takes the touches left of the accessory; the accessory keeps its own.
    func installTapTarget(_ control: UIControl) {
        tapTarget?.removeFromSuperview()
        tapTarget = control
        control.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(control, at: 0)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor), control.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        root.isUserInteractionEnabled = false
        // The row dims while the target is held, like a plain button (the leading slot and text; the accessory keeps its own press).
        highlightObservation = control.observe(\.isHighlighted, options: [.new]) { [weak self] control, _ in
            guard let self else { return }
            let alpha = control.isHighlighted ? CGFloat(HassTokens.ControlState.pressedOpacity) : 1
            self.leadingStack.alpha = alpha
        }
        updateTapTrailing()
    }

    /// The row has a second line (a due label), so it is at least the subtitle height.
    var hasSecondLine = false { didSet { updateMinHeight() } }

    // MARK: Build

    private let glyphHolder = UIView()

    private func build() {
        glyphView.contentMode = .center
        glyphView.isAccessibilityElement = false
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphHolder.translatesAutoresizingMaskIntoConstraints = false
        glyphHolder.addSubview(glyphView)
        glyphHolder.setContentHuggingPriority(.required, for: .horizontal)
        glyphWidth = glyphHolder.widthAnchor.constraint(equalToConstant: rowContent.style.leadingColumn)
        // A glyph with no image (a symbol this OS lacks) has no intrinsic height; without a weak zero it would stretch to the height a
        // self-sizing cell proposes. The image's own size outranks it.
        let collapsed = glyphView.heightAnchor.constraint(equalToConstant: 0)
        collapsed.priority = UILayoutPriority(100)
        NSLayoutConstraint.activate([collapsed,
            glyphWidth,
            glyphView.centerXAnchor.constraint(equalTo: glyphHolder.centerXAnchor),
            glyphView.topAnchor.constraint(equalTo: glyphHolder.topAnchor), glyphView.bottomAnchor.constraint(equalTo: glyphHolder.bottomAnchor),
        ])

        chevronView.contentMode = .center
        chevronView.isAccessibilityElement = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevronView.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.footnote, weight: .semibold)))

        valueLabel.widthReference = self
        valueLabel.textAlignment = .right
        valueLabel.isAccessibilityElement = false

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.isAccessibilityElement = true
        textStack.accessibilityTraits = textTraits
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        leadingStack.axis = .horizontal
        leadingStack.alignment = .center
        leadingStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        root.alignment = .center
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        minHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: rowContent.style.minHeight)
        rootPadding = [
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(rootPadding + [minHeight])
        updatePadding()
        arrange()
    }

    private var isAccessibilitySize: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }

    /// The margin either side of the row: the content's, or the style's.
    private var sidePadding: CGFloat { rowContent.horizontalPadding ?? rowContent.style.sidePadding }

    private func updatePadding() {
        let style = rowContent.style
        let vertical = rowContent.verticalPadding ?? style.verticalPadding
        rootPadding[0].constant = sidePadding
        rootPadding[1].constant = -(accessory != nil ? (accessoryTrailingInset ?? sidePadding) : sidePadding)
        // The padding sits around the text, not the row: an accessory (a 44 pt button) may be taller than the text and sets the height.
        rootPadding[2].constant = 0
        rootPadding[3].constant = 0
        NSLayoutConstraint.deactivate(bodyConstraints)
        bodyConstraints = []
        if let bodyView {
            // The body hangs from the line above and closes the row; the line's own bottom padding is the gap between them.
            rootPadding[3].isActive = false
            bodyConstraints = [
                bodyView.topAnchor.constraint(equalTo: root.bottomAnchor),
                bodyView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sidePadding),
                bodyView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -sidePadding),
                bodyView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            ]
            NSLayoutConstraint.activate(bodyConstraints)
        } else {
            rootPadding[3].isActive = true
        }
        leadingStack.isLayoutMarginsRelativeArrangement = true
        leadingStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: vertical, leading: 0, bottom: vertical, trailing: 0)
        updateMinHeight()
    }

    private func updateMinHeight() {
        let style = rowContent.style
        let tall = rowContent.subtitle != nil || hasSecondLine
        minHeight?.constant = rowContent.minHeight ?? (tall ? style.minHeightWithSubtitle : style.minHeight)
    }

    /// Where the tap target ends: at the accessory, or at the row's edge.
    private func updateTapTrailing() {
        tapTrailing?.isActive = false
        guard let tapTarget else { return }
        if let accessory, accessory.superview != nil, !isAccessibilitySize {
            tapTrailing = tapTarget.trailingAnchor.constraint(equalTo: accessory.leadingAnchor)
        } else {
            tapTrailing = tapTarget.trailingAnchor.constraint(equalTo: trailingAnchor)
        }
        tapTrailing?.isActive = true
    }

    /// The structure for the current content and text size: leading, text, value, accessory and chevron in a row, or at accessibility
    /// sizes the accessory under the text.
    private func arrange() {
        let style = rowContent.style
        for view in root.arrangedSubviews { root.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in leadingStack.arrangedSubviews { leadingStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in textStack.arrangedSubviews { textStack.removeArrangedSubview(view); view.removeFromSuperview() }
        leadingStack.spacing = style.gap
        leadingStack.alignment = rowContent.alignsLeadingToTop ? .top : .center
        textStack.alignment = textView != nil ? .fill : rowContent.isCentered ? .center : .leading
        updatePadding()
        installLeading()
        let centered = rowContent.isCentered
        let leadingAbove = isAccessibilitySize && style.leadingAboveTextAtAccessibilitySizes && rowContent.hasLeading && !centered
        let accessibilityStacked = isAccessibilitySize && !centered
        if leadingAbove { textStack.addArrangedSubview(glyphHolder) }
        if let textView {
            textStack.addArrangedSubview(textView)
        } else {
            textStack.addArrangedSubview(titleLabel)
        }
        if !leadingAbove, rowContent.hasLeading { leadingStack.addArrangedSubview(glyphHolder) }
        leadingStack.addArrangedSubview(textStack)
        let showsValueInline = rowContent.value != nil && !valueStacked && !accessibilityStacked
        let showsValueBelow = rowContent.value != nil && !showsValueInline

        if accessibilityStacked {
            root.axis = .vertical
            root.alignment = .fill
            root.spacing = HassTokens.Spacing.s
            let top = UIStackView(arrangedSubviews: [leadingStack] + (rowContent.showsChevron ? [chevronView] : []))
            top.axis = .horizontal
            top.spacing = style.gap
            top.alignment = .center
            root.addArrangedSubview(top)
            if let accessory { accessory.removeFromSuperview(); root.addArrangedSubview(accessory) }
        } else if centered {
            root.axis = .horizontal
            root.alignment = .center
            root.spacing = 0
            for spacer in [centerSpacers.leading, centerSpacers.trailing] {
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            root.addArrangedSubview(centerSpacers.leading)
            root.addArrangedSubview(leadingStack)
            root.addArrangedSubview(centerSpacers.trailing)
            // Equal spacers centre the content; the pair needs a common superview (the stack) before it is constrained.
            if centerSpacers.leading.constraints.isEmpty {
                centerSpacers.leading.widthAnchor.constraint(equalTo: centerSpacers.trailing.widthAnchor).isActive = true
            }
            textStack.setContentHuggingPriority(.required, for: .horizontal)
        } else {
            root.axis = .horizontal
            root.alignment = .center
            root.spacing = style.gap
            root.addArrangedSubview(leadingStack)
            if showsValueInline { root.addArrangedSubview(valueLabel) }
            if let accessory {
                accessory.setContentHuggingPriority(expandsAccessory ? .defaultLow : .required, for: .horizontal)
                root.addArrangedSubview(accessory)
            }
            if rowContent.showsChevron { root.addArrangedSubview(chevronView) }
            textStack.setContentHuggingPriority(expandsAccessory ? .required : .defaultLow, for: .horizontal)
        }
        valueLabel.textAlignment = showsValueBelow ? .natural : .right
        updateSubtitle(valueBelow: showsValueBelow)
        updateTapTrailing()
        setNeedsLayout()
    }

    /// The glyph column's content: the symbol, the check, or the caller's view.
    private func installLeading() {
        for view in glyphHolder.subviews where view !== glyphView { view.removeFromSuperview() }
        glyphView.isHidden = rowContent.leadingView != nil
        if let view = rowContent.leadingView {
            view.translatesAutoresizingMaskIntoConstraints = false
            glyphHolder.addSubview(view)
            // A view with a frame and no intrinsic size (an app icon preview) keeps the size it was made at.
            if view.intrinsicContentSize.width == UIView.noIntrinsicMetric, view.bounds.width > 0 {
                NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: view.bounds.width),
                                             view.heightAnchor.constraint(equalToConstant: view.bounds.height)])
            }
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: glyphHolder.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: glyphHolder.centerYAnchor),
                view.leadingAnchor.constraint(greaterThanOrEqualTo: glyphHolder.leadingAnchor),
                view.trailingAnchor.constraint(lessThanOrEqualTo: glyphHolder.trailingAnchor),
                view.topAnchor.constraint(greaterThanOrEqualTo: glyphHolder.topAnchor),
                view.bottomAnchor.constraint(lessThanOrEqualTo: glyphHolder.bottomAnchor),
            ])
        }
    }

    /// The labels wrap at the row's current width less the leading column, value, accessory, chevron and gaps (``UKWrapWidth``), taken
    /// at layout time: the text stack is leading aligned (the pending bar keeps its size), so a label's own last width must not decide
    /// it. Also decides whether the value fits beside the text.
    override func layoutSubviews() {
        super.layoutSubviews()
        let style = rowContent.style
        let accessibilityStacked = isAccessibilitySize && !rowContent.isCentered
        let leadingAbove = accessibilityStacked && style.leadingAboveTextAtAccessibilitySizes
        let padding = sidePadding + (accessory != nil ? (accessoryTrailingInset ?? sidePadding) : sidePadding)
        var reserved = padding
        if rowContent.hasLeading, !accessibilityStacked { reserved += leadingWidth + style.gap }
        if let accessory, !accessibilityStacked {
            reserved += max(expandsAccessory ? HassTokens.minTarget : accessory.intrinsicContentSize.width, 0) + style.gap
        }
        if rowContent.showsChevron { reserved += max(chevronView.intrinsicContentSize.width, 0) + (accessibilityStacked ? 0 : style.gap) }
        if rowContent.hasLeading, accessibilityStacked, !leadingAbove { reserved += leadingWidth + style.gap }
        let textReserved = reserved
        // The value beside the text while both fit on a line, else under it.
        if rowContent.value != nil, !accessibilityStacked, textView == nil {
            let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let wanted = max(titleLabel.sizeThatFits(unbounded).width,
                             rowContent.subtitle == nil ? 0 : subtitleLabel.sizeThatFits(unbounded).width)
            let value = valueLabel.sizeThatFits(unbounded).width
            let stacked = wanted + style.gap + value > bounds.width - textReserved
            if bounds.width > 0, stacked != valueStacked {
                valueStacked = stacked
                DispatchQueue.main.async { [weak self] in self?.arrange() }
            }
        }
        if rowContent.value != nil, !valueStacked, !accessibilityStacked { reserved += max(valueLabel.intrinsicContentSize.width, 0) + style.gap }
        if UKWrapWidth.set([titleLabel, subtitleLabel], in: self, reserving: reserved) { textStack.invalidateIntrinsicContentSize() }
        if valueStacked || accessibilityStacked { UKWrapWidth.set(valueLabel, in: self, reserving: textReserved) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        guard let tapTarget else { return hit }
        if let accessory, hit === accessory || hit.isDescendant(of: accessory) { return hit }
        // The text stack is switched off so the tap target gets its touches, and a disabled parent hides the accessory from
        // `super`: ask the accessory itself (the Edit and Undo buttons of a task row would never take a finger otherwise).
        if let accessory, accessory.superview != nil, accessory.isUserInteractionEnabled, !accessory.isHidden,
           let inner = accessory.hitTest(convert(point, to: accessory), with: event) {
            return inner
        }
        return tapTarget.bounds.contains(convert(point, to: tapTarget)) ? tapTarget : hit
    }

    /// The leading column's width: the style's, or the caller's view when it is wider (an avatar).
    private var leadingWidth: CGFloat { max(glyphWidth.constant, rowContent.leadingView?.bounds.width ?? 0) }

    private func rescale() {
        let style = rowContent.style
        glyphWidth.constant = UIFontMetrics(forTextStyle: .body).scaledValue(for: style.leadingColumn, compatibleWith: traitCollection)
        glyphWidth.priority = rowContent.leadingView == nil ? .required : .defaultHigh
        if !rowContent.isCentered, root.axis != (isAccessibilitySize ? .vertical : .horizontal) || (isAccessibilitySize && style.leadingAboveTextAtAccessibilitySizes) { arrange() }
        updateTapTrailing()
    }

    private func updateSubtitle(valueBelow: Bool? = nil) {
        for view in textStack.arrangedSubviews where view !== titleLabel && view !== textView && view !== glyphHolder {
            textStack.removeArrangedSubview(view); view.removeFromSuperview()
        }
        if textView == nil {
            if rowContent.subtitle != nil, rowContent.subtitleIsValue, valuesPending {
                textStack.addArrangedSubview(pendingBar)
            } else if rowContent.subtitle != nil {
                textStack.addArrangedSubview(subtitleLabel)
            }
        }
        let below = valueBelow ?? (rowContent.value != nil && (valueStacked || isAccessibilitySize))
        if rowContent.value != nil, below { textStack.addArrangedSubview(valueLabel) }
        updateMinHeight()
        let subtitle = valuesPending && rowContent.subtitleIsValue ? nil : rowContent.subtitle
        textStack.accessibilityLabel = rowContent.spokenLabel ?? Self.accessibilityLabel(title: rowContent.title, subtitle: subtitle)
        textStack.accessibilityValue = rowContent.spokenValue ?? rowContent.value
        textStack.accessibilityIdentifier = rowContent.identifier
        textStack.accessibilityHint = rowContent.hint
    }

    /// "Title, subtitle": the two read as one element (SwiftUI `.accessibilityElement(children: .combine)`).
    static func accessibilityLabel(title: String, subtitle: String?) -> String {
        [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    private func updateCard() {
        backgroundColor = drawsCard ? (cardColor ?? .secondarySystemGroupedBackground) : nil
        layer.cornerRadius = drawsCard ? HassTokens.Radius.tile : 0
        layer.cornerCurve = .continuous
    }

    private func restyle() {
        let style = rowContent.style
        let secondary = UKDesignSurface.secondary(on: surface)
        titleLabel.text = rowContent.title
        titleLabel.font = .ukFont(.body, weight: rowContent.titleWeight ?? .regular)
        titleLabel.textAlignment = rowContent.isCentered ? .center : .natural
        titleLabel.textColor = rowContent.titleInk ?? UKDesignSurface.title(on: surface)
        subtitleLabel.font = .ukFont(rowContent.subtitleStyle ?? style.subtitleStyle, monospacedDigit: style.monospacedSubtitle)
        subtitleLabel.text = rowContent.subtitle
        valueLabel.font = .ukFont(style.valueStyle, weight: rowContent.valueWeight ?? .regular, monospacedDigit: style == .grouped)
        valueLabel.text = rowContent.value
        valueLabel.textColor = rowContent.valueInk ?? secondary
        let subtitleInk = rowContent.subtitleInk ?? secondary
        if subtitleLabel.textColor != subtitleInk { UKMotion.crossFade(subtitleLabel) { self.subtitleLabel.textColor = subtitleInk } }
        if let check = rowContent.check {
            glyphView.image = UIImage(systemName: CheckRowMetrics.symbol(checked: check.isChecked),
                                      withConfiguration: UIImage.SymbolConfiguration(textStyle: .body))
            glyphView.tintColor = check.isChecked ? check.checkedTint : check.uncheckedTint
            glyphView.alpha = check.dimmed ? CGFloat(CheckRowMetrics.dimmedGlyphOpacity) : 1
        } else {
            let glyphInk = rowContent.glyph ?? secondary
            glyphView.image = rowContent.symbol.flatMap {
                UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(rowContent.glyphStyle ?? style.glyphStyle, weight: style == .module ? .medium : .regular)))
            }
            if glyphView.tintColor != glyphInk { UKMotion.crossFade(glyphView) { self.glyphView.tintColor = glyphInk } }
            glyphView.alpha = rowContent.glyphOpacity
        }
        chevronView.tintColor = style == .module ? secondary : UIColor.label.withAlphaComponent(0.3)
        updateSubtitle()
    }

    /// The elements VoiceOver visits: the text (or the tap target that carries it), then the accessory's and the body's own controls.
    override var accessibilityElements: [Any]? {
        get { (isTextAccessible ? [(tapTarget as Any?) ?? textStack] : []) + (accessory.map { [$0] } ?? []) + (bodyView.map { [$0] } ?? []) }
        set {}
    }
}

// MARK: - Row button

/// Presses a ``UKRowView`` like a list cell (``ModuleRowButtonStyle``): a light highlight across the row while held, down at once and
/// released with the `quick` fade. The whole row is the 44 pt-plus target; VoiceOver gets one button named "Title, subtitle".
class UKRowButton: UIControl, UKSurfaceStyled {
    let row: UKRowView
    var surface: TileSurface {
        get { row.surface }
        set { row.surface = newValue; highlightView.backgroundColor = UKDesignInk.primary }
    }
    var onTap: (() -> Void)?
    private let highlightView = UIView()

    init(_ row: UKRowView, onTap: (() -> Void)? = nil) {
        self.row = row
        self.onTap = onTap
        super.init(frame: .zero)
        highlightView.backgroundColor = UKDesignInk.primary
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        row.isUserInteractionEnabled = false
        for view in [highlightView, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { onTap?() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if isHighlighted {
                highlightView.alpha = 0.10
            } else {
                UKMotion.quick { self.highlightView.alpha = 0 }
            }
        }
    }

    override var accessibilityLabel: String? {
        get {
            let content = row.rowContent
            return UKRowView.accessibilityLabel(title: content.title, subtitle: row.valuesPending && content.subtitleIsValue ? nil : content.subtitle)
        }
        set {}
    }

    override var accessibilityValue: String? {
        get { row.rowContent.value }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? .button : [.button, .notEnabled] }
        set {}
    }
}
#endif
