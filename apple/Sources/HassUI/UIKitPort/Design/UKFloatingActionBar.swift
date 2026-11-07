#if os(iOS)
import HassDesign
import Observation
import UIKit

/// One floating action: a labeled capsule or an icon-only glass circle (`FloatingAction`). The accessibility identifier is
/// `fab.<id>`.
public struct UKFloatingAction {
    public var id: String
    public var title: String
    public var symbol: String
    public var showsTitle: Bool
    public var isActive: Bool
    public var isProminent: Bool
    public var action: () -> Void

    public init(id: String, title: String, symbol: String, showsTitle: Bool = true, isActive: Bool = false,
                isProminent: Bool = true, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.showsTitle = showsTitle
        self.isActive = isActive
        self.isProminent = isProminent
        self.action = action
    }
}

extension UKFloatingAction {
    /// The action as a plain glass capsule (an icon-only action shown with its title).
    fileprivate var untinted: UKFloatingAction {
        var copy = self
        copy.isProminent = false
        return copy
    }
}

/// The search field that sits in the bar (`FloatingSearch`). Observable: the bar updates when ``text`` or ``isExpanded``
/// change, and the page filters from ``text``.
@MainActor
@Observable
public final class UKFloatingSearch {
    public var text: String
    public var isExpanded: Bool
    /// Placeholder and accessibility label, e.g. "Search Recipes".
    public let prompt: String

    public init(prompt: String, text: String = "", isExpanded: Bool = false) {
        self.prompt = prompt
        self.text = text
        self.isExpanded = isExpanded
    }
}

/// Floating page actions along the bottom edge (`FloatingActionBar`; pattern `.agents/patterns/floating-actions.md`).
///
/// Search is a glass capsule that fills the bar's leading space, with the other actions as glass circles trailing it. Tapping it
/// opens the field, which takes the bar's full width and hides the other actions. A page's primary labeled action is a `#0071E3`
/// glass capsule. At accessibility text sizes the labelled actions take full-width rows above a row of circles.
///
/// Pin it to a page with ``UKPinnedBarViewController`` (the page's last row scrolls clear of it):
///
/// ```swift
/// let bar = UKFloatingActionBar(actions: [UKFloatingAction(id: "add", title: "Add Task", symbol: "plus") { add() }],
///                               search: UKFloatingSearch(prompt: "Search Tasks"))
/// return UKPinnedBarViewController(content: list, bar: bar, scrollView: list.tableView)
/// ```
public final class UKFloatingActionBar: UIView {
    /// The prominent capsule's fill: G's `#0071E3`.
    public static var tint: UIColor { UIColor(FloatingActionBar.tintToken) }
    /// An active circle's fill: `#F2F2F7` under a black glyph.
    public static var activeTint: UIColor { UIColor(FloatingActionBar.activeTintToken) }
    /// The glyph on an active circle.
    public static var activeGlyph: UIColor { UIColor(FloatingActionBar.activeGlyphToken) }

    public var actions: [UKFloatingAction] { didSet { rebuild() } }
    /// A bar that spans a split window (the Duo partly folded): the search stays in the leading `leadingColumn` points (the list's
    /// pane, hinge to the left of it) and the other actions trail the far edge. Nil: the search fills the bar, as everywhere else.
    public private(set) var leadingColumn: CGFloat?
    /// The icon-only actions show their titles too (a capsule each), where the bar has the room of a whole window.
    public private(set) var expandsActions = false
    public private(set) var search: UKFloatingSearch?

