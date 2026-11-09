@testable import HassCore
import HassTestSupport
import Testing

/// The optional schema fields for ids that used to live outside the `*Config` facades: the document's value wins, a missing
/// field answers empty, and the demo house resolves.
@MainActor
struct HouseConfigOutsideFacadesTests {
    private static func source(_ edit: (inout HouseConfig) -> Void) -> HouseConfigSource {
        var house = DemoHouse.config
        edit(&house)
        let source = HouseConfigSource()
        source.set(house)
        return source
    }

    // MARK: - Weather

    @Test func weatherIdsComeFromTheDocument() {
        let source = Self.source { $0.home.airQualityEntityId = "sensor.demo_aqi_x"; $0.home.sunEntityId = "sun.demo_x" }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(WeatherEntities.airQuality == "sensor.demo_aqi_x")
            #expect(WeatherEntities.sun == "sun.demo_x")
        }
    }

    @Test func missingWeatherIdsAnswerEmpty() {
        let source = Self.source { $0.home.airQualityEntityId = nil; $0.home.sunEntityId = nil }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(WeatherEntities.airQuality.isEmpty)
            #expect(WeatherEntities.sun.isEmpty)
        }
    }

    @Test func theDemoHouseResolvesWeatherIds() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(WeatherEntities.airQuality == DemoHouse.config.home.airQualityEntityId)
            #expect(WeatherEntities.airQuality.contains("demo_"))
            #expect(WeatherEntities.sun.contains("demo_"))
        }
    }

    // MARK: - Script-powered devices

    @Test func scriptPowerDevicesComeFromTheDocument() {
        let device = ScriptPowerActions(activeEntityId: "input_boolean.demo_a", onScript: "demo_on", offScript: "demo_off")
        let source = Self.source { $0.media.scriptPowerDevices = [device] }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(ScriptPowerActions.all == [device])
            #expect(ScriptPowerActions.toggleScript == "demo_off")
        }
    }

    @Test func missingScriptPowerDevicesAnswerNone() {
        let source = Self.source { $0.media.scriptPowerDevices = nil }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(ScriptPowerActions.all.isEmpty)
            #expect(ScriptPowerActions.toggleScript.isEmpty)
        }
    }

    @Test func theDemoHouseResolvesScriptPowerDevices() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(ScriptPowerActions.all.count == 2)
            #expect(ScriptPowerActions.all.allSatisfy { $0.activeEntityId.contains("demo_") && $0.onScript.hasPrefix("demo_") })
        }
    }

    // MARK: - Source-select remote

    @Test func sourceSelectRemoteIdComesFromTheDocument() {
        let source = Self.source { $0.media.sourceSelect.remoteId = $0.media.remotes[0].id }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaRemotes.sourceSelectRemote == DemoHouse.config.media.remotes[0])
        }
    }

    @Test func missingRemoteIdAnswersEmpty() {
        let source = Self.source { $0.media.sourceSelect.remoteId = nil }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaRemotes.sourceSelectRemoteId.isEmpty)
        }
    }

    @Test func theDemoHouseResolvesTheSourceSelectRemote() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(MediaRemotes.sourceSelectRemote.id == DemoHouse.config.media.remotes.last?.id)
        }
    }

    // MARK: - Household Away (existing bedroom fields)

    @Test func householdAwayIdsFollowTheDocumentAndAreEmptyWithoutOne() {
        let source = Self.source { $0.bedroom.householdAwayEntityId = "sensor.demo_away_x"; $0.bedroom.householdAwayScript = "demo_away_cmd" }
        HouseConfigSource.$scoped.withValue(source) {
            #expect(HouseholdAway.statusEntityId == "sensor.demo_away_x")
            #expect(HouseholdAway.commandService == "demo_away_cmd")
        }
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(HouseholdAway.statusEntityId.isEmpty)
            #expect(HouseholdAway.commandService.isEmpty)
        }
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(HouseholdAway.statusEntityId == DemoHouse.config.bedroom.householdAwayEntityId)
        }
    }

    // MARK: - Round trip

    @Test func theDemoHouseCarriesTheNewFieldsAndTheyRoundTrip() throws {
        let demo = DemoHouse.config
        #expect(demo.home.airQualityEntityId != nil && demo.home.sunEntityId != nil)
        #expect(demo.media.scriptPowerDevices != nil)
        #expect(demo.media.sourceSelect.remoteId != nil)
        #expect(try HouseConfig.decode(demo.encoded()) == demo)
    }

    @Test func aDocumentWithoutTheFieldsStillDecodes() throws {
        var house = DemoHouse.config
        house.home.airQualityEntityId = nil
        house.home.sunEntityId = nil
        house.media.scriptPowerDevices = nil
        house.media.sourceSelect.remoteId = nil
        #expect(try HouseConfig.decode(house.encoded()) == house)
    }
}
