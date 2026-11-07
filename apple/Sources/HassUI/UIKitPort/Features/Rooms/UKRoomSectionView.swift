#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One titled section and its cards in the web's section layouts (`RoomSectionView`; web `RoomGrid`, `DashboardViewPage.tsx:284`).
@MainActor
final class UKRoomSectionView: UIView, UKGridMeasuring {
    private let section: RoomSection
    private let cards: UKRoomCards
    private let controller: RoomController
    private let imageServer: HassServer?
    private let context: UKContext
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let header: UKPageSectionHeaderView
    private var regular: Bool?

    init(section: RoomSection, cards: UKRoomCards, controller: RoomController, imageServer: HassServer?, context: UKContext) {
        self.section = section
        self.cards = cards
        self.controller = controller
        self.imageServer = imageServer
        self.context = context
        header = UKPageSectionHeaderView(section.title)
        super.init(frame: .zero)
        addSubview(column)
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "room.section.\(section.title)"
        rebuild()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: UKRoomSectionView, _) in view.rebuild() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isRegular: Bool { traitCollection.horizontalSizeClass == .regular }

    /// The default grid (up to 4 columns), or at most `columns` filling the width. Both keep the scaled minimum tile width, so they reflow to
    /// one column at accessibility sizes. Tiles in a grid share one height, set by the tallest.
    private func grid(_ items: [RoomCard], columns: Int? = nil, spansPage: Bool = true) -> UIView {
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: columns ?? 4, equalRowHeights: true)
        grid.setItems(items.map { UKGridItem(cards.view(for: $0), span: spansPage && $0.isFullWidth ? 4 : 1) })
        return grid
    }

    private func rebuild() {
        let regular = isRegular
        guard regular != self.regular else { return }
        self.regular = regular
        var views: [UIView] = [header]
        switch section.layout {
        case .grid:
            views.append(grid(section.cards))
        case .twoColumnFill:
            views.append(grid(section.cards, columns: 2))
        case .leadRow where RoomSectionView.leadJoinsGrid(section, regularWidth: regular):
            views.append(grid(section.cards, columns: 2, spansPage: false))
        case .leadRow:
            if let lead = section.cards.first { views.append(cards.view(for: lead)) }
            let rest = Array(section.cards.dropFirst())
            if !rest.isEmpty { views.append(grid(rest, columns: RoomSectionView.followUpColumns(rest.count))) }
        case let .appLaunch(remoteId):
            if let remote = controller.remote(remoteId) { views.append(UKRoomAppLaunchGrid(remote: remote, imageServer: imageServer, context: context)) }
        }
        column.setViews(views)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
    }
}

/// Square app tiles from a remote's apps (`RoomAppLaunchGrid`), sharing the remote sheet's app tile.
@MainActor
final class UKRoomAppLaunchGrid: UKRoomsGrid {
    init(remote: MediaRemoteController, imageServer: HassServer?, context: UKContext) {
        super.init(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, fill: .none)
        var tiles: [UKAppTileView] = []
        let items = remote.config.apps.map { app -> UKGridItem in
            let tile = UKAppTileView(surface: context.surface)
            tile.identifierPrefix = "room.app."
            tile.onHeightChange = { [weak self] in self?.remeasure() }
            tiles.append(tile)
            return UKGridItem(tile)
        }
        setItems(items)
        for (app, tile) in zip(remote.config.apps, tiles) { bindTile(tile, app: app, remote: remote, imageServer: imageServer) }
    }

    private let bag = UKObservationBag()

    private func bindTile(_ tile: UKAppTileView, app: MediaRemoteApp, remote: MediaRemoteController, imageServer: HassServer?) {
        bag.observe { [weak tile] in
            tile?.configure(app: app, display: remote.display(app), imageURL: imageServer.flatMap { server in app.imagePath.map(server.url) }) {
                remote.tap(app)
            }
        }
    }
}

/// The Kitchen's Groceries section: the grocery list and Food (`KitchenGroceriesSection`).
@MainActor
final class UKKitchenGroceriesSection: UIView, UKGridMeasuring {
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)

    init(controller: RoomController, environment: UKTileEnvironment, bag: UKObservationBag, navigate: @escaping (HomeRoute) -> Void) {
        super.init(frame: .zero)
        typealias G = RoomsConfig.Groceries
        func model(_ title: String, _ subtitle: @escaping @MainActor () -> String?, _ icon: String, _ identifier: String) -> UKGlassTileModel {
            // Pages, not devices: dark tiles with no colour family (direction G, Colour families).
            UKGlassTileModel(title: title, subtitle: subtitle(), symbol: SymbolMap.symbol(for: icon), family: .neutral, isActive: false, kind: .navigate,
                             identifier: identifier)
        }
        let listSubtitle: @MainActor () -> String? = { G.subtitle(count: controller.displayedState(G.listEntityId)) }
        let foodSubtitle: @MainActor () -> String? = { QuickLinks.allFoodSubtitle { controller.displayedState($0) } }
        let list = UKGlassTileView(model: model(G.listTitle, listSubtitle, "mdi:clipboard-list", "room.groceries.list"), environment: environment)
        list.accessibilityHint = "Opens the \(G.listTitle) page"
        // The grocery list is the Chores lane's page.
        UKRoomsBind.tile(list, bag: bag, environment: environment, action: { navigate(.groceryList) },
                         model: { model(G.listTitle, listSubtitle, "mdi:clipboard-list", "room.groceries.list") })
        let food = UKGlassTileView(model: model("Food", foodSubtitle, "mdi:food-fork-drink", "room.groceries.food"), environment: environment)
        food.accessibilityHint = "Opens the Food page"
        UKRoomsBind.tile(food, bag: bag, environment: environment, action: { navigate(.food) },
                         model: { model("Food", foodSubtitle, "mdi:food-fork-drink", "room.groceries.food") })
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid.setItems([UKGridItem(list), UKGridItem(food)])
        column.setViews([UKPageSectionHeaderView("Groceries"), grid])
        addSubview(column)
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
    }
}
#endif
