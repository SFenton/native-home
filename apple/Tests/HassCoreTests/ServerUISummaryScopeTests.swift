import Foundation
import Testing
@testable import HassCore

struct ServerUISummaryScopeTests {
    private func person(_ key: String, user: String) -> HouseConfig.Person {
        .init(key: key, name: key, haUserId: user, personEntityId: "person.\(key)", taskAssignee: key,
              soloTripId: key, seesAdminTodo: key == "demo_a",
              summaryLists: .init(overdue: "todo.\(key)_overdue", dueToday: "todo.\(key)_today", noDueDate: "todo.\(key)_undated"))
    }

    @Test func pinsOnlyAuthenticatedViewersListsAndStartsOnProfile() throws {
        let scope = try ServerUISummaryScope(authenticatedUserID: " USER-B ", people: [
            person("demo_a", user: "user-a"), person("demo_b", user: "user-b"),
        ])
        #expect(scope.viewer?.key == "demo_b")
        #expect(scope.initialTab == .profile && scope.tabs == SummaryTab.allCases)
        #expect(scope.lists(for: .overdue).map(\.entityId) == ["todo.demo_b_overdue"])
        #expect(scope.lists(for: .upcoming).map(\.entityId) == ["todo.demo_b_today", "todo.demo_b_undated"])
        #expect(!scope.showsAdminTodo)
    }

    @Test func guestNeverGetsPersonalCollectionsAndAmbiguousIdentityRejects() throws {
        let people = [person("demo_a", user: "user-a")]
        let scope = try ServerUISummaryScope(authenticatedUserID: "guest-user", people: people)
        #expect(scope.tabs == [.profile, .expiredFood])
        #expect(scope.lists == nil && scope.lists(for: .upcoming).isEmpty)
        #expect(throws: ServerUISummaryScope.Failure.missingIdentity) {
            try ServerUISummaryScope(authenticatedUserID: " ", people: people)
        }
        #expect(throws: ServerUISummaryScope.Failure.ambiguousIdentity) {
            try ServerUISummaryScope(authenticatedUserID: "user-a", people: people + [person("demo_b", user: "USER-A")])
        }
    }

    @Test @MainActor func configuredIdentityPinsCommandAndSnapshotValuesWithoutChangingResidentKeys() throws {
        var person = person("demo_a", user: "user-a")
        person.name = "Original Person"
        person.soloTripId = "original_traveler"
        let emptySource = HouseConfigSource()
        try HouseConfigSource.$scoped.withValue(emptySource) {
            let scope = try ServerUISummaryScope(authenticatedUserID: "user-a", people: [person])
            let viewer = try #require(scope.viewer)
            let command = HouseholdAway.Command.scheduleSoloTrip(traveler: viewer,
                start: WallClock(date: "2026-11-15", time: "10:00"),
                end: WallClock(date: "2026-11-17", time: "18:00"))
            let data = HouseholdAway.serviceData(for: command, expectedRevision: 1, requestId: "fixed-request")
            #expect(data["traveler"] == .string("original_traveler"))
            let snapshot = HouseholdAway.Snapshot(entity: .init(entityId: "sensor.demo_plan", state: "scheduled",
                attributes: ["contract_version": .number(1), "mode": "solo_trip", "traveler": "original_traveler"]), people: [person])
            #expect(snapshot.traveler?.name == "Original Person")
            #expect(snapshot.traveler == viewer)
            #expect(Set([viewer, Resident(key: person.key)]).count == 1)
            #expect(try JSONEncoder().encode(viewer) == JSONEncoder().encode(person.key))
        }
    }
}
