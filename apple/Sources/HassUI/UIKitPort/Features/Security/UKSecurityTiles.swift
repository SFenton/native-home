#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Lock

/// A lock tile bound to its entity (`SecurityDoorTile` + `LockTile`): locks when unlocked, unlocks otherwise, with explicit
/// services. Filled while unlocked or moving, the red error face while jammed or after a rejected command ("Didn't Respond" for
/// 4 s). The tapped state shows until Home Assistant reports a change and rolls back if the call fails.
///
/// ```swift
/// let lock = UKLockTileBinder(tile: SecurityConfig.controlTiles[0], context: context, caller: caller)
/// grid.setItems([UKGridItem(lock.view)])      // keep the binder alive as long as the tile
/// ```
@MainActor
final class UKLockTileBinder {
    let view: UKGlassTileView
    private let tile: SecurityConfig.Tile
    private let context: UKContext
    private let caller: any HassServiceCalling
    private let bag = UKObservationBag()
    private let identifier: String
    private var actions: OptimisticActions?

    /// - Parameters:
    ///   - identifier: The tile's accessibility identifier; `security.tile.<entity id>` by default.
    init(tile: SecurityConfig.Tile, context: UKContext, caller: any HassServiceCalling, identifier: String? = nil) {
        self.tile = tile
        self.context = context
        self.caller = caller
        let id = identifier ?? "security.tile.\(tile.entityId)"
        self.identifier = id
        view = UKGlassTileView(model: UKGlassTileModel(title: tile.title, symbol: "lock", family: .contact, isActive: false,
                                                       behavior: TileBehavior(TileActionCatalog.classification(of: tile), primary: LockActions.actionId),
                                                       identifier: id),
                               environment: UKTileEnvironment(context: context))
        bind()
    }

    private func bind() {
        bag.removeAll()
        let box = context.store.entity(tile.entityId)
        let id = identifier
        bag.observe { [weak self] in
            guard let self else { return }
            let live = box.state
            // The live state with any pending tapped value over it.
            let state = live?.showing(actions?.shown(tile.entityId))
            let failed = actions?.isFailed(tile.entityId) ?? false
            let value = state?.state
            let unavailable = state?.isUnavailable ?? true
            let provider = LockActions(entityId: tile.entityId)
            let specs = provider.actions(for: state)
            // An action tile, text and disc: the disc carries the state glyph and the body does what it shows, in one tap.
            var model = UKGlassTileModel(
                title: tile.title,
                subtitle: unavailable ? "Unavailable" : failed ? "Didn't Respond" : SecurityConfig.stateText(value),
                symbol: specs.first?.symbol ?? "lock.fill", family: .contact, isActive: LockActions.isFilled(value),
                isUnavailable: unavailable, isError: value == "jammed" || failed,
                behavior: TileBehavior(TileActionCatalog.classification(of: tile), primary: LockActions.actionId),
                actions: specs.items, identifier: id)
            model.stateCandidates = provider.stateTextCandidates
            view.configure(model, environment: UKTileEnvironment(context: context), perform: { [weak self] actionId in
                if let call = specs.first(where: { $0.id == actionId })?.call { self?.send(call) }
            })
        }
    }

    private func send(_ call: ServiceCall) {
        let created = actions == nil
        let actions = actions ?? OptimisticActions(store: context.store, rules: [tile.entityId: .liveChange], caller: caller)
        self.actions = actions
        // The pending value is read by the render, which only re-runs on what it read: rebind once the path exists.
        if created { bind() }
        // The lock's own transitional state shows until it reports: a tracked action's "Unlocking…" with the arc in its disc. Any live
        // change clears it (locks report "locking" and "unlocking" on the way).
        actions.perform(call, showing: [OptimisticIntent(tile.entityId, value: call.service == "lock" ? "locking" : "unlocking")])
    }
}

// MARK: - Garage door

/// A garage door tile driven by ``GarageDoorController`` (web `GarageDoorTile.tsx`): the Security page's Doors section and the
/// garage room's cards draw it. Direction G: the contact family, filled while the door is open or moving, and the red error face
/// after a failed command. "Sending Open…" reads at once, the controller locks out double taps, and VoiceOver hears each
/// phase change without focus moving.
///
/// ```swift
/// let door = UKGarageDoorTileBinder(tile: tile, context: context, caller: caller, canSend: { connection.isReady })
/// ```
@MainActor
final class UKGarageDoorTileBinder {
    let view: UKGlassTileView
    let controller: GarageDoorController
    private let tile: SecurityConfig.Tile
    private let context: UKContext
    private let canSend: () -> Bool
    private let bag = UKObservationBag()
    private var lastPhase: GarageDoorController.Phase = .idle

