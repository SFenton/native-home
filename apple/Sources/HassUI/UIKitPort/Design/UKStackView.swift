#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Measuring

/// A view a stack can ask for its natural width and how it gives room (`sh.stack@1`).
///
/// A view that does not conform is measured by `sizeThatFits` with no bound, and never gives room.
@MainActor
protocol UKStackMeasuring: AnyObject {
    /// The width the view takes with all the room it wants.
    var stackNaturalWidth: CGFloat { get }
    /// Whether the view takes the width of its column (a text that wraps) instead of its natural width.
    var stackFillsWidth: Bool { get }
    /// Whether the view can give room to its neighbours (a text cut with an ellipsis or slid as a ticker).
    var stackShrinks: Bool { get }
}

// MARK: - Stack

/// A row or a column of views with optional spacing, padding, lines between, a surface, a tap and one accessibility element (`sh.stack@1`).
///
/// It is values and closures: the stack gets its definition and its children's views, and tells nobody anything but the tap. ``ServerUIStackLayout``
/// chooses the arrangement (a horizontal stack collapses to a column at an accessibility text size, or when what must fit does not), and
/// ``ServerUIStackPlacement`` gives each child its frame, so this view only measures and places. Frames mirror in a right-to-left language.
///
/// With an action the whole stack is one button (HIG, Buttons): at least 44 pt tall, named by its label, dimmed with `isEnabled`. Without
/// one it takes no touch of its own and passes each to the child under it (a button, a control or a row inside it works), so a page still
/// scrolls under it.
@MainActor
final class UKStackView: UIControl, UKGridMeasuring, UKStackMeasuring {
    /// A child and the id the groups name it by.
    struct Member {
        let id: String
        let view: UIView
    }

    private(set) var definition: ServerUIStack?
    private(set) var members: [Member] = []
    /// The arrangement chosen the last time the stack was measured; `nil` before the first.
    private(set) var arrangement: ServerUIStackLayout.Result?
    /// What the tap does, or `nil` for a stack that is not a button.
    var onActivate: (() -> Void)?

