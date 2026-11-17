#if os(iOS)
import HassCore
import Observation
import UIKit

// MARK: - Typed source adapters

/// Missing HA data is an explicit value state, not a coerced false, zero or successful empty string.
enum UKServerUIValue<Value> {
    case ready(Value)
    case loading
    case unavailable

    var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

/// Per-document source adapters. Views still observe only the EntityBoxes and overlays they read.
@MainActor
final class UKServerUIBindings {
    typealias D = ServerUICompositionDocument
    let context: UKContext
    private(set) var definitions: [String: D.Source]
    private(set) var powers: [String: UKServerUIPowerSource]
    private(set) var alarms: [String: UKServerUIAlarmSource]
    private(set) var weather: [String: UKServerUIWeatherSource] = [:]
    private(set) var lights: [String: ServerUIHomeLightSource] = [:]
    private var homeLightActions: OptimisticActions?
    private(set) var climates: [String: ServerUIClimateAdapter]
    private var climateController: ClimateController?
    let roomVisits: ServerUIRoomVisits?
    private(set) var devices: [String: ServerUIRoomDeviceSource]
    private let scheduleStorage: (any HassScheduleStoring)?
    private(set) var bedroomProviders: [String: UKServerUIBedroomProvider]
    private(set) var bedroomRegistry: UKServerUIBedroomRegistry?
    private(set) var deviceProviders: ServerUIDeviceProviders?
    private(set) var remotes: [String: ServerUIRemoteSession]
    private var remoteProviders: [String: ServerUIRemoteSession]
    private(set) var vacuums: [String: UKServerUIVacuumSource]
    private let vacuumEnvironment: UKServerUIVacuumEnvironment
    private(set) var cameras: [String: UKServerUICameraSource]
    let cameraPool: CameraStreamPool
    private let weatherReader: ServerUIWeatherReader?
    private let cameraReader: UKCameraReadProvider?
    /// The `app-state@1` values: window, clock, system, notifications and preferences (``UKServerUIAppStateSource``).
    let appState: UKServerUIAppStateSource

    init(sources: [D.Source], context: UKContext,
         scheduleStorage: (any HassScheduleStoring)? = nil,
         bedroomProviders: [String: UKServerUIBedroomProvider] = [:],
         bedroomRegistry: UKServerUIBedroomRegistry? = nil,
         remoteProviders: [String: ServerUIRemoteSession] = [:],
         deviceProviders: ServerUIDeviceProviders? = nil,
         vacuums: UKServerUIVacuumEnvironment = .init(),
         cameraPool: CameraStreamPool = .shared,
         weatherReader: ServerUIWeatherReader? = nil, cameraReader: UKCameraReadProvider? = nil) {
        self.context = context
        appState = context.appState ?? UKServerUIAppStateSource(push: context.push)
        self.weatherReader = weatherReader
        self.cameraReader = cameraReader
        roomVisits = context.caller.map { ServerUIRoomVisits(caller: $0) }
        let storage: (any HassScheduleStoring)? = scheduleStorage
            ?? (context.caller as? any HassScheduleStoring)
            ?? (context.caller == nil ? context.connection : nil)
        self.scheduleStorage = storage
        self.bedroomProviders = bedroomProviders
        self.bedroomRegistry = bedroomRegistry
        self.remoteProviders = remoteProviders
        self.deviceProviders = deviceProviders
        remotes = Dictionary(uniqueKeysWithValues: sources.compactMap {
            guard case .mediaRemote(let id, let providerID) = $0, let session = remoteProviders[providerID] else { return nil }
            return (id, session)
        })
        vacuumEnvironment = vacuums
        self.cameraPool = cameraPool
        definitions = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        powers = Dictionary(uniqueKeysWithValues: sources.compactMap {
            if case .powerToggle = $0 { return ($0.id, UKServerUIPowerSource(context: context)) }
            return nil
        })
        alarms = Dictionary(uniqueKeysWithValues: sources.compactMap {
            if case .alarmMode(_, let entityID) = $0 {
                return ($0.id, UKServerUIAlarmSource(entityID: entityID, context: context))
            }
            return nil
        })
        let climateController = context.caller.map {
            ClimateController(store: context.store, caller: $0, configuredEntityIds: Self.climateTargets(sources))
        }
        self.climateController = climateController
        climates = Dictionary(uniqueKeysWithValues: sources.compactMap {
            guard case .climate(_, let configuration) = $0 else { return nil }
            return ($0.id, ServerUIClimateAdapter(configuration: configuration, store: context.store, caller: context.caller,
                                                  controller: climateController))
        })
        devices = Dictionary(uniqueKeysWithValues: sources.compactMap {
            guard case .roomDevice(_, let descriptor) = $0, let caller = context.caller ?? context.connection else { return nil }
            return ($0.id, ServerUIRoomDeviceSource(descriptor: descriptor, store: context.store, caller: caller, storage: storage))
        })
        self.vacuums = Dictionary(uniqueKeysWithValues: sources.compactMap {
            if case .vacuum(_, let descriptor) = $0 {
                return ($0.id, UKServerUIVacuumSource(descriptor: descriptor, context: context, environment: vacuums))
            }
            return nil
        })
        cameras = Dictionary(uniqueKeysWithValues: sources.compactMap {
            guard case .camera(_, let configuration) = $0 else { return nil }
            return ($0.id, UKServerUICameraSource(configuration: configuration, context: context, pool: cameraPool, reader: cameraReader))
        })
        applyHomeSources(sources)
    }

