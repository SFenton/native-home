#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Actions

/// What a todo row does, shared by the Chores pages and the Summary sheet's chore tabs (``TodoListSection``): one source for the
/// swipes, the context menu and the VoiceOver actions (``TodoRowActions``), the check-off with its announcement, and the delete
/// confirmation.
@MainActor
enum UKTodoListActions {
    /// The actions a row offers.
    static func actions(for item: TodoItem, canEdit: Bool, canDelete: Bool) -> TodoRowActions {
        TodoRowActions(item: item, canEdit: canEdit, canDelete: canDelete)
    }

    /// Checks `item` off (or puts it back); a tick that keeps the row listed in its done look is announced (HIG Undo and redo).
    static func toggle(_ item: TodoItem, in list: ChoresConfig.TodoList, controller: TodoListController) {
        let completing = item.status != .completed
        Task { await controller.toggle(item, completionScript: list.completionScript) }
        if completing, list.hideCompleted { Announcer.announce(TodoItemRow.completionAnnouncement(item.displayTitle)) }
    }

    /// Reopens a task checked off a moment ago (`todo.update_item`, also on the Admin To-Do).
    static func undo(_ item: TodoItem, controller: TodoListController) {
        Task { await controller.undo(item) }
    }

    /// The fill behind a swipe button (``TodoListSection/swipeTint(_:)``).
    static func swipeTint(_ action: TodoRowActions.Action) -> UIColor { UIColor(TodoListSection.swipeTintToken(action)) }

    /// The swipe buttons for an edge: Complete leads in green; Delete (red, outermost) and Edit (blue) trail. A full swipe performs
    /// the first.
    static func swipeConfiguration(_ actions: TodoRowActions, item: TodoItem, leading: Bool,
                                   perform: @escaping (TodoRowActions.Action) -> Void) -> UISwipeActionsConfiguration? {
        let list = leading ? actions.leading : actions.trailing
        return UKSwipeAction.configuration(list.map { action in
            UKSwipeAction(action.title, systemImage: action.symbol, tint: swipeTint(action), identifier: "todo.swipe.\(action.rawValue).\(item.identity)", role: action == .delete ? .destructive : .normal) { done in
                perform(action)
                done(true)
            }
        })
    }

    /// The long-press menu: every action, leading then trailing.
    static func menu(_ actions: TodoRowActions, perform: @escaping (TodoRowActions.Action) -> Void) -> UIMenu {
        UIMenu(children: actions.all.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.symbol), attributes: action == .delete ? .destructive : []) { _ in perform(action) }
        })
    }

    /// Asks before deleting a task (``AlertCopy``): one dialog on the page, since a swipe or menu Delete is gone once the swipe
    /// closes.
    static func confirmDelete(_ item: TodoItem, controller: TodoListController, from presenter: UIViewController, source: UKPopoverSource = .none) {
        UKAlerts.confirmationDialog(TodoListSection.deleteSpec(for: item), from: presenter, source: source, confirmIdentifier: "todo.delete.confirm") {
            Task { await controller.remove(item) }
        }
    }
}

// MARK: - Cells

/// One task as a list cell: the row on its share of the list's module card (``ModuleRowBackground``) with the hairline above it.
/// The row binds nothing itself; the page reconfigures the cell when the item, its due label or its position changes.
@MainActor
final class UKTodoRowCell: UICollectionViewListCell {
    static let reuseIdentifier = "UKTodoRowCell"
    private let card = UKModuleRowBackgroundView()
    let row = UKTodoItemRow()
    private var hairline: UKHairline?

    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyUpdatesBackgroundConfiguration = false
        automaticallyUpdatesContentConfiguration = false
        backgroundConfiguration = .clear()
        if !UKPerfSwitches.isOff(.ukRowCard) { backgroundView = card }
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor), row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        ukFitted(layoutAttributes)
    }

    func configure(item: TodoItem, now: Date, density: ModuleDensity, isFirst: Bool, isLast: Bool, surface: TileSurface, actions: UKTodoItemRow.Actions) {
        card.configure(density: density, surface: surface, isFirst: isFirst, isLast: isLast, selected: false)
        row.configure(item: item, now: now, surface: surface, actions: actions)
        hairline?.removeFromSuperview()
        hairline = nil
        row.isHidden = UKPerfSwitches.isOff(.ukRowContent)
        if !isFirst, !UKPerfSwitches.isOff(.ukRowHairline) {
            let line = UKHairline(inset: .fixed(ModuleRowMetrics.textInset), surface: surface)
            line.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(line)
            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: contentView.topAnchor),
                line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
            hairline = line
        }
    }
}

/// A list row that is not part of the module (``TodoPlainRow``): a header, an error, a spinner, the quick links. It draws no card and
/// no separator and keeps no system insets, so it lines up with the module's edges. The hosted view reports its height for a width
/// (``UKGridMeasuring``) or by Auto Layout.
@MainActor
final class UKTodoPlainCell: UICollectionViewListCell {
    static let reuseIdentifier = "UKTodoPlainCell"
    private var hosted: UIView?
    private var insets = UIEdgeInsets.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        automaticallyUpdatesBackgroundConfiguration = false
        automaticallyUpdatesContentConfiguration = false
        backgroundConfiguration = .clear()
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Hosts `view` with `top` and `bottom` space (the row's `listRowInsets`).
    func host(_ view: UIView, top: CGFloat, bottom: CGFloat) {
        if hosted !== view {
            hosted?.removeFromSuperview()
            contentView.addSubview(view)
            hosted = view
        }
        insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hosted?.removeFromSuperview()
        hosted = nil
    }

    private func height(forWidth width: CGFloat) -> CGFloat {
        guard let hosted else { return insets.top + insets.bottom }
        let inner: CGFloat
        if let measuring = hosted as? UKGridMeasuring {
            inner = measuring.gridHeight(forWidth: width)
        } else {
            inner = ceil(hosted.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        }
        return inner + insets.top + insets.bottom
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        CGSize(width: targetSize.width, height: height(forWidth: targetSize.width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hosted?.frame = CGRect(x: 0, y: insets.top, width: contentView.bounds.width,
                               height: max(0, contentView.bounds.height - insets.top - insets.bottom))
    }
}

/// A loading list's arc, centred in a 44 pt row (`ArcSpinner(.compact, label: "Loading …")`).
@MainActor
final class UKTodoSpinnerRow: UIView {
    private let spinner: UKArcSpinnerView

    init(label: String) {
        spinner = UKArcSpinnerView(.compact, label: label)
        super.init(frame: .zero)
        spinner.color = UKDesignInk.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor), spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
