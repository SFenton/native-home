import Foundation
import Observation

/// Drives the humidifier sheet's controls (web `useHumidifierController`, `HumidifierModalContent.tsx`).
///
/// Optimistic values clear only when Home Assistant reports the same value, or after 8 s (the LV600S is slow to
/// echo over the cloud).
@MainActor
@Observable
public final class HumidifierController {
    /// What stops the controls (web `fault`).
    public enum Fault: String, Sendable { case tank, water }

    /// Web `HUMIDIFIER_OPTIMISTIC_REVERT_MS`.
    public static let revert: Duration = .seconds(8)
    /// Web `DEFAULT_TARGET_HUMIDITY`.
    public static let defaultTargetHumidity = 50
    /// Mist dial range (0 is off).
    public static let mistRange = 0...9
    /// Target humidity dial range and step.
    public static let targetRange = 40...80
    public static let targetStep = 5
    /// Device timer range and step, in minutes.
    public static let timerRange = 0...720
    public static let timerStep = 30

    public let config: HumidifierConfig
    public let commands: RoomDeviceCommands

    /// Creates a controller.
    public init(config: HumidifierConfig, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in config.optimisticEntityIds { rules[id] = .confirmation }
        commands = RoomDeviceCommands(store: store, caller: caller, rules: rules, scheduler: scheduler) { [store, config] id in
            HumidifierController.liveValue(id, entity: store.entity(id).state, config: config)
        }
    }

    /// The live value the overlay compares against: numbers normalized the way the web reads them.
    static func liveValue(_ id: String, entity: EntityState?, config: HumidifierConfig) -> String? {
        let number = DeviceState.number(entity)
        func clamped(_ value: Double?, _ fallback: Int, _ range: ClosedRange<Int>) -> String {
            String(min(range.upperBound, max(range.lowerBound, Int((value ?? Double(fallback)).rounded()))))
        }
        switch id {
        case config.modeEntityId:
            return (entity.flatMap { HumidifierMode(rawValue: $0.state) } ?? .manual).rawValue
        case config.mistLevelEntityId:
            return clamped(number, 5, 1...9)
        case config.targetHumidityEntityId:
            return String(validTarget(number) ?? defaultTargetHumidity)
        case config.warmLevelEntityId:
            return clamped(number, 0, 0...3)
        case config.timerMinutesEntityId:
            return clamped(number, 0, timerRange)
        default:
            return entity?.state
        }
    }

    private static func validTarget(_ value: Double?) -> Int? {
        guard let value, value >= Double(targetRange.lowerBound), value <= Double(targetRange.upperBound) else { return nil }
        return Int(value.rounded())
    }

    // MARK: - State

    private func int(_ id: String, _ fallback: Int) -> Int { commands.displayed(id).flatMap { Int($0) } ?? fallback }

    /// The power switch is missing, `unavailable` or `unknown`.
    public var isUnavailable: Bool { EntityState.isUnavailable(commands.entity(config.powerEntityId)?.state) }
    public var powerOn: Bool { commands.displayed(config.powerEntityId) == "on" }
    public var mode: HumidifierMode { commands.displayed(config.modeEntityId).flatMap(HumidifierMode.init(rawValue:)) ?? .manual }
    /// The saved mist level 1–9 (shown even while off).
    public var mistLevel: Int { int(config.mistLevelEntityId, 5) }
    /// Home Assistant's mist level, `nil` when it reports none.
    public var currentMistLevel: Int? {
        DeviceState.number(commands.entity(config.mistLevelEntityId)) == nil ? nil
            : commands.live(config.mistLevelEntityId).flatMap { Int($0) }
    }
    public var targetHumidity: Int { int(config.targetHumidityEntityId, Self.defaultTargetHumidity) }
    /// Home Assistant reports a target inside 40–80%, or one was just set.
    public var targetHumidityValid: Bool {
        commands.overlay.pending[config.targetHumidityEntityId] != nil
            || Self.validTarget(DeviceState.number(commands.entity(config.targetHumidityEntityId))) != nil
    }
    public var warmLevel: Int { int(config.warmLevelEntityId, 0) }
    public var timerMinutes: Int { int(config.timerMinutesEntityId, 0) }
    public var displayOn: Bool { commands.displayed(config.displayEntityId) == "on" }
    public var currentHumidity: Double? { DeviceState.number(commands.entity(config.currentHumidityEntityId)) }
    /// Seconds left on the device timer.
    public var timerRemaining: Double? { DeviceState.number(commands.entity(config.timerRemainingEntityId)) }
    public var humidifying: Bool { commands.entity(config.humidifyingEntityId)?.state == "on" }