    /// Retains action models on ordinary publications; a pending target cannot be rebound or removed.
    func validateReplacement(_ sources: [D.Source]) throws {
        let next = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let changed = Set(definitions.keys).filter { definitions[$0] != next[$0] }
        if !changed.isEmpty, roomVisits?.pendingCount ?? 0 > 0 {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
        }
        if !changed.isEmpty, bedroomProviders.values.contains(where: \.protectsPublication) {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
        }
        // A dependency change can retarget an otherwise identical model descriptor.
        if !changed.isEmpty, powers.values.contains(where: \.hasPendingIntent)
            || alarms.values.contains(where: \.hasPendingIntent)
            || lights.values.contains(where: \.hasPendingIntent)
            || climates.values.contains(where: \.hasPendingIntent)
            || devices.values.contains(where: \.hasPendingIntent)
            || vacuums.values.contains(where: \.isPinned)
            || cameras.values.contains(where: \.hasPendingIntent) {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
        }
        for source in sources {
            if case .camera(_, let configuration) = source, !cameraPool.accepts(configuration.camera(title: "")) {
                throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
            }
        }
        for id in changed where remotes[id]?.hasInteraction == true {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
        }
    }

    func replaceProviders(bedrooms: [String: UKServerUIBedroomProvider], remotes: [String: ServerUIRemoteSession]) {
        bedroomProviders = bedrooms
        remoteProviders = remotes
    }

