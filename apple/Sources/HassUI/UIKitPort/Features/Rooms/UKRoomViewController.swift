#if os(iOS)
import HassCore
import HassDesign
import os
import UIKit

private let viewerLog = Logger(subsystem: "com.sfenton.home", category: "Rooms")

/// A config-driven room page (`RoomScreen` + `RoomPageContent`; web `SourceRoomPage`; spec `.agents/pages/rooms/spec.md`).
///
/// Status rail, then the room's sections in a responsive section grid (two columns where the window is wide), then the sheet for whichever
/// card was opened. Single page in every pose (owner's split rules). Every tile is created once and bound to its own entities.
@MainActor
final class UKRoomViewController: UKPageViewController {
    private let page: RoomPage
    private let controller: RoomController
    private let viewer = UKRoomsViewer()
    private let injectedViewer: HouseholdResident?
    private let fans: [String: BathroomFanController]
    private let bedroom: BedroomDevices?
    private var cards: UKRoomCards!
    private var scroll: UKPageScrollView!
    private let columns = UKFoldColumns(spacing: HassTokens.Spacing.xl)
    private var sectionGrid: UKRoomsGrid?
    private var sectionItems: [UKGridItem] = []
    private var sections: [UKRoomSectionView] = []
    /// A route Quick Links chose, pushed once its sheet has gone so the push never races the dismissal.
    private var pendingRoute: HomeRoute?
    private var isPresenting = false
    private let imageServer: HassServer?

    init(page: RoomPage, context: UKContext, viewer injected: HouseholdResident? = nil) {
        self.page = page
        let caller: any HassServiceCalling = context.caller ?? context.connection ?? UKRoomsNullCaller()
        let roomController = RoomController(page: page, store: context.store, caller: caller)
        controller = roomController
        injectedViewer = injected
        imageServer = context.connection?.server
        var fans: [String: BathroomFanController] = [:]
        for card in page.allCards where card.control == .bathroomFan {
            if let config = BathroomFanConfig.forPowerEntity(card.entityId) {
                fans[card.entityId] = BathroomFanController(config: config, store: context.store, caller: caller)
            }
        }
        self.fans = fans
        // Bedroom sheets read service responses; callers that cannot (the gallery's recorder) keep the generic tiles.
        let hasBedroom = page.allCards.contains { card in
            switch roomController.sheet(for: card) {
            case .device(.wakeLight), .device(.bed): true
            default: false
            }
        }
        if hasBedroom, !(caller is any HassServiceResponding) {
            viewerLog.notice("bedroom devices unavailable: the caller cannot read service responses; showing generic tiles")
        }
        bedroom = hasBedroom ? (caller as? any HassServiceResponding).map { BedroomDevices(store: context.store, caller: $0, canEdit: false) } : nil
        super.init(context: context, title: page.title)
        viewer.resident = injected
    }

    // MARK: View

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        cards = UKRoomCards(controller: controller, context: context, viewer: viewer, fans: fans, bedroom: bedroom, bag: bag)
        cards.open = { [weak self] card in self?.open(card) }

        // Flat: the status rail, then the sections in one responsive grid. Partly folded: the rail spans the top (or leads, wrapped at an
        // accessibility size) and every section sits wholly on one side, by the parity of its index (`.agents/design/section-sides.md`).
        var parts: [UKFoldColumns.Section] = []
        if !page.overviewCards.isEmpty {
            let rail = UKChipRailView()
            rail.setChips(page.overviewCards.map { cards.chip($0) })
            rail.accessibilityContainerType = .semanticGroup
            rail.accessibilityLabel = "\(page.title) status"
            parts.append(.init(rail, side: .top, fullBleed: true, wrappedSide: .leading))
        }
        parts += sectionParts()
        columns.setSections(parts)
        columns.sideInset = HassTokens.Spacing.l
        columns.splitIdentifier = "room.columns.split"
        columns.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        columns.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
        columns.onSplitChange = { [weak self] split in self?.place(sectionsSplit: split) }
        scroll = UKPageScrollView(content: columns, padding: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        scroll.accessibilityIdentifier = "room.scroll.\(page.id)"
        install(scrollView: scroll)

        bag.observe { [weak self] in
            guard let self else { return }
            columns.hinge = context.shell?.windowHinge
        }
        bag.observe { [weak self] in
            guard let self else { return }
            self.bedroom?.wakeLight.canEdit = self.viewer.isAdmin
        }
        if let navigator = context.navigator {
            bag.observe { [weak self] in
                _ = navigator.pendingSheet
                self?.openLinkedSheet()
            }
        }
        loadViewer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        openLinkedSheet()
    }

    /// Personalized titles ("Your Side") need the signed-in user; the page shows plain titles until then.
    private func loadViewer() {
        guard injectedViewer == nil, let connection = context.connection else { return }
        Task { @MainActor [weak self] in
            let user: HassUser
            do { user = try await connection.currentUser() } catch {
                viewerLog.error("signed-in user read failed: \(String(describing: error), privacy: .public)")
                return
            }
            self?.viewer.resident = HouseholdResident.forUserId(user.id)
            self?.viewer.isAdmin = user.isAdmin
        }
    }

