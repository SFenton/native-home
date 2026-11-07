import Foundation

/// Reads an entity by id; the Climate logic takes one so it stays pure and testable.
public typealias EntityLookup = (String) -> EntityState?

/// Pure Climate page rules ported from the web `ThermostatPage`
/// (`ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx`). No UI, no service calls.
public enum ClimateLogic {
    // MARK: - Formatting

    /// Short state text (web `formatCompactEntityState`): sensors and text read as-is, everything else is title-cased.
    /// - Parameters:
    ///   - entity: The entity, `nil` when the server doesn't know it.
    ///   - state: An optimistic state shown instead of the live one.
    public static func compactState(_ entity: EntityState?, state override: String? = nil) -> String {
        guard let entity else { return "Unavailable" }
        let state = override ?? entity.state
        if state == "unavailable" { return "Unavailable" }
        if entity.entityId.hasPrefix("binary_sensor.contact") { return state == "on" ? "Open" : "Closed" }
        if entity.entityId.hasPrefix("binary_sensor.") { return state == "on" ? "Active" : "Clear" }
        if entity.entityId.hasPrefix("light.") { return state == "on" ? "On" : "Off" }
        if entity.domain == "sensor" || entity.domain == "input_text" { return state }
        return StateText.titleCase(state)
    }

    /// A select option as shown: multi-word options as-is, else title-cased (web `formatSelectOption`).
    public static func selectOption(_ value: String) -> String {
        if value.isEmpty { return "Unknown" }
        return value.contains(" ") ? value : StateText.titleCase(value)
    }

    /// `pre_cool` → `Pre-Cool`, else ``selectOption(_:)`` (web `formatPredictiveState`).
    public static func predictiveState(_ value: JSONValue?) -> String {
        guard let value = value?.string, !value.isEmpty else { return "Unknown" }
        let key = value.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
        return key == "pre_cool" ? "Pre-Cool" : selectOption(value)
    }

    /// A number from a JSON value or numeric string (web `numberValue`).
    public static func number(_ value: JSONValue?) -> Double? { value?.finiteNumber }

    /// `72.0°F`, or `--°F` when not a number (web `formatTemperatureValue`).
    public static func temperature(_ value: Double?, unit: String = "°F") -> String {
        (value.map { String(format: "%.1f", $0) } ?? "--") + unit
    }

    /// The entity's temperature unit: `temperature_unit`, then `unit_of_measurement`, else `°F`.
    public static func unit(of entity: EntityState?) -> String {
        entity?.attributes["temperature_unit"]?.string ?? entity?.attributes["unit_of_measurement"]?.string ?? "°F"
    }

    // MARK: - Home / away

    /// The Whole Home mode text and reason (web `useThermostatHomeAwayStatus`).
    public struct HomeAwayStatus: Equatable, Sendable {
        /// `Home`, `Away`, `Unknown` or `Unavailable`.
        public var state: String
        public var reason: String
    }

    public static func homeAwayStatus(_ lookup: EntityLookup) -> HomeAwayStatus {
        let reasonEntity = lookup(ClimateConfig.homeAwayReasonEntityId)
        let reason = reasonEntity.flatMap { $0.isUnavailable || $0.state.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.state }
        // The web passes a sensor's raw `unknown` through, so its `Unknown` checks never match it; read it as Unknown
        // (departure recorded in the page spec).
        let entity = lookup(ClimateConfig.homeAwayEntityId)
        let state = entity?.state == "unknown" ? "Unknown" : compactState(entity)
        return HomeAwayStatus(state: state, reason: reason ?? ClimateConfig.Copy.noReason)
    }

    /// Away when the effective mode is `Away`, or it is unknown and the fallback says away (web `thermostatEffectiveAway`).
    public static func isEffectivelyAway(state: String, fallbackAway: Bool) -> Bool {
        state == "Away" || ((state == "Unknown" || state == "Unavailable") && fallbackAway)
    }

    /// The house is effectively away: the Whole Home dial shows the eco-away thermostat.
    public static func isEffectivelyAway(_ lookup: EntityLookup) -> Bool {
        isEffectivelyAway(state: homeAwayStatus(lookup).state, fallbackAway: lookup(ClimateConfig.awayModeEntityId)?.state == "on")
    }