    public var fault: Fault? {
        if commands.entity(config.tankRemovedEntityId)?.state == "on" { return .tank }
        if commands.entity(config.waterLowEntityId)?.state == "on" { return .water }
        return nil
    }

    /// Unavailable or faulted: output controls are disabled.
    public var isBlocked: Bool { isUnavailable || fault != nil }

    /// Sleep mode runs output itself: the level, presets, warm mist and display are locked.
    public var isSleep: Bool { mode == .sleep }

    /// The mist dial can be dragged.
    public var canSetLevel: Bool { !isBlocked && !isSleep }

    /// The power button is enabled (off with a fault can't turn on).
    public var canTogglePower: Bool { !isUnavailable && (powerOn || fault == nil) }

    /// `72°F`, or Unavailable.
    public var temperatureText: String {
        let entity = commands.entity(config.currentTemperatureEntityId)
        guard let entity, !EntityState.isUnavailable(entity.state) else { return "Unavailable" }
        guard let value = DeviceState.number(entity) else { return StateText.titleCase(entity.state) }
        return "\(Int(value.rounded()))\(entity.attributes["unit_of_measurement"]?.string ?? "°")"
    }

    /// `45%`, or Unavailable.
    public var humidityText: String { Self.percent(currentHumidity) }

    /// The sheet subtitle and room tile subtitle (web `humidifierSubtitle`).
    public var subtitle: String {
        if isUnavailable { return "Unavailable" }
        if !powerOn { return "Off" }
        switch fault {
        case .tank: return "Tank Removed"
        case .water: return "Water Low"
        case nil: return "\(humidifying ? "Humidifying" : "On") • \(humidityText)"
        }
    }

    /// The hint under the dial (web `HumidifierHero` hint).
    public var hint: String? {
        if isUnavailable { return "Humidifier controls are unavailable." }
        switch fault {
        case .tank: return "Reinsert the water tank to restore controls."
        case .water: return "Refill the tank to restore output controls."
        case nil: break
        }
        if isSleep { return "Sleep mode controls output automatically." }
        return powerOn ? "Drag the dial to adjust mist output." : nil
    }

    /// The fault banner text.
    public var faultMessage: String? {
        switch fault {
        case .tank: "Tank removed. Reinsert it before turning the humidifier on."
        case .water: "Water is low. Refill the tank before turning the humidifier on."
        case nil: nil
        }
    }