    private let group: UIView
    private var host: UIView { (group as? UIVisualEffectView)?.contentView ?? group }
    private let bag = UKObservationBag()
    private var stack: UIStackView?
    /// The glass group's leading edge: pinned to the bar's margin when the bar fills (search, accessibility sizes), otherwise free
    /// so the group (one backdrop and SDF for its whole bounds) hugs the capsule like SwiftUI's glass does instead of spanning the width.
    private lazy var groupLeading = group.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.l)
    private lazy var groupHugging = group.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: HassTokens.Spacing.l)
    private var searchCollapsed: UKBarSearchCollapsed?
    private var searchExpanded: UKBarSearchExpanded?
    private var actionViews: [UIView] = []
    private var builtExpanded = false
    private var builtAccessibility = false
    private var lastSymbolsActive: [String: Bool] = [:]

    /// The circles' size, growing with the glyph (Dynamic Type) up to 1.5 times the base.
    var buttonSize: CGFloat {
        min(UIFontMetrics(forTextStyle: .title3).scaledValue(for: FloatingActionBar.size), FloatingActionBar.size * FloatingActionBar.maxGrowth)
    }

    public init(actions: [UKFloatingAction], search: UKFloatingSearch? = nil) {
        self.actions = actions
        self.search = search
        if #available(iOS 26, *), !UKPerfSwitches.isOff(.ukFabContainer) {
            let effect = UIGlassContainerEffect()
            effect.spacing = 0
            group = UIVisualEffectView(effect: effect)
        } else {
            group = UIView()
        }
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(group)
        groupHugging.isActive = true
        group.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            group.topAnchor.constraint(equalTo: topAnchor),
            group.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            group.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.rebuild() }
        rebuild()
        bag.observe { [weak self] in self?.syncSearch() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Swaps the search field (nil removes it).
    public func setSearch(_ newSearch: UKFloatingSearch?) {
        search = newSearch
        bag.removeAll()
        rebuild()
        bag.observe { [weak self] in self?.syncSearch() }
    }

    /// Changes how the bar spreads over a split window (``leadingColumn``, ``expandsActions``); animated, the old bar dissolves into the new
    /// one (Reduce Motion: the shorter dissolve).
    public func setSplit(leadingColumn column: CGFloat?, expandsActions expands: Bool, animated: Bool) {
        guard column != leadingColumn || expands != expandsActions else { return }
        let change = { [self] in
            leadingColumn = column
            expandsActions = expands
            rebuild()
            layoutIfNeeded()
        }
        guard animated, window != nil else { change(); return }
        let duration = UKMotion.reduceMotion ? MotionTokens.quickDuration : MotionTokens.standardDuration
        UIView.transition(with: self, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: change)
    }

    /// Updates the applied state of an action's circle without rebuilding the bar (the filter turned on).
    public func setActive(_ isActive: Bool, forActionID id: String) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].isActive != isActive else { return }
        actions[index].isActive = isActive
        (actionViews.first { $0.accessibilityIdentifier == "fab.\(id)" } as? UKBarGlassControl)?.setActive(isActive)
    }

    // MARK: Build

    private var isAccessibilityLayout: Bool {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory && search?.isExpanded != true
    }

    private func rebuild() {
        stack?.removeFromSuperview()
        actionViews = []
        searchCollapsed = nil
        searchExpanded = nil
        guard !actions.isEmpty || search != nil else { stack = nil; return }
        let size = buttonSize
        builtAccessibility = isAccessibilityLayout
        builtExpanded = search?.isExpanded == true
        let root: UIStackView
        if builtAccessibility {
            root = UIStackView()
            root.axis = .vertical
            root.alignment = .trailing
            root.spacing = HassTokens.Spacing.s
            for action in actions where action.showsTitle {
                let view = UKBarCapsuleButton(action: action, fillsWidth: true, buttonSize: size)
                view.widthReference = self
                actionViews.append(view)
                root.addArrangedSubview(view)
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            }
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = HassTokens.Spacing.s
            row.alignment = .center
            if let search {
                let circle = UKBarCircleButton(id: "search", title: search.prompt, symbol: "magnifyingglass", isActive: !search.text.isEmpty, buttonSize: size) { [weak self] in
                    self?.openSearch()
                }
                actionViews.append(circle)
                row.addArrangedSubview(circle)
            }
            for action in actions where !action.showsTitle {
                let view = UKBarCircleButton(id: action.id, title: action.title, symbol: action.symbol, isActive: action.isActive, buttonSize: size, perform: action.action)
                actionViews.append(view)
                row.addArrangedSubview(view)
            }
            root.addArrangedSubview(row)
        } else {
            root = UIStackView()
            root.axis = .horizontal
            root.alignment = .center
            root.spacing = HassTokens.Spacing.s
            if let search {
                let collapsed = UKBarSearchCollapsed(search: search, buttonSize: size) { [weak self] in self?.openSearch() }
                let expanded = UKBarSearchExpanded(search: search, buttonSize: size) { [weak self] in self?.closeSearch() }
                searchCollapsed = collapsed
                searchExpanded = expanded
                root.addArrangedSubview(collapsed)
                root.addArrangedSubview(expanded)
                collapsed.isHidden = search.isExpanded
                expanded.isHidden = !search.isExpanded
                if let column = leadingColumn {
                    // The search ends at the hinge; the space after it (kept while the field is open) is what the actions trail across.
                    for field in [collapsed, expanded] {
                        let width = field.widthAnchor.constraint(equalToConstant: max(0, column - 2 * HassTokens.Spacing.l))
                        width.priority = UILayoutPriority(999)
                        width.isActive = true
                    }
                    let spacer = UIView()
                    spacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
                    spacer.isUserInteractionEnabled = false
                    root.addArrangedSubview(spacer)
                }
            }
            for action in actions {
                let view: UIView = action.showsTitle || expandsActions
                    ? UKBarCapsuleButton(action: action.showsTitle ? action : action.untinted, fillsWidth: false, buttonSize: size,
                                         givesWay: search != nil && leadingColumn == nil)
                    : UKBarCircleButton(id: action.id, title: action.title, symbol: action.symbol, isActive: action.isActive, buttonSize: size, perform: action.action)
                (view as? UKBarCapsuleButton)?.widthReference = self
                view.isHidden = search?.isExpanded == true
                actionViews.append(view)
                root.addArrangedSubview(view)
            }
        }
        stack = root
        host.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            root.topAnchor.constraint(equalTo: host.topAnchor), root.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ]
        // `safeAreaBar(alignment: .trailing)`: a bar without a search field sits at the trailing edge; with one it fills.
        constraints.append(root.leadingAnchor.constraint(equalTo: host.leadingAnchor))
        NSLayoutConstraint.activate(constraints)
        let fills = search != nil || builtAccessibility
        groupLeading.isActive = fills
        groupHugging.isActive = !fills
        syncSearch()
    }

    // MARK: Search state

    private func openSearch() {
        search?.isExpanded = true
        searchExpanded?.focus()
    }

    private func closeSearch() {
        search?.text = ""
        search?.isExpanded = false
    }

    /// Follows the search model: shows the field or the capsule (a spring unless Reduce Motion), mirrors the query.
    private func syncSearch() {
        guard let search else { return }
        let expanded = search.isExpanded
        let query = search.text
        searchCollapsed?.update(query: query)
        if expanded != builtExpanded || isAccessibilityLayout != builtAccessibility {
            if isAccessibilityLayout != builtAccessibility {
                rebuild()
                if expanded { searchExpanded?.focus() }
                return
            }
            builtExpanded = expanded
            let apply = { [self] in
                searchCollapsed?.isHidden = expanded
                searchExpanded?.isHidden = !expanded
                searchCollapsed?.alpha = expanded ? 0 : 1
                searchExpanded?.alpha = expanded ? 1 : 0
                actionViews.forEach { $0.isHidden = expanded; $0.alpha = expanded ? 0 : 1 }
                layoutIfNeeded()
            }
            if window == nil { apply() } else {
                // Reduce Motion: the search capsule swaps in place without the spring.
                UKMotion.animate(.standard, animations: apply)
            }
            if !expanded { searchExpanded?.blur() }
        }
        if let circle = actionViews.first(where: { $0.accessibilityIdentifier == "fab.search" }) as? UKBarGlassControl {
            circle.setActive(!query.isEmpty)
        }
    }
}