    /// The entity the Whole Home dial binds to.
    public static func wholeHomeDialEntityId(_ lookup: EntityLookup) -> String {
        isEffectivelyAway(lookup) ? ClimateConfig.ecoAwayThermostatEntityId : ClimateConfig.globalThermostatEntityId
    }

    /// `hvac_action`, falling back to the state, then `idle` (web `rawThermostatAction`).
    public static func hvacAction(_ entity: EntityState?) -> String {
        entity?.attributes["hvac_action"]?.string ?? entity?.state ?? "idle"
    }

    /// A room's away flag: its climate entity's `away_mode_active`, else the global away sensor (web `useThermostatRoomAwayMode`).
    public static func roomAwayMode(climateEntityId: String, _ lookup: EntityLookup) -> Bool {
        if case let .bool(value)? = lookup(climateEntityId)?.attributes["away_mode_active"] { return value }
        return lookup(ClimateConfig.awayModeEntityId)?.state == "on"
    }

    /// The away notice for the Whole Home section or a room, or `nil` when none shows (web `ThermostatAwayModeDetails`).
    /// - Parameter useEffectiveMode: The Whole Home section uses the effective mode; rooms use their own flag.
    public static func awayNotice(climateEntityId: String, useEffectiveMode: Bool, _ lookup: EntityLookup) -> String? {
        let status = homeAwayStatus(lookup)
        let entityAway = roomAwayMode(climateEntityId: climateEntityId, lookup)
        let away = useEffectiveMode ? isEffectivelyAway(state: status.state, fallbackAway: entityAway) : entityAway
        let showsStatus = ["Away", "Unknown", "Unavailable"].contains(status.state)
        guard away || showsStatus else { return nil }
        let mode = lookup(ClimateConfig.vacationModeEntityId)?.state == "on" ? "Vacation Mode" : "Away Mode"
        if status.state == "Away" || away {
            return "\(mode) Active. The room may be cooler or warmer than your heat/cool targets to save energy while away."
        }
        return "\(status.state) Mode. \(status.reason)"
    }

    /// Automatic Thermostat is explicitly off (the page shows a warning).
    public static func showsIntegrationWarning(_ lookup: EntityLookup) -> Bool {
        lookup(ClimateConfig.integrationEntityId)?.state == "off"
    }

    // MARK: - Contacts and rooms

    /// `on` or `open` (web `isContactOpen`).
    public static func isContactOpen(_ entity: EntityState?) -> Bool { entity?.state == "on" || entity?.state == "open" }

    /// The open contact sensors, or none while the aggregate is closed (web `OpenContactSensorsSection`).
    public static func openContactSensors(_ lookup: EntityLookup) -> [ClimateConfig.ContactSensor] {
        guard isContactOpen(lookup(ClimateConfig.contactSensorsEntityId)) else { return [] }
        return ClimateConfig.contactSensors.filter { isContactOpen(lookup($0.entityId)) }
    }

    /// `Open`, `Closed`, `Unknown`, `Unavailable` (web `formatContactEntityState`).
    public static func contactState(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        switch entity.state {
        case "unavailable": return "Unavailable"
        case "unknown": return "Unknown"
        case "on", "open": return "Open"
        case "off", "closed": return "Closed"
        default: return StateText.titleCase(entity.state)
        }
    }

    /// `on`, `active` or `occupied` (web `isOccupancyActive`).
    public static func isOccupied(_ entity: EntityState?) -> Bool {
        ["on", "active", "occupied"].contains(entity?.state ?? "")
    }

    /// `70.9°F · Occupied` (web `ThermostatRoomRow`).
    public static func roomSubtitle(_ room: ClimateConfig.Room, _ lookup: EntityLookup) -> String {
        "\(roomTemperature(room, lookup)) · \(roomOccupancy(room, lookup))"
    }

