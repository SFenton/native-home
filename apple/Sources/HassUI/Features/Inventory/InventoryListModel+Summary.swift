import HassCore

extension InventoryListModel {
    /// "4 of 41 Items": the cards `filter` would show, under the Filter sheet's title (mockup n6-inventory-filter).
    func filterSummary(_ filter: InventoryFilterMode) -> String {
        let cards = displayItems
        let shown = InventoryCatalog.visible(cards, sort: sortMode, direction: sortDirection, filter: filter, calendar: calendar).count
        return "\(shown) of \(cards.count) \(cards.count == 1 ? "Item" : "Items")"
    }
}
