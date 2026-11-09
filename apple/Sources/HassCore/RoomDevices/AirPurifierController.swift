import Foundation
import Observation

/// Drives one air purifier's sheet (web `AirQualityModalContent.tsx`): fan mode, the auto sub-mode while in Auto,
/// and the speed while in Manual.
///
/// The web shows no optimistic state here; natively each choice highlights at once and gives way to Home
/// Assistant on its next change or after 2 s (HIG: Feedback), so the tiles never look unresponsive.
@MainActor
@Observable
public final class AirPurifierController {
    /// One choice tile.
    public struct Option: Hashable, Sendable, Identifiable {
        public var title: String
        public var icon: String
        /// The `select` option, or the fan percentage for speeds.
        public var value: String
        public var id: String { value }
    }

    /// `FAN_MODE_OPTIONS`.
    public static let fanModes: [Option] = [
        .init(title: "Manual", icon: "mdi:fan", value: "Manual"),
        .init(title: "Sleep", icon: "mdi:weather-night", value: "Sleep"),
        .init(title: "Auto", icon: "mdi:fan-auto", value: "Auto"),
    ]

    /// `AUTO_MODE_OPTIONS`.
    public static let autoModes: [Option] = [
        .init(title: "Default", icon: "mdi:fan", value: "Default"),
        .init(title: "Quiet", icon: "mdi:volume-off", value: "Quiet"),
        .init(title: "Efficient", icon: "mdi:leaf", value: "Efficient"),
    ]

    /// `MANUAL_SPEED_OPTIONS` (values are fan percentages).
    public static let speeds: [Option] = [
        .init(title: "Off", icon: "mdi:fan-off", value: "0"),
        .init(title: "Low", icon: "mdi:fan-speed-1", value: "33"),
        .init(title: "Medium", icon: "mdi:fan-speed-2", value: "66"),
        .init(title: "High", icon: "mdi:fan-speed-3", value: "100"),
    ]

    public static let revert: Duration = .seconds(2)

    public let config: AirPurifierConfig
    public let commands: RoomDeviceCommands

    /// Creates a controller.
    public init(config: AirPurifierConfig, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        let fanId = config.fanEntityId
        let rules: [String: OptimisticOverlay.ClearRule] = [
            config.modeEntityId: .liveChange, config.autoModeEntityId: .liveChange, config.fanEntityId: .liveChange,
        ]
        // The fan's overlay value is its speed (the `percentage` attribute), not its on/off state.
        commands = RoomDeviceCommands(store: store, caller: caller, rules: rules, scheduler: scheduler) { [store] id in
            guard id == fanId else { return store.entity(id).state?.state }
            return store.entity(fanId).state?.attributes["percentage"]?.number.map { String(Int($0.rounded())) }
        }
    }

    // MARK: - State

    /// The fan mode shown (`Manual`, `Sleep`, `Auto`).
    public var mode: String? { commands.displayed(config.modeEntityId) }
    /// The Auto sub-mode shown.
    public var autoMode: String? { commands.displayed(config.autoModeEntityId) }
    /// The speed shown, as a percentage string.
    public var percentage: String? { commands.displayed(config.fanEntityId) }

    public var modeUnavailable: Bool { EntityState.isUnavailable(commands.entity(config.modeEntityId)?.state) }
    public var autoModeUnavailable: Bool { EntityState.isUnavailable(commands.entity(config.autoModeEntityId)?.state) }
    public var fanUnavailable: Bool { EntityState.isUnavailable(commands.entity(config.fanEntityId)?.state) }

    /// Auto modes show only in Auto.
    public var showsAutoModes: Bool { mode == "Auto" }
    /// Speeds show only in Manual.
    public var showsSpeeds: Bool { mode == "Manual" }

    /// `12 AQI • 3 µg/m³`-style summary for a room card (web `formatAirQualitySummary`).
    public var summary: String {
        "\(Self.metric(commands.entity(config.aqiEntityId))) • \(Self.metric(commands.entity(config.pm25EntityId)))"
    }

    /// A sensor value with its unit (web `formatAirMetricState`).
    public static func metric(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        let raw = entity.state.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty || EntityState.isUnavailable(raw) { return DeviceState.compact(entity) }
        let unit = entity.attributes["unit_of_measurement"]?.string ?? ""
        let value = unit.isEmpty && raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
        return unit.isEmpty || value.contains(unit) ? value : "\(value) \(unit)"
    }

