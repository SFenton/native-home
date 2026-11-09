#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

/// Builds and binds the views of one room page: the status chips and the cards (`RoomCardView`, `RoomCardTile`, `BathroomFanRoomTile`,
/// `GarageDoorTile`). Every view is created once and bound to the entities it shows through the page's bag, so a live change to one entity
/// costs the views that read it one update; the sections only arrange them.
@MainActor
final class UKRoomCards {
    let controller: RoomController
    let context: UKContext
    let viewer: UKRoomsViewer
    let fans: [String: BathroomFanController]
    let bedroom: BedroomDevices?
    let bag: UKObservationBag
    var open: (RoomCard) -> Void = { _ in }
    private let clock = UKRoomsClock()
    private var cards: [String: UIView] = [:]
    private var chips: [String: UKRoomChipView] = [:]

    init(controller: RoomController, context: UKContext, viewer: UKRoomsViewer, fans: [String: BathroomFanController], bedroom: BedroomDevices?,
         bag: UKObservationBag) {
        self.controller = controller
        self.context = context
        self.viewer = viewer
        self.fans = fans
        self.bedroom = bedroom
        self.bag = bag
    }

    private var environment: UKTileEnvironment { UKTileEnvironment(context: context) }

    // MARK: Chips

    /// An overview chip (`RoomChip`).
    func chip(_ card: RoomCard) -> UKRoomChipView {
        if let existing = chips[card.id] { return existing }
        let view = UKRoomChipView()
        view.accessibilityIdentifier = "room.chip.\(card.title)"
        var first = true
        bag.observe { [weak self, weak view] in
            guard let self, let view else { return }
            let chip = self.controller.chip(card)
            let summary = ScreenshotPrivacy.isRedacting && card.kind == .occupancy ? "Hidden" : chip.summary
            let appearance = StatusChipAppearance.room(card, chip: chip)
            view.configure(title: chip.title, summary: summary, symbol: appearance.symbol, family: appearance.family, isActive: appearance.isFilled,
                           tint: appearance.tint, action: chip.opensSheet ? { [weak self] in self?.open(card) } : nil, animated: !first)
            first = false
        }
        chips[card.id] = view
        return view
    }

    // MARK: Cards

    /// The view for a card, created on first use.
    func view(for card: RoomCard) -> UIView {
        if let existing = cards[card.id] { return existing }
        let built: UIView
        if card.control == .bathroomFan, let fan = fans[card.entityId] {
            built = fanTile(card, fan: fan)
        } else if card.control == .garageDoor, let tile = RoomCardView.garageTile(card) {
            built = garageTile(card, tile: tile)
        } else if let bed = RoomCardView.bed(card, in: bedroom) {
            // A bed side's climate entity says "heat" whatever the pod is doing; its controller knows the level and power.
            built = bedTile(card, bed: bed)
        } else {
            built = cardTile(card)
        }
        cards[card.id] = built
        return built
    }

    private func kind(_ semantics: RoomTileSemantics) -> GlassTileKind {
        switch semantics {
        case .modal: .navigate
        case .command: .command
        case .toggle: .toggle
        case let .selection(isSelected): .selection(isSelected: isSelected)
        case .state: .state
        }
    }

    // MARK: Actions

    /// A card's discs and how they run (`RoomCardTile.Provision`).
    private struct Provision {
        var specs: [TileActionSpec]
        /// Every state line the provider can show, for the tile's minimum width.
        var candidates: [String]
        var run: (TileActionSpec) -> Void
        /// A remote's volume slider: the level and where a release sends it. Nil: none shows.
        var volume: (percent: Int, commit: (Int) -> Void)?
        /// A previous, next or volume write was rejected and its failed face is showing.
        var failed = false
        /// The state line, when the provider's face says it better than the card's (a source's "On the TV", a script's "Turning On…").
        var subtitle: String?
        /// ``subtitle`` is the tile's state line even when nil (an unchosen source says nothing).
        var overridesSubtitle = false
        /// The state line the provision gives, if it gives one: the double optional keeps "nothing to say" apart from "no opinion".
        var stateLine: String?? { overridesSubtitle ? .some(subtitle) : nil }
        /// The tile's fill, when the disc's state is the truth (a purifier follows its fan, not its mode select).
        var isActive: Bool?
    }

    private var holders: [String: UKActionsHolder] = [:]

