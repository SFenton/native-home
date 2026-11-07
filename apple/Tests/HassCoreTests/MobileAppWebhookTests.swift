import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The JSON body a stub transport recorded.
func sentBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

let mobileAppServer = HassServer(baseURL: URL(string: "https://ha.example.com")!)
let mobileAppWebhook = MobileAppWebhook(server: mobileAppServer, webhookID: "hook-123")

// MARK: - Client

@Suite("Mobile app webhook client")
struct MobileAppWebhookClientTests {
    func client(_ transport: StubHTTPTransport, webhook: MobileAppWebhook? = mobileAppWebhook) -> MobileAppWebhookClient {
        MobileAppWebhookClient(source: FixedMobileAppWebhookSource(webhook), transport: transport)
    }

    @Test func updateLocationPostsToTheWebhookWithoutAToken() async throws {
        let transport = StubHTTPTransport([(200, "{}")])
        let report = try #require(LocationReport(fix: LocationFix(latitude: 37.6, longitude: -122.3, horizontalAccuracy: 12)))
        try await client(transport).updateLocation(report)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://ha.example.com/api/webhook/hook-123")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "The webhook id addresses the registration")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try sentBody(request)
        #expect(body["type"] as? String == "update_location")
        #expect((body["data"] as? [String: Any])?["gps_accuracy"] as? Int == 12)
    }

    @Test func registerAndUpdateSensors() async throws {
        let transport = StubHTTPTransport([
            (201, #"{"success":true}"#),
            (200, #"{"battery_level":{"success":true},"focus":{"success":true,"is_disabled":true},"#
                + #""connectivity_ssid":{"success":false,"error":{"code":"not_registered","message":"x"}},"#
                + #""storage":{"success":false,"error":{"code":"invalid_format"}},"app-version":{"success":false}}"#),
        ])
        let sensor = MobileAppSensor(uniqueID: "battery_level", name: "Battery Level", state: 80)
        let webhook = client(transport)
        try await webhook.registerSensor(sensor)
        let outcome = try await webhook.updateSensorStates([sensor])
        #expect(try sentBody(transport.requests[0])["type"] as? String == "register_sensor")
        #expect(try sentBody(transport.requests[1])["type"] as? String == "update_sensor_states")
        #expect(outcome.notRegistered == ["connectivity_ssid"])
        #expect(outcome.disabled == ["focus"])
        #expect(outcome.failed == ["storage": "invalid_format", "app-version": "unknown"])
    }

    @Test func emptyUpdateSendsNothing() async throws {
        let transport = StubHTTPTransport([])
        #expect(try await client(transport).updateSensorStates([]) == SensorUpdateOutcome())
        #expect(transport.requests.isEmpty)
    }

    @Test func unreadableUpdateResponseIsUnexpected() async throws {
        let transport = StubHTTPTransport([(200, "[]")])
        await #expect(throws: MobileAppWebhookError.unexpectedResponse) {
            _ = try await client(transport).updateSensorStates([MobileAppSensor(uniqueID: "a", name: "A", state: 1)])
        }
        let nested = StubHTTPTransport([(200, #"{"a":true}"#)])
        await #expect(throws: MobileAppWebhookError.unexpectedResponse) {
            _ = try await client(nested).updateSensorStates([MobileAppSensor(uniqueID: "a", name: "A", state: 1)])
        }
    }

    @Test func zonesAreRead() async throws {
        let transport = StubHTTPTransport([(200, """
        [{"entity_id":"zone.home","state":"1","attributes":{"latitude":37.6,"longitude":-122.3,"radius":50,"passive":false,"friendly_name":"Home"}},
         {"entity_id":"zone.work","attributes":{"latitude":37.7,"longitude":-122.2,"radius":200.5}},
         {"entity_id":"sensor.demo_not_a_zone","attributes":{"latitude":1,"longitude":2,"radius":3}},
         {"entity_id":"zone.demo_broken","attributes":{"latitude":1}},
         "junk"]
        """)])
        let zones = try await client(transport).zones()
        #expect(try sentBody(transport.requests[0])["type"] as? String == "get_zones")
        #expect(zones == [
            HAZone(entityID: "zone.home", latitude: 37.6, longitude: -122.3, radius: 50, friendlyName: "Home"),
            HAZone(entityID: "zone.work", latitude: 37.7, longitude: -122.2, radius: 200.5, friendlyName: "work"),
        ])
        await #expect(throws: MobileAppWebhookError.unexpectedResponse) {
            _ = try await client(StubHTTPTransport([(200, "{}")])).zones()
        }
    }

    @Test func failuresAreTyped() async throws {
        let report = try #require(LocationReport(fix: LocationFix(latitude: 1, longitude: 2, horizontalAccuracy: 5)))
        await #expect(throws: MobileAppWebhookError.notRegistered) {
            try await client(StubHTTPTransport([]), webhook: nil).updateLocation(report)
        }
        await #expect(throws: MobileAppWebhookError.registrationGone) {
            try await client(StubHTTPTransport([(410, "")])).updateLocation(report)
        }
        await #expect(throws: MobileAppWebhookError.status(500)) {
            try await client(StubHTTPTransport([(500, "")])).updateLocation(report)
        }
        let offline = StubHTTPTransport([])
        offline.error = URLError(.notConnectedToInternet)
        await #expect(throws: MobileAppWebhookError.network) {
            try await client(offline).updateLocation(report)
        }
        let cancelled = StubHTTPTransport([])
        cancelled.error = CancellationError()
        await #expect(throws: CancellationError.self) {
            try await client(cancelled).updateLocation(report)
        }
    }
}

