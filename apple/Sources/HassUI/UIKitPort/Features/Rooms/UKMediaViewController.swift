#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Media page (`MediaScreen`; web `MediaPage`; spec `.agents/pages/media/spec.md`): one section per room, the room's TV leading on its own
/// row and opening its remote, the room's sources and quick launches in a grid under it that run their command in place. Sections sit side by
/// side when the page is wide enough.
@MainActor
final class UKMediaViewController: UKPageViewController {
    private let store: EntityStore
    private let caller: any HassServiceCalling
    private let imageServer: HassServer?
    /// The Music Room's controller, shared by its source tiles and its remote so optimistic source changes show in both.
    private var musicRoom: MediaRemoteController
    private let initialTab: MediaRemoteTab
    private var pendingRemote: MediaRemoteConfig?
    private var scroll: UKPageScrollView!
    private let columns = UKFoldColumns(spacing: HassTokens.Spacing.xl)
    private var sectionGrid: UKRoomsGrid?
    private var sectionItems: [UKGridItem] = []

    init(context: UKContext, openRemote: MediaRemoteConfig? = nil, initialTab: MediaRemoteTab = .controls) {
        store = context.store
        caller = context.caller ?? context.connection ?? UKRoomsNullCaller()
        imageServer = context.connection?.server
        self.initialTab = initialTab
        pendingRemote = openRemote
        musicRoom = MediaRemoteController(config: MediaRemotes.sourceSelectRemote, store: context.store, caller: context.caller ?? context.connection ?? UKRoomsNullCaller())
        super.init(context: context, title: "Media")
    }

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildSections()
        columns.sideInset = HassTokens.Spacing.l
        columns.splitIdentifier = "media.columns.split"
        columns.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        columns.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
        columns.onSplitChange = { [weak self] split in self?.place(split: split) }
        scroll = UKPageScrollView(content: columns, padding: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        scroll.accessibilityIdentifier = "media.scroll"
        install(scrollView: scroll)
        bag.observe { [weak self] in
            guard let self else { return }
            columns.hinge = context.shell?.windowHinge
        }
    }

    /// Holds the observations of the tiles, which come from the house document, so a rebuild ends the old ones.
    private let structureBag = UKObservationBag()

    /// Builds one section per room from the house document and hands them to the columns. Called from `viewDidLoad` and again by
    /// ``houseLayoutDidChange()``.
    private func buildSections() {
        structureBag.removeAll()
        let environment = UKTileEnvironment(context: context)
        let grid = UKRoomsGrid(minCellWidth: 340, maxColumns: 3, spacing: HassTokens.Spacing.xl, relativeTo: .body)
        sectionItems = MediaPageConfig.sections.map { UKGridItem(section($0, environment: environment)) }
        if columns.isSplit { grid.isHidden = true } else { grid.setItems(sectionItems) }
        sectionGrid = grid
        // Partly folded: Living Room and Cinema Room lead, Music Room trails (parity of the index; `.agents/design/section-sides.md`).
        var parts: [UKFoldColumns.Section] = [.init(grid, side: .leading, visibility: .flatOnly)]
        for (index, item) in sectionItems.enumerated() {
            parts.append(.init(item.view, side: FoldColumns.side(forConfiguredIndex: index), visibility: .splitOnly))
        }
        columns.setSections(parts)
    }

    override func houseLayoutDidChange() {
        musicRoom = MediaRemoteController(config: MediaRemotes.sourceSelectRemote, store: store, caller: caller)
        buildSections()
    }

    /// Moves the sections between the flat grid and the columns, starting from the frames they had so the reflow slides them.
    private func place(split: Bool) {
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let remote = pendingRemote {
            pendingRemote = nil
            open(remote)
        }
    }

    private func section(_ section: MediaPageConfig.Section, environment: UKTileEnvironment) -> UIView {
        let column = UKColumnView(spacing: HassTokens.Spacing.m)
        var views: [UIView] = [UKPageSectionHeaderView(section.title)]
        if let lead = section.lead { views.append(tile(lead, environment: environment, spansFullRow: true)) }
        if !section.followUps.isEmpty {
            let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
            grid.setItems(section.followUps.map { UKGridItem(tile($0, environment: environment)) })
            views.append(grid)
        }
        column.setViews(views)
        column.accessibilityContainerType = .semanticGroup
        column.accessibilityIdentifier = "media.section.\(MediaCardTile.slug(section.title))"
        return column
    }

