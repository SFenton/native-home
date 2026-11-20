import Foundation
import Testing
@testable import HassCore

/// The askable universe is what the configuration names; everything else is "not set up", and a set is valid only when the
/// configuration defines it. Demo names only.
struct AskConfiguredScopeTests {
    // MARK: Helpers

    private func state(_ id: String, _ value: String, name: String, deviceClass: String? = nil) -> EntityState {
        AskDemoHouse.state(id, value, name: name, deviceClass: deviceClass)
    }

    /// An index over `states`; the document references every one of them except `unconfigured`.
    private func index(
        _ states: [EntityState], registry: [AskRegistryEntity] = [], unconfigured: Set<String> = [], titles: [String: [String]] = [:],
        configuration: AskConfiguration = AskConfiguration(), areas: [AskArea] = AskDemoHouse.areas, deviceLists: [AskKind: [String]] = [:]
    ) -> AskableIndex {
        let document = AskHouseDocument(
            referencedEntityIds: Set(states.map(\.entityId)).subtracting(unconfigured), entityTitles: titles, deviceLists: deviceLists
        )
        let house = AskHouse(
            name: "Demo Home", states: states, registry: registry.isEmpty ? nil : registry, areas: areas, floors: AskDemoHouse.floors,
            document: document, now: AskDemoHouse.now, timeZone: AskDemoHouse.utc
        )
        return AskableIndex(house: house, configuration: configuration)
    }

    private func resolve(_ question: String, _ index: AskableIndex) -> AskResolution { AskResolver(index: index).resolve(question) }

    // MARK: Not configured

    struct Row: Sendable, CustomTestStringConvertible {
        let question: String
        let route: AskRoute
        var testDescription: String { question }
    }

    static let scopeRows: [Row] = [
        Row(question: "Is the porch light on?", route: .notConfigured),
        Row(question: "What's the attic humidity?", route: .notConfigured),
        Row(question: "Is the bedroom tv playing?", route: .notConfigured),
        Row(question: "Is the kitchen light on?", route: .found),
        Row(question: "Is the elevator on?", route: .none),
    ]

    @Test(arguments: scopeRows) func anUnconfiguredThingIsNotSetUpAndAnAbsentOneIsNone(row: Row) {
        #expect(resolve(row.question, AskDemoHouse.index()).route == row.route)
    }