    /// - Parameters:
    ///   - canSend: Whether a command can go out now (`SecurityScreen.canSend`); read inside an observation, so it follows the connection.
    ///   - identifier: The tile's accessibility identifier; `security.tile.<entity id>` by default.
    init(tile: SecurityConfig.Tile, context: UKContext, caller: any HassServiceCalling, canSend: @escaping () -> Bool, identifier: String? = nil) {
        self.tile = tile
        self.context = context
        self.canSend = canSend
        let live = context.store.entity(tile.entityId).state?.state
        controller = GarageDoorController(entityId: tile.entityId, liveState: live, caller: caller, scheduler: TaskRevertScheduler())
        let id = identifier ?? "security.tile.\(tile.entityId)"
        view = UKGlassTileView(model: UKGlassTileModel(title: tile.title, symbol: "door.garage.closed", family: .contact, isActive: false,
                                                       behavior: TileBehavior(TileActionCatalog.classification(of: tile), primary: CoverActions.actionId),
                                                       identifier: id),
                               environment: UKTileEnvironment(context: context))
        let box = context.store.entity(tile.entityId)
        // Feeds the live state and the connection into the controller (`garageDoorFeedback`).
        bag.observe { [weak self] in
            // Read here, applied a turn later: the controller is observable, and this observation must track only the box and the
            // connection.
            let live = box.state?.state
            let sendable = canSend()
            Task { @MainActor [weak self] in
                self?.controller.liveDidChange(live)
                self?.controller.connectionDidChange(canSend: sendable)
            }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            render(id: id)
        }
    }

    private func render(id: String) {
        let controller = controller
        let unavailable = !controller.isAvailable
        // One morphing disc (id `CoverActions.actionId`, stable across Open, Close and Reverse): the only place the door's verb, glyph and
        // phase are decided is `CoverActions`.
        let specs = GarageDoorTile.specs(for: controller)
        var model = UKGlassTileModel(
            title: tile.title, subtitle: GarageDoorTile.subtitle(for: controller), symbol: specs.first?.symbol ?? "door.garage.closed",
            family: .contact, isActive: !unavailable && CoverActions.isFilled(controller.displayState), isUnavailable: unavailable,
            isError: controller.phase == .error,
            behavior: TileBehavior(TileActionCatalog.classification(of: tile), primary: CoverActions.actionId), actions: specs.items, identifier: id)
        model.stateCandidates = CoverActions(entityId: controller.entityId).stateTextCandidates
        view.configure(model, environment: UKTileEnvironment(context: context), perform: { [weak controller] _ in controller?.send() })
        // The tile announces its own error face (title and "Error"), so the failure speaks once.
        let phase = controller.phase
        if phase != lastPhase {
            lastPhase = phase
            if phase != .idle, phase != .error { Announcer.announce("\(tile.title), \(GarageDoorTile.subtitle(for: controller))") }
        }
    }
}

// MARK: - Section

/// A titled grid of lock and garage door tiles (owner, 2026-10-16: doors as tiles, not rows): the Security page's Doors and Car
/// sections. Tiles share one height, set by the tallest, and reflow to one column at accessibility sizes.
@MainActor
final class UKSecurityTileSection: UIView, UKGridMeasuring {
    private let header: UKPageSectionHeaderView
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var locks: [UKLockTileBinder] = []
    private var doors: [UKGarageDoorTileBinder] = []

    var hinge: CGRect? {
        get { grid.hinge }
        set { grid.hinge = newValue }
    }

    init(_ title: String, tiles: [SecurityConfig.Tile], context: UKContext, caller: any HassServiceCalling, canSend: @escaping () -> Bool) {
        header = UKPageSectionHeaderView(title)
        super.init(frame: .zero)
        grid.followsFold = true
        addSubview(header)
        addSubview(grid)
        var views: [UIView] = []
        for tile in tiles {
            switch tile.kind {
            case .garageDoor:
                let door = UKGarageDoorTileBinder(tile: tile, context: context, caller: caller, canSend: canSend)
                doors.append(door)
                views.append(door.view)
            case .lock, .vehicle, .alarm:
                let lock = UKLockTileBinder(tile: tile, context: context, caller: caller)
                locks.append(lock)
                views.append(lock.view)
            }
        }
        grid.setItems(views.map { UKGridItem($0) })
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            grid.configuration.minCellWidth = UKFont.scaled(140, relativeTo: .subheadline, traits: traitCollection)
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var spacing: CGFloat { HassTokens.Spacing.s + 2 }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        header.gridHeight(forWidth: width) + spacing + grid.gridHeight(forWidth: width)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight = header.gridHeight(forWidth: bounds.width)
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        grid.frame = CGRect(x: 0, y: headerHeight + spacing, width: bounds.width, height: grid.gridHeight(forWidth: bounds.width))
    }
}
#endif