    /// The provider for the card's class (`TileActionCatalog.kind(of:)`), fed the shown state; nil for a card with none.
    private func provision(_ card: RoomCard, holder: UKActionsHolder, bed: BedSideController?, activate: @escaping () -> Void) -> Provision? {
        let controller = self.controller
        switch TileActionCatalog.kind(of: card) {
        case .power where TileActionCatalog.powerEntityId(of: card) != nil:
            // A purifier and a humidifier open their sheet and carry a power disc: explicit `turn_on` / `turn_off` on the entity, shown at
            // once and rolled back on failure. The purifier tile fills with its fan, not its mode select.
            let entityId = TileActionCatalog.powerEntityId(of: card)!
            let provider = PowerToggleActions.entity(entityId)
            let specs = provider.actions(for: controller.store.entity(entityId).state?.showing(holder.actions?.shown(entityId)))
            return Provision(specs: specs, candidates: provider.stateTextCandidates, run: { spec in
                let actions = holder.actions ?? OptimisticActions(store: controller.store, rules: [entityId: .liveChange], caller: controller.caller)
                holder.actions = actions
                actions.perform(spec, failing: entityId)
            }, failed: holder.actions?.isFailed(entityId) == true, isActive: specs.first?.isOn)
        case .sourceSelect:
            // Music Room sources choose (selection face, option C): the disc is the choice, the tap is today's toggle, so the room's
            // shared remote controller keeps the optimistic source and a chosen source turns the TV off.
            guard let provider = RolloutTileSupport.sourceProvider(title: card.title) else { return nil }
            let face = RolloutTileSupport.sourceFace(provider, state: controller.entity(card.entityId))
            return Provision(specs: face.specs, candidates: provider.stateTextCandidates, run: { _ in activate() }, subtitle: face.subtitle, overridesSubtitle: true)
        case .scriptPower:
            // Switch and SHIELD: a power disc tracked through the tile's own script until the active boolean reports.
            guard let provider = RolloutTileSupport.scriptProvider(forEntity: card.entityId) else { return nil }
            let specs = RolloutTileSupport.scriptSpecs(provider, store: controller.store, actions: holder.actions)
            let live = controller.store.entity(provider.activeEntityId).state
            let phase = specs.first?.phase ?? .ready
            return Provision(specs: specs, candidates: provider.stateTextCandidates, run: { spec in
                let actions = holder.actions ?? RolloutTileSupport.scriptActions(provider, store: controller.store, caller: controller.caller)
                holder.actions = actions
                actions.perform(spec)
            }, failed: holder.actions?.isFailed(provider.activeEntityId) == true, subtitle: provider.stateText(live: live, phase: phase),
                             overridesSubtitle: true, isActive: specs.first?.isOn)
        case .bedSidePower:
            // A bed side opens its sheet and carries a power disc; the bed controller owns the effect and turning off asks first.
            guard let bed else { return nil }
            let provider = BedSidePowerActions(bed.config, isReadOnly: bed.scope.readOnly)
            let shown = EntityState(entityId: bed.config.climateEntityId, state: bed.sideAvailable ? (bed.isOn ? "on" : "off") : "unavailable")
            let specs = provider.actions(for: shown)
            return Provision(specs: specs, candidates: provider.stateTextCandidates, run: { spec in bed.setPower(on: spec.isOn != true) })
        case .power:
            // A towel rack flips through the room's optimistic path; a PC presses its on/off button and is tracked through the PC's own
            // status text ("Turning On…"). Either way the tap is the card's own.
            let state = controller.entity(card.entityId)
            let provider: PowerToggleActions
            if card.action == .flip {
                provider = .entity(card.entityId)
            } else {
                let prefix = card.entityId.dropFirst("input_boolean.".count).dropLast("_power".count)
                provider = .pc(prefix: String(prefix), statusText: controller.entity("input_text.\(prefix)_power_state")?.state)
            }
            return Provision(specs: provider.actions(for: state), candidates: provider.stateTextCandidates, run: { _ in activate() })
        case .vacuum:
            let state = controller.store.entity(card.entityId).state
            let shown = state?.showing(holder.actions?.shown(card.entityId))
            let provider = VacuumActions(entityId: card.entityId)
            return Provision(specs: provider.actions(for: shown), candidates: provider.stateTextCandidates, run: { spec in
                let actions = holder.actions ?? OptimisticActions(store: controller.store, rules: [card.entityId: .liveChange], caller: controller.caller)
                holder.actions = actions
                actions.perform(spec)
            })
        case .mediaRemote:
            // Power while off or idle; previous / play-pause / next below the text and a volume slider under them while it plays.
            guard let id = card.sheet, let config = MediaRemotes.config(id: id), let remote = controller.remote(id) else { return nil }
            let live = controller.store.entity(config.mediaEntityId).state
            let state = live?.showing(remote.displayedState(config.mediaEntityId)).showing(holder.actions?.shown(config.mediaEntityId))
            let provider = MediaTransportActions(config: config)
            let specs = provider.actions(for: state)
            let volumeState = controller.store.entity(config.volumeEntityId).state
            let volume = RemoteTileSupport.showsVolume(config: config, specs: specs, volume: volumeState)
                ? (percent: remote.volumePercent, commit: { (percent: Int) in remote.setVolume(percent: percent) }) : nil
            return Provision(specs: specs, candidates: provider.stateTextCandidates, run: { spec in
                if spec.id == PowerToggleActions.actionId {
                    _ = remote.press(config.power)
                    return
                }
                let actions = holder.actions ?? OptimisticActions(store: controller.store, rules: [config.mediaEntityId: .liveChange], caller: controller.caller)
                holder.actions = actions
                actions.perform(spec, failing: config.mediaEntityId)
            }, volume: volume, failed: holder.actions?.isFailed(config.mediaEntityId) == true || remote.volumeWriteFailed)
        case .none, .bathroomFan, .garageDoor, .command:
            // The fan and the garage door have their own tiles (``view(for:)``); a plain command has no disc.
            return nil
        case .lock, .momentaryCommand, .hotFlash, .alarmMode, .sprinkler, .roomLightsPower, .selection:
            // Not a room card's class: Security, Admin, the bed sheet, Quick Links, Sprinklers, the Home overview and the selection pages draw
            // theirs. A room card that reaches here means the catalog gained a class this port has not wired.
            assertionFailure("Room card \(card.id) has the tile action class \(TileActionCatalog.kind(of: card)), which UKRoomCards does not draw")
            return nil
        }
    }

