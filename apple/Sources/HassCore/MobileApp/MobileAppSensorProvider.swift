import Foundation

/// Turns one part of a ``DeviceStatus`` into `mobile_app` sensors. A provider whose reading is nil reports nothing.
///
/// Every name, unique id, state string and icon mirrors the official Home Assistant app's sensor of the same name
/// (`home-assistant/iOS` `Sources/Shared/API/Webhook/Sensors`), so templates port by changing the device prefix.
public protocol MobileAppSensorProvider: Sendable {
    /// The sensors for `status`.
    func sensors(for status: DeviceStatus) -> [MobileAppSensor]
}

/// Every provider the app reports, in registration order.
public enum MobileAppSensors {
    /// The core set (plan Phase 3).
    public static let standard: [any MobileAppSensorProvider] = [
        BatterySensors(), ConnectivitySensors(), LocationPermissionSensor(), LastUpdateTriggerSensor(),
        GeocodedLocationSensor(), AppVersionSensor(), AudioOutputSensor(), FocusSensor(),
    ]

    /// Every sensor `providers` report for `status`.
    public static func sensors(for status: DeviceStatus,
                               providers: [any MobileAppSensorProvider] = standard) -> [MobileAppSensor] {
        providers.flatMap { $0.sensors(for: status) }
    }
}

// MARK: - Battery

/// "Battery Level" (`battery_level`) and "Battery State" (`battery_state`).
public struct BatterySensors: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let battery = status.battery else { return [] }
        let icon = Self.icon(level: battery.level, state: battery.state)
        return [
            MobileAppSensor(
                uniqueID: "battery_level", name: "Battery Level", state: .int(battery.level), icon: icon,
                deviceClass: "battery", unit: "%", stateClass: "measurement",
                attributes: ["Battery State": .string(battery.state.rawValue), "Low Power Mode": .bool(battery.isLowPowerMode)]
            ),
            MobileAppSensor(
                uniqueID: "battery_state", name: "Battery State", state: .string(battery.state.rawValue), icon: icon,
                attributes: ["Battery Level": .int(battery.level), "Low Power Mode": .bool(battery.isLowPowerMode)]
            ),
        ]
    }

    /// The official app's battery icon: tenths while discharging, the charging set's coarser steps while charging.
    static func icon(level: Int, state: DeviceStatus.Battery.State) -> String {
        if state == .charging {
            switch level {
            case 100...: return "mdi:battery-charging-100"
            case 80...: return "mdi:battery-charging-80"
            case 60...: return "mdi:battery-charging-60"
            case 40...: return "mdi:battery-charging-40"
            case 20...: return "mdi:battery-charging-20"
            default: return "mdi:battery-outline"
            }
        }
        switch level {
        case 100...: return "mdi:battery"
        case 10...: return "mdi:battery-\(level / 10 * 10)"
        default: return "mdi:battery-outline"
        }
    }
}

// MARK: - Connectivity

/// "Connection Type" (`connectivity_connection_type`), "SSID" (`connectivity_ssid`) and "BSSID"
/// (`connectivity_bssid`). SSID and BSSID are left out when the app may not read Wi-Fi details.
public struct ConnectivitySensors: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let network = status.network else { return [] }
        var sensors = [
            MobileAppSensor(uniqueID: "connectivity_connection_type", name: "Connection Type",
                            state: .string(network.connection.rawValue), icon: network.connection.icon),
        ]
        guard network.canReadWiFi else { return sensors }
        sensors.append(MobileAppSensor(
            uniqueID: "connectivity_ssid", name: "SSID", state: .string(network.ssid ?? "Not Connected"),
            icon: network.ssid == nil ? "mdi:wifi-off" : "mdi:wifi"
        ))
        sensors.append(MobileAppSensor(
            uniqueID: "connectivity_bssid", name: "BSSID", state: .string(network.bssid.map(Self.formatBSSID) ?? "Not Connected"),
            icon: network.bssid == nil ? "mdi:wifi-off" : "mdi:wifi-star"
        ))
        return sensors
    }

    /// Pads each octet to two digits (`0:1a:b` → `00:1a:0b`), as iOS sometimes drops leading zeros.
    static func formatBSSID(_ bssid: String) -> String {
        bssid.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.count == 1 ? "0\($0)" : String($0) }
            .joined(separator: ":")
    }
}

