#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Value-only canonical room section

/// The room feature and ServerUI share exactly the same header, tracks and lead-row arrangement.
@MainActor
final class UKRoomSectionContent: UIView, UKGridMeasuring {
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let header = UKPageSectionHeaderView("")
    private var title = ""
    private var arrangement: ServerUICompositionDocument.RoomSectionArrangement = .grid
    private var leadJoinsAtRegularWidth = false
    private var items: [UKGridItem] = []
    private var grids: [UKRoomsGrid] = []
    private var needsRebuild = false

    var itemViews: [UIView] { items.map(\.view) }
    var itemSpans: [Int] { items.map(\.span) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(column)
        accessibilityContainerType = .semanticGroup
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: UKRoomSectionContent, _) in view.rebuild() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, arrangement: ServerUICompositionDocument.RoomSectionArrangement,
                   leadJoinsAtRegularWidth: Bool, items: [UKGridItem]) {
        guard needsRebuild || title != self.title || arrangement != self.arrangement || leadJoinsAtRegularWidth != self.leadJoinsAtRegularWidth
                || items.map(\.view) != self.items.map(\.view) || items.map(\.span) != self.items.map(\.span) else { return }
        self.title = title
        self.arrangement = arrangement
        self.leadJoinsAtRegularWidth = leadJoinsAtRegularWidth
        self.items = items
        rebuild()
    }

    private func rebuild() {
        needsRebuild = false
        // Release old grid ownership before adopting retained tile instances.
        grids.forEach { $0.setItems([]) }
        grids = []
        column.setViews([])
        header.configure(title: title, detail: nil)
        func grid(_ items: [UKGridItem], columns: Int = 4) -> UKRoomsGrid {
            let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: columns, equalRowHeights: true)
            grid.setItems(items)
            grids.append(grid)
            return grid
        }
        var views: [UIView] = [header]
        switch arrangement {
        case .grid: views.append(grid(items))
        case .twoColumnFill: views.append(grid(items, columns: 2))
        case .leadRow where leadJoinsAtRegularWidth && traitCollection.horizontalSizeClass == .regular:
            views.append(grid(items.map { UKGridItem($0.view) }, columns: 2))
        case .leadRow:
            if let lead = items.first { views.append(lead.view) }
            let rest = Array(items.dropFirst())
            if !rest.isEmpty { views.append(grid(rest, columns: rest.count > 2 ? 2 : 4)) }
        }
        column.setViews(views)
        ukRemeasureContainers(includingSelf: true)
    }

    /// Reconciliation releases every old owner before another container adopts a retained view.
    func releaseItems() {
        grids.forEach { $0.setItems([]) }
        column.setViews([])
        items = []
        needsRebuild = true
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); column.frame = bounds }
}
#endif