    /// A room's temperature, `70.9°F` (the trailing value of its row).
    public static func roomTemperature(_ room: ClimateConfig.Room, _ lookup: EntityLookup) -> String {
        let temperature = lookup(room.temperatureEntityId)
        return self.temperature(number(temperature.map { .string($0.state) }), unit: unit(of: temperature))
    }

    /// A room's occupancy, `Occupied` (the subtitle of its row).
    public static func roomOccupancy(_ room: ClimateConfig.Room, _ lookup: EntityLookup) -> String {
        StateText.titleCase(lookup(room.occupancyEntityId)?.state)
    }

    /// A vent cover's state text (web `ClimateCard` → `formatCompactEntityState`).
    public static func ventState(_ entity: EntityState?) -> String { compactState(entity) }

    /// Whether a vent cover is open (or opening): the Vents family fills its tile.
    public static func isVentOpen(_ entity: EntityState?) -> Bool {
        guard let state = entity?.state else { return false }
        return state == "open" || state == "opening"
    }

    /// A vent tile's state line: `Open · 60%` while open with a reported position, else ``ventState(_:)``
    /// (`Open`, `Closed`, `Unavailable`). The position is the cover's `current_position`, 0 to 100.
    public static func ventSubtitle(_ entity: EntityState?) -> String {
        let state = ventState(entity)
        guard isVentOpen(entity), let position = number(entity?.attributes["current_position"]) else { return state }
        return "\(state) · \(Int(position.rounded()))%"
    }

    // MARK: - Tracking

    /// Counts and enablement for the Tracking tab (web `useThermostatTrackingSummary`).
    public struct TrackingSummary: Equatable, Sendable {
        public var selectedCount: Int
        public var occupiedOnlyCount: Int
        /// Untracked rooms forced to critical protection.
        public var criticalCount: Int
        /// Track Selected Rooms is on.
        public var selectedEnabled: Bool
        /// Track Selected Rooms is on and the critical select is Track Select Critical.
        public var criticalEnabled: Bool
        /// The critical select's state, or `Unavailable`.
        public var criticalPolicy: String
        public var totalRooms: Int

        /// Selected Rooms opener subtitle.
        public var selectedSubtitle: String {
            selectedEnabled ? "\(selectedCount) of \(totalRooms) selected" : ClimateConfig.Copy.enableTrackSelectedFirst
        }

        /// Critical Protection opener subtitle.
        public var criticalSubtitle: String {
            if criticalEnabled { return "\(PluralCopy.count(criticalCount, "room")) forced" }
            return selectedEnabled ? criticalPolicy : ClimateConfig.Copy.enableTrackSelectedFirst
        }

        /// Occupied Only opener subtitle.
        public var occupiedOnlySubtitle: String { "\(occupiedOnlyCount) of \(totalRooms) occupied only" }

        /// Whether a page's opener is enabled.
        public func isEnabled(_ page: ClimateConfig.TrackingPage) -> Bool {
            switch page {
            case .selectedRooms: selectedEnabled
            case .criticalProtection: criticalEnabled
            case .occupiedOnly: true
            }
        }

        public func subtitle(_ page: ClimateConfig.TrackingPage) -> String {
            switch page {
            case .selectedRooms: selectedSubtitle
            case .criticalProtection: criticalSubtitle
            case .occupiedOnly: occupiedOnlySubtitle
            }
        }
    }

    /// The tracking summary. `state` reads a switch's shown (optimistic) state, so counts follow taps at once.
    public static func trackingSummary(_ lookup: EntityLookup, state: (String) -> String? = { _ in nil }) -> TrackingSummary {
        func shown(_ id: String) -> String? { state(id) ?? lookup(id)?.state }
        let rooms = ClimateConfig.rooms
        let tracked = shown(ClimateConfig.trackSelectedEntityId)
        let policy = shown(ClimateConfig.ecoCriticalEntityId)
        let selectedEnabled = tracked == "on"
        return TrackingSummary(
            selectedCount: rooms.filter { shown($0.trackEntityId) == "on" }.count,
            occupiedOnlyCount: rooms.filter { shown($0.occupiedOnlyEntityId) == "on" }.count,
            criticalCount: rooms.filter { shown($0.trackEntityId) != "on" && shown($0.forceCriticalEntityId) == "on" }.count,
            selectedEnabled: selectedEnabled,
            criticalEnabled: selectedEnabled && policy == ClimateConfig.trackSelectCriticalOption,
            criticalPolicy: policy ?? "Unavailable",
            totalRooms: rooms.count
        )
    }

