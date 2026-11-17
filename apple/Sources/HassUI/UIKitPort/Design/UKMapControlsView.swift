#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Corner button groups on a picture (`sh.surface-controls@1`)

/// One button of a corner group as it draws now: values only, so the view never reads a store or a renderer.
struct UKMapControlItem: Equatable {
    /// The id the press closure receives.
    let id: String
    /// The SF Symbol to draw (already resolved against the device's symbol set).
    var symbol: String
    /// What VoiceOver and Voice Control read, and the title in More's menu.
    var label: String
    /// What VoiceOver adds after the label.
    var hint: String?
    /// The reason a dimmed button is dimmed, spoken as its VoiceOver value.
    var value: String?
    /// The accessibility identifier.
    var identifier: String
    /// A dimmed button keeps its place and does nothing.
    var isEnabled = true
}

/// One corner's group as it draws now: a row or a column of the buttons that are visible.
struct UKMapControlGroup: Equatable {
    let corner: MapControlCorner
    let axis: MapControlAxis
    var items: [UKMapControlItem]
}

/// The corner button groups over a picture: the canonical component of the corner-groups pattern (`.agents/patterns/map-controls.md`).
///
/// Each group is one Liquid Glass shape holding 44 pt buttons edge to edge, 8 pt in from the two edges of its corner. `layoutSubviews` runs the
/// fit rule (``MapControlFit``) on the view's own size, so an iPhone, a folded Duo and an iPad are one rule: a group with more buttons than fit
/// shows all but one and then More, a `UIMenu` of the rest. The view takes only values and a closure; it is generic over whatever card it
/// floats on (HIG, Layout: groups pin to the card, which is inside the safe area already).
///
/// Taps outside the buttons reach the picture beneath.
@MainActor
final class UKMapControlsView: UIView {
    /// The id of the button pressed.
    var onPress: ((String) -> Void)?
    /// The groups that draw, in the order they were given. A group with no visible button draws nothing and frees its edge.
    private(set) var groups: [UKMapControlGroup] = []
    /// What the fit rule gave each drawn group at the current size, in the order of ``drawnGroups``.
    private(set) var fit: [MapControlFit.Result] = []

