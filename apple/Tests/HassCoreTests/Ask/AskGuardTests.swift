import Foundation
import Testing
@testable import HassCore

/// The "which one?" guard: a lock, garage, alarm, presence or person answer is never picked from a field with a near sibling.
/// Demo names only.
struct AskGuardTests {
    // MARK: Helpers

    private static func state(_ id: String, _ value: String, _ name: String, deviceClass: String? = nil) -> EntityState {
        AskDemoHouse.state(id, value, name: name, deviceClass: deviceClass)
    }

    private static func index(_ states: [EntityState], configuration: AskConfiguration = AskConfiguration()) -> AskableIndex {
        let document = AskHouseDocument(referencedEntityIds: Set(states.map(\.entityId)))
        let house = AskHouse(
            name: "Demo Home", states: states, registry: nil, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors,
            document: document, now: AskDemoHouse.now, timeZone: AskDemoHouse.utc
        )
        return AskableIndex(house: house, configuration: configuration)
    }

    // MARK: Table

    /// One guarded kind: the states, and the question for each situation.
    struct Row: Sendable, CustomTestStringConvertible {
        let kind: String
        let states: [EntityState]
        /// The question names one device's whole name; a second device's name holds one more word.
        let exactQuestion: String
        let exactPick: String
        let exactSibling: String
        /// The question names part of a name; two devices hold it, one with a longer name.
        let partialQuestion: String
        let partialPick: String
        let partialSibling: String
        /// A question only one device can answer.
        let singleQuestion: String
        let singleId: String
        /// A question about the whole set.
        let groupQuestion: String
        let groupIds: Set<String>
        var testDescription: String { kind }
    }

    static let rows: [Row] = [
        Row(
            kind: "lock",
            states: [
                state("lock.demo_garden", "locked", "Garden Lock"), state("lock.demo_garden_gate", "unlocked", "Garden Gate Lock"),
                state("lock.demo_cellar_hatch", "locked", "Cellar Hatch Lock"), state("lock.demo_cellar_hatch_side", "locked", "Cellar Hatch Side Lock"),
                state("lock.demo_attic", "locked", "Attic Lock"),
            ],
            exactQuestion: "is the garden lock locked", exactPick: "lock.demo_garden", exactSibling: "lock.demo_garden_gate",
            partialQuestion: "is the cellar lock locked", partialPick: "lock.demo_cellar_hatch", partialSibling: "lock.demo_cellar_hatch_side",
            singleQuestion: "is the attic lock locked", singleId: "lock.demo_attic",
            groupQuestion: "are all the locks locked",
            groupIds: ["lock.demo_garden", "lock.demo_garden_gate", "lock.demo_cellar_hatch", "lock.demo_cellar_hatch_side", "lock.demo_attic"]
        ),
        Row(
            kind: "garage",
            states: [
                state("cover.demo_garage_barn", "closed", "Barn Garage Door", deviceClass: "garage"),
                state("cover.demo_garage_barn_annex", "open", "Barn Annex Garage Door", deviceClass: "garage"),
                state("cover.demo_garage_rear", "closed", "Rear Workshop Garage Door", deviceClass: "garage"),
                state("cover.demo_garage_rear_side", "closed", "Rear Workshop Side Garage Door", deviceClass: "garage"),
                state("cover.demo_garage_shed", "closed", "Shed Garage Door", deviceClass: "garage"),
            ],
            exactQuestion: "is the barn garage door closed", exactPick: "cover.demo_garage_barn", exactSibling: "cover.demo_garage_barn_annex",
            partialQuestion: "is the rear garage door closed", partialPick: "cover.demo_garage_rear", partialSibling: "cover.demo_garage_rear_side",
            singleQuestion: "is the shed garage door closed", singleId: "cover.demo_garage_shed",
            groupQuestion: "are all the garage doors closed",
            groupIds: ["cover.demo_garage_barn", "cover.demo_garage_barn_annex", "cover.demo_garage_rear", "cover.demo_garage_rear_side", "cover.demo_garage_shed"]
        ),
        Row(
            kind: "alarm",
            states: [
                state("alarm_control_panel.demo_hall", "disarmed", "Hall Alarm"), state("alarm_control_panel.demo_hall_annex", "armed_away", "Hall Annex Alarm"),
                state("alarm_control_panel.demo_loft_east", "disarmed", "Loft East Alarm"), state("alarm_control_panel.demo_loft_east_wing", "disarmed", "Loft East Wing Alarm"),
                state("alarm_control_panel.demo_porch", "disarmed", "Porch Alarm"),
            ],
            exactQuestion: "is the hall alarm armed", exactPick: "alarm_control_panel.demo_hall", exactSibling: "alarm_control_panel.demo_hall_annex",
            partialQuestion: "is the loft alarm armed", partialPick: "alarm_control_panel.demo_loft_east", partialSibling: "alarm_control_panel.demo_loft_east_wing",
            singleQuestion: "is the porch alarm armed", singleId: "alarm_control_panel.demo_porch",
            groupQuestion: "are all the alarms armed",
            groupIds: ["alarm_control_panel.demo_hall", "alarm_control_panel.demo_hall_annex", "alarm_control_panel.demo_loft_east", "alarm_control_panel.demo_loft_east_wing", "alarm_control_panel.demo_porch"]
        ),
        Row(
            kind: "person",
            states: [
                state("person.demo_sam", "home", "Sam"), state("person.demo_sam_guest", "not_home", "Sam Guest"),
                state("person.demo_robin_lee", "home", "Robin Lee"), state("person.demo_robin_lee_jr", "home", "Robin Lee Junior"),
                state("person.demo_kit", "not_home", "Kit"),
            ],
            exactQuestion: "is sam home", exactPick: "person.demo_sam", exactSibling: "person.demo_sam_guest",
            partialQuestion: "is robin home", partialPick: "person.demo_robin_lee", partialSibling: "person.demo_robin_lee_jr",
            singleQuestion: "is kit home", singleId: "person.demo_kit",
            groupQuestion: "is everyone home",
            groupIds: ["person.demo_sam", "person.demo_sam_guest", "person.demo_robin_lee", "person.demo_robin_lee_jr", "person.demo_kit"]
        ),
        Row(
            kind: "occupancy",
            states: [
                state("binary_sensor.demo_den", "on", "Den Presence", deviceClass: "occupancy"),
                state("binary_sensor.demo_den_corner", "off", "Den Corner Presence", deviceClass: "occupancy"),
                state("binary_sensor.demo_study_desk", "off", "Study Desk Presence", deviceClass: "occupancy"),
                state("binary_sensor.demo_study_desk_left", "off", "Study Desk Left Presence", deviceClass: "occupancy"),
                state("binary_sensor.demo_nook", "on", "Nook Presence", deviceClass: "occupancy"),
            ],
            exactQuestion: "is the den presence sensor on", exactPick: "binary_sensor.demo_den", exactSibling: "binary_sensor.demo_den_corner",
            partialQuestion: "is the study presence sensor on", partialPick: "binary_sensor.demo_study_desk", partialSibling: "binary_sensor.demo_study_desk_left",
            singleQuestion: "is the nook presence sensor on", singleId: "binary_sensor.demo_nook",
            groupQuestion: "are the presence sensors on",
            groupIds: ["binary_sensor.demo_den", "binary_sensor.demo_den_corner", "binary_sensor.demo_study_desk", "binary_sensor.demo_study_desk_left", "binary_sensor.demo_nook"]
        ),
    ]

