#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The inventory page's Sort and Filter sheets (``InventorySortSheet``, ``InventoryFilterSheet``), on the shared filter sheet.
@MainActor
enum UKInventorySheets {
    static func sort(model: InventoryListModel, onDismissed: @escaping () -> Void) -> UKInventoryDraftSheet {
        UKInventoryDraftSheet.sort(model: model, onDismissed: onDismissed)
    }

    static func filter(model: InventoryListModel, onDismissed: @escaping () -> Void) -> UKInventoryDraftSheet {
        UKInventoryDraftSheet.filter(model: model, onDismissed: onDismissed)
    }
}

/// A sort or filter sheet that edits a draft and applies it on demand. It keeps itself alive while it is up.
@MainActor
final class UKInventoryDraftSheet {
    private var sheet: UKFilterSheet!
    private var retained: UKInventoryDraftSheet?
    private let refresh: () -> Void

    private init(refresh: @escaping () -> Void) { self.refresh = refresh }

    func present(from presenter: UIViewController) {
        retained = self
        sheet.present(from: presenter)
    }

    // MARK: Sort

    /// Sort Inventory (web `InventorySortSheet`): Apply commits the draft and Reset puts it back to Title, Ascending.
    static func sort(model: InventoryListModel, onDismissed: @escaping () -> Void) -> UKInventoryDraftSheet {
        var mode = model.sortMode
        var direction = model.sortDirection
        weak var holder: UKInventoryDraftSheet?
        func sections() -> [UKFormSection] {
            [
                UKFormSection(id: "by", header: "Sort By", rows: InventorySortMode.allCases.map { option in
                    UKFormRow(id: option.rawValue, identifier: "inventory.sort.\(option.rawValue)",
                              .option(title: option.title, subtitle: option.subtitle, swatch: [], isSelected: mode == option) { mode = option; holder?.refresh() })
                }),
                // Option rows rather than a segmented control and footnote: both were reported clipped at large text sizes.
                UKFormSection(id: "direction", header: "Sort Direction", rows: InventorySortDirection.allCases.map { option in
                    UKFormRow(id: "direction-\(option.rawValue)", identifier: "inventory.sort.direction.\(option.rawValue)",
                              .option(title: option.title, subtitle: option.hint, swatch: [], isSelected: direction == option) { direction = option; holder?.refresh() })
                }),
            ]
        }
        var created: UKInventoryDraftSheet!
        created = UKInventoryDraftSheet {
            holder?.sheet.update(subtitle: nil, canApply: mode != model.sortMode || direction != model.sortDirection,
                                 canReset: mode != .title || direction != .ascending, sections: sections())
        }
        holder = created
        created.sheet = UKFilterSheet(
            title: "Sort Inventory", canApply: false, canReset: mode != .title || direction != .ascending,
            onApply: {
                model.sortMode = mode
                model.sortDirection = direction
            },
            onReset: {
                mode = .title
                direction = .ascending
                holder?.refresh()
            },
            sections: sections(),
            onDismissed: { [weak created] in
                created?.retained = nil
                onDismissed()
            })
        return created
    }

    // MARK: Filter

    /// Filter Inventory (web `InventoryFilterSheet`; mockup n6-inventory-filter): a "Show" checkmark list of the filters, each with what it
    /// keeps, and how many cards the chosen one shows under the title.
    static func filter(model: InventoryListModel, onDismissed: @escaping () -> Void) -> UKInventoryDraftSheet {
        var mode = model.filterMode
        weak var holder: UKInventoryDraftSheet?
        func sections() -> [UKFormSection] {
            // "Show" rather than the web's "Filter Items", which repeated the sheet title.
            [UKFormSection(id: "show", header: "Show", rows: InventoryFilterMode.allCases.map { option in
                UKFormRow(id: option.rawValue, identifier: "inventory.filter.\(option.rawValue)",
                          .option(title: option.title, subtitle: option.subtitle, swatch: [], isSelected: mode == option) { mode = option; holder?.refresh() })
            })]
        }
        var created: UKInventoryDraftSheet!
        created = UKInventoryDraftSheet {
            holder?.sheet.update(subtitle: model.filterSummary(mode), canApply: mode != model.filterMode, canReset: mode != .all, sections: sections())
        }
        holder = created
        created.sheet = UKFilterSheet(
            title: "Filter Inventory", subtitle: model.filterSummary(mode), canApply: false, canReset: mode != .all,
            onApply: { model.filterMode = mode },
            onReset: {
                mode = .all
                holder?.refresh()
            },
            sections: sections(),
            onDismissed: { [weak created] in
                created?.retained = nil
                onDismissed()
            })
        return created
    }
}
#endif