    private var groupViews: [MapControlCorner: GroupView] = [:]
    private var observers: UKObserverTokens?
    private var appliedKey: [String]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        addInteraction(UILargeContentViewerInteraction())
        observers = NotificationCenter.default.ukObserveAccessibility { [weak self] in self?.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The groups with a visible button.
    var drawnGroups: [UKMapControlGroup] { groups.filter { !$0.items.isEmpty } }

    /// The corners that hold a drawn group.
    var occupiedCorners: Set<MapControlCorner> { Set(drawnGroups.map(\.corner)) }

    /// Draws `groups`. Equal groups change nothing; a changed group updates in place with no animation of its own.
    func apply(_ groups: [UKMapControlGroup]) {
        guard groups != self.groups else { return }
        self.groups = groups
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let drawn = drawnGroups
        fit = MapControlFit.fit(width: bounds.width, height: bounds.height, groups: drawn.map { .init(corner: $0.corner, axis: $0.axis, count: $0.items.count) })
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let inset = CGFloat(MapControlFit.inset), side = CGFloat(MapControlFit.controlSize)
        for corner in MapControlCorner.allCases where !drawn.contains(where: { $0.corner == corner }) { groupViews[corner]?.isHidden = true }
        for (group, result) in zip(drawn, fit) {
            let view = groupViews[group.corner] ?? makeGroupView(group.corner)
            view.isHidden = false
            view.configure(group, result: result)
            let count = CGFloat(result.shown + (result.more ? 1 : 0))
            // A group of one counts as a column, whatever its axis (it draws as a 44 pt circle either way).
            let isRow = group.axis == .row && count > 1
            let size = CGSize(width: isRow ? side * count : side, height: isRow ? side : side * count)
            let onLeft = group.corner.isLeading != rightToLeft
            let x = onLeft ? inset : bounds.width - inset - size.width
            let y = group.corner.isTop ? inset : bounds.height - inset - size.height
            view.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        // No explicit `accessibilityElements`: the buttons are plain elements in the view tree, which VoiceOver reads in place order
        // (leading to trailing, top to bottom), the order the groups are authored in.
    }

    private func makeGroupView(_ corner: MapControlCorner) -> GroupView {
        let view = GroupView(corner: corner) { [weak self] id in self?.onPress?(id) }
        groupViews[corner] = view
        addSubview(view)
        return view
    }

    /// Taps outside a group fall through to the picture.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        groupViews.values.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    /// The frame of the group at `corner`, for tests and evidence.
    func frame(of corner: MapControlCorner) -> CGRect? {
        groupViews[corner].flatMap { $0.isHidden ? nil : $0.frame }
    }

    /// A button by its accessibility identifier, for tests.
    func button(identifier: String) -> UIControl? {
        groupViews.values.lazy.filter { !$0.isHidden }.flatMap(\.accessibleButtons).first { $0.accessibilityIdentifier == identifier }
    }

    private func restyle() {
        for view in groupViews.values { view.restyle() }
    }
}

// MARK: - One group

extension UKMapControlsView {
    /// A group: one glass shape (a circle for a group of one, a capsule for more) behind its icons, with the buttons above.
    @MainActor
    fileprivate final class GroupView: UIView {
        let corner: MapControlCorner
        private let onPress: (String) -> Void
        private let glass = UKNavigationGlassView(shape: .capsule)
        /// The opaque plate Reduce Transparency and Increase Contrast give a group (`.agents/design/mockups`, vacuum-map-controls).
        private let plate = UIView()
        private let icons = UIStackView()
        private let buttons = UIStackView()
        private var applied: [Button.Kind] = []
        private var axis: NSLayoutConstraint.Axis = .vertical

        init(corner: MapControlCorner, onPress: @escaping (String) -> Void) {
            self.corner = corner
            self.onPress = onPress
            super.init(frame: .zero)
            glass.isUserInteractionEnabled = false
            addSubview(glass)
            glass.ukPin(to: self)
            plate.isUserInteractionEnabled = false
            plate.layer.cornerCurve = .continuous
            glass.contentView.addSubview(plate)
            plate.ukPin(to: glass.contentView)
            for stack in [icons, buttons] {
                stack.distribution = .fillEqually
                stack.isUserInteractionEnabled = stack === buttons
                stack.translatesAutoresizingMaskIntoConstraints = false
            }
            glass.contentView.addSubview(icons)
            icons.ukPin(to: glass.contentView)
            addSubview(buttons)
            buttons.ukPin(to: self)
            restyle()
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: GroupView, _) in view.restyle() }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        var accessibleButtons: [UIControl] { buttons.arrangedSubviews.compactMap { $0 as? UIControl } }

        override func layoutSubviews() {
            super.layoutSubviews()
            plate.layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        /// Shows `result.shown` buttons of `group` and, when the rule says so, More with the rest.
        func configure(_ group: UKMapControlGroup, result: MapControlFit.Result) {
            let shown = Array(group.items.prefix(result.shown))
            let hidden = result.more ? Array(group.items.dropFirst(result.shown)) : []
            var states = shown.map { Button.Kind.item($0) }
            if result.more { states.append(.more(hidden, corner: corner)) }
            let isRow = group.axis == .row && states.count > 1
            let wanted: NSLayoutConstraint.Axis = isRow ? .horizontal : .vertical
            if states != applied || axis != wanted {
                applied = states
                axis = wanted
                icons.axis = wanted
                buttons.axis = wanted
                for stack in [icons, buttons] { stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() } }
                for state in states {
                    let button = Button(kind: state) { [onPress] id in onPress(id) }
                    icons.addArrangedSubview(button.iconView)
                    buttons.addArrangedSubview(button)
                }
            }
        }

        /// The plate: opaque under Reduce Transparency when there is no glass to turn opaque by itself, and with an outline under Increase Contrast.
        func restyle() {
            let reduced = UIAccessibility.isReduceTransparencyEnabled, darker = UIAccessibility.isDarkerSystemColorsEnabled
            var hasGlass = false
            if #available(iOS 26, *) { hasGlass = true }
            // iOS 26's glass turns opaque by itself under Reduce Transparency; below it the thin material is replaced by an opaque fill.
            let opaque = (reduced && !hasGlass) || darker
            plate.backgroundColor = opaque ? Self.plateFill : .clear
            plate.layer.borderWidth = darker ? 1 : 0
            plate.layer.borderColor = UKDesignInk.primary.resolvedColor(with: traitCollection).cgColor
        }

        private static let plateFill = UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x3A3A3C) : .white }
    }
}

