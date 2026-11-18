@testable import HassCore
import Testing

// MARK: - The viewer's person is found once per people revision

@MainActor
struct PersonLookupTests {
    private func person(_ id: String, userID: String?, state: String = "home") -> EntityState {
        EntityState(entityId: id, state: state, attributes: userID.map { ["user_id": .string($0)] } ?? [:])
    }

    private func house(extra: [EntityState] = []) -> EntityStore {
        let store = EntityStore()
        store.replaceAll((0..<200).map { EntityState(entityId: "light.demo_\($0)", state: "off") } + extra)
        return store
    }

    @Test func aRepeatedReadScansTheHouseOnce() {
        let store = house(extra: [person("person.demo_a", userID: "u1")])
        var lookup = PersonLookup()
        for _ in 0..<50 { #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == "person.demo_a") }
        #expect(lookup.scans == 1)
    }

    @Test func anUnrelatedEntityChangeDoesNotScanAgain() {
        let store = house(extra: [person("person.demo_a", userID: "u1")])
        var lookup = PersonLookup()
        _ = lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store)
        store.apply([EntityState(entityId: "light.demo_3", state: "on")])
        store.apply([person("person.demo_a", userID: "u1", state: "not_home")])
        #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == "person.demo_a")
        #expect(lookup.scans == 1, "a light and a person's whereabouts are not who the person is")
    }

    @Test func aPersonComingOrGoingScansAgain() {
        let store = house()
        var lookup = PersonLookup()
        #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == nil)
        store.apply([person("person.demo_b", userID: "u1")])
        #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == "person.demo_b")
        store.apply([], removing: ["person.demo_b"], freshness: .live)
        #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == nil)
        #expect(lookup.scans == 3)
    }

    @Test func aPersonPointingAtAnotherUserScansAgain() {
        let store = house(extra: [person("person.demo_a", userID: "u1")])
        var lookup = PersonLookup()
        _ = lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store)
        store.apply([person("person.demo_a", userID: "u2")])
        #expect(lookup.personID(forUser: "u1", revision: store.peopleRevision, in: store) == nil)
        #expect(lookup.personID(forUser: "u2", revision: store.peopleRevision, in: store) == "person.demo_a")
    }

    @Test func anotherUserOrStoreScansAgain() {
        let first = house(extra: [person("person.demo_a", userID: "u1")])
        let second = house(extra: [person("person.demo_z", userID: "u1")])
        var lookup = PersonLookup()
        _ = lookup.personID(forUser: "u1", revision: first.peopleRevision, in: first)
        #expect(lookup.personID(forUser: "u9", revision: first.peopleRevision, in: first) == nil)
        #expect(lookup.personID(forUser: "u1", revision: second.peopleRevision, in: second) == "person.demo_z",
                "the same revision number in another store is another answer")
    }

    @Test func theRevisionMovesWhenAPersonChangesWho() {
        let store = house(extra: [person("person.demo_a", userID: "u1")])
        let before = store.peopleRevision
        store.apply([person("person.demo_a", userID: "u1", state: "away")])
        #expect(store.peopleRevision == before)
        store.apply([person("person.demo_a", userID: "u2")])
        #expect(store.peopleRevision == before + 1)
        store.replaceAll([person("person.demo_a", userID: "u3")])
        #expect(store.peopleRevision == before + 2)
    }
}
