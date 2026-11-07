#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// "Due in 3 days" after a calendar glyph in secondary ink, or an overdue span after a clock: orange under a day, red beyond
/// (``DueLabel``). The glyph sits on the text's first baseline.
@MainActor
final class UKTodoDueLabel: UIView {
    private let icon = UIImageView()
    private let label = UILabel.uk(.subheadline, monospacedDigit: true, ink: UKDesignInk.primary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .small)
        icon.contentMode = .center
        icon.isAccessibilityElement = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: HassTokens.Spacing.xs),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The text and glyph colour for a tone on a surface (``DueLabel/color(_:surface:)``).
    static func color(_ tone: TodoItem.DueTone, surface: TileSurface) -> UIColor {
        switch tone {
        case .future: UKDesignSurface.secondary(on: surface)
        case .overdueHours: UKDesignInk.warning
        case .overdueLong: UKDesignInk.error
        }
    }

    func configure(text: String, tone: TodoItem.DueTone, surface: TileSurface) {
        label.text = text
        icon.image = UIImage(systemName: tone == .future ? "calendar" : "clock")
        let color = Self.color(tone, surface: surface)
        label.textColor = color
        icon.tintColor = color
    }
}

/// A checkable task row with its due label and an optional edit button (``TodoItemRow``): a check circle the size of the
/// title, a body title, a subheadline due line and a trailing edit glyph, or Undo for a task checked off a moment ago. The whole
/// row left of the trailing button is the toggle, 52 pt tall (60 with a due line) or more. The title starts 16 + 24 + 14 pt in,
/// where the module's hairlines inset. The layout is the shared ``UKCheckRow`` (pattern `check-row.md`).
///
/// The row draws no card: a list cell (``UKTodoRowCell``) or a sheet's module draws it. Use it directly in a module of your own
/// (the Summary sheet's chore tabs do):
///
/// ```swift
/// let row = UKTodoItemRow()
/// row.configure(item: item, surface: .sheet,
///               actions: .init(onToggle: { toggle(item) }, onEdit: { edit(item) }, onUndo: nil, onDelete: { ask(item) }))
/// ```
///
/// `configure` is cheap and idempotent: call it again whenever the item, the due label's clock or an action changes. Identifiers
/// and labels are the SwiftUI row's: `todo.item.<identity>` (the toggle, value "Not done, Due in 3 days" or "Done"),
/// `todo.edit.<identity>`, `todo.undo.<identity>`.
@MainActor
final class UKTodoItemRow: UIView {
    /// What the row's buttons do. A nil action takes its button away.
    struct Actions {
        var onToggle: () -> Void
        /// The edit button's action; nil when the row can't be edited.
        var onEdit: (() -> Void)?
        /// Puts the task back while it is checked off and still listed; replaces the edit button.
        var onUndo: (() -> Void)?
        /// A VoiceOver custom action: the swipe and the context menu live on the list row.
        var onDelete: (() -> Void)?
        /// The long-press menu on the row (the control would otherwise take the press as a tap); nil for none.
        var menu: (() -> UIMenu?)?

        init(onToggle: @escaping () -> Void, onEdit: (() -> Void)? = nil, onUndo: (() -> Void)? = nil, onDelete: (() -> Void)? = nil,
             menu: (() -> UIMenu?)? = nil) {
            self.menu = menu
            self.onToggle = onToggle
            self.onEdit = onEdit
            self.onUndo = onUndo
            self.onDelete = onDelete
        }
    }

    private let titleLabel = UILabel.uk(.body, ink: UKDesignInk.primary)
    private let due = UKTodoDueLabel()
    private let textStack = UIStackView()
    private let undoButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    /// The shared check row (``UKCheckRow``): the circle, the text block, and Undo or the edit button as its accessory.
    private let checkRow: UKCheckRow
    private var toggle: UIControl { checkRow.toggle }
    private var actions = Actions(onToggle: {})
    private var surface = TileSurface.page
    private var titleText = ""
    private var isDone = false