// MARK: - One button

extension UKMapControlsView {
    /// A 44 pt button: a transparent control over its icon, which lives in the group's glass. Press dims the icon (HIG, Buttons: always give a
    /// custom button a press state); a dimmed button keeps its place and says why as its value; More opens a menu of the buttons that did not fit.
    @MainActor
    fileprivate final class Button: UIButton {
        enum Kind: Equatable {
            case item(UKMapControlItem)
            case more([UKMapControlItem], corner: MapControlCorner)
        }

        let iconView = UIImageView()
        private let kind: Kind
        private let onPress: (String) -> Void

        init(kind: Kind, onPress: @escaping (String) -> Void) {
            self.kind = kind
            self.onPress = onPress
            super.init(frame: .zero)
            let symbol: String
            switch kind {
            case .item(let item): symbol = item.symbol
            case .more: symbol = "ellipsis"
            }
            iconView.image = Self.image(symbol)
            iconView.tintColor = UKDesignInk.primary
            iconView.contentMode = .center
            iconView.isUserInteractionEnabled = false
            configureAccessibility()
            configureAction()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// Body semibold fixed at the Large size, the symbol Locate has always had; it does not grow with Dynamic Type (the button stays 44 pt).
        static func image(_ symbol: String) -> UIImage? {
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body, weight: .semibold)))
        }

        private func configureAccessibility() {
            isAccessibilityElement = true
            accessibilityTraits = .button
            showsLargeContentViewer = true
            switch kind {
            case .item(let item):
                accessibilityLabel = item.label
                accessibilityHint = item.hint
                accessibilityValue = item.isEnabled ? nil : item.value
                accessibilityIdentifier = item.identifier
                largeContentTitle = item.label
                largeContentImage = Self.image(item.symbol)
                isEnabled = item.isEnabled
                if !item.isEnabled { accessibilityTraits.insert(.notEnabled) }
                iconView.alpha = item.isEnabled ? 1 : 0.4
            case .more(_, let corner):
                accessibilityLabel = "More Map Controls"
                accessibilityHint = "Shows the rest of the buttons in this corner."
                accessibilityIdentifier = "map.controls.more.\(corner.rawValue)"
                largeContentTitle = "More Map Controls"
                largeContentImage = Self.image("ellipsis")
            }
        }

        private func configureAction() {
            switch kind {
            case .item(let item):
                addAction(UIAction { [onPress] _ in
                    UKTapFeedback.tap()
                    onPress(item.id)
                }, for: .touchUpInside)
            case .more(let hidden, _):
                // HIG, Menus: a menu of the commands that did not fit, in order, each with its symbol and its label as the title.
                menu = UIMenu(children: hidden.map { item in
                    UIAction(title: item.label, subtitle: item.isEnabled ? nil : item.value, image: UIImage(systemName: item.symbol),
                             attributes: item.isEnabled ? [] : .disabled) { [onPress] _ in
                        UKTapFeedback.tap()
                        onPress(item.id)
                    }
                })
                showsMenuAsPrimaryAction = true
            }
        }

        override var isHighlighted: Bool {
            didSet {
                guard isEnabled else { return }
                iconView.alpha = isHighlighted ? 0.5 : 1
            }
        }
    }
}
#endif