    /// The page's sections as the columns see them: the flat grid (single column only) and one entry per section (split only), or the
    /// empty state, which sits in the leading region.
    private func sectionParts() -> [UKFoldColumns.Section] {
        let visible = page.visibleSections
        let isKitchen = page.id == "kitchen"
        if visible.isEmpty && !isKitchen {
            let empty = UKRoomsMeasured(UKStateMessageView(symbol: SymbolMap.symbol(for: RoomNavigation.item(for: page.id)?.icon ?? "mdi:home"), title: "Nothing Here Yet!",
                                                  message: "Once some devices are added to this room, we can display them here.", identifier: "room.empty"))
            return [.init(empty, side: .leading)]
        }
        let count = visible.count + (isKitchen ? 1 : 0)
        let grid = UKRoomsGrid(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, relativeTo: .body)
        var items: [UKGridItem] = []
        var sides: [FoldSide] = []
        if isKitchen {
            let groceries = UKKitchenGroceriesSection(controller: controller, environment: UKTileEnvironment(context: context), bag: bag) { [weak self] route in
                self?.open(route)
            }
            items.append(UKGridItem(groceries, span: count == 1 ? 2 : 1))
            sides.append(FoldColumns.side(forConfiguredIndex: 0))
        }
        for section in visible {
            let view = UKRoomSectionView(section: section, cards: cards, controller: controller, imageServer: imageServer, context: context)
            sections.append(view)
            items.append(UKGridItem(view, span: RoomSectionView.isFullWidth(section, sectionCount: count) ? 2 : 1))
            sides.append(FoldColumns.side(forConfiguredIndex: sides.count, override: section.foldSide.flatMap { FoldSide(rawValue: $0.rawValue) }))
        }
        grid.setItems(items)
        sectionGrid = grid
        sectionItems = items
        return [.init(grid, side: .leading, visibility: .flatOnly)]
            + zip(items, sides).map { UKFoldColumns.Section($0.0.view, side: $0.1, visibility: .splitOnly) }
    }

    /// Moves the sections between the flat grid and the columns, starting from the frames they had so the reflow slides them.
    private func place(sectionsSplit split: Bool) {
        guard let grid = sectionGrid else { return }
        let views = sectionItems.map(\.view)
        let old = views.map { $0.superview == nil ? CGRect.zero : $0.convert($0.bounds, to: columns) }
        if split {
            grid.setItems([])
            grid.isHidden = true
            for (view, frame) in zip(views, old) {
                columns.addSubview(view)
                view.frame = frame
            }
        } else {
            grid.isHidden = false
            grid.setItems(sectionItems)
            for (view, frame) in zip(views, old) { view.frame = columns.convert(frame, to: grid) }
        }
    }

    // MARK: Sheets

    /// Opens a card: its remote sheet, its device lane's sheet, else its room sheet.
    private func open(_ card: RoomCard) {
        switch RoomPageContent.opening(card, controller: controller, hasConnection: context.connection != nil, fans: fans, bedroom: bedroom) {
        case let .remote(shared):
            present(UKMediaRemoteSheet.make(controller: shared, imageServer: imageServer, initialTab: .controls, context: context.with { $0.surface = .sheet }))
        case let .device(modal):
            // The vacuum opens the Vacuums page's own sheet.
            if case let .vacuum(vacuum) = modal, let page = UKScreens.sheetPage(for: vacuum, context: context) {
                present(UKVacuumSheet.modal(for: page))
                return
            }
            let sheet = UKRoomDeviceSheets.make(for: modal, context: context, onOpenBed: { [weak self] side in
                // The wake-light sheet's "open this bed's alarms", once it has closed.
                guard let self, let bedroom = self.bedroom,
                      let bed = UKRoomDeviceSheets.make(for: .bed(bedroom, side: side, tab: .alarms), context: self.context) else { return }
                self.present(bed)
            })
            present(sheet ?? UKRoomCardSheetPage.make(controller: controller, card: card, viewer: viewer, context: context,
                                                      onDismissed: { [weak self] in self?.sheetDismissed() }))
        case .sheet:
            present(UKRoomCardSheetPage.make(controller: controller, card: card, viewer: viewer, context: context, onDismissed: { [weak self] in self?.sheetDismissed() }))
        }
    }

    private func present(_ sheet: UIViewController) {
        guard presentedViewController == nil else { return }
        if let modal = sheet as? UKHassModalController {
            #if DEBUG
            UKRoomsLastCall.attach(to: modal, caller: controller.caller)
            #endif
            modal.present(from: self)
        } else {
            present(sheet, animated: true)
        }
    }

    private func sheetDismissed() {
        guard let chosen = pendingRoute else { return }
        pendingRoute = nil
        open(chosen)
    }

    /// Pushes a route on the section's stack; a gallery has no navigator, so the page it sits in pushes it.
    private func open(_ route: HomeRoute) {
        if context.navigator != nil, context.section != nil { context.push(route); return }
        navigationController?.pushViewController(UKScreens.destination(for: route, context: context), animated: true)
    }

    /// Opens the card a link's `#anchor` names (a Live Activity tap on a vacuum opens its sheet).
    private func openLinkedSheet() {
        guard isViewLoaded, view.window != nil, let anchor = context.navigator?.takeSheet(forPage: page.id),
              let card = page.allCards.first(where: { $0.sheet == anchor }) else { return }
        open(card)
    }
}
#endif
