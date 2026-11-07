import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The optional schema-2 fields that carry ids the app used to derive from a name: a climate room's
/// `occupiedOnlyEntityId` and an air purifier's `aqiEntityId`, `autoModeEntityId`, `fanEntityId` and `modeEntityId`.
/// A document that names them wins; a missing field falls back to the generic derivation.
struct HouseConfigDerivedIdFieldsTests {
    // MARK: - Climate rooms

    @Test func aRoomReadsItsOccupiedOnlySwitchFromTheDocument() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let rooms = ClimateConfig.rooms
            #expect(!rooms.isEmpty)
            for room in rooms {
                #expect(room.occupiedOnlyEntityId == "switch.demo_\(room.key)_occupied_only")
            }
        }
    }

    @Test func aRoomWithoutTheFieldIsNotConfiguredAndNeverGuessed() throws {
        let room = try JSONDecoder().decode(ClimateConfig.Room.self, from: Data(#"{"title": "Demo Room", "ventEntityIds": []}"#.utf8))
        #expect(room.occupiedOnlyOverride == nil)
        #expect(room.occupiedOnlyEntityId.isEmpty)
    }

    @Test func aRoomRoundTripsTheFieldAndOmitsAMissingOne() throws {
        let named = ClimateConfig.Room("Demo Room", occupiedOnlyEntityId: "switch.demo_named")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(named)) as? [String: Any])
        #expect(object["occupiedOnlyEntityId"] as? String == "switch.demo_named")
        #expect(try JSONDecoder().decode(ClimateConfig.Room.self, from: JSONEncoder().encode(named)) == named)

        let bare = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ClimateConfig.Room("Demo Room"))) as? [String: Any])
        #expect(bare["occupiedOnlyEntityId"] == nil)
    }

    // MARK: - Air purifiers

    @Test func aPurifierReadsItsIdsFromTheDocument() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let purifiers = AirPurifierConfig.all
            #expect(purifiers.count == 6)
            for purifier in purifiers {
                #expect(purifier.aqiEntityId.hasSuffix("_air_quality_index") && purifier.fanEntityId.hasSuffix("_purifier"))
                #expect(purifier.fanEntityId.hasPrefix("fan.demo_") && purifier.modeEntityId.hasPrefix("select.demo_"))
            }
        }
    }

    @Test func aPurifierWithoutTheFieldsHasNoFanAndDerivesTheGenericSensors() throws {
        let json = #"{"roomTitle": "Demo Room", "pm25EntityId": "sensor.demo_unit_pm2_5"}"#
        let purifier = try JSONDecoder().decode(AirPurifierConfig.self, from: Data(json.utf8))
        #expect(purifier.aqiEntityId == "sensor.demo_unit_air_quality_index")
        #expect(purifier.autoModeEntityId == "select.demo_unit_auto_mode")
        #expect(purifier.fanEntityId.isEmpty)
        #expect(purifier.modeEntityId == "select.demo_unit_fan_mode")
    }

    @Test func aPurifierFieldWinsOverTheDerivationOneAtATime() throws {
        let json = #"{"roomTitle": "Demo Room", "pm25EntityId": "sensor.demo_unit_pm2_5", "fanEntityId": "fan.demo_named"}"#
        let purifier = try JSONDecoder().decode(AirPurifierConfig.self, from: Data(json.utf8))
        #expect(purifier.fanEntityId == "fan.demo_named")
        #expect(purifier.modeEntityId == "select.demo_unit_fan_mode")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(purifier)) as? [String: Any])
        #expect(object["fanEntityId"] as? String == "fan.demo_named" && object["modeEntityId"] == nil)
    }

    @Test func theDemoDocumentRoundTrips() throws {
        let data = try DemoHouse.config.encoded()
        #expect(try HouseConfig.decode(data) == DemoHouse.config)
    }
}