// MARK: - Glass controls

/// A glass piece of the bar that is one button: the glass, the content under it, and a transparent button on top that takes the
/// touch (so the interactive glass lifts and shimmers under it). The control itself is the accessibility element.
class UKBarGlassControl: UIView {
    let glass: UKGlassView
    let content = UIView()
    private let button = UIButton(type: .custom)

    init(shape: UKGlassView.Shape, tint: UIColor?, interactive: Bool = true, perform: @escaping () -> Void) {
        glass = UKGlassView(shape: shape, tint: tint, isInteractive: interactive && !UKPerfSwitches.isOff(.ukFabInteractive))
        super.init(frame: .zero)
        addSubview(glass)
        glass.ukPin(to: self)
        content.isUserInteractionEnabled = false
        glass.contentView.addSubview(content)
        content.ukPin(to: glass.contentView)
        glass.contentView.addSubview(button)
        button.ukPin(to: glass.contentView)
        button.addAction(UIAction { _ in perform() }, for: .touchUpInside)
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setActive(_ isActive: Bool) {}

    override func accessibilityActivate() -> Bool {
        button.sendActions(for: .touchUpInside)
        return true
    }
}

/// An icon-only glass circle (`FloatingBarCircleButton`).
final class UKBarCircleButton: UKBarGlassControl {
    private let image = UIImageView()
    private var isActive: Bool

