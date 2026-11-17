import Foundation
import Testing
@testable import HassCore

// MARK: - Swipe, words, ink and groups (`sh.tile-swipe@1`, `sh.state-words@1`, `sh.tile-ink-default@1`, `sh.grid-state-groups@1`)

/// The decode rules and pure rules of the four tile-contract capabilities. The shared corpus (`ServerUIContractCorpusTests`) holds every accepted
/// and refused document; these hold what the documents decode to and the rules that have no document of their own.
@MainActor
struct ServerUITileContractTests {
    private func publication(_ file: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("accept/\(file).json")))
    }

    private func components(_ publication: ServerUICompositionPublication) -> [ServerUICompositionDocument.Component] {
        func walk(_ items: [ServerUICompositionDocument.Component]) -> [ServerUICompositionDocument.Component] {
            items + items.flatMap { walk($0.childComponents) }
        }
        return (publication.document.pages.map(\.surface) + publication.document.modals.map(\.surface)).flatMap { walk($0.components) }
    }

    // MARK: Swipe

    @Test func aStateTileSwipeDecodesWithItsRangeValueAndCall() throws {
        let tile = try #require(components(publication("tile-swipe-cover-position")).compactMap { c -> ServerUICompositionDocument.StateTile? in
            if case .stateTile(let tile) = c { tile } else { nil }
        }.first)
        let swipe = try #require(tile.swipe)
        #expect(swipe.range == .init(min: 0, max: 100, step: 1))
        #expect(swipe.value != nil)
        #expect(swipe.action?.domain == "cover")
        #expect(swipe.label == "position")
        #expect(swipe.format == "{value}%")
        #expect(swipe.haptic == .detent)
        #expect(swipe.showsBand)
    }

    @Test func aLightGroupTileSwipeDecodesWithTheLightsOwnRange() throws {
        let tile = try #require(components(publication("tile-swipe-light-minimal")).compactMap { c -> ServerUICompositionDocument.HomeLightTile? in
            if case .homeLightTile(let tile) = c { tile } else { nil }
        }.first)
        #expect(tile.swipe?.range == .init(min: 0, max: 100, step: 1))
        #expect(tile.swipe?.detent == 10)
        #expect(tile.swipe?.value == nil)
    }

    @Test func swipeIsOffByDefault() throws {
        let tiles = try components(publication("tile-swipe-light-with-no-swipe-needs-no-id")).compactMap { c -> ServerUICompositionDocument.HomeLightTile? in
            if case .homeLightTile(let tile) = c { tile } else { nil }
        }
        #expect(!tiles.isEmpty)
        #expect(tiles.allSatisfy { $0.swipe == nil && $0.words == nil })
        let capabilities = try publication("tile-swipe-light-with-no-swipe-needs-no-id").capabilities
        #expect(!capabilities.contains("sh.tile-swipe@1"))
    }

    @Test func theDefaultDetentIsATenthOfTheSpanRoundedUpToAStep() {
        #expect(ServerUITileSwipe.defaultDetent(.init(min: 0, max: 100, step: 1)) == 10)
        #expect(ServerUITileSwipe.defaultDetent(.init(min: 60, max: 85, step: 0.5)) == 2.5)
        #expect(ServerUITileSwipe.defaultDetent(.init(min: 0, max: 7, step: 1)) == 1)
        #expect(ServerUITileSwipe.defaultDetent(.init(min: 0, max: 100, step: 20)) == 20)
    }

    @Test func theRangeAndDetentRulesNameTheirPointers() {
        func problems(_ range: ServerUITileSwipe.Range, detent: Double? = nil, format: String? = nil,
                      present: Set<String> = ["value", "action", "label"], tile: ServerUITileSwipe.Tile = .state) -> [String] {
            ServerUITileSwipe.problems(range: range, detent: detent, format: format, present: present, tile: tile).map { "\($0.code.rawValue)\($0.at)" }
        }
        #expect(problems(.init(min: 0, max: 100, step: 1)).isEmpty)
        #expect(problems(.init(min: 5, max: 5, step: 1)) == ["invalid_value/range/max"])
        #expect(problems(.init(min: 0, max: 10, step: 0)) == ["invalid_value/range/step"])
        #expect(problems(.init(min: 0, max: 101, step: 1)) == ["limit_exceeded/range/step"])
        #expect(problems(.init(min: 0, max: 100, step: 1), detent: 15).isEmpty, "a multiple of the step, at most 25 ticks")
        #expect(problems(.init(min: 0, max: 100, step: 1), detent: 0.5) == ["invalid_value/detent"])
        #expect(problems(.init(min: 0, max: 100, step: 1), detent: 3) == ["limit_exceeded/detent"])
        #expect(problems(.init(min: 0, max: 100, step: 1), format: "no number") == ["invalid_value/format"])
        #expect(problems(.init(min: 0, max: 100, step: 1), format: "{value} {other}") == ["invalid_value/format"])
        #expect(problems(.init(min: 0, max: 100, step: 1), present: ["value"]) == ["missing_required/action", "missing_required/label"])
        #expect(problems(.init(min: 0, max: 10, step: 1), present: [], tile: .lightGroup) == ["invalid_value/range"])
        #expect(problems(.init(min: 0, max: 100, step: 1), present: ["label", "format"], tile: .lightGroup)
                == ["invalid_combination/format", "invalid_combination/label"])
    }

    // MARK: Words

    @Test func wordsDecodeOnTheThreeTiles() throws {
        let light = try #require(components(publication("state-words-light-group-all-keys")).compactMap { c -> ServerUIStateWords? in
            if case .homeLightTile(let tile) = c { tile.words } else { nil }
        }.first)
        #expect(light.level?.contains("{value}") == true)
        let overview = try #require(components(publication("state-words-overview-lights-all-keys")).compactMap { c -> ServerUIStateWords? in
            if case .roomOverviewTile(let tile) = c { tile.words } else { nil }
        }.first)
        #expect(overview.on == "Lit" && overview.off == "Dark" && overview.unavailable == "No Answer" && overview.count == "{count} Lit")
        let device = try #require(components(publication("state-words-custom-light-brightness")).compactMap { c -> ServerUIStateWords? in
            if case .deviceControl(let control) = c { control.words } else { nil }
        }.first)
        #expect(device.level != nil || device.off != nil || device.unavailable != nil)
    }

    @Test func eachTileTakesOnlyTheWordsItDraws() {
        let all = ServerUIStateWords(on: "A", off: "B", unavailable: "C", count: "{count}", level: "{value}")
        func refused(_ keys: Set<ServerUIStateWords.Key>) -> [String] { all.problems(allowed: keys).map { "\($0.code.rawValue):\($0.key.rawValue)" } }
        #expect(refused(ServerUIStateWords.lightGroupKeys) == ["invalid_combination:count"])
        #expect(refused(ServerUIStateWords.brightnessKeys) == ["invalid_combination:on", "invalid_combination:count"])
        #expect(refused(ServerUIStateWords.overviewKeys(projection: "lights")) == ["invalid_combination:level"])
        #expect(refused(ServerUIStateWords.overviewKeys(projection: "occupancy")) == ["invalid_combination:count", "invalid_combination:level"])
        #expect(refused(ServerUIStateWords.overviewKeys(projection: "contacts")).count == 4)
    }

    @Test func tokensAreRequiredWhereTheyBelong() {
        func issue(_ words: ServerUIStateWords) -> String? {
            words.problems(allowed: Set(ServerUIStateWords.Key.allCases)).first.map { "\($0.code.rawValue):\($0.key.rawValue)" }
        }
        #expect(issue(.init(count: "Many")) == "invalid_value:count")
        #expect(issue(.init(level: "{count}")) == "invalid_value:level")
        #expect(issue(.init(level: "{value} {value}%")) == nil)
        #expect(issue(.init(level: "{value}{")) == "invalid_value:level")
        #expect(issue(.init(on: "{value}")) == "invalid_value:on")
        #expect(issue(.init(off: "a } b")) == "invalid_value:off")
        #expect(issue(.init(on: "Lit", off: "Dark", count: "{count} Lit", level: "{value} percent")) == nil)
    }

    @Test func absentWordsDrawProductionsText() {
        let words = ServerUIStateWords()
        #expect(words.levelText(percent: 45) == "45%")
        #expect(words.countText(3) == "3 On")
        #expect(ServerUIStateWords(count: "{count} Lit").countText(3) == "3 Lit")
        #expect(ServerUIStateWords(level: "{value} percent").levelText(percent: 45) == "45 percent")
    }

    @Test func aRoomOverviewSaysItsWordsAndProductionsOtherwise() {
        let reads: [String: EntityState] = [
            "light.demo_a": EntityState(entityId: "light.demo_a", state: "on", attributes: [:]),
            "light.demo_b": EntityState(entityId: "light.demo_b", state: "on", attributes: [:]),
            "light.demo_c": EntityState(entityId: "light.demo_c", state: "off", attributes: [:]),
        ]
        let read: RoomOverview.Read = { reads[$0] }
        let many = RoomGroup("Den", [RoomGroupItem("A", "light.demo_a"), RoomGroupItem("B", "light.demo_b"), RoomGroupItem("C", "light.demo_c")])
        let one = RoomGroup("Den", [RoomGroupItem("A", "light.demo_a")])
        let none = RoomGroup("Den", [RoomGroupItem("C", "light.demo_c")])
        #expect(RoomOverview.cardSubtitle(.lights, many, read: read) == "2 On")
        #expect(RoomOverview.cardSubtitle(.lights, one, read: read) == "On")
        #expect(RoomOverview.cardSubtitle(.lights, none, read: read) == "Off")
        let words = ServerUIStateWords(on: "Lit", off: "Dark", count: "{count} Lit")
        #expect(RoomOverview.cardSubtitle(.lights, many, read: read, words: words) == "2 Lit")
        #expect(RoomOverview.cardSubtitle(.lights, one, read: read, words: words) == "Lit")
        #expect(RoomOverview.cardSubtitle(.lights, none, read: read, words: words) == "Dark")
        #expect(RoomOverview.cardSubtitle(.occupancy, one, read: { _ in EntityState(entityId: "x", state: "on", attributes: [:]) }) == "Occupied")
        #expect(RoomOverview.cardSubtitle(.occupancy, one, read: { _ in EntityState(entityId: "x", state: "off", attributes: [:]) }) == "Not Occupied")
        #expect(RoomOverview.cardSubtitle(.occupancy, one, read: { _ in EntityState(entityId: "x", state: "on", attributes: [:]) }, words: words) == "Lit")
    }

    // MARK: Ink

    @Test func theInkIdIsOptionalInAManifestAndNeverRequired() {
        let needed: Set<String> = ["sh.page@1", "sh.shell@1"]
        let sorted = needed.sorted()
        #expect(ServerUITileInkDefault.matches(sorted, requirements: needed))
        #expect(ServerUITileInkDefault.matches((sorted + [ServerUITileInkDefault.capability]).sorted(), requirements: needed))
        #expect(!ServerUITileInkDefault.matches(sorted + ["sh.grid@1"], requirements: needed))
        #expect(!ServerUITileInkDefault.matches([ServerUITileInkDefault.capability], requirements: needed))
    }

    @Test func aManifestThatListsTheInkIdDrawsThePrimaryInk() throws {
        #expect(ServerUITileInkDefault.declared(by: ["sh.page@1"]) == .muted)
        #expect(ServerUITileInkDefault.declared(by: ["sh.page@1", "sh.tile-ink-default@1"]) == .primary)
        #expect(try publication("tile-ink-default-state-tile").inkDefault == .primary)
        #expect(try publication("tile-swipe-light-with-no-swipe-needs-no-id").inkDefault == .muted)
    }

    // MARK: Groups

    @Test func groupsDecodeInTheirDrawnOrder() throws {
        let grid = try #require(components(publication("grid-groups-two-groups")).compactMap { c -> ServerUIGridGroups? in
            if case .grid(let grid) = c { grid.groups } else { nil }
        }.first)
        #expect(grid.items.map(\.title) == ["On", "Off"])
        #expect(grid.items[0].states == [.active])
        #expect(grid.items[1].states == [.idle, .unavailable])
    }

    @Test func aGridWithNoGroupsIsTodaysGrid() throws {
        let grids = try components(publication("grid-groups-without-groups-needs-no-id")).compactMap { c -> ServerUICompositionDocument.Grid? in
            if case .grid(let grid) = c { grid } else { nil }
        }
        #expect(grids.allSatisfy { $0.groups == nil })
    }

    @Test func groupsArrangeByStateAndDropEmptyOnes() {
        let groups = ServerUIGridGroups(items: [
            .init(id: "on", title: "Lights On", states: [.active]),
            .init(id: "off", title: "Lights Off", states: [.idle, .unavailable]),
        ])
        let tiles: [(key: String, state: ServerUIGridGroups.State)] = [("a", .idle), ("b", .active), ("c", .unavailable), ("d", .active), ("e", .idle)]
        let sections = groups.arrange(tiles)
        #expect(sections.map(\.group.id) == ["on", "off"])
        #expect(sections[0].keys == ["b", "d"])
        #expect(sections[1].keys == ["a", "c", "e"], "inside a group tiles keep the grid's order")
        #expect(groups.arrange([("a", .idle)]).map(\.group.id) == ["off"], "a group with no tiles is not drawn")
        #expect(groups.arrange([(key: String, state: ServerUIGridGroups.State)]()).isEmpty, "a grid whose groups are all empty draws nothing")
    }

    @Test func aStateNoGroupHoldsGoesUnderTheLastGroup() {
        let groups = ServerUIGridGroups(items: [.init(id: "a", title: "A", states: [.active]), .init(id: "b", title: "B", states: [.idle])])
        #expect(groups.index(of: .unavailable) == 1)
    }

    @Test func everyStateIsInExactlyOneGroup() {
        func problems(_ items: [(String, [ServerUIGridGroups.State])]) -> [String] {
            ServerUIGridGroups.problems(items.map { (id: $0.0, states: $0.1) }).map { "\($0.code.rawValue)\($0.at)" }
        }
        #expect(problems([("a", [.active]), ("b", [.idle, .unavailable])]).isEmpty)
        #expect(problems([("a", [.active, .idle, .unavailable])]).isEmpty)
        #expect(problems([("a", [.active]), ("b", [.active, .idle, .unavailable])]) == ["invalid_combination/items/1/states/0"])
        #expect(problems([("a", [.active]), ("b", [.idle])]) == ["invalid_combination/items"])
        #expect(problems([("a", [.active, .active, .idle, .unavailable])]) == ["invalid_combination/items/0/states/1"])
        #expect(problems([("a", [.active]), ("a", [.idle, .unavailable])]) == ["duplicate_id/items/1/id"])
    }
}
