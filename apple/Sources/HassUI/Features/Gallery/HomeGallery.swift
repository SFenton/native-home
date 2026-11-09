#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Synthetic Home states for the gallery, built from the other galleries' fixtures (not a copy of the live house).
enum HomeFixtures {
    /// A reading for the Climate, Occupancy and Air Quality status chips, keyed by the chips' own entity ids (the house
    /// document's, so the values follow whichever house the gallery draws).
    static var statusChipStates: [EntityState] {
        let readings = ["Climate": "70.0 - 72.4°F", "Occupancy": "on", "Air Quality": "21 - 34"]
        let details = ["Air Quality": "4 - 9"]
        return HomeConfig.statusChips.flatMap { chip -> [EntityState] in
            let main = readings[chip.title].map { EntityState(entityId: chip.entityId, state: $0) }
            let detail = chip.detailEntityId.flatMap { id in details[chip.title].map { EntityState(entityId: id, state: $0) } }
            return [main, detail].compactMap { $0 }
        }
    }

    /// The store the Home gallery reads, in both the SwiftUI and the UIKit app.
    @MainActor static func store(environment: [String: String] = ProcessInfo.processInfo.environment) -> EntityStore {
        let store = EntityStore()
        store.replaceAll(states(environment: environment), freshness: .live)
        return store
    }

    static func states(environment: [String: String] = ProcessInfo.processInfo.environment) -> [EntityState] {
        var byId: [String: EntityState] = [:]
        func add(_ states: [EntityState]) { for state in states { byId[state.entityId] = state } }
        add(RoomsFixtures.states)
        add(SecurityFixtures.states(.standard))
        add(WeatherFixtures.states(
            condition: environment["FENTON_GALLERY_WEATHER_CONDITION"] ?? "rainy", night: environment["FENTON_GALLERY_WEATHER_NIGHT"] == "1",
            airQuality: environment["FENTON_GALLERY_WEATHER_NOAQI"] != "1"))
        // Every third light on, so the Lights chip fills and the overview has rooms in both sections.
        add(RoomOverview.lightEntityIds.enumerated().map { EntityState(entityId: $1, state: $0.isMultiple(of: 3) ? "on" : "off") })
        add(RoomOverview.contactEntityIds.enumerated().map { EntityState(entityId: $1, state: $0 == 0 ? "on" : "off") })
        add(HomeFixtures.statusChipStates)
        for toggle in HomeConfig.guestToggles {
            let on = environment["FENTON_GALLERY_GUESTS"] != "0" && toggle.entityId == HomeConfig.guestToggles.first?.entityId
            byId[toggle.entityId] = EntityState(entityId: toggle.entityId, state: on ? "on" : "off")
        }
        return Array(byId.values)
    }
}
#endif
