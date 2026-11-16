#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Tab areas

/// The areas of a tab container, stacked top to bottom in document order (`sh.tab-blocks@1`).
///
/// Each area keeps one panel for its whole life, keyed by the area's id and never by a tab. A tab change adds the panels of the
/// areas that begin to show and removes the ones that stop; a panel that shows on both tabs is not touched, so a shared map keeps its
/// picture and its zoom (AGENTS.md, "No reload"). An area has no chrome of its own.
@MainActor
final class UKServerUIAreaStack: UIView, UKGridMeasuring {
    private var panels: [String: UKColumnView] = [:]
    private var shown: [(id: String, panel: UKColumnView)] = []

    /// Whether any area's children are not the ones its panel holds, so the panels must be emptied before they are filled again.
    func needsReparent(areas: [ServerUITabArea], children: [[UIView]]) -> Bool {
        zip(areas, children).contains { panels[$0.0.id]?.views != $0.1 } || panels.keys.contains { id in !areas.contains { $0.id == id } }
    }

    /// Empties every panel, before the same views are given to another owner.
    func clear() { panels.values.forEach { $0.setViews([]) } }

    /// The ids of the areas on show, in order.
    var shownIDs: [String] { shown.map(\.id) }

    /// Shows the areas in `ids`.
    /// - Parameters:
    ///   - areas: Every area of the container.
    ///   - children: The views of each area's children, parallel to `areas`.
    ///   - ids: The areas to show now, a subset of `areas`.
    ///   - animated: Whether an area that begins to show fades in. Reduce Motion never animates.
    func apply(areas: [ServerUITabArea], children: [[UIView]], showing ids: [String], animated: Bool) {
        for (area, views) in zip(areas, children) {
            let panel = panels[area.id] ?? UKColumnView(spacing: HassTokens.Spacing.m)
            panel.spacing = HassTokens.Spacing.m
            panel.shouldGroupAccessibilityChildren = true
            if panel.views != views { panel.setViews(views) }
            panel.isHidden = views.isEmpty
            panels[area.id] = panel
        }
        for id in panels.keys where !areas.contains(where: { $0.id == id }) {
            panels[id]?.removeFromSuperview()
            panels[id] = nil
        }
        let next = areas.filter { ids.contains($0.id) }.compactMap { area in panels[area.id].map { (area.id, $0) } }
        let before = Set(shown.map(\.id))
        for old in shown where !next.contains(where: { $0.0 == old.id }) { old.panel.removeFromSuperview() }
        for (id, panel) in next where panel.superview !== self {
            addSubview(panel)
            if animated, !before.contains(id), !UKMotion.reduceMotion {
                panel.alpha = 0
                UIView.animate(withDuration: UKSmoothContentSwapView<String>.Timing().fadeIn, delay: 0, options: .curveEaseOut) { panel.alpha = 1 }
            } else { panel.alpha = 1 }
        }
        shown = next.map { (id: $0.0, panel: $0.1) }
        setNeedsLayout()
    }

    private func heights(width: CGFloat) -> [CGFloat] {
        shown.map { $0.panel.isHidden ? 0 : $0.panel.gridHeight(forWidth: width) }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let visible = zip(shown, heights(width: width)).filter { !$0.0.panel.isHidden }.map(\.1)
        return visible.reduce(0, +) + HassTokens.Spacing.m * CGFloat(max(visible.count - 1, 0))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for (entry, height) in zip(shown, heights(width: bounds.width)) where !entry.panel.isHidden {
            entry.panel.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height + HassTokens.Spacing.m
        }
    }
}

// MARK: - What a container shows now

/// What the container last showed for each tab and area, so a rule that cannot be answered keeps its answer (`whenUnknown: keep`).
struct UKServerUILayoutMemory {
    var tabs: [String: Bool] = [:]
    var areas: [String: Bool] = [:]
    var discs: [String: Bool] = [:]
}

/// The tabs, the tab on show and the areas on show for one pass of a tab container.
@MainActor
struct UKServerUITabLayout {
    typealias D = ServerUICompositionDocument

    /// The container with only the tabs whose rule lets them show.
    let container: D.LocalTabs
    /// The tab on show: the one asked for while it shows, else the fallback tab, else the first that shows.
    let selection: String
    /// The ids of the areas that draw on the tab on show, in document order.
    let shownAreas: [String]

    /// Resolves `container` against what its rules read.
    /// - Parameters:
    ///   - container: The container, with the scope's tab filter already applied.
    ///   - requested: The tab the person or a rule chose.
    ///   - reader: What the rules read.
    ///   - memory: What each tab and area last showed.
    static func resolve(_ container: D.LocalTabs, requested: String, reader: some ServerUIReading,
                        memory: inout UKServerUILayoutMemory) -> Self {
        var visible = container
        var nextTabs: [String: Bool] = [:]
        visible.tabs = container.tabs.filter { tab in
            let shows = tab.visibility?.isShown(reader, previous: memory.tabs[tab.id]) ?? true
            nextTabs[tab.id] = shows
            return shows
        }
        // A container never draws nothing: with every tab hidden it keeps the first.
        if visible.tabs.isEmpty, let first = container.tabs.first { visible.tabs = [first] }
        memory.tabs = nextTabs
        let tab = ServerUILayoutRules.tabOnShow(container, requested: requested, in: reader, previous: memory.tabs)
        let selection = visible.tabs.contains { $0.id == tab } ? tab : visible.tabs[0].id
        var nextAreas: [String: Bool] = [:]
        let shown = container.areas.filter { area in
            guard area.scope.shows(on: selection) else { return false }
            let shows = area.visibility?.isShown(reader, previous: memory.areas[area.id]) ?? true
            nextAreas[area.id] = shows
            return shows
        }
        memory.areas.merge(nextAreas) { _, new in new }
        return Self(container: visible, selection: selection, shownAreas: shown.map(\.id))
    }

    /// The items of `items`, parallel to `tabs`, that belong to a tab still on show.
    func keeping<T>(_ items: [T], parallelTo tabs: [D.LocalTabs.TabContent]) -> [T] {
        let ids = Set(container.tabs.map(\.id))
        return zip(tabs, items).filter { ids.contains($0.0.id) }.map(\.1)
    }
}
#endif
