import Foundation
import Observation

// MARK: - Injected climate adapter

/// One immutable source and its canonical command model, retained across compatible publications.
@MainActor @Observable
public final class ServerUIClimateAdapter {
    public let configuration: ServerUIClimateSource
    public let controller: ClimateController?
    @ObservationIgnored private let store: EntityStore
    public private(set) var commandCount = 0
    public private(set) var failureCount = 0
    /// Native gestures hold publication acceptance until the edit ends.
    private var editingControls: Set<String> = []

    /// Creates a server uiclimate adapter.
    public init(configuration: ServerUIClimateSource, store: EntityStore, caller: (any HassServiceCalling)?,
                scheduler: any RevertScheduler = TaskRevertScheduler(), controller: ClimateController? = nil) {
        self.configuration = configuration
        self.store = store
        self.controller = controller ?? caller.map { ClimateController(store: store, caller: $0, scheduler: scheduler,
                                                                      configuredEntityIds: configuration.commandEntityIds) }
    }

    public var lookup: EntityLookup { { [store] in store.entity($0).state } }
    public var target: String { configuration.target(lookup) }
    public var entity: EntityState? { store.entity(target).state }
    public var hasPendingIntent: Bool {
        !editingControls.isEmpty || commandCount > 0 || (controller?.pendingCommandCount ?? 0) > 0 || controller?.overlay.pending.isEmpty == false
    }
    /// Tells the session the control is being edited, so a live update does not overwrite the edit in progress.
    public func setEditing(_ editing: Bool, controlID: String) {
        if editing { editingControls.insert(controlID) } else { editingControls.remove(controlID) }
    }
    public var isEnabled: Bool {
        controller != nil && entity?.isUnavailable == false && configuration.isEnabled(state: shown)
    }
    /// The value to show for the entity, preferring a pending optimistic one.
    public func shown(_ id: String) -> String? { controller?.shown(id) ?? store.entity(id).state?.state }

    /// Two canonical readings remain separate lines at narrow room-tile widths.
    public var roomSubtitle: String? {
        guard let temperature = configuration.sensorEntityId.flatMap(lookup), !temperature.isUnavailable,
              let occupancy = configuration.occupancyEntityId.flatMap(lookup), !occupancy.isUnavailable else { return nil }
        return "\(ClimateLogic.temperature(ClimateLogic.number(.string(temperature.state)), unit: ClimateLogic.unit(of: temperature)))\n\(StateText.titleCase(occupancy.state))"
    }

    /// Tracking disclosure rows obey the same live policy as their destination controls.
    public func navigationEnabled(_ props: ServerUIClimateControl.Properties) -> Bool {
        guard props.kind == .link, let status = props.status else { return props.kind == .roomTile }
        let page: ClimateConfig.TrackingPage
        switch status.projection {
        case .trackingSelected: page = .selectedRooms
        case .trackingCritical: page = .criticalProtection
        case .trackingOccupiedOnly: return true
        default:
            return self.status(status) != nil && (entity?.domain != "select" || !ClimateLogic.selectOptions(entity).isEmpty)
        }
        return trackingSummary?.isEnabled(page) == true
    }

    /// The option currently selected for the control kind.
    public func selected(_ kind: ServerUIClimateControl.Kind) -> String? {
        switch kind {
        case .mode: controller?.shown("\(target)#hvac_mode") ?? entity?.state
        case .fan: controller?.shown("\(target)#fan_mode") ?? entity?.attributes["fan_mode"]?.string
        case .preset: controller?.shown("\(target)#preset_mode") ?? entity?.attributes["preset_mode"]?.string
        default: shown(target)
        }
    }

    /// The choices the control offers, in authored order.
    public func choices(_ props: ServerUIClimateControl.Properties) -> [ServerUIClimateControl.Choice] {
        choices(props.choices ?? [], kind: props.kind)
    }

    /// The choices the control offers, in authored order.
    public func choices(_ authored: [ServerUIClimateControl.Choice], kind: ServerUIClimateControl.Kind) -> [ServerUIClimateControl.Choice] {
        let attribute: String
        switch kind {
        case .mode: attribute = "hvac_modes"
        case .fan: attribute = "fan_modes"
        case .preset: attribute = "preset_modes"
        default: attribute = "options"
        }
        let supported = entity?.attributes[attribute]?.array?.compactMap(\.string) ?? []
        return authored.filter { supported.contains($0.value) }
    }