// MARK: - Bodies

@Suite("Location report body")
struct LocationReportTests {
    @Test func everyValidFieldIsSentRounded() throws {
        let fix = LocationFix(latitude: 37.61, longitude: -122.33, horizontalAccuracy: 8.6, altitude: -3.4,
                              verticalAccuracy: 4.5, speed: 2.4, course: 359.6)
        let report = try #require(LocationReport(fix: fix, batteryLevel: 81, locationName: "home"))
        let data = report.webhookData
        #expect(data["gps"] as? [Double] == [37.61, -122.33])
        #expect(data["gps_accuracy"] as? Int == 9)
        #expect(data["battery"] as? Int == 81)
        #expect(data["speed"] as? Int == 2)
        #expect(data["course"] as? Int == 360)
        #expect(data["altitude"] as? Int == -3, "Below sea level is a real altitude")
        #expect(data["vertical_accuracy"] as? Int == 5)
        #expect(data["location_name"] as? String == "home")
        #expect(report.webhookBody["type"] as? String == "update_location")
    }

    @Test func invalidValuesAreLeftOut() throws {
        let fix = LocationFix(latitude: 1, longitude: 2, horizontalAccuracy: 30, altitude: 120, verticalAccuracy: -1,
                              speed: -1, course: -1)
        let data = try #require(LocationReport(fix: fix, batteryLevel: -1)).webhookData
        #expect(Set(data.keys) == ["gps", "gps_accuracy"])
        #expect(try #require(LocationReport(fix: fix, batteryLevel: 101)).batteryLevel == nil)
    }

    @Test func invalidFixesMakeNoReport() {
        #expect(LocationReport(fix: LocationFix(latitude: 1, longitude: 2, horizontalAccuracy: -1)) == nil)
        #expect(LocationReport(fix: LocationFix(latitude: 91, longitude: 2, horizontalAccuracy: 5)) == nil)
        #expect(LocationReport(fix: LocationFix(latitude: 1, longitude: 181, horizontalAccuracy: 5)) == nil)
    }
}

@Suite("Mobile app sensor bodies")
struct MobileAppSensorBodyTests {
    @Test func registerCarriesTheMetadata() throws {
        let sensor = MobileAppSensor(uniqueID: "battery_level", name: "Battery Level", state: 80, icon: "mdi:battery-80",
                                     deviceClass: "battery", unit: "%", stateClass: "measurement",
                                     entityCategory: .diagnostic, attributes: ["Low Power Mode": false])
        let body = sensor.registerBody
        #expect(body["type"] as? String == "register_sensor")
        let data = try #require(body["data"] as? [String: Any])
        #expect(data["unique_id"] as? String == "battery_level")
        #expect(data["name"] as? String == "Battery Level")
        #expect(data["type"] as? String == "sensor")
        #expect(data["state"] as? Int == 80)
        #expect(data["icon"] as? String == "mdi:battery-80")
        #expect(data["device_class"] as? String == "battery")
        #expect(data["unit_of_measurement"] as? String == "%")
        #expect(data["state_class"] as? String == "measurement")
        #expect(data["entity_category"] as? String == "diagnostic")
        #expect((data["attributes"] as? [String: Any])?["Low Power Mode"] as? Bool == false)
        #expect(sensor.id == "battery_level")
    }

    @Test func registerLeavesOutMissingMetadata() throws {
        let data = try #require(MobileAppSensor(uniqueID: "focus", name: "Focus", kind: .binarySensor, state: true)
            .registerBody["data"] as? [String: Any])
        #expect(Set(data.keys) == ["unique_id", "name", "type", "state", "attributes"])
        #expect(data["type"] as? String == "binary_sensor")
    }

    @Test func updateCarriesOnlyWhatChanges() throws {
        let sensors = [
            MobileAppSensor(uniqueID: "ssid", name: "SSID", state: "Home", icon: "mdi:wifi", deviceClass: "x", unit: "y"),
            MobileAppSensor(uniqueID: "geo", name: "Geo", state: .null, attributes: ["Location": .array([1.5, 2.5]), "N": 3.5]),
        ]
        let body = MobileAppSensor.updateBody(sensors)
        #expect(body["type"] as? String == "update_sensor_states")
        let entries = try #require(body["data"] as? [[String: Any]])
        #expect(Set(entries[0].keys) == ["unique_id", "type", "state", "icon", "attributes"])
        #expect(entries[0]["state"] as? String == "Home")
        #expect(entries[1]["state"] is NSNull)
        #expect(Set(entries[1].keys) == ["unique_id", "type", "state", "attributes"])
        let attributes = try #require(entries[1]["attributes"] as? [String: Any])
        #expect(attributes["Location"] as? [Double] == [1.5, 2.5])
        #expect(attributes["N"] as? Double == 3.5)
    }

    @Test func outcomeRejectsOtherShapes() {
        #expect(SensorUpdateOutcome(json: Data("nope".utf8)) == nil)
        #expect(SensorUpdateOutcome(json: Data(#"{"a":{"success":true}}"#.utf8)) == SensorUpdateOutcome())
    }
}

@Suite("Mobile app webhook target")
struct MobileAppWebhookTargetTests {
    @Test func urlAddressesTheWebhook() async {
        #expect(mobileAppWebhook.url.absoluteString == "https://ha.example.com/api/webhook/hook-123")
        #expect(await FixedMobileAppWebhookSource(mobileAppWebhook).currentWebhook() == mobileAppWebhook)
        #expect(await FixedMobileAppWebhookSource(nil).currentWebhook() == nil)
    }
}