    func apply(_ sources: [D.Source]) {
        let next = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        powers = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .powerToggle = source else { return nil }
            let retained = definitions[source.id] == source ? powers[source.id] : nil
            return (source.id, retained ?? UKServerUIPowerSource(context: context))
        })
        alarms = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .alarmMode(_, let entityID) = source else { return nil }
            let retained = definitions[source.id] == source ? alarms[source.id] : nil
            return (source.id, retained ?? UKServerUIAlarmSource(entityID: entityID, context: context))
        })
        devices = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .roomDevice(_, let descriptor) = source, let caller = context.caller ?? context.connection else { return nil }
            let retained = definitions[source.id] == source ? devices[source.id] : nil
            return (source.id, retained ?? ServerUIRoomDeviceSource(descriptor: descriptor, store: context.store, caller: caller, storage: scheduleStorage))
        })
        remotes = Dictionary(uniqueKeysWithValues: sources.compactMap {
            guard case .mediaRemote(let id, let providerID) = $0, let session = remoteProviders[providerID] else { return nil }
            return (id, session)
        })
        vacuums = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .vacuum(_, let descriptor) = source else { return nil }
            let retained = definitions[source.id] == source ? vacuums[source.id] : nil
            return (source.id, retained ?? UKServerUIVacuumSource(descriptor: descriptor, context: context, environment: vacuumEnvironment))
        })
        cameras = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .camera(_, let configuration) = source else { return nil }
            let retained = definitions[source.id] == source ? cameras[source.id] : nil
            return (source.id, retained ?? UKServerUICameraSource(configuration: configuration, context: context, pool: cameraPool, reader: cameraReader))
        })
        applyHomeSources(sources)
        let targetsChanged = Self.climateTargets(sources) != Self.climateTargets(Array(definitions.values))
        if targetsChanged {
            climateController = context.caller.map { ClimateController(store: context.store, caller: $0,
                                                                       configuredEntityIds: Self.climateTargets(sources)) }
        }
        climates = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .climate(_, let configuration) = source else { return nil }
            let retained = !targetsChanged && definitions[source.id] == source ? climates[source.id] : nil
            return (source.id, retained ?? ServerUIClimateAdapter(configuration: configuration, store: context.store, caller: context.caller,
                                                                 controller: climateController))
        })
        definitions = next
    }

    private func applyHomeSources(_ sources: [D.Source]) {
        weather = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .homeWeather(_, let configuration) = source else { return nil }
            let retained = definitions[source.id] == source ? weather[source.id] : nil
            return (source.id, retained ?? UKServerUIWeatherSource(configuration: configuration, context: context, reader: weatherReader))
        })
        let targets = Self.homeLightTargets(sources)
        let changed = homeLightActions == nil || targets != Self.homeLightTargets(Array(definitions.values))
        if changed {
            homeLightActions = (context.caller ?? context.connection).map {
                OptimisticActions(store: context.store, rules: Dictionary(uniqueKeysWithValues: targets.map { ($0, .liveChange) }), caller: $0)
            }
        }
        lights = Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            guard case .homeLight(_, let entityId, let members) = source, let caller = context.caller ?? context.connection else { return nil }
            let retained = !changed && definitions[source.id] == source ? lights[source.id] : nil
            return (source.id, retained ?? ServerUIHomeLightSource(entityId: entityId, memberEntityIds: members, caller: caller,
                actions: homeLightActions, readMember: { [context] in context.store.entity($0).state }) { [context] in
                context.store.entity(entityId).state
            })
        })
    }

    private static func homeLightTargets(_ sources: [D.Source]) -> Set<String> {
        Set(sources.flatMap { source -> [String] in
            if case .homeLight(_, let entityId, let members) = source { return [entityId] + members }
            return []
        })
    }

    /// The projected status of a source; `words` are a room overview tile's own (`sh.state-words@1`).
    func status(_ sourceId: String, words: ServerUIStateWords? = nil) -> ServerUIHomeStatus.Value? {
        guard case .homeStatus(_, let configuration) = definitions[sourceId] else { return nil }
        return ServerUIHomeStatus.project(configuration, pending: context.valuesPending,
                                          redacted: ScreenshotPrivacy.isRedacting && [.occupancy, .entity].contains(configuration.projection),
                                          words: words, read: homeEntity)
    }

    /// Shell binds navigation copy over exactly the sources its overview tiles use.
    func homeOverviewSubtitle(_ kind: RoomOverviewKind, sourceIds: [String]) throws -> String? {
        guard [.lights, .occupancy, .contacts].contains(kind), !sourceIds.isEmpty, Set(sourceIds).count == sourceIds.count else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        var groups: [RoomGroup] = []
        for id in sourceIds {
            guard case .homeStatus(_, let config) = definitions[id], config.format == .room,
                  config.projection.rawValue == kind.rawValue else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            groups.append(RoomGroup("", entityId: config.rangeEntityId, config.entityIds.map { RoomGroupItem("", $0) }))
        }
        for id in sourceIds {
            if let value = status(id), ["loading", "unavailable", "hidden", "empty"].contains(value.state) { return value.text }
        }
        return RoomOverview.sheetSubtitle(kind, groups: groups, read: homeEntity)
    }

    private func homeEntity(_ id: String) -> EntityState? {
        let entity = context.store.entity(id).state
        return entity?.isUnavailable == false ? entity?.showing(homeLightActions?.shown(id)) : entity
    }

    private static func climateTargets(_ sources: [D.Source]) -> [String] {
        Set(sources.flatMap { source -> [String] in
            guard case .climate(_, let configuration) = source else { return [] }
            return configuration.commandEntityIds
        }).sorted()
    }

    /// Gives expressions the environment they are evaluated in (entity boxes, the optimistic overlay, the viewer, app state). The
    /// renderer sets it once it exists; without one an expression sees an empty house and is unavailable.
    var readerProvider: (() -> UKServerUIReader)?

    /// A text slot's value: a literal, a typed read, or an operand (`sh.rules@1`), each with the fallback it carries
    /// (``ServerUIStringResolver``). Evaluated inside the caller's observation, so it follows exactly the entities it reads.
    func string(_ value: D.StringValue) -> UKServerUIValue<String> {
        let readValue: (D.Read) -> ServerUIReadResult = { self.textResult($0) }
        let result: ServerUIReadResult
        if let environment = readerProvider?() {
            result = ServerUIStringResolver.resolve(value, read: readValue, in: environment)
        } else if case .expression = value {
            return .unavailable
        } else {
            result = ServerUIStringResolver.resolve(value, read: readValue, in: UKEmptyReading())
        }
        switch result {
        case .value(.string(let text)): return .ready(text)
        case .loading: return .loading
        case .value, .unavailable: return .unavailable
        }
    }

    /// A typed read as text for a text slot: a value that is not text is unavailable.
    func textResult(_ read: D.Read) -> ServerUIReadResult {
        switch self.read(read) {
        case .loading: .loading
        case .unavailable: .unavailable
        case .ready(.string(let text)): .value(.string(text))
        case .ready: .unavailable
        }
    }

    func entityID(for sourceID: String) -> UKServerUIValue<String> {
        guard let source = definitions[sourceID], let entityId = source.entityId else { return .unavailable }
        let value: UKServerUIValue<String>
        switch entityId {
        case .literal(let id): value = .ready(id)
        case .read(let read):
            switch self.read(read) {
            case .ready(.string(let id)): value = .ready(id)
            case .loading: value = .loading
            default: value = .unavailable
            }
        }
        guard case .ready(let id) = value else { return value }
        guard id.utf16.count <= 160,
              id.range(of: "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$", options: .regularExpression) == id.startIndex..<id.endIndex else {
            return .unavailable
        }
        if case .powerToggle = source,
           !D.Source.powerEntityDomains.contains(String(id.prefix(while: { $0 != "." }))) { return .unavailable }
        return .ready(id)
    }

    func read(_ read: D.Read) -> UKServerUIValue<JSONValue> {
        guard let source = definitions[read.sourceId] else { return .unavailable }
        if case .homeStatus = source, let status = status(read.sourceId) {
            switch read.path {
            case ["stateText"]: return .ready(.string(status.text))
            case ["state"]: return .ready(.string(status.state))
            case ["phase"]: return .ready(.string(status.unavailable ? "unavailable" : status.state == "loading" ? "loading" : "ready"))
            case ["isActive"]: return .ready(.bool(status.active))
            case ["count"], ["total"], ["unavailableCount"]:
                // The counts of `sh.home-status-counts@1`: a number once the members have answered, loading until then.
                if status.state == "loading" { return .loading }
                let number: Int? = read.path == ["count"] ? status.count : read.path == ["total"] ? status.total : status.unavailableCount
                return status.state == "hidden" ? .unavailable : number.map { .ready(.number(Double($0))) } ?? .unavailable
            default: return .unavailable
            }
        }
        if case .appState(_, let topic) = source, read.path.count == 1 {
            switch appState.read(topic, field: read.path[0]) {
            case .value(let value): return .ready(value)
            case .loading: return .loading
            case .unavailable: return .unavailable
            }
        }
        if case .todoCounts(_, let configuration) = source {
            let text: String
            let phase: String
            if context.valuesPending {
                text = configuration.loadingText
                phase = "loading"
            } else if let result = ServerUITodoCounts.text(configuration: configuration, state: {
                self.context.store.entity($0).state?.state
            }) {
                text = result
                phase = "ready"
            } else {
                text = configuration.unavailableText
                phase = "unavailable"
            }
            switch read.path {
            case ["stateText"]: return .ready(.string(text))
            case ["phase"]: return .ready(.string(phase))
            default: return .unavailable
            }
        }
        if case .roomDevice = source {
            guard let device = devices[read.sourceId] else { return .unavailable }
            if context.valuesPending { return .loading }
            if read.path == ["phase"] {
                return .ready(.string(device.hasPendingIntent ? "inFlight" : device.isUnavailable ? "unavailable" : "ready"))
            }
            if read.path == ["stateText"] { return device.isUnavailable ? .unavailable : .ready(.string(device.stateText)) }
            return .unavailable
        }
        if case .bedroom = source {
            guard let provider = bedroom(read.sourceId) else { return .unavailable }
            if context.valuesPending { return .loading }
            if read.path == ["phase"] { return .ready(.string(provider.available ? "ready" : "unavailable")) }
            guard read.path == ["stateText"] else { return .unavailable }
            switch provider {
            case .bed(let controller): return .ready(.string(controller.tileSubtitle()))
            case .wake(let controller): return .ready(.string(WakeLight.subtitle(controller.snapshot)))
            case .draft: return .unavailable
            }
        }
        if case .sprinklerState(_, let configuration) = source {
            guard read.path.count == 1, let field = read.path.first else { return .unavailable }
            if field == "phase" {
                if context.valuesPending { return .ready(.string("loading")) }
                let available = ServerUISprinklerState.value("available", configuration: configuration) {
                    self.context.store.entity($0).state
                }
                return .ready(.string(available == .bool(true) ? "ready" : "unavailable"))
            }
            if context.valuesPending { return .loading }
            guard let value = ServerUISprinklerState.value(field, configuration: configuration, entity: {
                self.context.store.entity($0).state
            }) else { return .unavailable }
            return .ready(value)
        }
        if case .vacuum = source {
            guard let controller = vacuums[read.sourceId]?.controller else { return .unavailable }
            if context.valuesPending { return .loading }
            switch read.path {
            case ["stateText"]: return .ready(.string(VacuumFormat.state(controller.statusState)))
            case ["batteryText"]: return .ready(.string(controller.batteryLabel))
            case ["phase"]: return .ready(.string(vacuums[read.sourceId]?.hasPendingCommand == true ? "inFlight" : controller.status.primaryAvailable ? "ready" : "unavailable"))
            default: return .unavailable
            }
        }
        if case .camera = source {
            guard read.path == ["phase"], let camera = cameras[read.sourceId] else { return .unavailable }
            return .ready(.string(camera.isPrivate ? "hidden" : context.valuesPending ? "loading"
                                  : camera.isAvailable ? camera.hasPendingIntent ? "inFlight" : "ready" : "unavailable"))
        }
        if case .inventorySummary(_, let configuration) = source {
            let text: String
            let phase: String
            if context.valuesPending {
                text = configuration.loadingText
                phase = "loading"
            } else if let summary = ServerUIInventorySummary.text(configuration: configuration, entity: {
                self.context.store.entity($0).state
            }) {
                text = summary
                phase = "ready"
            } else {
                text = configuration.unavailableText
                phase = "unavailable"
            }
            switch read.path {
            case ["stateText"]: return .ready(.string(text))
            case ["phase"]: return .ready(.string(phase))
            default: return .unavailable
            }
        }
        let entity = entityID(for: read.sourceId)
        guard case .ready(let id) = entity else {
            if case .loading = entity { return .loading }
            return .unavailable
        }
        switch source {
        case .haEntity:
            let state = context.store.entity(id).state
            if context.valuesPending { return .loading }
            guard let state, !state.isUnavailable else { return .unavailable }
            var value: JSONValue?
            if read.path == ["state"] { value = .string(state.state) }
            else if read.path.first == "attributes" {
                value = .object(state.attributes)
                for segment in read.path.dropFirst() { value = value?[segment] }
            }
            guard let value else { return .unavailable }
            switch (read.kind, value) {
            case (.string, .string), (.entityID, .string), (.boolean, .bool): return .ready(value)
            case (.number, .number(let number)) where number.isFinite: return .ready(value)
            default: return .unavailable
            }
        case .powerToggle:
            guard let power = powers[read.sourceId] else { return .unavailable }
            let state = power.projection(entityID: id, symbol: "")
            if context.valuesPending { return .loading }
            guard let field = read.path.first, read.path.count == 1 else { return .unavailable }
            switch field {
            case "stateText": return .ready(.string(state.text))
            case "phase":
                return .ready(.string(state.spec.phase == .ready ? "ready" : (state.spec.phase == .inFlight ? "inFlight" : "unavailable")))
            case "isError": return .ready(.bool(state.failed))
            case "isOn": return state.spec.phase == .unavailable ? .unavailable : .ready(.bool(state.spec.isOn == true))
            default: return .unavailable
            }
        case .alarmMode:
            guard read.path == ["phase"], let alarm = alarms[read.sourceId] else { return .unavailable }
            let phase = alarm.projection.spec.phase
            return .ready(.string(context.valuesPending ? "loading" : phase == .ready ? "ready" : phase == .inFlight ? "inFlight" : "unavailable"))
        case .securityDoor:
            // The door's phase comes from the entity alone: the tile that shows it is a `state-tile` (`ServerUIDoorLowering`).
            guard read.path == ["phase"], case .securityDoor(_, let entityID, _)? = definitions[read.sourceId] else { return .unavailable }
            if context.valuesPending { return .ready(.string("loading")) }
            let live = context.store.entity(entityID).state
            let sendable = context.caller != nil && context.connection.map({ SecurityScreen.canSend($0.status) }) != false
            return .ready(.string(sendable && !ScreenshotPrivacy.isRedacting && live?.isUnavailable == false ? "ready" : "unavailable"))
        case .climate:
            guard read.path.count == 1, let climate = climates[read.sourceId] else { return .unavailable }
            if read.path != ["phase"] {
                if context.valuesPending { return .loading }
                return climate.trackingValue(read.path[0]).map { .ready($0) } ?? .unavailable
            }
            return .ready(.string(context.valuesPending ? "loading" : climate.hasPendingIntent ? "inFlight" : climate.isEnabled ? "ready" : "unavailable"))
        case .householdAwayStatus:
            guard read.path.count == 1 else { return .unavailable }
            if context.valuesPending {
                return read.path == ["phase"] ? .ready(.string("loading")) : .loading
            }
            let entity = context.store.entity(id).state
            let snapshot = HouseholdAway.Snapshot(entity: entity)
            let recognized = entity.flatMap { HouseholdAway.State(rawValue: $0.state) } != nil
                && entity?.attributes["mode"]?.string.flatMap(HouseholdAway.Mode.init(rawValue:)) != nil
            if read.path == ["phase"] { return .ready(.string(snapshot.available && recognized ? "ready" : "unavailable")) }
            guard snapshot.available, recognized else { return .unavailable }
            switch read.path {
            case ["mode"]: return .ready(.string(snapshot.mode.rawValue))
            case ["state"]: return .ready(.string(snapshot.state.rawValue))
            default: return .unavailable
            }
        case .inventorySummary, .todoCounts, .roomNavigation, .roomDevice, .bedroom,
             .mediaRemote, .deviceProvider, .sprinklerState, .vacuum, .inventoryList, .todoCollection, .profileAccount, .camera, .settingsProvider, .appState, .pipeline:
            return .unavailable
        case .homeStatus, .homeWeather, .homeLight: return .unavailable
        }
    }

    /// Reads only the explicit entity box; missing values retain unavailable semantics.
    func roomEntity(_ sourceId: String) -> EntityState? {
        guard !context.valuesPending, case .haEntity = definitions[sourceId],
              let id = entityID(for: sourceId).value else { return nil }
        return context.store.entity(id).state
    }

    func roomVisible(_ visibility: D.RoomVisibility?) -> Bool {
        guard let visibility else { return true }
        if case .homeStatus = definitions[visibility.sourceId], let status = status(visibility.sourceId) {
            return visibility.states.contains(status.state)
        }
        guard let state = roomEntity(visibility.sourceId), !state.isUnavailable else { return false }
        return visibility.states.contains(state.state)
    }

    /// Missing and mismatched providers fail preparation, never render a plausible placeholder.
    func validateBedroomSources(_ sources: [D.Source], providers: [String: UKServerUIBedroomProvider]? = nil,
                                registry: UKServerUIBedroomRegistry? = nil) throws {
        if let registry = registry ?? bedroomRegistry {
            try registry.validate(sources, supplied: providers ?? bedroomProviders)
            return
        }
        for (index, source) in sources.enumerated() {
            guard case .bedroom(_, let id, let kind) = source else { continue }
            guard (providers ?? bedroomProviders)[id]?.kind == kind else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)/inputs/providerId")
            }
        }
    }

    func bedroom(_ sourceId: String) -> UKServerUIBedroomProvider? {
        guard case .bedroom(_, let id, _) = definitions[sourceId] else { return nil }
        return bedroomProviders[id]
    }

    func install(_ prepared: UKServerUIDeviceProviders) {
        bedroomProviders = prepared.bedrooms
        bedroomRegistry = prepared.bedroomRegistry
        remoteProviders = prepared.remotes
        deviceProviders = prepared.domain
    }
}