    /// Pins targets at submit time and revalidates the source, tracking policy and command vocabulary.
    @discardableResult
    public func submit(_ intent: ClimateConfiguredIntent, expectedTarget: String,
                       failed: @escaping @MainActor () -> Void = {}) -> Task<Void, Never> {
        commandCount += 1
        return Task { @MainActor [self] in
            defer { commandCount -= 1 }
            do {
                guard target == expectedTarget, isEnabled, let controller else { throw ClimateConfiguredError.unavailable }
                let intentTargets: [String]
                switch intent {
                case .toggle(let id), .setSwitch(let id, _), .select(let id, _),
                     .mode(let id, _), .fan(let id, _), .preset(let id, _): intentTargets = [id]
                case .temperature(let ids, let values, _):
                    let range = values["target_temp_low"] != nil
                    intentTargets = range && target == configuration.entityId && !configuration.rangeCommitEntityIds.isEmpty
                        ? configuration.rangeCommitEntityIds : [target]
                    guard ids == intentTargets else { throw ClimateConfiguredError.invalidIntent }
                }
                if case .temperature = intent {} else if intentTargets != [target] { throw ClimateConfiguredError.invalidIntent }
                try await controller.execute(intent)
            } catch {
                failureCount += 1
                failed()
            }
        }
    }

    /// Domain projections contain no page copy; state labels and units are authored.
    public func status(_ status: ServerUIClimateControl.Status) -> String? {
        guard let entity, !entity.isUnavailable else { return nil }
        let sensor = (configuration.sensorEntityId == nil ? entity : configuration.sensorEntityId.flatMap(lookup))
            .flatMap { $0.isUnavailable ? nil : $0 }
        let value: String?
        switch status.projection {
        case .trackingSelected, .trackingCritical, .trackingOccupiedOnly:
            guard let summary = trackingSummary else { return nil }
            let page: ClimateConfig.TrackingPage = status.projection == .trackingSelected ? .selectedRooms
                : status.projection == .trackingCritical ? .criticalProtection : .occupiedOnly
            return summary.subtitle(page)
        case .predictive:
            let state = shown(target)
            let label = status.states.first { $0.state == state }?.text ?? status.fallbackText
            guard state == "on" else { return label }
            guard let recommendation = entity.attributes["current_recommendation"] ?? sensor.map({ .string($0.state) }) else { return nil }
            return "\(label) · \(ClimateLogic.predictiveState(recommendation))"
        case .explanation:
            guard let sensor else { return nil }
            let unit = sensor.attributes["temperature_unit"]?.string ?? sensor.attributes["unit_of_measurement"]?.string
            guard unit == nil || unit == status.unit else { return nil }
            return ClimateLogic.predictiveReasonBullets(sensor, unit: status.unit).joined(separator: "\n\n")
        case .comfortBand, .forecastRange:
            guard let sensor else { return nil }
            let unit = sensor.attributes["temperature_unit"]?.string ?? sensor.attributes["unit_of_measurement"]?.string
            guard unit == nil || unit == status.unit else { return nil }
            let keys = status.projection == .comfortBand ? ("comfort_low", "comfort_high") : ("forecast_low", "forecast_high")
            guard let low = sensor.attributes[keys.0]?.finiteNumber, let high = sensor.attributes[keys.1]?.finiteNumber else { return nil }
            return "\(ClimateLogic.temperature(low, unit: status.unit)) - \(ClimateLogic.temperature(high, unit: status.unit))"
        case .state, .occupancy: value = shown(target)
        case .action: value = ClimateLogic.hvacAction(configuration.actionEntityId.flatMap(lookup) ?? entity)
        case .temperature:
            let unit = entity.attributes["temperature_unit"]?.string ?? entity.attributes["unit_of_measurement"]?.string
            guard unit == nil || unit == status.unit else { return nil }
            let number = entity.domain == "sensor" ? Double(entity.state) : entity.attributes["current_temperature"]?.finiteNumber
            return number.flatMap { $0.isFinite ? ClimateLogic.temperature($0, unit: status.unit) : nil }
        case .vent:
            let text = status.states.first { $0.state == entity.state }?.text ?? status.fallbackText
            guard ClimateLogic.isVentOpen(entity), let position = entity.attributes["current_position"]?.finiteNumber else { return text }
            return "\(text) · \(Int(position.rounded()))%"
        case .recommendation: value = entity.attributes["current_recommendation"]?.string ?? sensor?.state
        case .reason: value = sensor?.attributes["reason"]?.string
        case .weather: value = sensor?.attributes["weather_entity"]?.string
        case .adjustment: value = sensor?.attributes["adjustment_status"]?.string
        case .indoor, .predicted, .comfortLow, .comfortHigh, .forecastLow, .forecastHigh:
            guard let sensor else { return nil }
            let unit = sensor.attributes["temperature_unit"]?.string ?? sensor.attributes["unit_of_measurement"]?.string
            guard unit == nil || unit == status.unit else { return nil }
            let attributes: [ServerUIClimateControl.Status.Projection: String] = [
                .indoor: "indoor_temperature", .predicted: "predicted_temperature",
                .comfortLow: "comfort_low", .comfortHigh: "comfort_high", .forecastLow: "forecast_low", .forecastHigh: "forecast_high"
            ]
            guard let key = attributes[status.projection], let number = sensor.attributes[key]?.finiteNumber else { return nil }
            return ClimateLogic.temperature(number, unit: status.unit)
        }
        guard let value else { return nil }
        if [.recommendation, .adjustment].contains(status.projection) {
            return status.states.first { $0.state == value }?.text ?? ClimateLogic.predictiveState(.string(value))
        }
        return status.states.first { $0.state == value }?.text ?? (status.projection == .reason || status.projection == .weather ? value : status.fallbackText)
    }

