#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// What an ``UKInventoryRowView`` asks for, presented over a page: the item editor as a sheet (while the window can't split), the quantity
/// prompt for Add to Groceries and a partial delete, and the single-unit delete confirmation (``SwiftUICore/View/inventoryRowActions(_:model:)``).
/// One implementation for the inventory pages and the Summary sheet's Expired Food tab.
///
/// ```swift
/// let actions = UKInventoryRowActionsHost(presentation: presentation, model: model, context: context)
/// actions.presenter = self          // the controller the sheets and dialogs present from
/// actions.start()                   // in viewDidLoad
/// // in viewDidAppear: actions.sync()
/// // row callbacks: onEdit: { presentation.open(item, in: model) }, onShop: { presentation.ask(.shopping(item)) },
/// //                swipe Delete: presentation.requestDelete(item, in: model)
/// ```
@MainActor
final class UKInventoryRowActionsHost {
    weak var presenter: UIViewController?
    private let presentation: InventoryPresentation
    private let model: InventoryListModel
    private let context: UKContext
    private let bag = UKObservationBag()
    private var editorShown = false
    private var promptShown: InventoryPrompt?
    private var confirmShown = false

    /// Something of the host's is up.
    var isPresenting: Bool { editorShown || promptShown != nil || confirmShown }

    init(presentation: InventoryPresentation, model: InventoryListModel, context: UKContext) {
        self.presentation = presentation
        self.model = model
        self.context = context
    }

    /// Follows the presentation for the host's lifetime.
    func start() {
        bag.observe { [weak self] in self?.sync() }
    }

    /// Presents what the presentation asks for, when the presenter is on screen and nothing else is up.
    func sync() {
        let editor = presentation.sheetEditor
        let prompt = presentation.prompt
        let confirm = presentation.confirmDelete
        _ = presentation.promptText
        guard let presenter, presenter.isViewLoaded, presenter.view.window != nil else { return }
        if editorShown {
            // The model closed the editor (a save finished, the last stock was deleted): take it down.
            if editor == nil, presenter.presentedViewController?.isBeingDismissed == false {
                editorShown = false
                presenter.presentedViewController?.dismiss(animated: true)
            }
            return
        }
        guard presenter.presentedViewController == nil else { return }
        if let editor {
            present(editor, from: presenter)
        } else if let prompt, promptShown == nil {
            present(prompt, from: presenter)
        } else if let confirm, !confirmShown {
            present(confirm, from: presenter)
        }
    }

    private func present(_ editor: InventoryEditorModel, from presenter: UIViewController) {
        editorShown = true
        UKInventoryEditorViewController.presentSheet(model: editor, from: presenter, context: context, onClose: { [weak self] in
            self?.presentation.editing = nil
        }, onDismissed: { [weak self] in
            guard let self else { return }
            self.editorShown = false
            if !self.presentation.canSplit, self.presentation.editing != nil { self.presentation.editing = nil }
        })
    }

    /// The quantity prompt (the web's `window.prompt`, as an alert with a field).
    private func present(_ prompt: InventoryPrompt, from presenter: UIViewController) {
        promptShown = prompt
        let alert = UIAlertController(title: prompt.title, message: prompt.message, preferredStyle: .alert)
        alert.addTextField { [presentation] field in
            field.text = presentation.promptText
            field.keyboardType = .decimalPad
            field.accessibilityIdentifier = "inventory.prompt.field"
            field.accessibilityLabel = "Quantity"
            field.placeholder = "Quantity"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.promptShown = nil
            self?.presentation.prompt = nil
            self?.presentation.finishSwipe(removed: false)
        })
        alert.addAction(UIAlertAction(title: prompt.confirmTitle, style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            self.presentation.promptText = alert?.textFields?.first?.text ?? ""
            self.promptShown = nil
            self.presentation.prompt = nil
            Task { await self.presentation.submit(prompt, in: self.model) }
        })
        presenter.present(alert, animated: true)
    }

    /// A swiped Delete on a row: asks to confirm (or for a quantity) and settles the swipe with `done`. The row is held
    /// open until the answer (confirm completes it as the card leaves, cancel closes it).
    static func swipeDelete(_ item: InventoryDisplayItem, in model: InventoryListModel, presentation: InventoryPresentation,
                            done: @escaping (Bool) -> Void, request: ((InventoryDisplayItem) -> Void)? = nil) {
        presentation.finishSwipe(removed: false)
        presentation.swipeCompletion = done
        if let request { request(item) } else { presentation.requestDelete(item, in: model) }
    }

    /// "Delete Honey?" on the page, not the row: a swipe Delete is gone once the swipe closes, so a row dialog never presents.
    private func present(_ item: InventoryDisplayItem, from presenter: UIViewController) {
        confirmShown = true
        UKInventoryAlerts.confirmDelete(InventoryPresentation.deleteSpec(item, space: model.space), from: presenter, confirmID: "inventory.delete.confirm",
                                        onConfirm: { [weak self] in
                                            guard let self else { return }
                                            self.confirmShown = false
                                            self.presentation.confirmDelete = nil
                                            Task { await self.model.delete(item) { self.presentation.finishSwipe(removed: $0) } }
                                        },
                                        onCancel: { [weak self] in
                                            self?.confirmShown = false
                                            self?.presentation.confirmDelete = nil
                                            self?.presentation.finishSwipe(removed: false)
                                        })
    }
}

/// The inventory row, for pages that draw it outside the inventory list (the Summary sheet's Expired Food tab).
typealias UKInventoryRow = UKInventoryRowView
#endif
