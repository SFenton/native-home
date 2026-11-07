import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Schema 2: neutral resident keys, role-keyed garage doors, brand-free field names and the Music Room action graphs in the
/// document. Schema 1 is no longer read: every server has been re-uploaded as schema 2.
struct HouseConfigSchemaV2Tests {
    typealias Config = HouseConfig

    // MARK: - Schema 1 is refused

    @Test func aSchemaOneDocumentIsRefused() throws {
        var object = try #require(JSONSerialization.jsonObject(with: DemoHouse.config.encoded()) as? [String: Any])
        object["schema"] = 1
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: Config.DecodeError.self) { try Config.decode(data) }
    }

    @Test func aSchemaOneEnvelopeIsRefused() throws {
        let reply = Data(#"{"schema": 1, "hash": "h", "config": {}}"#.utf8)
        #expect(throws: Config.DecodeError.self) { try HouseConfigEnvelope.decode(reply) }
    }

    // MARK: - Writing schema 2

    @Test func theDocumentIsSchemaTwo() throws {
        let data = try DemoHouse.config.encoded()
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["schema"] as? Int == 2)
        #expect(Config.supportedSchema == 2 && Config.minimumSchema == 2)
        #expect(try Config.decode(data) == DemoHouse.config)
    }

    @Test func theDocumentCarriesNoSchemaOneKey() throws {
        let text = String(decoding: try DemoHouse.config.encoded(), as: UTF8.self)
        for gone in ["hueSync", "musicRoomXbox", "isDonetick", "donetickTask", "donetickAssignee", "mainFloorPause", "garageDoorEntityIds"] {
            #expect(!text.contains("\"\(gone)\""), "\(gone) is a schema 1 key")
        }
    }

    @Test func residentsAreKeyedByNeutralIds() throws {
        let keys = DemoHouse.config.chores.people.map(\.key)
        #expect(keys == (1...keys.count).map { "resident_\($0)" })
    }

    @Test func aNewerSchemaIsStillRefused() throws {
        #expect(throws: Config.DecodeError.unsupportedSchema(found: 3, supported: 2)) {
            try Config.decode(Data(#"{"schema": 3}"#.utf8))
        }
    }

    // MARK: - The document drives the facades

    @Test func residentsReadTheirRecordFromTheDocument() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(Resident.allCases == [.resident1, .resident2])
            #expect(Resident.resident1.name == "Alex" && Resident.resident2.name == "Sam")
            #expect(Resident.resident1.other == .resident2 && Resident.resident2.other == .resident1)
            #expect(Resident.forUserId(" \(Resident.resident2.haUserId.uppercased()) ") == .resident2)
            #expect(Resident.forUserId("not-a-user") == nil && Resident.forUserId(nil) == nil)
            #expect(Resident(soloTripId: Resident.resident1.soloTripId) == .resident1)
            #expect(Resident(soloTripId: "nobody") == nil)
            #expect(ChoresConfig.showsAdminTodo(to: .resident1) && !ChoresConfig.showsAdminTodo(to: .resident2))
            #expect(ChoresConfig.showsAdminTodo(to: nil))
        }
    }

    @Test func anUnknownResidentReadsAsItsKey() {
        let stranger = Resident(key: "resident_9")
        #expect(stranger.name == "resident_9" && stranger.haUserId.isEmpty && stranger.other.key != "")
        #expect(ChoresConfig.showsAdminTodo(to: stranger))
    }

    @Test func residentRoundTripsAsAString() throws {
        let data = try JSONEncoder().encode([Resident.resident1])
        #expect(String(decoding: data, as: UTF8.self) == #"["resident_1"]"#)
        #expect(try JSONDecoder().decode([Resident].self, from: data) == [.resident1])
    }

    @Test func summaryListsAndExpiredFoodComeFromTheDocument() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let lists = ProfileSummary.lists(for: .resident1)
            #expect(lists.overdue.entityId == DemoHouse.config.chores.people[0].summaryLists.overdue)
            #expect(lists.dueToday.entityId == DemoHouse.config.chores.people[0].summaryLists.dueToday)
            #expect(lists.noDueDate.entityId == DemoHouse.config.chores.people[0].summaryLists.noDueDate)
            #expect(ProfileSummary.expiredFoodEntityId == DemoHouse.config.food.expiredItemsEntityId)
        }
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(ProfileSummary.expiredFoodEntityId.isEmpty)
        }
    }

    @Test func garageDoorsAreReadByRole() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(SecurityConfig.leftGarageDoorEntityId == DemoHouse.config.security.garageDoors["left"])
            #expect(SecurityConfig.rightGarageDoorEntityId == DemoHouse.config.security.garageDoors["right"])
        }
    }

    @Test func sourceSelectActionsReadTheDocumentsGraphs() throws {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            let select = DemoHouse.config.media.sourceSelect
            #expect(MediaRemotes.MusicRoom.tvToggle == select.actions["tvToggle"])
            #expect(MediaRemotes.MusicRoom.fortnite == select.actions["launcher"])
            #expect(MediaRemotes.MusicRoom.xboxToggle == select.actions["consoleToggle"])
            #expect(MediaRemotes.MusicRoom.xboxSourceToggle == select.actions["consoleSourceToggle"])
            #expect(MediaRemotes.MusicRoom.serverToggle == select.actions["serverToggle"])
            #expect(MediaRemotes.MusicRoom.windowsPCToggle == select.actions["pcToggle"])
            let console = SourceSelectActions.musicRoom(.console)
            #expect(console.select == select.commands["consoleOn"] && console.deselect == select.commands["tvOff"])
            #expect(console.title == select.sources["console"])
            #expect(SourceSelectActions.musicRoom(.server).select == select.commands["serverOn"])
            #expect(SourceSelectActions.musicRoom(.pc).select == select.commands["pcOn"])
            if case let .command(launcher)? = select.actions["launcher"] {
                #expect(SourceSelectActions.musicRoom(.launcher).select == launcher)
            } else {
                Issue.record("the launcher is a plain command")
            }
        }
    }

    @Test func withoutADocumentTheGraphsAreInert() {
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(MediaRemotes.MusicRoom.tvToggle == .command(MediaRemotes.MusicRoom.inertCommand))
            #expect(MediaRemotes.MusicRoom.tvOff == MediaRemotes.MusicRoom.inertCommand)
        }
    }

    @Test func aDocumentWithoutAGraphRoleAnswersTheInertOne() {
        var house = DemoHouse.config
        house.media.sourceSelect.actions["tvToggle"] = nil
        house.media.sourceSelect.commands["tvOff"] = nil
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            #expect(MediaRemotes.MusicRoom.tvToggle == .command(MediaRemotes.MusicRoom.inertCommand))
            #expect(MediaRemotes.MusicRoom.tvOff == MediaRemotes.MusicRoom.inertCommand)
        }
    }

    @Test func renamedFieldsReadThroughTheirNewKeys() throws {
        let demo = DemoHouse.config
        let studio = try #require(demo.media.remotes.first { $0.lightSync != nil })
        let resolvers: [MediaRemoteStateResolver?] = studio.devices.map(\.stateResolver)
        #expect(resolvers.contains(MediaRemoteStateResolver.consoleState))
        #expect(demo.chores.pages.contains { $0.hasTaskForm })
        #expect(demo.chores.pages.contains { if case .assignedTask = $0.addAction { true } else { false } })
        #expect(demo.vacuums.autoCleanControls.contains { $0.kind == .pause })
    }

    // MARK: - Odd documents

    @Test func aLauncherThatIsNotAPlainCommandLeavesTheTileUnavailable() {
        var house = DemoHouse.config
        house.media.sourceSelect.actions["launcher"] = .state(
            entityId: "sensor.demo_x", cases: [], otherwise: .textPrompt(targetEntityId: "input_text.demo_x"))
        let source = HouseConfigSource()
        source.set(house)
        HouseConfigSource.$scoped.withValue(source) {
            let tile = SourceSelectActions.musicRoom(.launcher)
            #expect(!tile.isAvailable)
            let spec = tile.actions(for: nil).first
            #expect(spec?.phase == .unavailable && spec?.call == nil && spec?.optimistic.isEmpty == true)
        }
    }

    @Test func galleryViewersResolveByKey() {
        HouseConfigSource.$scoped.withValue(DemoHouse.source) {
            #expect(Resident(viewerName: "resident_2") == .resident2)
            #expect(Resident(viewerName: "nobody") == nil)
        }
    }
}