    /// `Off`, `30m`, `1h 30m` (web `formatDurationMinutes`).
    public static func formatMinutes(_ minutes: Int) -> String {
        if minutes <= 0 { return "Off" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Remaining seconds rounded up to minutes (web `formatDurationSeconds`).
    public static func formatSeconds(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "Off" }
        return formatMinutes(max(1, Int((seconds / 60).rounded(.up))))
    }

    static func percent(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "Unavailable" }

    /// Off, Low, Medium or High.
    public static func warmTitle(_ level: Int) -> String {
        HumidifierConfig.warmLevels.first { $0.value == level }?.title ?? "Level \(level)"
    }

    // MARK: - Info

    /// One Info tab status row.
    public struct InfoItem: Hashable, Sendable, Identifiable {
        public enum Tone: String, Sendable { case neutral, ok, active, warning, danger, unavailable }
        public var title: String
        public var icon: String
        public var value: String
        public var tone: Tone
        public var id: String { title }

        public init(title: String, icon: String, value: String, tone: Tone) {
            self.title = title
            self.icon = icon
            self.value = value
            self.tone = tone
        }
    }

    /// Device State rows (web `InfoPanel`).
    public var deviceItems: [InfoItem] {
        let outputTone: InfoItem.Tone = isUnavailable ? .unavailable : fault == .tank ? .danger : fault == .water ? .warning
            : humidifying ? .active : powerOn ? .ok : .neutral
        let output = fault == .tank ? "Tank Removed" : fault == .water ? "Water Low" : humidifying ? "Humidifying" : powerOn ? "Idle" : "Off"
        return [
            InfoItem(title: "Output", icon: "mdi:air-humidifier", value: output, tone: outputTone),
            InfoItem(title: "Water", icon: "mdi:water", value: fault == nil ? "OK" : "Low", tone: fault == nil ? .ok : .warning),
            InfoItem(title: "Tank", icon: "mdi:water", value: fault == .tank ? "Removed" : "Installed", tone: fault == .tank ? .danger : .ok),
            InfoItem(title: "Mode", icon: "mdi:fan-auto", value: mode.title, tone: .neutral),
            InfoItem(title: "Display", icon: "mdi:monitor", value: displayOn ? "On" : "Off", tone: .neutral),
            InfoItem(title: "Warm Mist", icon: "mdi:fire", value: Self.warmTitle(warmLevel), tone: .neutral),
        ]
    }

    /// Environment rows.
    public var environmentItems: [InfoItem] {
        let mist = powerOn ? currentMistLevel.map { "Level \($0)" } ?? "Unavailable" : "Saved \(mistLevel)"
        return [
            InfoItem(title: "Humidity", icon: "mdi:water-percent", value: humidityText, tone: .neutral),
            InfoItem(title: "Temperature", icon: "mdi:thermometer", value: temperatureText, tone: .neutral),
            InfoItem(title: "Mist Level", icon: "mdi:air-humidifier", value: mist, tone: .neutral),
            InfoItem(title: "Timer", icon: "mdi:clock-outline", value: Self.formatSeconds(timerRemaining), tone: .neutral),
        ]
    }

    // MARK: - Actions

    private func intent(_ id: String, _ value: String) -> OptimisticIntent { OptimisticIntent(id, value, revertAfter: Self.revert) }

    /// Sets the mist level through the level script; 0 turns the humidifier off.
    public func setLevel(_ level: Int) {
        let next = min(Self.mistRange.upperBound, max(Self.mistRange.lowerBound, level))
        var intents = [intent(config.powerEntityId, next > 0 ? "on" : "off")]
        if next > 0 { intents.append(intent(config.mistLevelEntityId, String(next))) }
        commands.perform(ServiceCall("script", config.setLevelScriptService, data: ["level": .number(Double(next))]), intents: intents)
    }

    /// Picks a mode. While off, this applies the whole profile (which turns it on).
    public func setMode(_ next: HumidifierMode) {
        if !powerOn {
            commands.perform(ServiceCall("script", config.applyProfileScriptService, data: [
                "display": .bool(displayOn),
                "mist_level": .number(Double(mistLevel)),
                "mode": .string(next.rawValue),
                "target_humidity": .number(Double(targetHumidity)),
                "warm_level": .number(Double(warmLevel)),
            ]), intents: [intent(config.powerEntityId, "on"), intent(config.modeEntityId, next.rawValue)])
            return
        }
        commands.perform(ServiceCall("select", "select_option", target: config.modeEntityId, data: ["option": .string(next.rawValue)]),
                         intents: [intent(config.modeEntityId, next.rawValue)])
    }

    /// Sets the Auto Humidity target, snapped to 5% steps within 40–80%.
    public func setTargetHumidity(_ humidity: Double) {
        let snapped = Int((humidity / Double(Self.targetStep)).rounded()) * Self.targetStep
        let next = min(Self.targetRange.upperBound, max(Self.targetRange.lowerBound, snapped))
        commands.perform(ServiceCall("number", "set_value", target: config.targetHumidityEntityId, data: ["value": .number(Double(next))]),
                         intents: [intent(config.targetHumidityEntityId, String(next))])
    }

    /// Sets the one-shot device timer, snapped to 30-minute steps within 0–720 (0 cancels it).
    public func setTimerMinutes(_ minutes: Int) {
        let snapped = Int((Double(minutes) / Double(Self.timerStep)).rounded()) * Self.timerStep
        let next = min(Self.timerRange.upperBound, max(Self.timerRange.lowerBound, snapped))
        commands.perform(ServiceCall("number", "set_value", target: config.timerMinutesEntityId, data: ["value": .number(Double(next))]),
                         intents: [intent(config.timerMinutesEntityId, String(next))])
    }

    /// Sets warm mist 0–3.
    public func setWarmLevel(_ level: Int) {
        let next = min(3, max(0, level))
        commands.perform(ServiceCall("number", "set_value", target: config.warmLevelEntityId, data: ["value": .number(Double(next))]),
                         intents: [intent(config.warmLevelEntityId, String(next))])
    }

    /// Turns the display on or off.
    public func setDisplay(_ on: Bool) {
        commands.perform(ServiceCall("switch", on ? "turn_on" : "turn_off", target: config.displayEntityId),
                         intents: [intent(config.displayEntityId, on ? "on" : "off")])
    }

    /// Turns the humidifier on or off.
    public func togglePower() {
        guard canTogglePower else { return }
        let next = !powerOn
        commands.perform(ServiceCall("switch", next ? "turn_on" : "turn_off", target: config.powerEntityId),
                         intents: [intent(config.powerEntityId, next ? "on" : "off")])
    }
}