    @Test func anUnconfiguredAnswerNamesWhatWasAskedAndNeverItsState() async {
        let answerer = AskAnswerer(index: AskDemoHouse.index())
        for question in ["Is the porch light on?", "What's the attic humidity?"] {
            let result = await answerer.answer(question)
            #expect(result.resolution.route == .notConfigured)
            #expect(result.path == .fixedNotConfigured)
            #expect(result.answer.contains("set up"), "\(result.answer)")
            for leak in ["55", "is on", "is off", "Yes", "No,"] { #expect(!result.answer.contains(leak), "\(result.answer)") }
            #expect(result.resolution.entityIds.isEmpty)
        }
    }

    @Test func aHelperOrHiddenEntityIsNeverReportedAsNotSetUp() {
        var states = AskDemoHouse.states
        states.append(state("number.demo_porch_dimmer", "50", name: "Demo Porch Dimmer"))
        #expect(resolve("what is the porch dimmer", AskDemoHouse.index(states: states)).route != .notConfigured)
    }

    @Test func theOverlayBringsAnEntityIntoScopeByNameByGroupOrByRecord() {
        var named = AskConfiguration()
        named.entityNames = ["light.demo_porch_light": ["veranda"]]
        #expect(resolve("is the veranda on", AskDemoHouse.index(configuration: named)).entityIds == ["light.demo_porch_light"])
        var recorded = AskConfiguration()
        recorded.scopeRecords = ["sensor.demo_attic_humidity"]
        let result = resolve("what is the attic humidity", AskDemoHouse.index(configuration: recorded))
        #expect(result.route == .found)
        #expect(result.entityIds == ["sensor.demo_attic_humidity"])
    }

    // MARK: Undefined sets

    static let setRows: [Row] = [
        Row(question: "Are the outdoor lights on?", route: .notConfigured),
        Row(question: "Are any lights on outside?", route: .notConfigured),
        Row(question: "Which room is the most humid?", route: .notConfigured),
        Row(question: "Are the lights on?", route: .group),
        Row(question: "Are all the locks locked?", route: .group),
        Row(question: "Which room is the warmest?", route: .group),
    ]

    @Test(arguments: setRows) func aSetNobodyConfiguredIsNotSetUp(row: Row) {
        var states = AskDemoHouse.states
        states.append(state("binary_sensor.demo_hall_motion", "off", name: "Demo Hall Motion", deviceClass: "motion"))
        states.append(state("sensor.demo_phone_battery", "20", name: "Demo Phone Battery", deviceClass: "battery"))
        #expect(resolve(row.question, AskDemoHouse.index(states: states)).route == row.route)
    }

    @Test func aGroupTheConfigurationDefinesIsAnswered() async {
        var configuration = AskConfiguration()
        configuration.groups = [AskGroup(id: "outdoor", say: ["outdoor lights", "outside lights"], kind: .light, entityIds: ["light.demo_porch_light"])]
        let answerer = AskAnswerer(index: AskDemoHouse.index(configuration: configuration))
        let result = await answerer.answer("Are the outdoor lights on?")
        #expect(result.resolution.route == .group)
        #expect(result.resolution.entityIds == ["light.demo_porch_light"])
        #expect(result.answer.contains("Porch"))
        // The same words with a room in them are not the group.
        #expect(AskResolver(index: AskDemoHouse.index(configuration: configuration)).resolve("Are the kitchen lights on?").entityIds != ["light.demo_porch_light"])
    }

    @Test func aRoomSetIsWhatTheConfigurationPlacesThere() {
        let result = resolve("Are the living room lights on?", AskDemoHouse.index())
        #expect(result.route == .group)
        #expect(Set(result.entityIds) == ["light.demo_lamp", "light.demo_kitchen_counter", "light.demo_broken_bulb"])
    }

    // MARK: One thing reported twice

    @Test func aGarageDoorReportedByACoverAndAContactSensorCountsOnce() async {
        let states = [
            state("cover.demo_garage_left", "closed", name: "Demo Garage Left Door", deviceClass: "garage"),
            state("cover.demo_garage_right", "closed", name: "Demo Garage Right Door", deviceClass: "garage"),
            state("binary_sensor.demo_garage_left_contact", "off", name: "Demo Garage Left Contact", deviceClass: "garage_door"),
            state("binary_sensor.demo_garage_right_contact", "off", name: "Demo Garage Right Contact", deviceClass: "garage_door"),
        ]
        let registry = [
            AskRegistryEntity(entityId: "cover.demo_garage_left", deviceId: "left"),
            AskRegistryEntity(entityId: "cover.demo_garage_right", deviceId: "right"),
            AskRegistryEntity(entityId: "binary_sensor.demo_garage_left_contact", deviceId: "left", deviceClass: "garage_door"),
            AskRegistryEntity(entityId: "binary_sensor.demo_garage_right_contact", deviceId: "right", deviceClass: "garage_door"),
        ]
        let answerer = AskAnswerer(index: index(states, registry: registry))
        let result = await answerer.answer("Are both garage doors shut?")
        #expect(result.resolution.route == .group)
        #expect(Set(result.resolution.entityIds) == ["cover.demo_garage_left", "cover.demo_garage_right"])
        #expect(result.answer.contains("all 2 garage doors"), "\(result.answer)")
        #expect(result.answer.contains("Left"), "named by the door")
        #expect(!result.answer.contains("Contact"))
    }

    @Test func anOverlaySameAsLinkCountsTheFirstPresentMember() {
        let states = [
            state("cover.demo_back_gate", "closed", name: "Demo Back Gate", deviceClass: "door"),
            state("binary_sensor.demo_back_gate_sensor", "off", name: "Demo Back Gate Sensor", deviceClass: "door"),
        ]
        var configuration = AskConfiguration()
        configuration.sameAs = [["cover.demo_back_gate", "binary_sensor.demo_back_gate_sensor"]]
        let aggregator = AskAggregator(index: index(states, configuration: configuration))
        #expect(aggregator.members(kind: .door, scope: .house).map(\.id) == ["cover.demo_back_gate"])
        let without = AskAggregator(index: index(states))
        #expect(without.members(kind: .door, scope: .house).count == 2)
    }

    // MARK: Names

    @Test func aPluralWordThatIsOneEntitysExactNameMeansThatEntity() {
        let states = [
            state("light.demo_a", "on", name: "Demo A Light"), state("light.demo_b", "off", name: "Demo B Light"),
            state("light.demo_lights", "on", name: "Lights"),
        ]
        #expect(resolve("Are the lights on?", index(states)).entityIds == ["light.demo_lights"])
        // Without such a name the plural is the set; and a name of another kind does not take the word.
        #expect(Set(resolve("Are the lights on?", index(Array(states.dropLast()))).entityIds) == ["light.demo_a", "light.demo_b"])
        let lockNamedDoors = [state("lock.demo_doors", "locked", name: "Doors"), state("binary_sensor.demo_d1", "off", name: "Demo Door One", deviceClass: "door")]
        #expect(resolve("Are any doors open?", index(lockNamedDoors)).entityIds == ["binary_sensor.demo_d1"])
    }

    @Test func oneClearlyClosestSiblingIsFoundNotSeveral() {
        let states = [
            state("binary_sensor.demo_hall_presence", "on", name: "Demo Hall Presence Sensor", deviceClass: "occupancy"),
            state("binary_sensor.demo_hall_entry_presence", "off", name: "Demo Hall Entry Presence Sensor", deviceClass: "occupancy"),
            state("light.demo_hall_light", "on", name: "Demo Hall Light"),
            state("light.demo_hall_entry_light", "off", name: "Demo Hall Entry Light"),
            state("light.demo_hall_entry_lamp", "off", name: "Demo Hall Entry Lamp"),
        ]
        let idx = index(states)
        #expect(resolve("is the hall light on", idx).entityIds == ["light.demo_hall_light"])
        // Two equally close names stay a question.
        let tie = resolve("is the hall entry lamp or light on", idx)
        #expect(tie.route != .found || tie.entityIds.count == 1)
    }

    @Test func aLockMatchRestingOnANameWithAnotherNearCandidateAsksWhichOne() {
        let states = [
            state("lock.demo_garden", "locked", name: "Demo Garden Lock"),
            state("lock.demo_garden_gate", "unlocked", name: "Demo Garden Gate Lock"),
        ]
        let guarded = resolve("is the garden lock locked", index(states))
        #expect(guarded.route == .several)
        #expect(Set(guarded.candidateIds) == ["lock.demo_garden", "lock.demo_garden_gate"])
        #expect(guarded.parts.first?.guardedPick == "lock.demo_garden", "the pick the margin held back is recorded")
        // The exact name is only the answer when nothing is close behind it.
        #expect(resolve("is the garden gate lock locked", index(states)).route == .several || resolve("is the garden gate lock locked", index(states)).entityIds == ["lock.demo_garden_gate"])
        // Turned off, the ordinary margin picks the closest name.
        var open = AskConfiguration()
        open.securityGuard = false
        #expect(resolve("is the garden lock locked", index(states, configuration: open)).entityIds == ["lock.demo_garden"])
        // A name far from its sibling is not a guess.
        let far = [state("lock.demo_garden", "locked", name: "Demo Garden Lock"), state("lock.demo_cellar", "locked", name: "Demo Cellar Hatch Lock")]
        #expect(resolve("is the garden lock locked", index(far)).entityIds == ["lock.demo_garden"], "\(resolve("is the garden lock locked", index(far)))")
    }

    @Test func theDocumentsTitleIsSpokenInsteadOfAHardwareName() async {
        let states = [state("lock.demo_hub_z300", "locked", name: "Demo Hub Z-300 Model Lock")]
        let idx = index(states, titles: ["lock.demo_hub_z300": ["Front Entrance"]])
        let result = await AskAnswerer(index: idx).answer("Is the front entrance locked?")
        #expect(result.resolution.entityIds == ["lock.demo_hub_z300"])
        #expect(result.answer.contains("Front Entrance"), "\(result.answer)")
        #expect(!result.answer.contains("Z-300"))
        // A title the friendly name already carries changes nothing.
        let same = index([state("light.demo_counter", "on", name: "Demo Kitchen Counter Light")], titles: ["light.demo_counter": ["Counter Light"]])
        #expect(same.entry("light.demo_counter")?.displayName == "Demo Kitchen Counter Light")
    }

    @Test func aHomeAssistantAliasIsANameSource() {
        var registry = AskDemoHouse.registry
        registry[0].aliases = ["the sunny lamp"]
        let house = AskHouse(
            name: "Demo Home", states: AskDemoHouse.states, registry: registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors,
            document: AskDemoHouse.document(), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc
        )
        #expect(AskResolver(index: AskableIndex(house: house)).resolve("is the sunny lamp on").entityIds == ["light.demo_kitchen_light"])
    }

    // MARK: Comparisons

    struct SetRow: Sendable, CustomTestStringConvertible {
        let question: String
        let route: AskRoute
        let ids: Set<String>
        var testDescription: String { question }
    }

    static let comparisons: [SetRow] = [
        SetRow(question: "Which room is the warmest?", route: .group, ids: ["sensor.demo_kitchen_temperature", "sensor.demo_office_temperature"]),
        SetRow(question: "Is the office the warmest room?", route: .group, ids: ["sensor.demo_kitchen_temperature", "sensor.demo_office_temperature"]),
        SetRow(question: "Is the office warmer than the kitchen?", route: .group, ids: ["sensor.demo_kitchen_temperature", "sensor.demo_office_temperature"]),
    ]

    @Test(arguments: comparisons) func comparisonsNameNoKindOrTwoScopes(row: SetRow) {
        let result = resolve(row.question, AskDemoHouse.index())
        #expect(result.route == row.route, "\(result)")
        #expect(Set(result.entityIds) == row.ids, "\(result.entityIds)")
    }

    @Test func aComparisonAnswerNamesTheWinner() async {
        let result = await AskAnswerer(index: AskDemoHouse.index()).answer("Which room is the warmest?")
        #expect(result.answer.contains("Office"), "\(result.answer)")
    }

    // MARK: Music

    @Test func musicIsAMediaWordUnlessItIsPartOfARoomName() {
        let areas = AskDemoHouse.areas + [AskArea(id: "music_room", name: "Music Room", floorId: "main")]
        let states = [
            state("light.demo_music_room_light", "off", name: "Demo Music Room Light"),
            state("media_player.demo_tv", "playing", name: "Demo Living Room TV"),
        ]
        let registry = [
            AskRegistryEntity(entityId: "light.demo_music_room_light", areaId: "music_room"),
            AskRegistryEntity(entityId: "media_player.demo_tv", areaId: "living_room"),
        ]
        let idx = index(states, registry: registry, areas: areas)
        let room = resolve("when did the music room light last come on", idx)
        #expect(room.entityIds == ["light.demo_music_room_light"])
        #expect(room.intent.predicate != .playing)
        #expect(resolve("is the music on", idx).intent.predicate == .playing)
    }
}
