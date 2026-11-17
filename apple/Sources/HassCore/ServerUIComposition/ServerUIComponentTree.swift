import Foundation

// MARK: - Rewriting a component tree

extension ServerUICompositionDocument.Component {
    /// The component with `transform` applied to every descendant first and then to itself, so a pass that rebuilds a kind
    /// (``ServerUIVacuumLowering``) reaches it wherever a container holds it.
    ///
    /// The containers are the ones ``childComponents`` walks: grids, sections, paged rows, pinned actions, status rails, room
    /// sections, local tabs (their tabs and areas), overlays, stacks and repeats.
    func mapped(_ transform: (Self) -> Self) -> Self {
        func all(_ children: [Self]) -> [Self] { children.map { $0.mapped(transform) } }
        var value = self
        switch self {
        case .grid(var item): item.children = all(item.children); value = .grid(item)
        case .section(var item): item.children = all(item.children); value = .section(item)
        case .pagedRow(var item): item.children = all(item.children); value = .pagedRow(item)
        case .pinnedActions(var item): item.children = all(item.children); value = .pinnedActions(item)
        case .statusRail(var item): item.children = all(item.children); value = .statusRail(item)
        case .roomSection(var item): item.children = all(item.children); value = .roomSection(item)
        case .overlay(var item): item.children = all(item.children); value = .overlay(item)
        case .stack(var item): item.children = all(item.children); value = .stack(item)
        case .repeatNode(var item): item.children = all(item.children); value = .repeatNode(item)
        case .localTabs(var item):
            item.tabs = item.tabs.map { tab in var tab = tab; tab.children = all(tab.children); return tab }
            item.areas = item.areas.map { area in var area = area; area.children = all(area.children); return area }
            value = .localTabs(item)
        default: break
        }
        return transform(value)
    }
}