    /// The notice text for the climate state, or nil when none applies.
    public func notice(_ copy: ServerUIClimateControl.Notice) -> String? {
        guard let inputs = configuration.homeAway else { return nil }
        let mode = lookup(inputs.modeEntityId)
        let state = mode?.state == "unknown" ? "Unknown" : mode?.isUnavailable == false ? mode?.state ?? "Unavailable" : "Unavailable"
        let reason = lookup(inputs.reasonEntityId)
        let reasonText = reason?.isUnavailable == false && reason?.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? reason?.state ?? copy.reasonFallback : copy.reasonFallback
        let away = entity?.attributes["away_mode_active"]?.bool ?? (lookup(inputs.fallbackEntityId)?.state == "on")
        return ClimateLogic.awayNotice(
            status: .init(state: state, reason: reasonText), entityAway: away, useEffectiveMode: copy.useEffectiveMode,
            vacation: lookup(inputs.vacationEntityId)?.state == "on", awayText: copy.awayText, vacationText: copy.vacationText,
            unknownText: copy.unknownText, unavailableText: copy.unavailableModeText, separator: copy.separator
        )
    }

    /// Typed counts for shell-owned value/row composition. Missing state is not a successful zero.
    public var trackingSummary: ClimateLogic.TrackingSummary? {
        guard let tracking = configuration.tracking, entity?.isUnavailable == false,
              let policy = shown(tracking.policyEntityId), !EntityState.isUnavailable(policy) else { return nil }
        var rooms: [ClimateLogic.TrackingRoomState] = []
        for room in tracking.rooms {
            let values = [room.selectedEntityId, room.criticalEntityId, room.occupiedOnlyEntityId].map(shown)
            guard values.allSatisfy({ $0 == "on" || $0 == "off" }) else { return nil }
            rooms.append(.init(selected: values[0] == "on", critical: values[1] == "on", occupiedOnly: values[2] == "on"))
        }
        return ClimateLogic.trackingSummary(rooms: rooms, selectedEnabled: shown(target) == "on",
                                            criticalPolicy: policy, criticalOption: tracking.criticalOption)
    }

    /// Fixed scalar fields, not a downloaded formatter or executable expression.
    public func trackingValue(_ field: String) -> JSONValue? {
        guard let summary = trackingSummary else { return nil }
        switch field {
        case "selectedCount": return .number(Double(summary.selectedCount))
        case "criticalCount": return .number(Double(summary.criticalCount))
        case "occupiedOnlyCount": return .number(Double(summary.occupiedOnlyCount))
        case "totalRooms": return .number(Double(summary.totalRooms))
        case "selectedEnabled": return .bool(summary.selectedEnabled)
        case "criticalEnabled": return .bool(summary.criticalEnabled)
        default: return nil
        }
    }
}
