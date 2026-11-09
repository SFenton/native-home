@testable import HassCore
import HassTestSupport
import Testing

/// Which entities the house document names, and which of them Home Assistant lacks (rule 15 of
/// `.agents/design/house-config-states.md`).
@Suite(.demoHouse)
struct HouseConfigEntitiesTests {
    @Test func entityIdsAreDomainDotObjectForKnownDomains() {
        #expect(HouseConfig.isEntityId("light.demo_kitchen_main"))
        #expect(HouseConfig.isEntityId("binary_sensor.demo_door_2"))
        #expect(!HouseConfig.isEntityId("house.fill"), "An SF Symbol is not an entity")
        #expect(!HouseConfig.isEntityId("photo.png"))
        #expect(!HouseConfig.isEntityId("light."))
        #expect(!HouseConfig.isEntityId(".light"))
        #expect(!HouseConfig.isEntityId("light.Kitchen"))
        #expect(!HouseConfig.isEntityId("Kitchen light"))
    }

    @Test func theDemoHouseNamesEntitiesAndNoSymbols() {
        let ids = DemoHouse.config.referencedEntityIds
        #expect(!ids.isEmpty)
        #expect(ids.allSatisfy(HouseConfig.isEntityId))
        #expect(ids.contains(DemoHouse.config.home.weatherEntityId))
    }

    @Test func nothingIsMissingBeforeTheFirstStateSet() {
        #expect(DemoHouse.config.missingEntityIds(hasReceivedFirstState: false) { _ in nil }.isEmpty)
    }

    @Test func anEntityHomeAssistantLacksIsMissingAndOthersAreNot() throws {
        let all = DemoHouse.config.referencedEntityIds
        let lacking = try #require(all.sorted().first)
        let missing = DemoHouse.config.missingEntityIds(hasReceivedFirstState: true) { id in
            id == lacking ? nil : EntityState(entityId: id, state: "on")
        }
        #expect(missing == [lacking])
    }

    @Test func anUnavailableEntityIsNotMissing() {
        let missing = DemoHouse.config.missingEntityIds(hasReceivedFirstState: true) { EntityState(entityId: $0, state: "unavailable") }
        #expect(missing.isEmpty, "Unavailable is a state Home Assistant reports; only an absent entity is not found")
    }

    @Test func missingIdsAreSorted() {
        let missing = DemoHouse.config.missingEntityIds(hasReceivedFirstState: true) { _ in nil }
        #expect(missing == missing.sorted() && missing.count == DemoHouse.config.referencedEntityIds.count)
    }

    @Test func aMissingConfiguredEntityDrawsAsUnavailableLikeAnUnavailableOne() throws {
        let chip = try #require(HomeConfig.statusChips.first { ![.lights, .contacts, .airQuality].contains($0.sheet) })
        let missing = HomeConfig.summary(for: chip) { _ in nil }
        let unavailable = HomeConfig.summary(for: chip) { EntityState(entityId: $0, state: "unavailable") }
        #expect(missing == "Unavailable" && unavailable == "Unavailable")
    }
}
