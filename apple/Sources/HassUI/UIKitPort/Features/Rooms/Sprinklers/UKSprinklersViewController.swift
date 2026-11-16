#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Sprinklers page (`SprinklersScreen`; web `SprinklersPage.tsx` + `SprinklerController.tsx`; spec
/// `.agents/pages/sprinklers/spec.md`).
///
/// One card per B-hyve controller (row and status pills); the row opens the controller's sheet. Cards sit side by side when the page
/// is wide enough (web `ResponsiveSectionGrid`).
@MainActor
final class UKSprinklersViewController: UKPageViewController {
    private var controllers: [SprinklerController]
    private let initialDetail: SprinklerDetail?
    /// A controller whose sheet opens as soon as the page is on screen (gallery and journeys).
    private var pendingOpen: SprinklerController?

    private let column = UKFoldColumns(spacing: HassTokens.Spacing.m)
    private var scroll: UKPageScrollView!
    private let header = UKPageSectionHeaderView("Controllers")
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl))
    private var cards: [UKSprinklerControllerCard] = []

    /// Creates the page.
    /// - Parameters:
    ///   - context: The page's context: its store and its caller (service calls go there; a recorder in the gallery).
    ///   - openController: A controller id whose sheet opens at once (gallery and journeys).
    ///   - detail: A detail page to show in that sheet at once.
    init(context: UKContext, openController: String? = nil, detail: SprinklerDetail? = nil) {
        let caller = context.roomsCaller
        let controllers = SprinklersConfig.controllers.map { SprinklerController(config: $0, store: context.store, caller: caller) }
        self.controllers = controllers
        pendingOpen = controllers.first { $0.id == openController }
        initialDetail = detail
        super.init(context: context, title: "Sprinklers")
    }

    // MARK: View

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildSections()
        column.sideInset = HassTokens.Spacing.l
        column.splitIdentifier = "sprinklers.columns.split"
        column.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        column.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
        column.onSplitChange = { [weak self] split in self?.place(cardsSplit: split) }
        scroll = UKPageScrollView(content: column, padding: UIEdgeInsets(
            top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        scroll.accessibilityIdentifier = "sprinklers.scroll"
        install(scrollView: scroll)
        grid.followsFold = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKSprinklersViewController, _) in page.rescale() }
        rescale()
        bag.observe { [weak self] in
            guard let self else { return }
            column.hinge = context.shell?.windowHinge
        }
    }

    /// Builds a card per controller from the house document and hands them to the columns. Called from `viewDidLoad` and again by
    /// ``houseLayoutDidChange()``.
    private func buildSections() {
        cards = controllers.map { controller in
            UKSprinklerControllerCard(controller: controller, context: context) { [weak self] in self?.open(controller) }
        }
        if column.isSplit {
            grid.setItems([])
            grid.isHidden = true
        } else {
            grid.setItems(cards.map { UKGridItem($0) })
        }
        for card in cards {
            card.onHeightChange = { [weak self] in
                guard let self, self.isViewLoaded else { return }
                // The grid measured the card at its old height: set the items again so it measures once more. Split, the columns
                // measure it themselves.
                if !self.column.isSplit { self.grid.setItems(self.cards.map { UKGridItem($0) }) }
                self.column.ukSetNeedsLayoutUpward()
                self.scroll?.contentChanged(animated: true)
            }
        }
        // Partly folded: the header and the first controller lead, the second trails level with it, then they alternate by index
        // (`.agents/design/section-sides.md`). Flat, the cards sit in the grid and the page is what it was.
        var sections: [UKFoldColumns.Section] = [.init(header, side: .leading), .init(grid, side: .leading, visibility: .flatOnly)]
        for (index, card) in cards.enumerated() {
            let side = FoldColumns.side(forConfiguredIndex: index)
            sections.append(.init(card, side: side, levelWith: index > 0 ? 2 : nil, visibility: .splitOnly))
        }
        column.setSections(sections)
    }

    override func houseLayoutDidChange() {
        let caller = context.roomsCaller
        controllers = SprinklersConfig.controllers.map { SprinklerController(config: $0, store: context.store, caller: caller) }
        cards.forEach { $0.removeFromSuperview() }
        buildSections()
        scroll.contentChanged(animated: false)
    }

    /// Moves the cards between the flat grid and the columns, starting from the frames they had so the reflow slides them.
    private func place(cardsSplit split: Bool) {
        let old = cards.map { $0.superview == nil ? CGRect.zero : $0.convert($0.bounds, to: column) }
        if split {
            grid.setItems([])
            grid.isHidden = true
            for (card, frame) in zip(cards, old) {
                column.addSubview(card)
                card.frame = frame
            }
        } else {
            grid.isHidden = false
            grid.setItems(cards.map { UKGridItem($0) })
            for (card, frame) in zip(cards, old) { card.frame = column.convert(frame, to: grid) }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let controller = pendingOpen {
            pendingOpen = nil
            open(controller, detail: initialDetail)
        }
    }

    /// The card width scales with Dynamic Type (`@ScaledMetric(relativeTo: .body)`).
    private func rescale() {
        var configuration = grid.configuration
        configuration.minCellWidth = UKFont.scaled(340, relativeTo: .body, traits: traitCollection)
        grid.configuration = configuration
        scroll?.contentChanged(animated: false)
    }

    private func open(_ controller: SprinklerController, detail: SprinklerDetail? = nil) {
        guard presentedViewController == nil else { return }
        UKSprinklerSheet.present(controller: controller, initialDetail: detail, context: context, from: self)
    }
}