    private let surface = UIView()
    private var moduleSurface: UKModuleView?
    private var lines: [UIView] = []
    /// The surface drawn now, so an observation tick that changes nothing does not rebuild it.
    private var drawnSurface: ServerUIStack.Surface?
    private var drawnSurfaceIsSet = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.isUserInteractionEnabled = false
        insertSubview(surface, at: 0)
        addAction(UIAction { [weak self] _ in self?.onActivate?() }, for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKStackView, _) in
            view.setNeedsLayout()
            view.ukRemeasureContainers(includingSelf: true)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKStackView, _) in view.paintBorder() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Content

    /// Whether the views handed over are not the ones this stack holds.
    func needsReparent(_ views: [UIView]) -> Bool { members.map(\.view) != views }

    /// Releases every child, before another owner takes them.
    func clear() {
        members.forEach { $0.view.removeFromSuperview() }
        members = []
    }

    /// Draws `value` around `members`.
    /// - Parameters:
    ///   - value: The stack.
    ///   - members: The children that are shown, in document order, with the ids the groups name them by.
    ///   - label: The words VoiceOver reads for a group, or `nil`.
    ///   - spokenValue: The value VoiceOver reads after the label, or `nil`.
    ///   - isEnabled: Whether the tap does anything now.
    func apply(_ value: ServerUIStack, members: [Member], label: String?, spokenValue: String?, isEnabled: Bool) {
        definition = value
        let kept = Set(members.map { ObjectIdentifier($0.view) })
        for old in self.members where !kept.contains(ObjectIdentifier(old.view)) { old.view.removeFromSuperview() }
        for member in members where member.view.superview !== self { addSubview(member.view) }
        self.members = members
        // A disabled control takes no touch for its children either, so a stack with no action stays enabled; it does nothing on a tap.
        self.isEnabled = value.action == nil || isEnabled
        // Always on, so a child inside a stack with no action of its own is reached; `hitTest` keeps the stack itself out of the way.
        isUserInteractionEnabled = true
        drawSurface(value.surface)
        drawLines(count: value.dividerCount(shown: members.count), line: value.dividers)
        describe(value, label: label, spokenValue: spokenValue)
        setNeedsLayout()
    }

    /// The accessibility the stack presents: one named element for `group`, the children as they are for `children`, nothing for `hidden`.
    private func describe(_ value: ServerUIStack, label: String?, spokenValue: String?) {
        accessibilityElementsHidden = value.accessibility?.element == .hidden
        guard let description = value.accessibility, description.element == .group else {
            isAccessibilityElement = false
            accessibilityLabel = nil
            return
        }
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityValue = spokenValue
        accessibilityHint = description.hint
        let role = description.role ?? (value.action == nil ? nil : .button)
        var traits: UIAccessibilityTraits = []
        switch role {
        case .button?: traits.insert(.button)
        case .header?: traits.insert(.header)
        case .text?, nil: traits.insert(.staticText)
        }
        if !isEnabled, value.action != nil { traits.insert(.notEnabled) }
        accessibilityTraits = traits
    }

    private func drawSurface(_ value: ServerUIStack.Surface?) {
        if drawnSurfaceIsSet, drawnSurface == value { return }
        drawnSurface = value
        drawnSurfaceIsSet = true
        moduleSurface?.removeFromSuperview()
        moduleSurface = nil
        surface.layer.borderWidth = 0
        surface.layer.cornerRadius = 0
        surface.backgroundColor = nil
        guard let value else { return }
        switch value {
        case .module(let density):
            let module = UKModuleView(density == .dense ? .dense : .thin)
            module.isUserInteractionEnabled = false
            insertSubview(module, aboveSubview: surface)
            moduleSurface = module
        case .fill(let fill, let border, let radius):
            surface.backgroundColor = UKStyledText.color(fill)
            surface.layer.cornerRadius = CGFloat(radius ?? Double(HassTokens.Radius.tile))
            surface.layer.cornerCurve = .continuous
            if let border {
                surface.layer.borderWidth = CGFloat(border.width)
                surface.layer.borderColor = UKStyledText.color(border.ink).resolvedColor(with: traitCollection).cgColor
            }
        }
    }

    private func drawLines(count: Int, line: ServerUIStack.Line?) {
        while lines.count > count { lines.removeLast().removeFromSuperview() }
        guard let line else { return }
        while lines.count < count {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            addSubview(view)
            lines.append(view)
        }
        for view in lines { view.backgroundColor = UKStyledText.color(line.ink) }
    }

    /// The border is a `CGColor`, so it is resolved for the appearance again when that changes.
    private func paintBorder() {
        if case .fill(_, let border?, _)? = definition?.surface {
            surface.layer.borderColor = UKStyledText.color(border.ink).resolvedColor(with: traitCollection).cgColor
        }
    }

    /// A stack with no action is never the target of a touch, only the children inside it are.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self && definition?.action == nil ? nil : hit
    }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted && definition?.action != nil ? 0.6 : 1 } }

    // MARK: Measuring

    private var insets: UIEdgeInsets {
        guard let padding = definition?.padding else { return .zero }
        return UIEdgeInsets(top: CGFloat(padding.top.points), left: CGFloat(padding.leading.points),
                            bottom: CGFloat(padding.bottom.points), right: CGFloat(padding.trailing.points))
    }

    private func natural(_ view: UIView) -> CGFloat {
        if let measuring = view as? UKStackMeasuring { return measuring.stackNaturalWidth }
        return ceil(view.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width)
    }

    private func height(of view: UIView, at width: CGFloat) -> CGFloat {
        if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
        return ceil(view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
    }

    /// Chooses the arrangement for `width` (the width inside the padding) and places the children.
    private func place(innerWidth width: CGFloat) -> ServerUIStackPlacement.Result {
        guard let definition else { return .init() }
        let measured = members.map { member -> (ServerUIStackLayout.Measure, ServerUIStackPlacement.Item) in
            let measuring = member.view as? UKStackMeasuring
            let natural = Double(natural(member.view))
            return (.init(id: member.id, width: natural, shrinks: measuring?.stackShrinks ?? false),
                    .init(id: member.id, width: natural, fillsWidth: measuring?.stackFillsWidth ?? false, shrinks: measuring?.stackShrinks ?? false))
        }
        let layout = ServerUIStackLayout.arrange(.init(
            axis: definition.axis, spacing: definition.spacing, groups: definition.groups, collapse: definition.collapse, children: measured.map(\.0),
            width: Double(width), accessibilitySize: traitCollection.preferredContentSizeCategory.isAccessibilityCategory))
        arrangement = layout
        let views = Dictionary(members.map { ($0.id, $0.view) }, uniquingKeysWith: { first, _ in first })
        return ServerUIStackPlacement.place(layout, items: measured.map(\.1), align: definition.align, distribution: definition.distribution,
                                            dividerWidth: definition.dividers?.width, width: Double(width)) { id, width in
            views[id].map { Double(self.height(of: $0, at: CGFloat(width))) } ?? 0
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let box = insets
        let placed = place(innerWidth: max(0, width - box.left - box.right))
        let content = CGFloat(placed.height) + box.top + box.bottom
        return definition?.action == nil ? ceil(content) : max(HassTokens.minTarget, ceil(content))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    var stackNaturalWidth: CGFloat {
        let box = insets
        return ceil(CGFloat(place(innerWidth: 100_000).width) + box.left + box.right)
    }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { false }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        moduleSurface?.frame = bounds
        let box = insets
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let inner = max(0, bounds.width - box.left - box.right)
        let placed = place(innerWidth: inner)
        // A stack with an action keeps at least 44 pt tall; its content stays centred in the room.
        let spare = max(0, bounds.height - box.top - box.bottom - CGFloat(placed.height))
        func rect(_ frame: ServerUIStackPlacement.Frame) -> CGRect {
            let x = rightToLeft ? inner - CGFloat(frame.x) - CGFloat(frame.width) : CGFloat(frame.x)
            return CGRect(x: box.left + x, y: box.top + spare / 2 + CGFloat(frame.y), width: CGFloat(frame.width), height: CGFloat(frame.height))
        }
        for member in members {
            member.view.frame = placed.frames[member.id].map(rect) ?? .zero
        }
        for (view, frame) in zip(lines, placed.dividers) { view.frame = rect(frame); view.isHidden = false }
        for view in lines.dropFirst(placed.dividers.count) { view.isHidden = true }
    }
}
#endif