    /// One media tile: opens a remote, or runs its command. Dark with a pink glyph while off, filled media pink while on.
    ///
    /// A remote is a navigation tile (glyph, text, chevron) with its actions from `MediaTransportActions`: Power beside the chevron while it is
    /// off or idle; previous / play-pause / next centred below the text, and a volume slider under them, while it plays or is paused. The set
    /// changing shape animates the tile's height when it spans its row (`TileActionSetTransition`).
    private func tile(_ card: MediaPageConfig.Card, environment: UKTileEnvironment, spansFullRow: Bool = false) -> UIView {
        let controller = musicRoom
        let caller = self.caller
        let identifier = "media.card.\(MediaCardTile.slug(card.section)).\(MediaCardTile.slug(card.device.title))"
        let holder = UKActionsHolder()
        let slider = UKTileVolumeSlider(title: card.device.title, percent: 0, identifier: "\(identifier).volume")

        /// The controller that runs `remote`: the shared one, or its own made now.
        func runner(for remote: MediaRemoteConfig) -> MediaRemoteController {
            if remote.id == controller.config.id { return controller }
            let own = holder.ownController ?? MediaRemoteController(config: remote, store: controller.store, caller: caller)
            holder.ownController = own
            return own
        }
        /// The remote's discs for its shown state: the controller's tapped state, then the transport's.
        func specs(for remote: MediaRemoteConfig) -> [TileActionSpec] {
            let live = controller.store.entity(remote.mediaEntityId).state
            let shown = holder.ownController ?? controller
            let state = live?.showing(shown.displayedState(remote.mediaEntityId)).showing(holder.actions?.shown(remote.mediaEntityId))
            return MediaCardTile.specs(for: remote, state: state)
        }
        /// The speaker's level: the controller's (with its tapped value) when there is one, else the entity's.
        func volumePercent(_ remote: MediaRemoteConfig) -> Int {
            if remote.id == controller.config.id { return controller.volumePercent }
            return holder.ownController?.volumePercent ?? RemoteTileSupport.volumePercent(controller.store.entity(remote.volumeEntityId).state)
        }
        /// Runs a disc: Power presses the remote's Power through its controller (which shows the tapped state and rolls it back on failure);
        /// play/pause shows the opposite state at once; previous and next just call.
        func run(_ spec: TileActionSpec, remote: MediaRemoteConfig) {
            if spec.id == PowerToggleActions.actionId {
                _ = runner(for: remote).press(remote.power)
                return
            }
            let actions = holder.actions ?? OptimisticActions(store: controller.store, rules: [remote.mediaEntityId: .liveChange], caller: caller)
            holder.actions = actions
            actions.perform(spec, failing: remote.mediaEntityId)
        }

        func model() -> UKGlassTileModel {
            let shown = holder.ownController ?? controller
            let display = shown.display(card.device)
            let look = MediaCardTile.look(card, display: display)
            if let remote = card.remote {
                // A remote opens whatever the TV's state: its discs are how the TV turns on and plays.
                let specs = specs(for: remote)
                let volume = RemoteTileSupport.showsVolume(config: remote, specs: specs, volume: controller.store.entity(remote.volumeEntityId).state)
                let failed = holder.actions?.isFailed(remote.mediaEntityId) == true || shown.volumeWriteFailed
                var model = UKGlassTileModel(title: card.device.title, subtitle: failed ? "Didn't Respond" : display.subtitle, symbol: look.symbol,
                                             family: .media, isActive: display.isActive, isError: failed,
                                             behavior: TileBehavior(TileActionCatalog.classification(of: card), primary: nil), actions: specs.items,
                                             identifier: identifier)
                model.stateCandidates = MediaTransportActions(config: remote).stateTextCandidates
                model.accessoryShown = volume
                model.reapplyGeneration = controller.store.reapplyGeneration
                if volume {
                    slider.update(percent: volumePercent(remote), isDisabled: false)
                    slider.onCommit = { runner(for: remote).setVolume(percent: $0) }
                }
                return model
            }
            if let source = sourceProvider(card) {
                // A Music Room source chooses (selection face, option C). The tap is today's toggle through the shared controller, so a chosen
                // source turns the TV off and Fortnite relaunches.
                let face = RolloutTileSupport.sourceFace(source, state: EntityState(entityId: card.device.entityId, state: display.state))
                var model = UKGlassTileModel(title: card.device.title, subtitle: face.subtitle, symbol: look.symbol, family: .media, isActive: display.isActive,
                                             isUnavailable: display.isDisabled,
                                             behavior: TileBehavior(TileActionCatalog.classification(of: card), primary: SourceSelectActions.actionId),
                                             actions: face.specs.items, identifier: identifier)
                model.stateCandidates = source.stateTextCandidates
                return model
            }
            if let device = scriptProvider(card) {
                // Nintendo Switch and Cinema Streamer: a power disc tracked through the tile's own script until the boolean reports.
                let specs = RolloutTileSupport.scriptSpecs(device, store: controller.store, actions: holder.actions)
                let live = controller.store.entity(device.activeEntityId).state
                let failed = holder.actions?.isFailed(device.activeEntityId) == true
                var model = UKGlassTileModel(title: card.device.title, subtitle: failed ? "Didn't Respond" : device.stateText(live: live, phase: specs.first?.phase ?? .ready),
                                             symbol: look.symbol, family: .media, isActive: specs.first?.isOn ?? false, isUnavailable: display.isDisabled, isError: failed,
                                             behavior: TileBehavior(TileActionCatalog.classification(of: card), primary: ScriptPowerActions.actionId),
                                             actions: specs.items, identifier: identifier)
                model.stateCandidates = device.stateTextCandidates
                return model
            }
            return UKGlassTileModel(title: card.device.title, subtitle: display.subtitle, symbol: look.symbol, family: .media,
                                    isActive: display.isActive, isUnavailable: display.isDisabled, kind: look.kind, identifier: identifier)
        }
        func sourceProvider(_ card: MediaPageConfig.Card) -> SourceSelectActions? {
            TileActionCatalog.kind(of: card) == .sourceSelect ? RolloutTileSupport.sourceProvider(title: card.device.title) : nil
        }
        func scriptProvider(_ card: MediaPageConfig.Card) -> ScriptPowerActions? {
            TileActionCatalog.kind(of: card) == .scriptPower ? RolloutTileSupport.scriptProvider(forEntity: card.device.entityId) : nil
        }
        let view = UKGlassTileView(model: model(), environment: environment)
        view.spansFullRow = spansFullRow
        if card.remote != nil { view.setAccessory(slider) }
        UKRoomsBind.tile(view, bag: structureBag, environment: environment, action: { [weak self] in
            if let remote = card.remote { self?.open(remote) } else { controller.tap(card.device) }
        }, perform: { id in
            if let device = scriptProvider(card) {
                let specs = RolloutTileSupport.scriptSpecs(device, store: controller.store, actions: holder.actions)
                guard let spec = specs.first(where: { $0.id == id }) else { return }
                let actions = holder.actions ?? RolloutTileSupport.scriptActions(device, store: controller.store, caller: caller)
                holder.actions = actions
                actions.perform(spec)
            } else if sourceProvider(card) != nil {
                controller.tap(card.device)
            } else if let remote = card.remote, let spec = specs(for: remote).first(where: { $0.id == id }) {
                run(spec, remote: remote)
            }
        }, model: model)
        return view
    }

    private func open(_ config: MediaRemoteConfig) {
        guard presentedViewController == nil else { return }
        let sheetContext = context.with { $0.surface = .sheet }
        let sheet: UIViewController
        if config.id == MediaRemotes.sourceSelectRemote.id {
            sheet = UKMediaRemoteSheet.make(controller: musicRoom, imageServer: imageServer, initialTab: initialTab, context: sheetContext)
        } else {
            sheet = UKMediaRemoteSheet.make(config: config, store: store, caller: caller, imageServer: imageServer, initialTab: initialTab,
                                            context: sheetContext)
        }
        guard let modal = sheet as? UKHassModalController else { present(sheet, animated: true); return }
        #if DEBUG
        UKRoomsLastCall.attach(to: modal, caller: caller)
        #endif
        modal.present(from: self)
    }
}
#endif