    /// The rooms a tracking page lists: Critical Protection lists only untracked rooms.
    public static func rooms(for page: ClimateConfig.TrackingPage, state: (String) -> String?) -> [ClimateConfig.Room] {
        guard page == .criticalProtection else { return ClimateConfig.rooms }
        return ClimateConfig.rooms.filter { state($0.trackEntityId) != "on" }
    }

    // MARK: - Select options

    /// One choice in a picker or option page.
    public struct Option: Identifiable, Hashable, Sendable {
        /// The raw value sent to Home Assistant.
        public var value: String
        public var label: String
        /// MDI icon, if the option has one.
        public var icon: String?
        /// Supporting description, if any.
        public var description: String?
        public var id: String { value }
    }

    /// A select's options with their presentation (web `useThermostatSelectControl` + `THERMOSTAT_OPTION_PRESENTATION`).
    public static func selectOptions(_ entity: EntityState?) -> [Option] {
        strings(entity?.attributes["options"]).map { value in
            let presentation = ClimateConfig.optionPresentations[value]
            return Option(value: value, label: selectOption(value), icon: presentation?.icon, description: presentation?.description)
        }
    }

    /// The hub's HVAC modes (`hvac_modes`) with icons and labels.
    public static func hvacModeOptions(_ entity: EntityState?) -> [Option] {
        strings(entity?.attributes["hvac_modes"]).map { value in
            Option(value: value, label: ClimateConfig.hvacModeLabels[value] ?? selectOption(value), icon: ClimateConfig.hvacModeIcons[value])
        }
    }

    /// The hub's fan modes (`fan_modes`); empty hides the fan picker.
    public static func fanModeOptions(_ entity: EntityState?) -> [Option] {
        strings(entity?.attributes["fan_modes"]).map { Option(value: $0, label: selectOption($0), icon: "mdi:fan") }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        (value?.array ?? []).compactMap { item in
            switch item {
            case let .string(text): text
            case let .number(number): number == number.rounded() ? String(Int(number)) : String(number)
            case let .bool(flag): String(flag)
            default: nil
            }
        }
    }

    // MARK: - Predictive Comfort

    /// The recommendation: the switch's `current_recommendation`, else the sensor's state.
    public static func predictiveRecommendation(_ lookup: EntityLookup) -> JSONValue? {
        lookup(ClimateConfig.predictiveComfortEntityId)?.attributes["current_recommendation"]
            ?? lookup(ClimateConfig.predictiveSensorEntityId).map { .string($0.state) }
    }

    /// The Predictive Comfort tile subtitle: `On · Pre-Cool` while on, else the state (web `PredictiveComfortSetting`).
    public static func predictiveSubtitle(_ lookup: EntityLookup, shownState: String?) -> String {
        let entity = lookup(ClimateConfig.predictiveComfortEntityId)
        let state = compactState(entity, state: shownState)
        guard shownState == "on" else { return state }
        return "\(state) · \(predictiveState(predictiveRecommendation(lookup)))"
    }

    /// One labelled value in Current Prediction.
    public struct Metric: Identifiable, Hashable, Sendable {
        public var label: String
        public var value: String
        public var id: String { label }
    }