// MARK: - Canonical optimistic power

/// One configured model, retaining overlays by immutable target even when a read-derived target changes.
@MainActor
@Observable
final class UKServerUIPowerSource {
    struct Projection {
        let spec: TileActionSpec
        let text: String
        let failed: Bool
        let candidates: [String]
    }

    @ObservationIgnored private let context: UKContext
    private(set) var actions: [String: OptimisticActions] = [:]
    private var pendingNetworkCalls = 0

    init(context: UKContext) { self.context = context }

    var hasPendingIntent: Bool { pendingNetworkCalls > 0 || actions.contains { $0.value.isPending($0.key) } }

    func projection(entityID: String?, symbol: String) -> Projection {
        let provider = entityID.map { PowerToggleActions.entity($0, symbol: symbol) }
            ?? PowerToggleActions(entityId: "", symbol: symbol, feedback: .optimistic, turnOn: nil, turnOff: nil)
        let live = entityID.flatMap { context.store.entity($0).state }
        let optimistic = entityID.flatMap { actions[$0]?.shown($0) }
        let shown = live?.showing(optimistic)
        var spec = provider.actions(for: live?.isUnavailable == false ? shown : live)[0]
        if context.caller == nil { spec = spec.with(phase: .unavailable) }
        else if pendingNetworkCalls > 0, spec.phase != .unavailable { spec = spec.with(phase: .inFlight) }
        let failed = entityID.map { actions[$0]?.isFailed($0) == true } ?? false
        spec.isError = failed
        let unavailable = EntityState.isUnavailable(live?.state)
        let text = unavailable ? "Unavailable" : (failed ? "Didn't Respond" : (spec.isOn == true ? "On" : "Off"))
        return Projection(spec: spec, text: text, failed: failed, candidates: provider.stateTextCandidates)
    }

    /// Revalidates at gesture/confirmation time. The provider chooses an explicit on/off call, never toggle.
    func perform(entityID: String, spec: TileActionSpec) throws {
        guard D.Source.powerEntityDomains.contains(String(entityID.prefix(while: { $0 != "." }))),
              let caller = context.caller, spec.phase == .ready, spec.call != nil,
              projection(entityID: entityID, symbol: spec.symbol).spec == spec else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        let model = actions[entityID] ?? OptimisticActions(store: context.store, rules: [entityID: .liveChange], caller: caller)
        actions[entityID] = model
        pendingNetworkCalls += 1
        model.perform(spec, failing: entityID)
        Task { [self] in
            await model.waitForCalls()
            pendingNetworkCalls -= 1
        }
    }

    private typealias D = ServerUICompositionDocument
}
#endif