    override init(frame: CGRect) {
        titleLabel.lineBreakMode = .byWordWrapping
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(due)
        checkRow = UKCheckRow(content: textStack)
        super.init(frame: frame)
        for part in [titleLabel, due] as [UIView] { part.isUserInteractionEnabled = false }
        toggle.addInteraction(UIContextMenuInteraction(delegate: self))
        checkRow.onToggle = { [weak self] in self?.actions.onToggle() }

        undoButton.setTitle("Undo", for: .normal)
        undoButton.titleLabel?.font = .ukFont(.body, weight: .semibold)
        undoButton.titleLabel?.adjustsFontForContentSizeCategory = true
        undoButton.contentHorizontalAlignment = .leading
        undoButton.setTitleColor(UKDesignInk.action, for: .normal)
        undoButton.addAction(UIAction { [weak self] _ in self?.actions.onUndo?() }, for: .touchUpInside)
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            undoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            undoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        undoButton.setContentHuggingPriority(.required, for: .horizontal)
        undoButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        editButton.setImage(UIImage(systemName: CheckRowMetrics.editSymbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .callout)), for: .normal)
        editButton.addAction(UIAction { [weak self] _ in self?.actions.onEdit?() }, for: .touchUpInside)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            editButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        editButton.setContentHuggingPriority(.required, for: .horizontal)
        editButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        checkRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkRow)
        NSLayoutConstraint.activate([
            checkRow.topAnchor.constraint(equalTo: topAnchor), checkRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            checkRow.leadingAnchor.constraint(equalTo: leadingAnchor), checkRow.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (row: UKTodoItemRow, _) in
            row.applyTitle()
            row.applyArrangement()
        }
        applyTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows `item`.
    /// - Parameters:
    ///   - item: The task.
    ///   - now: The clock the due label reads.
    ///   - surface: `.page` on the wallpaper, `.sheet` in a sheet (the secondary ink follows the sheet).
    ///   - actions: What the toggle and the trailing button do.
    func configure(item: TodoItem, now: Date = .now, surface: TileSurface = .page, actions: Actions) {
        self.actions = actions
        self.surface = surface
        let title = item.displayTitle
        let done = item.status == .completed
        let dueLabel = done ? nil : item.dueLabel(now: now)
        let changed = done != isDone
        titleText = title
        isDone = done

        checkRow.setChecked(done, checkedTint: .systemGreen, uncheckedTint: UKDesignSurface.secondary(on: surface))
        if changed, window != nil { UKMotion.stateColor { self.applyTitle() } } else { applyTitle() }

        if let dueLabel {
            due.configure(text: dueLabel.text, tone: dueLabel.tone, surface: surface)
            due.isHidden = false
        } else {
            due.isHidden = true
        }
        checkRow.hasSecondLine = dueLabel != nil

        let identity = item.identity
        toggle.isAccessibilityElement = true
        toggle.accessibilityLabel = title
        toggle.accessibilityValue = TodoItemRow.accessibilityValue(completed: done, due: dueLabel?.text)
        // A button, not a toggle button: XCUITest finds the SwiftUI row among the buttons, and a toggle trait makes it a switch.
        toggle.accessibilityTraits = [.button]
        toggle.accessibilityHint = done ? "Marks the task not done." : "Marks the task done."
        toggle.accessibilityIdentifier = "todo.item.\(identity)"
        var custom: [UIAccessibilityCustomAction] = []
        if actions.onUndo != nil {
            custom.append(UIAccessibilityCustomAction(name: "Undo") { [weak self] _ in self?.actions.onUndo?(); return true })
        }
        if actions.onDelete != nil {
            custom.append(UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in self?.actions.onDelete?(); return true })
        }
        toggle.accessibilityCustomActions = custom
        undoButton.accessibilityIdentifier = "todo.undo.\(identity)"
        editButton.accessibilityLabel = "Edit \(title)"
        editButton.accessibilityIdentifier = "todo.edit.\(identity)"
        editButton.tintColor = UKDesignSurface.secondary(on: surface)
        applyArrangement()
    }

    private func applyTitle() {
        let text = NSMutableAttributedString(string: titleText)
        let range = NSRange(location: 0, length: text.length)
        text.addAttributes([
            .font: UIFont.ukFont(.body),
            .foregroundColor: isDone ? UKDesignSurface.secondary(on: surface) : UKDesignInk.primary,
        ], range: range)
        if isDone { text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        titleLabel.attributedText = text
    }

    /// Undo drops under the title at accessibility sizes so the title keeps the row's width; the accessory is Undo, the edit button,
    /// or nothing (the plain row margin).
    private func applyArrangement() {
        let inline = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if undoButton.superview === textStack { undoButton.removeFromSuperview() }
        if actions.onUndo != nil {
            if inline {
                checkRow.setAccessory(nil, trailingInset: CheckRowMetrics.plainTrailingInset)
                textStack.addArrangedSubview(undoButton)
            } else {
                checkRow.setAccessory(undoButton, trailingInset: CheckRowMetrics.textAccessoryTrailingInset)
            }
        } else if actions.onEdit != nil {
            checkRow.setAccessory(editButton, trailingInset: CheckRowMetrics.iconAccessoryTrailingInset)
        } else {
            checkRow.setAccessory(nil, trailingInset: CheckRowMetrics.plainTrailingInset)
        }
    }

    /// The buttons a screen reader reaches after the toggle.
    override var accessibilityElements: [Any]? {
        get {
            var elements: [Any] = [toggle]
            if undoButton.superview != nil { elements.append(undoButton) }
            if editButton.superview != nil { elements.append(editButton) }
            return elements
        }
        set {}
    }
}

extension UKTodoItemRow: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu = actions.menu?() else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
#endif
