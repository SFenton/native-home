import HassCore
import HassDesign
import SwiftUI

// MARK: - Entity mapping

extension ThermostatDialConfiguration {
    /// Maps a `climate` entity the way the web's `ThermostatDial` reads it
    /// (`ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4188`).
    ///
    /// - Range mode when both `target_temp_low` and `target_temp_high` are numbers, else one `temperature` handle.
    /// - Range defaults: `min_temp` 45, `max_temp` 95, `target_temp_step` 0.5.
    /// - The action is `hvac_action`, falling back to the state.
    /// - Parameters:
    ///   - entity: The climate entity, or `nil` if the server doesn't know it (shown unavailable).
    ///   - title: Name used in accessibility labels.
    public init(entity: EntityState?, title: String) {
        let attributes = entity?.attributes ?? [:]
        let low = attributes["target_temp_low"]?.number
        let high = attributes["target_temp_high"]?.number
        let targets: ThermostatTargets? = if let low, let high {
            .range(low: low, high: high)
        } else {
            attributes["temperature"]?.number.map { .single($0) }
        }
        self.init(
            title: title,
            min: attributes["min_temp"]?.number ?? 45,
            max: attributes["max_temp"]?.number ?? 95,
            step: attributes["target_temp_step"]?.number ?? 0.5,
            current: attributes["current_temperature"]?.number,
            targets: targets,
            action: attributes["hvac_action"]?.string ?? entity?.state ?? "idle",
            unit: attributes["temperature_unit"]?.string ?? attributes["unit_of_measurement"]?.string ?? "°F",
            isUnavailable: entity?.isUnavailable ?? true,
            isOff: entity?.state == "off"
        )
    }
}

extension ThermostatTargets {
    /// What the dial says when Home Assistant rejects these setpoints: "Couldn't set 68°. Check the connection."
    public var failureMessage: String {
        func text(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
        }
        switch self {
        case let .single(value): return "Couldn't set \(text(value))°. Check the connection."
        case let .range(low, high): return "Couldn't set \(text(low))° to \(text(high))°. Check the connection."
        }
    }

    /// `climate.set_temperature` service data for `entityIds`.
    public func setTemperatureData(entityIds: [String]) -> [String: any Sendable] {
        var data: [String: any Sendable] = serviceData
        data["entity_id"] = entityIds.count == 1 ? entityIds[0] : entityIds
        return data
    }
}