// MARK: - Controller card

/// A controller's card (direction G, n4 sprinklers): a low battery warning above it, then the controller as a navigation tile, then one
/// module holding its battery, next and last watering, and hub status (`SprinklerControllerCard`).
///
/// The tile is the pattern's (rollout lane M, audit item 30; `SprinklerControllerTile`): glyph, name and status, the **Stop Watering** disc and
/// the chevron (it opens the controller's sheet). The disc dims in place while idle so the tile never changes shape (`SprinklerActions`); a tap
/// runs `SprinklerController.stopWatering()`, which shows the valve closed at once. While watering, the tile fills in the water family.
@MainActor
final class UKSprinklerControllerCard: UIView, UKGridMeasuring {
    private let controller: SprinklerController
    private let format = SprinklerFormat()
    private let bag = UKObservationBag()
    private let tile: UKGlassTileView
    private let tileEnvironment: UKTileEnvironment
    private let pills: UKSprinklerPillGrid
    private let module: UKRoomsModuleStack
    private var alertHost: UKRoomsFittedView?
    private var alertMessage: String?
    /// Called when the card's height changed with its content (the low battery warning came or went).
    var onHeightChange: (() -> Void)?

    init(controller: SprinklerController, context: UKContext, open: @escaping () -> Void) {
        self.controller = controller
        tileEnvironment = UKTileEnvironment(context: context)
        tile = UKGlassTileView(model: Self.model(controller, format: format), environment: tileEnvironment)
        pills = UKSprinklerPillGrid(kind: .card, valuesPending: context.valuesPending)
        module = UKRoomsModuleStack(rows: [pills])
        super.init(frame: .zero)
        addSubview(tile)
        addSubview(module)
        // The tile opens the sheet even while the controller is offline: its status lives there.
        tile.action = open
        tile.onPerform = { [weak controller] id in if id == SprinklerActions.actionId { controller?.stopWatering() } }
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refresh() {
        let snapshot = controller.snapshot
        tile.configure(Self.model(controller, format: format), environment: tileEnvironment)
        pills.show(snapshot)
        // Dense while the battery pill is orange (direction G, Layers: warm text on the thicker module).
        module.density = snapshot.batteryLow ? .dense : .thin
        let message: String?
        if snapshot.batteryLow, let percent = snapshot.batteryPercent {
            message = SprinklerFormat.lowBatteryWarning(title: controller.config.title, percent: percent)
        } else {
            message = nil
        }
        if message != alertMessage {
            alertMessage = message
            alertHost?.removeFromSuperview()
            alertHost = message.map { text in
                let host = UKRoomsFittedView(UKInlineAlertView(text, symbol: "battery.25percent"))
                addSubview(host)
                return host
            }
            setNeedsLayout()
            onHeightChange?()
        }
    }

    /// The controller as a navigation tile with the Stop Watering disc (`SprinklerControllerTile`); `isUnavailable` is not passed, so the
    /// card still opens its sheet offline.
    private static func model(_ controller: SprinklerController, format: SprinklerFormat) -> UKGlassTileModel {
        let specs = SprinklerActions(controller.config).actions(for: controller.snapshot, shownValve: controller.activeValve)
        var model = UKGlassTileModel(
            title: controller.config.title, subtitle: format.subtitle(controller.snapshot), symbol: SprinklerStyle.symbol, family: .water,
            isActive: controller.isWatering,
            behavior: TileBehavior(.classify(hasDestination: true, actions: TileActionKind.sprinkler.restingActionCount), primary: nil),
            actions: specs.items, identifier: "sprinklers.controller.\(controller.id)")
        model.bodyHint = "Opens the controller."
        return model
    }

    private func alertHeight(_ width: CGFloat) -> CGFloat {
        guard let alertHost else { return 0 }
        return alertHost.gridHeight(forWidth: width) + HassTokens.Spacing.m
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        pills.hinge = UKHinge.frame
        return alertHeight(width) + tile.gridHeight(forWidth: width) + HassTokens.Spacing.m + module.gridHeight(forWidth: width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        if let alertHost {
            let height = alertHost.gridHeight(forWidth: bounds.width)
            alertHost.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            y = height + HassTokens.Spacing.m
        }
        let tileHeight = tile.gridHeight(forWidth: bounds.width)
        tile.frame = CGRect(x: 0, y: y, width: bounds.width, height: tileHeight)
        y += tileHeight + HassTokens.Spacing.m
        module.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
    }
}
#endif