    // MARK: - Actions

    /// Picks a fan mode.
    public func selectMode(_ option: Option) {
        guard !modeUnavailable else { return }
        select(config.modeEntityId, option.value)
    }

    /// Picks an Auto sub-mode.
    public func selectAutoMode(_ option: Option) {
        guard !autoModeUnavailable else { return }
        select(config.autoModeEntityId, option.value)
    }

    /// Sets a Manual speed (`fan.set_percentage`).
    public func selectSpeed(_ option: Option) {
        guard !fanUnavailable, let percentage = Double(option.value) else { return }
        commands.perform(ServiceCall("fan", "set_percentage", target: config.fanEntityId, data: ["percentage": .number(percentage)]),
                         intents: [OptimisticIntent(config.fanEntityId, option.value, revertAfter: Self.revert)])
    }

    private func select(_ entityId: String, _ option: String) {
        commands.perform(ServiceCall("select", "select_option", target: entityId, data: ["option": .string(option)]),
                         intents: [OptimisticIntent(entityId, option, revertAfter: Self.revert)])
    }
}

/// Drives the grill sheet (web `GrillModalContent.tsx`): the grill's state and four detail cards; the two switches
/// can be tapped.
@MainActor
@Observable
public final class GrillController {
    /// How a detail card shows.
    public struct DetailDisplay: Equatable, Sendable {
        public var value: String
        public var isActive: Bool
        public var isUnavailable: Bool
        /// A switch that can be tapped.
        public var isActionable: Bool
    }

    public static let revert: Duration = .seconds(2)

    public let config: GrillConfig
    public let commands: RoomDeviceCommands

    /// Creates a controller.
    public init(config: GrillConfig = .bearGrills, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for detail in config.details where detail.isSwitch { rules[detail.entityId] = .liveChange }
        commands = RoomDeviceCommands(store: store, caller: caller, rules: rules, scheduler: scheduler)
    }

    /// The grill's state line, e.g. `Idle` or `Unavailable`.
    public var stateText: String {
        guard let entity = commands.entity(config.stateEntityId) else { return "Unavailable" }
        return EntityState.isUnavailable(entity.state) ? "Unavailable" : StateText.titleCase(entity.state)
    }

    /// The grill is off or unreachable (the room card greys out; web `disabledStates`).
    public var isOff: Bool {
        let state = commands.entity(config.stateEntityId)?.state
        return EntityState.isUnavailable(state) || state == "off"
    }

    /// How a card shows.
    public func display(_ detail: GrillConfig.Detail) -> DetailDisplay {
        let unavailable = EntityState.isUnavailable(commands.entity(detail.entityId)?.state)
        let shown = commands.displayed(detail.entityId)
        var entity = commands.entity(detail.entityId)
        if let shown { entity?.state = shown }
        let value: String = if unavailable { "Unavailable" } else if let entity { Self.value(entity) } else { "Unavailable" }
        return DetailDisplay(value: value, isActive: !unavailable && (entity?.isActive ?? false),
                             isUnavailable: unavailable, isActionable: detail.isSwitch && !unavailable)
    }

    /// A sensor's value with its unit, or a switch's On/Off.
    static func value(_ entity: EntityState) -> String {
        if entity.domain == "switch" { return entity.state == "on" ? "On" : "Off" }
        let unit = entity.attributes["unit_of_measurement"]?.string ?? ""
        return unit.isEmpty || entity.state.hasSuffix(unit) ? entity.state : "\(entity.state)\(unit == "%" ? "" : " ")\(unit)"
    }

    /// Flips a switch with an explicit `turn_on` / `turn_off` (the web sends `homeassistant.toggle`).
    public func toggle(_ detail: GrillConfig.Detail) {
        let display = display(detail)
        guard display.isActionable else { return }
        let next = !display.isActive
        commands.perform(ServiceCall("switch", next ? "turn_on" : "turn_off", target: detail.entityId),
                         intents: [OptimisticIntent(detail.entityId, next ? "on" : "off", revertAfter: Self.revert)])
    }
}