    /// `RoomCardTile`: a tile whose kind follows the card's semantics, in its device's colour family. A card that carries actions (PCs, towel
    /// racks, the vacuum, a remote's Power) is classified by `TileActionCatalog` and draws the provider's discs: a PC or towel rack is an action
    /// tile (text and disc), the vacuum and a remote are navigation tiles with discs beside the chevron.
    private func cardTile(_ card: RoomCard, bed: BedSideController? = nil) -> UKGlassTileView {
        let controller = self.controller
        let viewer = self.viewer
        let clock = self.clock
        let holder = holders[card.id] ?? UKActionsHolder()
        holders[card.id] = holder
        let slider = UKTileVolumeSlider(title: card.title, percent: 0, identifier: "room.card.\(card.title).volume")
        let activate: () -> Void = { [weak self] in
            guard let self else { return }
            if self.controller.tap(card) == .openSheet { self.open(card) }
        }
        func model() -> UKGlassTileModel {
            let display = controller.display(card, viewer: viewer.resident)
            let provision = self.provision(card, holder: holder, bed: bed, activate: activate)
            let failed = controller.isFailed(card) || (holder.actions?.isFailed(card.entityId) ?? false) || (provision?.failed ?? false)
            var face = RoomTileFace.resolve(card, entity: controller.displayEntity(card), display: display, running: controller.usesAlternate(card))
            var deviceSubtitle: String?
            if let bed {
                clock.setRunning(bed.hotFlashHolding)
                let now = bed.hotFlashHolding ? clock.now : Date()
                face = RoomCardView.face(bed)
                deviceSubtitle = bed.tileSubtitle(now: now)
            }
            let subtitle = failed ? "Didn't Respond" : provision?.stateLine ?? (deviceSubtitle ?? display.subtitle)
            if let provision {
                var model = UKGlassTileModel(
                    title: display.title, subtitle: subtitle, symbol: SymbolMap.symbol(for: card.icon), family: face.family, isActive: provision.isActive ?? face.isActive,
                    isUnavailable: card.hasInteraction && !display.isEnabled, isError: failed,
                    behavior: TileBehavior(TileActionCatalog.classification(of: card), primary: provision.specs.first?.id),
                    actions: provision.specs.items, identifier: "room.card.\(card.title)")
                // On the body only: a navigation card's hint set from outside would also be read on its disc (bed, purifier, humidifier).
                if model.behavior == .navigate { model.bodyHint = "Opens \(display.title)" }
                model.stateCandidates = provision.candidates
                model.accessoryShown = provision.volume != nil
                model.reapplyGeneration = controller.store.reapplyGeneration
                if let volume = provision.volume {
                    slider.title = display.title
                    slider.onCommit = volume.commit
                    slider.update(percent: volume.percent, isDisabled: false)
                }
                return model
            }
            return UKGlassTileModel(title: display.title, subtitle: subtitle, symbol: SymbolMap.symbol(for: card.icon), family: face.family,
                                    isActive: face.isActive, isUnavailable: card.hasInteraction && !display.isEnabled, isError: failed,
                                    kind: kind(display.semantics), identifier: "room.card.\(card.title)")
        }
        let tile = UKGlassTileView(model: model(), environment: environment)
        if TileActionCatalog.kind(of: card) == .mediaRemote, bed == nil { tile.setAccessory(slider) }
        UKRoomsBind.tile(tile, bag: bag, environment: environment, action: { [weak self] in
            guard let self else { return }
            if self.controller.tap(card) == .openSheet { self.open(card) }
        }, perform: { [weak self] id in
            guard let self else { return }
            if let provision = self.provision(card, holder: holder, bed: bed, activate: activate), let spec = provision.specs.first(where: { $0.id == id }) {
                provision.run(spec)
            }
        }, model: model)
        return tile
    }

