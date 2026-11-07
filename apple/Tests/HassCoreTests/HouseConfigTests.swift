import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// `HouseConfig` is the house's data as one document: the demo house survives a round trip, unknown keys are ignored, a
/// newer schema is refused, and the required roles are checked at decode.
@Suite(.demoHouse)
struct HouseConfigTests {
    typealias Config = HouseConfig

    // MARK: - Round trips

    /// Encodes `value`, decodes it back and expects the same value, so a section loses nothing in transit.
    private func roundTrips<T: Codable & Equatable>(_ value: T, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(T.self, from: data) == value, sourceLocation: sourceLocation)
    }

    @Test func wholeDocumentRoundTrips() throws {
        let demo = DemoHouse.config
        #expect(demo.schema == Config.supportedSchema)
        #expect(try Config.decode(demo.encoded()) == demo)
    }

    @Test func everySectionRoundTrips() throws {
        let demo = DemoHouse.config
        try roundTrips(demo.home)
        try roundTrips(demo.security)
        try roundTrips(demo.climate)
        try roundTrips(demo.customLights)
        try roundTrips(demo.food)
        try roundTrips(demo.chores)
        try roundTrips(demo.household)
        try roundTrips(demo.media)
        try roundTrips(demo.roomDevices)
        try roundTrips(demo.sprinklers)
        try roundTrips(demo.vacation)
        try roundTrips(demo.vacuums)
        try roundTrips(demo.bedroom)
        try roundTrips(demo.rooms)
    }

    // MARK: - The sections are what the facades read

    @Test func sectionsAreWhatTheFacadesRead() {
        let demo = DemoHouse.config
        #expect(demo.home.statusChips == HomeConfig.statusChips)
        #expect(demo.home.cameras == HomeConfig.cameras)
        #expect(demo.security.controlTiles == SecurityConfig.controlTiles)
        #expect(demo.security.alarmEntityId == SecurityConfig.alarmEntityId)
        #expect(demo.climate.rooms == ClimateConfig.rooms)
        #expect(demo.climate.contactSensors == ClimateConfig.contactSensors)
        #expect(demo.customLights.lights == CustomLightsConfig.lights)
        #expect(demo.food.spaces == FoodConfig.spaces)
        #expect(demo.food.allFoodTint.green == FoodConfig.allFoodTint.green)
        #expect(demo.chores.pages == ChoresConfig.pages)
        #expect(demo.household.presenceRooms == HouseholdSettingsConfig.Admin.presenceRooms)
        #expect(demo.media.remotes == MediaRemotes.all)
        #expect(demo.media.pageSections == MediaPageConfig.sections)
        #expect(demo.security.garageDoors == ["left": SecurityConfig.leftGarageDoorEntityId, "right": SecurityConfig.rightGarageDoorEntityId])
        #expect(demo.roomDevices.airPurifiers == AirPurifierConfig.all)
        #expect(demo.sprinklers.controllers == SprinklersConfig.controllers)
        #expect(demo.vacation.checklist == Vacation.checklist)
        #expect(demo.vacuums.vacuums == Vacuums.all)
        #expect(demo.bedroom.beds == MasterBedroom.beds)
        #expect(demo.rooms.pages == RoomsConfig.pages)
        #expect(demo.rooms.grid.items == RoomNavigation.items)
        #expect(demo.rooms.quickLinks == QuickLinks.items)
    }

    @Test func demoSectionsAreNotEmpty() {
        let demo = DemoHouse.config
        #expect(!demo.home.statusChips.isEmpty && !demo.home.cameras.isEmpty)
        #expect(!demo.climate.rooms.isEmpty && !demo.customLights.lights.isEmpty)
        #expect(!demo.chores.people.isEmpty && !demo.chores.quickLinks.isEmpty)
        #expect(!demo.media.remotes.isEmpty && !demo.media.remoteIdByMediaPlayer.isEmpty)
        #expect(!demo.vacuums.vacuums.isEmpty && !demo.vacuums.outcomeReconciliations.isEmpty)
        #expect(!demo.rooms.lightGroups.isEmpty && !demo.rooms.pages.isEmpty)
    }

    @Test func peopleAndQuickLinksCarryTheTupleValues() throws {
        let chores = DemoHouse.config.chores
        #expect(chores.people.map(\.key) == ChoresConfig.Resident.allCases.map(\.key))
        let groceries = try #require(chores.quickLinks.first { $0.countsGroceries })
        #expect(groceries.pageId == ChoresConfig.groceries.id)
        #expect(groceries.id == groceries.pageId)
        #expect(chores.people.map(\.id) == chores.people.map(\.key))
    }

    @Test func mediaPlayerLookupStillResolvesAfterExtraction() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_media_player_2")?.id == "media-room-streamer")
        }
        #expect(MediaRemotes.config(forMediaPlayer: "media_player.demo_nowhere") == nil)
    }

    // MARK: - Decoding rules

    /// The demo document as a JSON object, to edit before decoding.
    private func demoObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: DemoHouse.config.encoded())
        return try #require(object as? [String: Any])
    }

    @Test func unknownKeysAreIgnored() throws {
        var object = try demoObject()
        object["futureTopLevel"] = ["anything": 1]
        var home = try #require(object["home"] as? [String: Any])
        home["futureField"] = "ignored"
        object["home"] = home
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try Config.decode(data) == DemoHouse.config)
    }

    @Test func newerSchemaIsRefused() throws {
        var object = try demoObject()
        object["schema"] = Config.supportedSchema + 1
        // Sections may have changed shape in a newer schema; the version is judged first.
        object["home"] = ["different": true]
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: Config.DecodeError.unsupportedSchema(found: Config.supportedSchema + 1, supported: Config.supportedSchema)) {
            try Config.decode(data)
        }
    }

    @Test func schemaBelowTheMinimumIsRefused() throws {
        for schema in [1, 0, -1] {
            var object = try demoObject()
            object["schema"] = schema
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: Config.DecodeError.self) { try Config.decode(data) }
        }
    }

    @Test func malformedDocumentsAreTyped() {
        #expect(throws: Config.DecodeError.self) { try Config.decode(Data("not json".utf8)) }
        #expect(throws: Config.DecodeError.self) { try Config.decode(Data(#"{"schema": 1}"#.utf8)) }
        #expect(throws: Config.DecodeError.self) { try Config.decode(Data(#"{"home": {}}"#.utf8)) }
    }

    /// The server hashes the encoded bytes, so equal documents must encode to equal bytes, in this process and the
    /// next: dictionaries are keyed objects, never arrays in hash order.
    @Test func encodingIsByteIdenticalAcrossEncodesAndCopies() throws {
        let first = try DemoHouse.config.encoded()
        #expect(first == (try DemoHouse.config.encoded()))
        let decoded = try Config.decode(first)
        #expect(first == (try decoded.encoded()), "A decoded copy re-encodes to the same bytes")
    }

    @Test func enumKeyedDictionariesEncodeAsObjects() throws {
        let rooms = try #require(try demoObject()["bedroom"] as? [String: Any])
        let beds = try #require(rooms["beds"] as? [[String: Any]])
        let levels = try #require(beds.first?["stageLevelEntityIds"] as? [String: String])
        #expect(Set(levels.keys) == Set(SchedulePhase.allCases.map(\.rawValue)))
    }

    @Test func compactEncodingStaysUnderTheServerLimit() throws {
        let size = try DemoHouse.config.encoded().count
        #expect(size < Config.serverByteLimit,
                "The encoded house is \(size) bytes; the server refuses more than \(Config.serverByteLimit) (HOUSE_CONFIG_MAX_BYTES, ha-fenton-home#13)")
        #expect(!(String(decoding: try DemoHouse.config.encoded(), as: UTF8.self)).contains("\n"), "Compact, not pretty-printed")
    }

    // MARK: - Durations and tagged enums

    @Test func durationsEncodeAsSeconds() throws {
        let intent = OptimisticIntent("media_player.demo_x", "on", revertAfter: .seconds(180), failsOnTimeout: true)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        #expect(object["revertAfterSeconds"] as? Double == 180)
        #expect(object["revertAfter"] == nil)
        try roundTrips(intent)

        let device = MediaRemoteDevice("TV", entityId: "media_player.demo_x", icon: "mdi:tv", activeHold: .seconds(45))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as? [String: Any])
        #expect(encoded["activeHoldSeconds"] as? Double == 45)
        try roundTrips(device)
        try roundTrips(MediaRemoteDevice("Read only", entityId: "media_player.demo_y", icon: "mdi:tv"))
    }

    @Test func everyDurationInTheDocumentIsANumberOfSeconds() throws {
        let text = String(decoding: try DemoHouse.config.encoded(), as: UTF8.self)
        #expect(!text.contains("\"revertAfter\""))
        #expect(!text.contains("\"activeHold\""))
        #expect(!text.contains("\"_0\""), "Enum payloads use named keys")
    }

    @Test func taggedEnumsRoundTripAndNameTheirPayload() throws {
        let call = ServiceCall("script", "turn_on", target: "script.demo_x")
        let command = MediaRemoteCommand.service(call, optimistic: [OptimisticIntent("a.b", "on", revertAfter: .seconds(8))])
        let actions: [MediaRemoteAction] = [
            .command(command), .command(.textPrompt(targetEntityId: "media_player.demo_x")),
            .state(entityId: nil, cases: [.init(["on"], command)], otherwise: command),
        ]
        for action in actions { try roundTrips(action) }
        for rule in [SemanticsRule.toggleOnUnless(["off"]), .toggleOnWhen(["on"]), .selectedWhen(["x"]), .state] { try roundTrips(rule) }
        for action in [RoomCardAction.flip, .remote(actions[0])] { try roundTrips(action) }
        for semantics in [RoomCardSemantics.modal, .command, .rule(.state)] { try roundTrips(semantics) }
        for action in [QuickLink.Action.detail(.rooms), .navigate("food")] { try roundTrips(action) }

        let data = try JSONEncoder().encode(actions[2])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "state")
        #expect(object["otherwise"] != nil)
    }

    @Test func unknownTagsAreRejected() {
        let decoder = JSONDecoder()
        for json in [#"{"type":"bogus"}"#, #"{"type":"bogus","states":[]}"#] {
            #expect(throws: DecodingError.self) { try decoder.decode(SemanticsRule.self, from: Data(json.utf8)) }
            #expect(throws: DecodingError.self) { try decoder.decode(MediaRemoteCommand.self, from: Data(json.utf8)) }
            #expect(throws: DecodingError.self) { try decoder.decode(MediaRemoteAction.self, from: Data(json.utf8)) }
            #expect(throws: DecodingError.self) { try decoder.decode(RoomCardAction.self, from: Data(json.utf8)) }
            #expect(throws: DecodingError.self) { try decoder.decode(RoomCardSemantics.self, from: Data(json.utf8)) }
            #expect(throws: DecodingError.self) { try decoder.decode(QuickLink.Action.self, from: Data(json.utf8)) }
        }
    }

    // MARK: - Source-select constants and generic names

    @Test func sourceSelectConstantsMirrorTheRoleConstants() {
        typealias M = MediaRemotes.MusicRoom
        let select = DemoHouse.config.media.sourceSelect
        #expect(select.entityIds["control"] == M.controlEntityId)
        #expect(select.entityIds["activeMediaSource"] == M.activeMediaSourceEntityId)
        #expect(select.syncHdmiStatusEntityIds == M.hueSyncHdmiStatusEntityIds)
        #expect(select.sources["console"] == M.Source.xbox)
        #expect(select.revertSeconds["consoleOff"].map { .seconds($0) } == M.Revert.xboxOff)
        #expect(select.revertSeconds["sync"].map { .seconds($0) } == M.Revert.hueSync)
        #expect(Duration.seconds(select.activeHoldSeconds) == M.xboxActiveHold)
        #expect(select.activeStates == M.xboxActiveStates)
        #expect(select.linkedState == M.xboxLinkedState)
    }

    @Test func sharedRoomValuesReferenceInsteadOfRepeating() {
        let demo = DemoHouse.config
        let fanPowers = Set(demo.roomDevices.bathroomFans.map(\.powerEntityId))
        #expect(Set(demo.rooms.shared.bathroomFanSheets.keys) == fanPowers)
        #expect(demo.security.garageDoors.count == 2)
    }

    // MARK: - Envelope

    @Test func envelopeReassemblesTheServerReply() throws {
        var object = try demoObject()
        object["schema"] = nil
        let reply: [String: Any] = ["schema": Config.supportedSchema, "hash": "abc123", "config": object]
        let envelope = try HouseConfigEnvelope.decode(JSONSerialization.data(withJSONObject: reply))
        #expect(envelope.config == DemoHouse.config)
        #expect(envelope.hash == "abc123")
    }

    @Test func envelopeReadsNotConfigured() throws {
        let envelope = try HouseConfigEnvelope.decode(Data(#"{"configured": false}"#.utf8))
        #expect(envelope.config == nil)
        #expect(envelope.hash == nil)
        #expect(envelope == HouseConfigEnvelope(config: nil, hash: nil))
    }

    @Test func envelopeRefusesNewerSchemaAndMalformedReplies() throws {
        let newer = #"{"schema": 3, "hash": "h", "config": {"anything": 1}}"#
        #expect(throws: Config.DecodeError.unsupportedSchema(found: 3, supported: Config.supportedSchema)) {
            try HouseConfigEnvelope.decode(Data(newer.utf8))
        }
        #expect(throws: Config.DecodeError.self) { try HouseConfigEnvelope.decode(Data("nope".utf8)) }
        #expect(throws: Config.DecodeError.self) { try HouseConfigEnvelope.decode(Data(#"{"hash": "h"}"#.utf8)) }
        #expect(throws: Config.DecodeError.self) { try HouseConfigEnvelope.decode(Data(#"{"schema": 1, "config": {}}"#.utf8)) }
    }

    // MARK: - Required roles

    /// Removes `role` from `media.sourceSelect.<map>` in the demo document.
    private func dataLacking(role: String, in map: String) throws -> Data {
        var object = try demoObject()
        var media = try #require(object["media"] as? [String: Any])
        var select = try #require(media["sourceSelect"] as? [String: Any])
        var roles = try #require(select[map] as? [String: Any])
        roles[role] = nil
        select[map] = roles
        media["sourceSelect"] = select
        object["media"] = media
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func demoDocumentCarriesEveryRequiredRole() {
        let select = DemoHouse.config.media.sourceSelect
        #expect(Set(select.entityIds.keys) == Config.SourceSelectRemote.requiredEntityRoles)
        #expect(Set(select.sources.keys) == Config.SourceSelectRemote.requiredSourceRoles)
        #expect(Set(select.revertSeconds.keys) == Config.SourceSelectRemote.requiredRevertRoles)
        #expect(throws: Never.self) { try DemoHouse.config.validateRoles() }
    }

    @Test func aMissingRoleIsRefusedAtDecodeAndNamed() throws {
        for (role, map) in [("volume", "entityIds"), ("tv", "sources"), ("sync", "revertSeconds")] {
            let data = try dataLacking(role: role, in: map)
            do {
                _ = try Config.decode(data)
                Issue.record("decoded a document without \(map).\(role)")
            } catch let Config.DecodeError.malformed(message) {
                #expect(message.contains("media.sourceSelect.\(map) lacks \(role)"))
            }
        }
    }

    @Test func extraRolesAreAccepted() throws {
        var object = try demoObject()
        var media = try #require(object["media"] as? [String: Any])
        var select = try #require(media["sourceSelect"] as? [String: Any])
        var sources = try #require(select["sources"] as? [String: Any])
        sources["streamer"] = "Streamer"
        select["sources"] = sources
        media["sourceSelect"] = select
        object["media"] = media
        #expect(try Config.decode(JSONSerialization.data(withJSONObject: object)).media.sourceSelect.sources["streamer"] == "Streamer")
    }
}
