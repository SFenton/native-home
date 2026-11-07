import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Ports of the web's `everShelfFood.test.ts` subtitle cases.
@Suite(.demoHouse)
struct FoodConfigTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9))!

    func states(_ list: [EntityState]) -> (String) -> EntityState? {
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.entityId, $0) })
        return { byId[$0] }
    }

    var expiring: EntityState {
        EntityState(entityId: FoodConfig.expiringSoonEntityId, state: "5", attributes: ["expiring_list": .array([
            .object(["location": .string("Fridge"), "days_remaining": .number(2)]),
            .object(["location": .string("frigo"), "days_remaining": .number(9)]),
            .object(["location": .string("frigo"), "days_remaining": .number(-1)]),
            .object(["location": .string("pantry"), "expiry_date": .string("2026-10-15")]),
            .object(["location": .string("dispensa"), "expiry_date": .string("2026-10-30")]),
            .object(["location": .string("Spice Rack"), "expiry_date": .string("2026-10-11T00:00:00")]),
            .object(["location": .string("spice_rack"), "expiry_date": .string("bad")]),
        ])])
    }

    @Test func spaceSubtitlesCountItemsExpiringThisWeek() {
        let state = states([expiring, EntityState(entityId: FoodConfig.spaces[1].entityId, state: "38")])
        let fridge = FoodConfig.spaces[1], pantry = FoodConfig.spaces[0], rack = FoodConfig.spaces[3], cabinet = FoodConfig.spaces[4]
        #expect(FoodConfig.spaceSubtitle(fridge, state: state, now: now, calendar: calendar) == "38 Items • 1 Expiring Soon")
        #expect(FoodConfig.spaceSubtitle(pantry, state: state, now: now, calendar: calendar) == "0 Items • 1 Expiring Soon")
        #expect(FoodConfig.spaceSubtitle(rack, state: state, now: now, calendar: calendar) == "0 Items • 1 Expiring Soon")
        #expect(FoodConfig.spaceSubtitle(cabinet, state: states([]), now: now, calendar: calendar) == "0 Items • 0 Expiring Soon")
    }

    @Test func allFoodPrefersTheTotalSensor() {
        let spaces = [EntityState(entityId: FoodConfig.spaces[0].entityId, state: "3"), EntityState(entityId: FoodConfig.spaces[2].entityId, state: "2.9")]
        #expect(FoodConfig.allFoodSubtitle(state: states(spaces + [expiring, EntityState(entityId: FoodConfig.totalItemsEntityId, state: "143")]))
            == "143 Items • 5 Expiring Soon")
        #expect(FoodConfig.allFoodSubtitle(state: states(spaces + [EntityState(entityId: FoodConfig.totalItemsEntityId, state: "unavailable")]))
            == "5 Items • 0 Expiring Soon")
        #expect(FoodConfig.foodSummarySubtitle(state: states(spaces + [expiring]), now: now, calendar: calendar) == "5 Items • 3 Expiring Soon")
        #expect(FoodConfig.summary(items: 1, expiring: 0) == "1 Item • 0 Expiring Soon")
    }

    @Test func spacesAreUniqueAndInWebOrder() {
        #expect(FoodConfig.spaces.map(\.title) == ["Pantry", "Fridge", "Freezer", "Spice Rack", "Cabinet"])
        #expect(Set(FoodConfig.spaces.map(\.id)).count == FoodConfig.spaces.count)
        #expect(FoodConfig.normalizedLocation(" Spice-Rack ") == "spice_rack")
    }
}
