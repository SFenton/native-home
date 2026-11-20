import Foundation

// MARK: - The chrome-hide rule

/// The rule a page's `hides` and the document's `tabsVisibility` apply to the shell chrome (`sh.page-chrome-hide@1`, `sh.tabs-visibility@1`).
///
/// Hiding is the only direction: a page cannot show what the app hides, and an item the app already shows on a first page only stays gone on a
/// pushed one. Back and a sheet's Close are not chrome items, so nothing here can name them. A document without either field draws as it always did.
public enum ServerUIChromeHide {

    /// The groups a page inherits once its own hides are applied.
    ///
    /// A group left with no item is dropped, so an emptied group leaves no bar button behind. Without `hides`, or with an empty `items`, the
    /// groups come back unchanged.
    /// - Parameters:
    ///   - groups: The app's chrome groups, or a modal's own.
    ///   - hides: What the page hides, or `nil`.
    /// - Returns: The groups the page shows.
    public static func groups(_ groups: [ServerUICompositionDocument.ChromeGroup], applying hides: ServerUICompositionDocument.PageHides?) -> [ServerUICompositionDocument.ChromeGroup] {
        guard let hides, !hides.items.isEmpty else { return groups }
        let dropped = Set(hides.items)
        return groups.compactMap { group in
            let kept = group.items.filter { item in
                if case .shellMenu = item { return true }
                return !dropped.contains(item.id)
            }
            guard kept.count != group.items.count else { return group }
            return kept.isEmpty ? nil : ServerUICompositionDocument.ChromeGroup(id: group.id, placement: group.placement, horizontal: group.horizontal,
                                                       vertical: group.vertical, items: kept)
        }
    }

    /// Whether the tab navigator hides while a page is on top of the selected stack.
    /// - Parameters:
    ///   - hides: The page's own hides, or `nil`.
    ///   - visibility: The document's `navigation.tabsVisibility`, or `nil` for `always`.
    ///   - depth: How many pages sit below the page in its stack; 0 is a root page.
    /// - Returns: `true` when the page hides the tabs itself, or the document shows them on a root page only and the page is pushed.
    public static func hidesTabs(hides: ServerUICompositionDocument.PageHides?, visibility: ServerUICompositionDocument.TabsVisibility?, depth: Int) -> Bool {
        if hides?.tabs == true { return true }
        return visibility == .rootOnly && depth > 0
    }
}
