#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - Injected canonical domain source

/// Parent integration can supply fixture maps/services without fetching or operating a house.
@MainActor
struct UKServerUIVacuumEnvironment {
    var loader: (ServerUIVacuumDescriptor) -> ValetudoMapLoader = { _ in ValetudoMapLoader() }
    var services: Set<String>?
    var serviceNames: (() async throws -> Set<String>)?
    var mapURL: ((ServerUIVacuumDescriptor, EntityState?) -> URL?)?
}

@MainActor
@Observable
final class UKServerUIVacuumSource {
    let descriptor: ServerUIVacuumDescriptor
    let controller: VacuumController?
    let autoClean: VacuumAutoCleanController?
    let mapState: VacuumMapState
    private(set) var failure: String?
    var draft: MapGridRect? { didSet { if draft != oldValue { draftActive = true } } }
    private(set) var draftActive = false
    private(set) var report: VacuumOutcomeContract?
    private(set) var cardCallCount = 0
    private let cardActions: OptimisticActions?
    @ObservationIgnored private let context: UKContext
    @ObservationIgnored private let mapURL: (ServerUIVacuumDescriptor, EntityState?) -> URL?
    @ObservationIgnored private let bag = UKObservationBag()
    @ObservationIgnored private var mounted: Set<ObjectIdentifier> = []
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var serviceTask: Task<Void, Never>?
    @ObservationIgnored private var mapKey: MapKey?
    @ObservationIgnored private var announcedControllerError: String?
    private struct MapKey: Equatable { let url: URL?; let live: Bool }