    init(id: String, title: String, symbol: String, isActive: Bool, buttonSize: CGFloat, perform: @escaping () -> Void) {
        self.isActive = isActive
        super.init(shape: .circle, tint: isActive ? UKFloatingActionBar.activeTint : nil, perform: perform)
        image.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title3, weight: .medium)))
        image.tintColor = isActive ? UKFloatingActionBar.activeGlyph : .white
        image.contentMode = .center
        content.addSubview(image)
        image.ukPin(to: content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: buttonSize), heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        accessibilityLabel = title
        accessibilityTraits = isActive ? [.button, .selected] : .button
        accessibilityIdentifier = "fab.\(id)"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        glass.setTint(active ? UKFloatingActionBar.activeTint : nil)
        UKMotion.dissolve(image) { [self] in image.tintColor = active ? UKFloatingActionBar.activeGlyph : .white }
        accessibilityTraits = active ? [.button, .selected] : .button
    }
}

/// A labelled action capsule (`FloatingBarCapsuleButton`): blue-tinted glass when prominent, clear of tint otherwise.
final class UKBarCapsuleButton: UKBarGlassControl {
    /// The bar the capsule sits in: its width is fixed by the page, so the title wraps within it rather than at the capsule's own
    /// width (which comes from the title).
    weak var widthReference: UIView?
    private let titleLabel = UILabel()
    private let glyph = UIImageView()

    init(action: UKFloatingAction, fillsWidth: Bool, buttonSize: CGFloat, givesWay: Bool = true) {
        super.init(shape: .capsule, tint: action.isProminent ? UKFloatingActionBar.tint : nil, perform: action.action)
        let icon = glyph
        icon.image = UIImage(systemName: action.symbol)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.preferred(.body, weight: .semibold))
        icon.tintColor = .white
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = titleLabel
        label.text = action.title
        label.font = UKFont.preferred(.body, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        // The labelled capsule gives way to the search field, wrapping its title (as the SwiftUI bar does beside a field).
        label.setContentCompressionResistancePriority(givesWay ? .defaultLow : .required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        content.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        let vertical = fillsWidth ? HassTokens.Spacing.s : 0
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: buttonSize),
            row.topAnchor.constraint(equalTo: content.topAnchor, constant: vertical),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -vertical),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: HassTokens.Spacing.l + 2),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -(HassTokens.Spacing.l + 2)),
        ])
        if fillsWidth { row.distribution = .fill }
        accessibilityLabel = action.title
        accessibilityTraits = action.isActive ? [.button, .selected] : .button
        accessibilityIdentifier = "fab.\(action.id)"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let reference = widthReference else { return }
        // The bar's width less its two side margins, the capsule's own padding, the glyph and the gap.
        let reserved = 2 * HassTokens.Spacing.l + 2 * (HassTokens.Spacing.l + 2) + glyph.intrinsicContentSize.width + 6
        UKWrapWidth.set(titleLabel, in: reference, reserving: reserved)
    }
}

