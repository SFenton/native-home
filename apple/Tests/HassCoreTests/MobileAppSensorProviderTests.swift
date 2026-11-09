import Foundation
@testable import HassCore
import Testing

@Suite("Mobile app sensors")
struct MobileAppSensorProviderTests {
    func sensor(_ id: String, in sensors: [MobileAppSensor]) throws -> MobileAppSensor {
        try #require(sensors.first { $0.uniqueID == id }, "\(id) missing")
    }

    @Test func nothingIsReportedWithoutReadings() {
        #expect(MobileAppSensors.sensors(for: DeviceStatus()).isEmpty)
    }

    @Test func everyReadingReportsTheOfficialAppsSensors() {
        let status = DeviceStatus(
            battery: .init(level: 80, state: .notCharging), network: .init(connection: .wifi, ssid: "DemoNet", bssid: "a:b:c:d:e:f"),
            locationPermission: LocationPermission(authorization: .always), appVersion: "0.1.0",
            audioOutputs: ["Built-in Speaker"], lastUpdateTrigger: .launch, place: GeocodedPlace(), isFocused: false
        )
        let sensors = MobileAppSensors.sensors(for: status)
        #expect(sensors.map(\.uniqueID) == [
            "battery_level", "battery_state", "connectivity_connection_type", "connectivity_ssid", "connectivity_bssid",
            "location-permission", "last_update_trigger", "geocoded_location", "app-version",
            "iphone-audio-output", "focus",
        ])
        #expect(sensors.map(\.name) == [
            "Battery Level", "Battery State", "Connection Type", "SSID", "BSSID", "Location permission",
            "Last Update Trigger", "Geocoded Location", "App Version", "Audio Output", "Focus",
        ])
    }

    @Test func battery() throws {
        let sensors = BatterySensors().sensors(for: DeviceStatus(battery: .init(level: 87, state: .notCharging, isLowPowerMode: true)))
        let level = try sensor("battery_level", in: sensors)
        #expect(level.state == .int(87))
        #expect(level.deviceClass == "battery" && level.unit == "%" && level.stateClass == "measurement")
        #expect(level.icon == "mdi:battery-80")
        #expect(level.attributes["Low Power Mode"] == .bool(true))
        #expect(level.attributes["Battery State"] == "Not Charging")
        let state = try sensor("battery_state", in: sensors)
        #expect(state.state == "Not Charging")
        #expect(state.attributes["Battery Level"] == .int(87))
    }

    @Test(arguments: [
        (100, DeviceStatus.Battery.State.full, "mdi:battery"), (55, .notCharging, "mdi:battery-50"),
        (9, .notCharging, "mdi:battery-outline"), (10, .unknown, "mdi:battery-10"),
        (100, .charging, "mdi:battery-charging-100"), (85, .charging, "mdi:battery-charging-80"),
        (65, .charging, "mdi:battery-charging-60"), (45, .charging, "mdi:battery-charging-40"),
        (25, .charging, "mdi:battery-charging-20"), (5, .charging, "mdi:battery-outline"),
    ])
    func batteryIcons(level: Int, state: DeviceStatus.Battery.State, icon: String) {
        #expect(BatterySensors.icon(level: level, state: state) == icon)
    }

    @Test func batteryLevelIsClamped() {
        #expect(DeviceStatus.Battery(level: 140, state: .full).level == 100)
        #expect(DeviceStatus.Battery(level: -5, state: .unknown).level == 0)
    }

    @Test func connectivity() throws {
        let connected = ConnectivitySensors().sensors(for: DeviceStatus(network: .init(connection: .wifi, ssid: "DemoNet", bssid: "a:1b:c:d:e:0")))
        #expect(try sensor("connectivity_connection_type", in: connected).state == "Wi-Fi")
        #expect(try sensor("connectivity_connection_type", in: connected).icon == "mdi:wifi")
        #expect(try sensor("connectivity_ssid", in: connected).state == "DemoNet")
        #expect(try sensor("connectivity_ssid", in: connected).icon == "mdi:wifi")
        #expect(try sensor("connectivity_bssid", in: connected).state == "0a:1b:0c:0d:0e:00")
        #expect(try sensor("connectivity_bssid", in: connected).icon == "mdi:wifi-star")

        let cellular = ConnectivitySensors().sensors(for: DeviceStatus(network: .init(connection: .cellular)))
        #expect(try sensor("connectivity_ssid", in: cellular).state == "Not Connected")
        #expect(try sensor("connectivity_ssid", in: cellular).icon == "mdi:wifi-off")
        #expect(try sensor("connectivity_bssid", in: cellular).state == "Not Connected")
        #expect(try sensor("connectivity_bssid", in: cellular).icon == "mdi:wifi-off")

        let unreadable = ConnectivitySensors().sensors(for: DeviceStatus(network: .init(connection: .wifi, canReadWiFi: false)))
        #expect(unreadable.map(\.uniqueID) == ["connectivity_connection_type"], "No entitlement: no SSID or BSSID")
    }

    @Test(arguments: [
        (DeviceStatus.Network.Connection.wifi, "Wi-Fi", "mdi:wifi"), (.cellular, "Cellular", "mdi:signal"),
        (.ethernet, "Ethernet", "mdi:ethernet"), (.none, "No Connection", "mdi:sim-off"), (.unknown, "Unknown", "mdi:help-circle"),
    ])
    func connectionTypes(connection: DeviceStatus.Network.Connection, state: String, icon: String) {
        #expect(connection.rawValue == state)
        #expect(connection.icon == icon)
    }

    @Test(arguments: [
        (LocationPermission.Authorization.notDetermined, "Not determined"), (.restricted, "Restricted"), (.denied, "Denied"),
        (.whenInUse, "Authorized when in use"), (.always, "Authorized Always"),
    ])
    func locationPermission(authorization: LocationPermission.Authorization, state: String) throws {
        let sensors = LocationPermissionSensor().sensors(for: DeviceStatus(locationPermission: LocationPermission(authorization: authorization, isPrecise: false)))
        let permission = try sensor("location-permission", in: sensors)
        #expect(permission.state == .string(state))
        #expect(permission.entityCategory == .diagnostic)
        #expect(permission.attributes["Precise"] == .bool(false))
    }

    @Test func lastUpdateTrigger() throws {
        let sensors = LastUpdateTriggerSensor().sensors(for: DeviceStatus(lastUpdateTrigger: .regionExited))
        #expect(try sensor("last_update_trigger", in: sensors).state == "Geographic Region Exited")
    }

    @Test func geocodedLocation() throws {
        let place = GeocodedPlace(
            name: "1 Main St", subThoroughfare: "1", thoroughfare: "Main St", subLocality: "Downtown", locality: "Cupertino",
            subAdministrativeArea: "Santa Clara", administrativeArea: "CA", postalCode: "95014", country: "United States",
            isoCountryCode: "US", timeZone: "America/Los_Angeles", areasOfInterest: ["Pike Place"],
            coordinate: [37.6, -122.3], zones: ["Home"]
        )
        let geocoded = try sensor("geocoded_location", in: GeocodedLocationSensor().sensors(for: DeviceStatus(place: place)))
        #expect(geocoded.state == "1 Main St\nCupertino, CA 95014\nUnited States")
        #expect(geocoded.attributes["Locality"] == "Cupertino")
        #expect(geocoded.attributes["Ocean"] == "N/A")
        #expect(geocoded.attributes["Areas Of Interest"] == .array(["Pike Place"]))
        #expect(geocoded.attributes["Location"] == .array([37.6, -122.3]))
        #expect(geocoded.attributes["Zones"] == .array(["Home"]))
        #expect(geocoded.attributes.count == 16)

        let unknown = try sensor("geocoded_location", in: GeocodedLocationSensor().sensors(for: DeviceStatus(place: GeocodedPlace())))
        #expect(unknown.state == "Unknown")
        #expect(unknown.attributes["Location"] == "N/A")
        #expect(unknown.attributes["Areas Of Interest"] == "N/A")
        #expect(unknown.attributes["Zones"] == .array([]))
    }

    @Test func mailingAddressSkipsMissingParts() {
        #expect(GeocodedPlace(locality: "Cupertino").mailingAddress == "Cupertino")
        #expect(GeocodedPlace(postalCode: "95014", country: "US").mailingAddress == "95014\nUS")
        #expect(GeocodedPlace(thoroughfare: "Main St").mailingAddress == "Main St")
        #expect(GeocodedPlace().mailingAddress == nil)
    }

    @Test func device() throws {
        let status = DeviceStatus(
            appVersion: "0.1.0",
            audioOutputs: ["Built-in Speaker", "AirPlay"], isFocused: true
        )
        let sensors = MobileAppSensors.sensors(for: status)
        #expect(try sensor("app-version", in: sensors).state == "0.1.0")
        // Disk space is not reported: Apple's only display reason (85F4.1) forbids sending it off the device.
        #expect(!sensors.contains { $0.uniqueID == "storage" })
        #expect(try sensor("iphone-audio-output", in: sensors).state == "Built-in Speaker, AirPlay")
        let focus = try sensor("focus", in: sensors)
        #expect(focus.kind == .binarySensor && focus.state == .bool(true))
    }

    @Test func sensorValueLiteralsAndJSON() {
        let values: [SensorValue] = ["a", 1, 1.5, true, .array([.null])]
        #expect(values == [.string("a"), .int(1), .double(1.5), .bool(true), .array([.null])])
        #expect(values[0].jsonObject as? String == "a")
        #expect((values[4].jsonObject as? [Any])?.first is NSNull)
    }
}

@Suite("Location permission")
struct LocationPermissionTests {
    @Test(arguments: [
        (LocationPermission(authorization: .notDetermined), LocationPermission.Stage.notDetermined),
        (LocationPermission(authorization: .whenInUse), .whenInUse),
        (LocationPermission(authorization: .always), .always),
        (LocationPermission(authorization: .denied), .denied),
        (LocationPermission(authorization: .restricted), .denied),
        (LocationPermission(authorization: .whenInUse, isPrecise: false), .reducedAccuracy),
        (LocationPermission(authorization: .always, isPrecise: false), .reducedAccuracy),
    ])
    func stages(permission: LocationPermission, stage: LocationPermission.Stage) {
        #expect(permission.stage == stage)
    }

    @Test func backgroundNeedsAlwaysAndPrecise() {
        #expect(LocationPermission(authorization: .always).allowsBackgroundReporting)
        #expect(!LocationPermission(authorization: .always, isPrecise: false).allowsBackgroundReporting)
        #expect(!LocationPermission(authorization: .whenInUse).allowsBackgroundReporting)
        #expect(LocationPermission(authorization: .whenInUse).isAuthorized)
        #expect(!LocationPermission.notDetermined.isAuthorized)
    }
}