    /// Indoor, Predicted, Comfort Band, Forecast, Weather and Adjustment (web `PredictiveComfortModalContent`).
    public static func predictiveMetrics(_ sensor: EntityState?) -> [Metric] {
        let attributes = sensor?.attributes ?? [:]
        func temperature(_ key: String) -> String { self.temperature(number(attributes[key])) }
        let forecast = attributes["forecast_low"] == nil && attributes["forecast_high"] == nil
            ? "Unknown" : "\(temperature("forecast_low")) - \(temperature("forecast_high"))"
        let weather: String = switch attributes["weather_entity"] {
        case nil, .null?: "Unknown"
        case let .string(text)?: text
        case let value?: "\(value.foundationValue)"
        }
        return [
            Metric(label: "Indoor", value: temperature("indoor_temperature")),
            Metric(label: "Predicted", value: temperature("predicted_temperature")),
            Metric(label: "Comfort Band", value: "\(temperature("comfort_low")) - \(temperature("comfort_high"))"),
            Metric(label: "Forecast", value: forecast),
            Metric(label: "Weather", value: weather),
            Metric(label: "Adjustment", value: predictiveState(attributes["adjustment_status"])),
        ]
    }

    /// The "Why this prediction?" bullets (web `buildPredictiveReasonBullets`, `DashboardViewPage.tsx:6720`).
    public static func predictiveReasonBullets(_ sensor: EntityState?) -> [String] {
        let attributes = sensor?.attributes ?? [:]
        var bullets: [String] = []
        let indoor = number(attributes["indoor_temperature"])
        let predicted = number(attributes["predicted_temperature"])
        let low = number(attributes["comfort_low"])
        let high = number(attributes["comfort_high"])
        let forecastLow = number(attributes["forecast_low"])
        let forecastHigh = number(attributes["forecast_high"])

        if let reason = attributes["reason"]?.string, !reason.trimmingCharacters(in: .whitespaces).isEmpty {
            bullets.append(sentence(reason))
        }
        if let predicted, let low, let high {
            let position = predicted > high ? "above" : predicted < low ? "below" : "inside"
            bullets.append("Predicted indoor temperature is \(temperature(predicted)), \(position) your \(temperature(low)) - \(temperature(high)) comfort band.")
        } else if let indoor {
            bullets.append("Current indoor temperature is \(temperature(indoor)), so the forecast is being compared against where the house is starting from.")
        }
        if forecastLow != nil || forecastHigh != nil {
            let range = if let forecastLow, let forecastHigh {
                "\(temperature(forecastLow)) - \(temperature(forecastHigh))"
            } else {
                temperature(forecastLow ?? forecastHigh)
            }
            bullets.append("Today's forecast range is \(range), which Predictive Comfort uses to estimate where the house is heading.")
        }
        if let loads = attributes["active_activity_entities"]?.array, !loads.isEmpty {
            let names = loads.map { entityLabel($0.string) }.joined(separator: ", ")
            bullets.append("\(names) \(loads.count == 1 ? "is" : "are") active, so the model is accounting for extra heat from configured devices.")
        } else {
            bullets.append("No configured heat-load devices are active right now.")
        }
        switch attributes["adjustment_status"]?.string {
        case "auto_adjust_disabled": bullets.append("Auto setpoint adjustments are off, so this is only a recommendation.")
        case "hvac_mode_changes_disabled": bullets.append("HVAC mode changes are off, so Predictive Comfort will not switch between heat and cool automatically.")
        case "skipped_away_mode": bullets.append("Away Mode is active and away adjustments are off, so Predictive Comfort will not change the thermostat.")
        case "rate_limited": bullets.append("Thermostat changes are paused briefly to avoid rapid repeated adjustments.")
        case "applied": bullets.append("Predictive Comfort has already applied the safe thermostat change.")
        default: break
        }
        // The heat-load line always appears, so the web's empty fallback cannot be reached; kept for parity.
        return bullets.isEmpty ? ["Predictive Comfort is waiting for enough live sensor and forecast data to explain this recommendation."] : bullets
    }

    /// Ends with `.`, `!` or `?` (web `sentence`).
    static func sentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return "" }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// `binary_sensor.demo_pc_power` → `Demo PC Power` (web `formatPredictiveEntityLabel`).
    static func entityLabel(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return "Unknown" }
        let name = value.contains(".") ? value.split(separator: ".", omittingEmptySubsequences: false).dropFirst().joined(separator: ".") : value
        return StateText.titleCase(name.replacingOccurrences(of: ".", with: "_"))
            .replacingOccurrences(of: "\\bPc\\b", with: "PC", options: .regularExpression)
    }
}