// MARK: - Location

/// "Location permission" (`location-permission`), with the official app's state strings.
public struct LocationPermissionSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let permission = status.locationPermission else { return [] }
        return [MobileAppSensor(
            uniqueID: "location-permission", name: "Location permission", state: .string(permission.sensorState),
            icon: "mdi:map", entityCategory: .diagnostic,
            attributes: ["Precise": .bool(permission.isPrecise)]
        )]
    }
}

/// "Last Update Trigger" (`last_update_trigger`): why the last location update was sent.
public struct LastUpdateTriggerSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let trigger = status.lastUpdateTrigger else { return [] }
        return [MobileAppSensor(uniqueID: "last_update_trigger", name: "Last Update Trigger",
                                state: .string(trigger.rawValue), icon: "mdi:cellphone-wireless",
                                entityCategory: .diagnostic)]
    }
}

/// "Geocoded Location" (`geocoded_location`): the mailing address of the last fix, and its parts as attributes
/// with the official app's keys ("N/A" for unknown parts).
public struct GeocodedLocationSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let place = status.place else { return [] }
        func text(_ value: String?) -> SensorValue { .string(value ?? "N/A") }
        let attributes: [String: SensorValue] = [
            "Administrative Area": text(place.administrativeArea),
            "Areas Of Interest": place.areasOfInterest.isEmpty ? "N/A" : .array(place.areasOfInterest.map(SensorValue.string)),
            "Country": text(place.country),
            "Inland Water": text(place.inlandWater),
            "ISO Country Code": text(place.isoCountryCode),
            "Locality": text(place.locality),
            "Location": place.coordinate.map { .array($0.map(SensorValue.double)) } ?? "N/A",
            "Name": text(place.name),
            "Ocean": text(place.ocean),
            "Postal Code": text(place.postalCode),
            "Sub Administrative Area": text(place.subAdministrativeArea),
            "Sub Locality": text(place.subLocality),
            "Sub Thoroughfare": text(place.subThoroughfare),
            "Thoroughfare": text(place.thoroughfare),
            "Time Zone": text(place.timeZone),
            "Zones": .array(place.zones.map(SensorValue.string)),
        ]
        return [MobileAppSensor(uniqueID: "geocoded_location", name: "Geocoded Location",
                                state: .string(place.mailingAddress ?? "Unknown"), icon: "mdi:map",
                                attributes: attributes)]
    }
}

// MARK: - Device

/// "App Version" (`app-version`).
public struct AppVersionSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let version = status.appVersion else { return [] }
        return [MobileAppSensor(uniqueID: "app-version", name: "App Version", state: .string(version),
                                icon: "mdi:cellphone-information", entityCategory: .diagnostic)]
    }
}

/// "Audio Output" (`iphone-audio-output`): the current output ports, comma separated.
public struct AudioOutputSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let outputs = status.audioOutputs else { return [] }
        return [MobileAppSensor(uniqueID: "iphone-audio-output", name: "Audio Output",
                                state: .string(outputs.joined(separator: ", ")), icon: "mdi:volume-high")]
    }
}

/// "Focus" (`focus`): a binary sensor, on while any Focus is on.
public struct FocusSensor: MobileAppSensorProvider {
    public init() {}

    public func sensors(for status: DeviceStatus) -> [MobileAppSensor] {
        guard let isFocused = status.isFocused else { return [] }
        return [MobileAppSensor(uniqueID: "focus", name: "Focus", kind: .binarySensor, state: .bool(isFocused),
                                icon: "mdi:moon-waning-crescent")]
    }
}