    private func bedTile(_ card: RoomCard, bed: BedSideController) -> UIView { cardTile(card, bed: bed) }

    // MARK: Bathroom fan

    /// The bathroom fan's tile (`BathroomFanRoomTile`): opens the fan sheet, with Lock and Power as trailing action discs left of the chevron
    /// (`FanRailActions` mapped to `TileActionItem`). One short status line, a live countdown while the timer runs, and discs that dim in
    /// place while their switch is unavailable. Identifiers `room.card.<title>.action.lock|power`.
    private func fanTile(_ card: RoomCard, fan: BathroomFanController) -> UIView {
        var environment = self.environment
        environment.singleLineSubtitle = true
        let clock = self.clock
        /// Lock and Power from `FanRailActions` (the provider owns verbs, glyphs and what dims), fed the shown state.
        func specs() -> [TileActionSpec] {
            let commands = fan.commands
            func shown(_ id: String) -> EntityState? { commands.entity(id)?.showing(commands.displayed(id)) }
            return FanRailActions(config: fan.config, lockState: shown(fan.config.lockEntityId), timerPending: fan.timerPending, autoUnlock: fan.autoUnlock)
                .actions(for: shown(fan.config.powerEntityId))
        }
        let candidates = FanRailActions(config: fan.config, lockState: nil, timerPending: false, autoUnlock: false).stateTextCandidates
        func model() -> UKGlassTileModel {
            clock.setRunning(fan.showsCountdown)
            let now = fan.showsCountdown ? clock.now : Date()
            var model = UKGlassTileModel(title: card.title, subtitle: fan.tileStatusText(at: now), symbol: SymbolMap.symbol(for: card.icon), family: .air,
                                         isActive: fan.powerAvailable && fan.powerOn, isError: fan.commandFailed,
                                         behavior: TileBehavior(TileActionCatalog.classification(of: card), primary: nil), actions: specs().items,
                                         identifier: "room.card.\(card.title)")
            model.spokenValue = fan.tileSpokenValue(at: now)
            model.stateCandidates = candidates
            return model
        }
        let tile = UKGlassTileView(model: model(), environment: environment)
        UKRoomsBind.tile(tile, bag: bag, environment: environment, action: { [weak self] in self?.open(card) }, perform: { id in
            // Both send the fan script's explicit target state (the controller never toggles).
            switch id {
            case "lock": fan.setLocked(!fan.locked)
            case "power": fan.setPower(!fan.powerOn)
            default: break
            }
        }, model: model)
        return tile
    }

    // MARK: Garage door

    /// The Security page's door control (`GarageDoorTile`), titled as the room card: the same action tile, with the card's identifier.
    private func garageTile(_ card: RoomCard, tile config: SecurityConfig.Tile) -> UIView {
        let connection = context.connection
        let binder = UKGarageDoorTileBinder(tile: config, context: context, caller: controller.caller,
                                            canSend: { connection.map { SecurityScreen.canSend($0.status) } ?? true },
                                            identifier: "room.card.\(card.title)")
        garageDoors.append(binder)
        return binder.view
    }

    private var garageDoors: [UKGarageDoorTileBinder] = []
}
#endif