    private func resolve(_ question: String, _ row: Row, configuration: AskConfiguration = AskConfiguration()) -> AskResolution {
        AskResolver(index: Self.index(row.states, configuration: configuration)).resolve(question)
    }

    // MARK: Cases

    @Test(arguments: rows) func anExactNameWithANearSiblingAsksWhichOne(row: Row) {
        let result = resolve(row.exactQuestion, row)
        #expect(result.route == .several, "\(result)")
        #expect(Set(result.candidateIds) == [row.exactPick, row.exactSibling], "\(result.candidateIds)")
        #expect(result.parts.first?.guardedPick == row.exactPick, "the pick the guard held back is recorded")
        #expect(result.entityIds.isEmpty)
    }

    @Test(arguments: rows) func aPartialNameWithANearSiblingAsksWhichOne(row: Row) {
        let result = resolve(row.partialQuestion, row)
        #expect(result.route == .several, "\(result)")
        #expect(Set(result.candidateIds) == [row.partialPick, row.partialSibling], "\(result.candidateIds)")
        #expect(result.parts.first?.guardedPick == row.partialPick)
    }

    @Test(arguments: rows) func aSingleUnambiguousMatchIsAnswered(row: Row) {
        let result = resolve(row.singleQuestion, row)
        #expect(result.route == .found, "\(result)")
        #expect(result.entityIds == [row.singleId])
    }

    @Test(arguments: rows) func aQuestionAboutTheWholeSetIsAGroupNotAQuestion(row: Row) {
        let result = resolve(row.groupQuestion, row)
        #expect(result.route == .group, "\(result)")
        #expect(Set(result.entityIds) == row.groupIds)
    }

    @Test(arguments: rows) func withTheGuardOffTheClosestNameIsPicked(row: Row) {
        var open = AskConfiguration()
        open.securityGuard = false
        let result = resolve(row.exactQuestion, row, configuration: open)
        #expect(result.route == .found, "\(result)")
        #expect(result.entityIds == [row.exactPick])
    }

    // MARK: Other margins

    @Test func aSiblingFarAwayInWordsIsNotAGuess() {
        let states = [Self.state("lock.demo_garden", "locked", "Garden Lock"), Self.state("lock.demo_cellar", "locked", "Cellar Hatch Side Door Lock")]
        let result = AskResolver(index: Self.index(states)).resolve("is the garden lock locked")
        #expect(result.route == .found)
        #expect(result.entityIds == ["lock.demo_garden"])
    }

    @Test func anOrdinaryKindNeedsOnlyTheOrdinaryMargin() {
        let states = [Self.state("light.demo_hall_entry", "off", "Hall Entry Light"), Self.state("light.demo_hall_entry_arch", "on", "Hall Entry Arch Light")]
        let result = AskResolver(index: Self.index(states)).resolve("is the hall entry light on")
        #expect(result.route == .found)
        #expect(result.entityIds == ["light.demo_hall_entry"])
    }

    @Test func twoEquallyCloseNamesStayAQuestion() {
        let states = [Self.state("light.demo_hall_entry_lamp", "off", "Hall Entry Lamp"), Self.state("light.demo_hall_entry_light", "off", "Hall Entry Light")]
        let result = AskResolver(index: Self.index(states)).resolve("is the hall entry on")
        #expect(result.route == .several)
        #expect(Set(result.candidateIds) == ["light.demo_hall_entry_lamp", "light.demo_hall_entry_light"])
    }
}