    init(descriptor: ServerUIVacuumDescriptor, context: UKContext, environment: UKServerUIVacuumEnvironment) {
        self.descriptor = descriptor
        self.context = context
        mapURL = environment.mapURL ?? { _, camera in
            context.connection.flatMap { ValetudoMapLoader.pictureURL(camera, server: $0.server) }
        }
        let vacuum = descriptor.configuration
        let loader = environment.loader(descriptor)
        mapState = VacuumMapState(vacuum: vacuum, loader: loader)
        controller = (context.caller ?? context.connection).map {
            VacuumController(vacuum: vacuum, store: context.store, caller: $0,
                reconciliationEntities: Dictionary(uniqueKeysWithValues: descriptor.outcomeReconciliations.map { ($0.roomId, $0.entityId) }))
        }
        controller?.services = environment.services
        autoClean = descriptor.autoCleanControl.flatMap { control in
            (context.caller ?? context.connection).map {
                VacuumAutoCleanController(store: context.store, caller: $0, controls: [control.configuration])
            }
        }
        cardActions = (context.caller ?? context.connection).map {
            OptimisticActions(store: context.store, rules: [descriptor.entityId: .liveChange], caller: $0)
        }
        let serviceNames = environment.serviceNames ?? context.connection.map { connection in
            { @MainActor in try await connection.serviceNames() }
        }
        if environment.services == nil, let serviceNames {
            serviceTask = Task { @MainActor [weak self] in
                do { self?.controller?.services = try await serviceNames() }
                catch { self?.fail("Home Assistant services could not be loaded.") }
            }
        }
        bag.observe { [weak self] in self?.syncMap() }
        bag.observe { [weak self] in
            guard let self else { return }
            let message = self.controller?.cleanError
            guard message != self.announcedControllerError else { return }
            self.announcedControllerError = message
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    deinit {
        mapTask?.cancel()
        serviceTask?.cancel()
    }

    var hasPendingCommand: Bool {
        controller?.hasPendingCommand == true || autoClean?.hasPendingIntent == true || cardCallCount > 0
            || cardActions?.isPending(descriptor.entityId) == true
    }

    var isPinned: Bool { hasPendingCommand || draftActive || report != nil }

    var cardState: EntityState? {
        context.store.entity(descriptor.entityId).state.map { $0.showing(cardActions?.shown(descriptor.entityId)) }
    }

    var cardFailed: Bool { cardActions?.isFailed(descriptor.entityId) == true }

    /// Page-card discs retain the canonical start/pause and dock provider, not the sheet's coordinated clean script.
    func cardCommands(_ commands: [ServerUICompositionDocument.VacuumCardCommand]) -> [TileActionSpec] {
        let available = VacuumActions(entityId: descriptor.entityId).actions(for: cardState)
        return commands.compactMap { command in
            guard var action = available.first(where: { $0.id == command.rawValue }) else { return nil }
            if let call = action.call, controller?.services?.contains("\(call.domain).\(call.service)") != true {
                action.phase = .unavailable
            }
            return action
        }
    }

    func runCard(_ command: ServerUICompositionDocument.VacuumCardCommand) {
        guard let action = cardCommands([command]).first, action.phase == .ready, let call = action.call, let cardActions else {
            fail("The vacuum command is no longer available."); return
        }
        failure = nil
        cardCallCount += 1
        let task = cardActions.perform(call, showing: action.optimistic + action.tracking, failing: descriptor.entityId)
        Task { @MainActor [self] in
            await task.value
            cardCallCount -= 1
            if cardFailed { fail("The vacuum did not respond.") }
        }
    }

    /// There is one map loader per retained source. Only visible map/editor consumers keep it running.
    func mounted(_ view: UIView, visible: Bool) {
        if visible { mounted.insert(ObjectIdentifier(view)) } else { mounted.remove(ObjectIdentifier(view)) }
        syncMap()
    }

    private func syncMap() {
        _ = mapState.loader.map
        _ = mapState.loader.provenance
        mapState.refresh()
        guard !mounted.isEmpty else {
            mapTask?.cancel(); mapTask = nil; mapKey = nil
            return
        }
        let config = descriptor.configuration
        let camera = context.store.entity(config.mapCameraEntityId).state
        let url = mapURL(descriptor, camera)
        let key = MapKey(url: url, live: controller?.status.primaryAvailable == true)
        guard key != mapKey else { return }
        mapKey = key
        mapTask?.cancel()
        let loader = mapState.loader
        mapTask = Task { @MainActor in await loader.run(url: key.url, live: key.live) }
    }

    func beginDraft() {
        guard !draftActive else { return }
        draft = controller?.areaSelection
        draftActive = true
    }

    @discardableResult
    func useDraft() -> Bool {
        guard let controller, !controller.normalCommandsDisabled, controller.selectedZones.isEmpty, mapState.isReady,
              let draft, mapState.allows(draft) else { fail("The area is no longer available for cleaning."); return false }
        controller.areaSelection = draft
        draftActive = false
        failure = nil
        return true
    }

    func discardDraft() {
        draft = controller?.areaSelection
        draftActive = false
    }

    func clearArea() {
        guard let controller, controller.roomsEditable else { fail("The cleaning area cannot be changed right now."); return }
        controller.areaSelection = nil
        failure = nil
    }

    func openReport(_ value: VacuumOutcomeContract) { report = value }
    func closeReport() { report = nil }

    func command(_ kind: VacuumController.Action.Kind) -> VacuumController.Action? {
        guard let controller else { return nil }
        let kind: VacuumController.Action.Kind = kind == .clean && controller.areaSelection != nil ? .cleanArea : kind
        let setup = controller.showsCleaningSetup ? [controller.cleanAction,
            controller.areaCleanAction(mapReady: mapState.isReady, selectionAllowed: mapState.allows(controller.areaSelection))] : []
        var action = (setup
            + controller.runtimeActions + controller.dockActions).first { $0.kind == kind }
        let service: String
        switch kind {
        case .clean: service = descriptor.cleanScript
        case .cleanArea: service = descriptor.areaCleaning?.script ?? ""
        case .cleanDock, .stopDockClean: service = descriptor.dockControls?.cleanScript ?? ""
        case .dryMops, .stopDrying: service = descriptor.dockControls?.dryScript ?? ""
        case .emptyBin: service = "button.press"
        case .resume: service = "vacuum.start"
        case .pause: service = "vacuum.pause"
        case .cancelResume: service = "vacuum.stop"
        case .stop: service = controller.liveState == "error" ? "vacuum.stop" : "vacuum.return_to_base"
        case .dock, .cancelSession: service = "vacuum.return_to_base"
        }
        if controller.services?.contains(service) != true {
            action?.isDisabled = true
            action?.detail = "This service is not available in Home Assistant."
        }
        return action
    }

    func run(_ kind: VacuumController.Action.Kind) {
        guard let action = command(kind), !action.isDisabled, let controller else {
            fail("The vacuum command is no longer available."); return
        }
        failure = nil
        controller.run(action.kind, pixelSize: mapState.scene?.interactionGeometry.pixelSize)
    }

    private struct SwitchTicket: Equatable {
        let revision: Int
        let state: String
        let area: MapGridRect?
        let rooms: [String]
        let services: Set<String>?
    }
    private var switchTicket: SwitchTicket? {
        controller.map { .init(revision: $0.intentRevision, state: $0.liveState, area: $0.areaSelection,
                              rooms: $0.selectedZones.map(\.entityId), services: $0.services) }
    }

    /// A mandatory native question cannot be removed by authoring. Its answer revalidates the captured intent.
    func switchTarget(_ mode: ServerUICompositionDocument.VacuumTarget, from presenter: UIViewController, proceed: @escaping () -> Void) {
        guard let controller, controller.roomsEditable else { fail("The vacuum is no longer ready."); return }
        let needsQuestion = mode == .rooms ? controller.areaSelection != nil : !controller.selectedZones.isEmpty
        let ticket = switchTicket
        let perform = { [weak self] in
            guard let self, self.switchTicket == ticket, controller.roomsEditable,
                  mode == .rooms || (self.mapState.isReady && (controller.selectedZones.isEmpty
                    || controller.services?.contains("input_boolean.turn_off") == true)) else {
                self?.fail("The cleaning target changed. Choose the target again."); return
            }
            if mode == .rooms { controller.areaSelection = nil }
            else { controller.clearRoomsForArea() }
            self.failure = nil
            proceed()
        }
        if needsQuestion {
            UKAlerts.alert(mode == .rooms ? AlertCopy.switchToRooms : AlertCopy.switchToArea, from: presenter, onConfirm: perform)
        } else { perform() }
    }

    func choose(_ entityID: String, selection: ServerUICompositionDocument.VacuumSelection, from presenter: UIViewController) {
        guard let controller else { fail("The vacuum connection is unavailable."); return }
        if selection == .autoClean {
            guard let room = descriptor.configuration.autoCleanDisabledRooms.first(where: { $0.entityId == entityID }),
                  !VacuumStatusResolver.isUnavailable(context.store.entity(entityID).state?.state),
                  controller.services?.contains("switch.turn_on") == true,
                  controller.services?.contains("switch.turn_off") == true else {
                fail("Automatic room selection is unavailable."); return
            }
            failure = nil
            controller.toggleAutoClean(room)
        } else {
            guard controller.roomsEditable, let room = descriptor.configuration.zones.first(where: { $0.entityId == entityID }),
                  controller.services?.contains("input_boolean.turn_on") == true,
                  controller.services?.contains("input_boolean.turn_off") == true else {
                fail("Room selection is unavailable."); return
            }
            if controller.roomToggleNeedsConfirmation(room) {
                switchTarget(.rooms, from: presenter) { [weak self, weak presenter] in
                    guard let presenter else { return }
                    self?.choose(entityID, selection: .rooms, from: presenter)
                }
            } else {
                failure = nil
                controller.toggleRoom(room)
            }
        }
    }

    func fail(_ message: String) {
        failure = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
#endif
