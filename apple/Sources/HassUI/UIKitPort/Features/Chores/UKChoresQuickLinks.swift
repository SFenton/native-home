#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Quick links to the Chores sub-pages (``ChoreQuickLinks``, web `ChoresIntro`, 2 to 3 columns). The grid grows to four on iPad and stops
/// there: four links fill four tracks and a wide Groceries closes the second row.
///
/// Each link is a navigation tile with the chevron in the list's own colour (rollout lane M, audit item 26; owner, 2026-10-27, pick A): the
/// open count moves into the state line, "3 open · 2 overdue" (`ChoresConfig.openSubtitle`), and the numeral is gone. Groceries still closes
/// the grid across two tracks. The view binds each tile to the entities its state line reads, so a count changes in place.
@MainActor
final class UKChoreQuickLinksView: UIView, UKGridMeasuring {
    private let column = UKColumnView(spacing: HassTokens.Spacing.s)
    private let heading = UKPageSectionHeaderView("Quick Links")
    private let grid: UKDynamicGridView
    private var tiles: [UKGlassTileView] = []
    private let bag = UKObservationBag()
    private let context: UKContext
    private let model: ChoresModel
    private let open: (ChoresConfig.Page) -> Void

    /// The web's links with Groceries moved last, where it spans the final row.
    static var links: [ChoresConfig.QuickLink] { ChoreQuickLinks.links }

    init(context: UKContext, model: ChoresModel, open: @escaping (ChoresConfig.Page) -> Void) {
        self.context = context
        self.model = model
        self.open = open
        grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
        super.init(frame: .zero)
        grid.followsFold = true
        var items: [UKGridItem] = []
        for link in Self.links {
            let tile = UKGlassTileView(model: UKGlassTileModel(title: link.title(viewer: model.viewer), symbol: ChoreQuickLinks.symbol(for: link),
                                                               family: ChoreQuickLinks.family(for: link), isActive: true, kind: .navigate),
                                       environment: UKTileEnvironment(context: context))
            tile.action = { [weak self] in self?.open(link.page) }
            tiles.append(tile)
            // Five links: Groceries closes the grid across two tracks, in two, three or four columns alike.
            items.append(UKGridItem(tile, span: link.countsGroceries ? 2 : 1))
        }
        grid.setItems(items)
        column.setViews([heading, grid])
        addSubview(column)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            // Scales with the tiles' text; the grid still stops at four columns on iPad.
            self.grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 150, compatibleWith: self.traitCollection)
        }
        bag.observe { [weak self] in self?.bind() }
        bag.observe { [weak self] in
            guard let self else { return }
            self.grid.hinge = self.context.shell?.windowHinge
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func bind() {
        let store = context.store
        let environment = UKTileEnvironment(context: context)
        let viewer = model.viewer
        for (link, tile) in zip(Self.links, tiles) {
            let title = link.title(viewer: viewer)
            let subtitle = link.openSubtitle { store.entity($0).state }
            var tileModel = UKGlassTileModel(title: title, subtitle: subtitle, symbol: ChoreQuickLinks.symbol(for: link),
                                             family: ChoreQuickLinks.family(for: link), isActive: true, kind: .navigate,
                                             identifier: ChoreQuickLinks.identifier(for: link))
            tileModel.bodyHint = "Opens the list."
            tile.configure(tileModel, environment: environment)
        }
        grid.invalidateMeasurements()
        // A subtitle that now wraps changes the header's height: the list cell hosting it measures again.
        if bounds.width > 0 {
            let height = gridHeight(forWidth: bounds.width)
            if abs(height - lastHeight) > 0.5 {
                lastHeight = height
                onHeightChange?()
            }
        }
    }

    /// Called when the view's height at its current width changed (a tile's subtitle wrapped or unwrapped).
    var onHeightChange: (() -> Void)?
    private var lastHeight: CGFloat = 0

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
    }
}
#endif