// MARK: - Search

/// The closed search field: a glass capsule with the magnifier and the prompt, or the query once one is typed.
final class UKBarSearchCollapsed: UKBarGlassControl {
    private let label = UILabel()
    private let search: UKFloatingSearch

    init(search: UKFloatingSearch, buttonSize: CGFloat, open: @escaping () -> Void) {
        self.search = search
        super.init(shape: .capsule, tint: nil, perform: open)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.preferred(.body, weight: .medium))
        icon.tintColor = UIColor(HassTokens.RGB.Surface.secondaryOnWash)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        label.font = UKFont.preferred(.body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, label, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.s
        content.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: buttonSize),
            row.topAnchor.constraint(equalTo: content.topAnchor), row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: HassTokens.Spacing.l),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        accessibilityLabel = search.prompt
        accessibilityIdentifier = "fab.search"
        update(query: search.text)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(query: String) {
        let text = query.isEmpty ? search.prompt : query
        let color = query.isEmpty ? UIColor(HassTokens.RGB.Surface.secondaryOnWash) : .white
        if label.text != text { label.text = text }
        if label.textColor != color { UKMotion.dissolve(label) { [label] in label.textColor = color } }
        accessibilityValue = query
        accessibilityTraits = query.isEmpty ? .button : [.button, .selected]
    }
}

/// The open search field with its close button (`FloatingSearchField.expanded`).
final class UKBarSearchExpanded: UIView, UITextFieldDelegate {
    private let glass = UKGlassView(shape: .capsule, tint: nil, isInteractive: false)
    private let field = UITextField()
    private let search: UKFloatingSearch

    init(search: UKFloatingSearch, buttonSize: CGFloat, close: @escaping () -> Void) {
        self.search = search
        super.init(frame: .zero)
        addSubview(glass)
        glass.ukPin(to: self)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIColor(HassTokens.RGB.Surface.secondaryOnWash)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        field.font = UKFont.preferred(.body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .white
        field.tintColor = .white
        field.attributedPlaceholder = NSAttributedString(
            string: search.prompt, attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.5)])
        field.returnKeyType = .search
        field.delegate = self
        field.text = search.text
        field.accessibilityIdentifier = "fab.search.field"
        field.addAction(UIAction { [weak self] _ in self?.search.text = self?.field.text ?? "" }, for: .editingChanged)
        let closeButton = UIButton(type: .custom)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title3))), for: .normal)
        closeButton.tintColor = UIColor(HassTokens.RGB.Surface.secondaryOnWash)
        closeButton.accessibilityLabel = "Close Search"
        closeButton.accessibilityIdentifier = "fab.search.close"
        closeButton.addAction(UIAction { _ in close() }, for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, field, closeButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.s
        glass.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: buttonSize),
            row.topAnchor.constraint(equalTo: glass.contentView.topAnchor), row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: HassTokens.Spacing.l),
            row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    func focus() {
        if field.text != search.text { field.text = search.text }
        // The field is unhidden by the same update that asks for focus; wait one turn for it to be in the window.
        DispatchQueue.main.async { [field] in field.becomeFirstResponder() }
    }

    func blur() { field.resignFirstResponder() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
#endif
