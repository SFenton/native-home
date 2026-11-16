import Foundation
import Testing
@testable import HassCore

// MARK: - Layout decode and rules

/// A reader over fixed values, so the layout rules are checked without a store.
private struct Reader: ServerUIReading {
    var values: [String: JSONValue] = [:]
    var loading: Set<String> = []
    var viewer: ServerUIViewer? = ServerUIViewer(userId: "u1", isAdmin: true)
    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        if loading.contains(sourceId) { return .loading }
        return values[sourceId].map { .value($0) } ?? .unavailable
    }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

private func number(_ id: String) -> ServerUIOperand { .read(sourceId: id, path: ["state"], as: .number) }

@MainActor
struct ServerUILayoutTests {
    typealias D = ServerUICompositionDocument

    /// The component at `index` of the third page of a corpus file, decoded.
    private func component(_ file: String, at index: Int = 0) throws -> D.Component {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent(file)
        let publication = try HouseConfigSource.$scoped.withValue(HouseConfigSource.demoForLayout) {
            try ServerUICompositionPublication.decode(Data(contentsOf: url))
        }
        return publication.document.pages[2].surface.components[index]
    }

    // MARK: Decode

    @Test func tabAreasKeepDocumentOrderAndScope() throws {
        guard case .localTabs(let tabs) = try component("reject/pending-tab-blocks-shared-tab-shared-tab.json") else { Issue.record("not tabs"); return }
        #expect(tabs.areas.count == 5)
        #expect(tabs.areas.first?.scope == .all)
        #expect(tabs.areas.map(\.scope).contains { if case .tabs(let ids) = $0 { ids.count == 1 } else { false } })
        #expect(tabs.tabs.allSatisfy { $0.children.isEmpty })
    }

    @Test func anAreaForTwoTabsShowsOnBothAndOnNoOther() throws {
        guard case .localTabs(let tabs) = try component("reject/pending-tab-blocks-two-tabs.json") else { Issue.record("not tabs"); return }
        let shared = try #require(tabs.areas.first { if case .tabs(let ids) = $0.scope { ids.count == 2 } else { false } })
        let shown = tabs.tabs.map(\.id).filter { shared.scope.shows(on: $0) }
        #expect(shown.count == 2)
        #expect(ServerUILayoutRules.areas(tabs, on: shown[0], in: Reader()).contains { $0.id == shared.id })
        let other = try #require(tabs.tabs.map(\.id).first { !shown.contains($0) })
        #expect(!ServerUILayoutRules.areas(tabs, on: other, in: Reader()).contains { $0.id == shared.id })
    }

    @Test(arguments: [("top", "titles"), ("bottom", "icons")])
    func tabBarSettingsDecode(placement: String, labels: String) throws {
        guard case .localTabs(let tabs) = try component("reject/pending-tab-bar-\(placement)-\(labels).json") else { Issue.record("not tabs"); return }
        #expect(tabs.tabBar?.placement.rawValue == placement)
        #expect(tabs.tabBar?.labels.rawValue == labels)
        #expect(tabs.pinned == (placement == "bottom"))
    }

    @Test func fallbackTabDecodes() throws {
        guard case .localTabs(let tabs) = try component("reject/pending-tab-fallback-second-tab.json") else { Issue.record("not tabs"); return }
        #expect(tabs.fallbackTabId == "two")
    }

    @Test func overlayKeepsTheBaseFirstAndEveryAnchor() throws {
        guard case .overlay(let overlay) = try component("reject/pending-overlay-five-anchors.json") else { Issue.record("not an overlay"); return }
        #expect(overlay.children.count == 5)
        #expect(overlay.anchors.map(\.anchor) == [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing])
        #expect(overlay.placement(of: overlay.children[0].node.id) == nil)
        #expect(overlay.placement(of: "d")?.inset.points == 24)
    }

    @Test func tilePartsDecodeTheProgressAndTheDestination() throws {
        guard case .stateTile(let tile) = try component("reject/pending-tile-parts-progress-math.json") else { Issue.record("not a tile"); return }
        #expect(tile.parts.progress != nil)
        guard case .stateTile(let linked) = try component("reject/pending-tile-parts-destination.json") else { Issue.record("not a tile"); return }
        #expect(linked.action != nil)
    }

    @Test func aBadgeOnATileDecodesAndNoneDrawsNothing() throws {
        guard case .navigationTile(let tile) = try component("reject/pending-badge-tiles.json", at: 0),
              case .stateTile(let plain) = try component("reject/pending-badge-tiles.json", at: 1) else { Issue.record("wrong nodes"); return }
        #expect(tile.node.badgeValue == .literal(.string("New")))
        #expect(plain.node.badgeValue == nil)
    }

    @Test func anUnsetSpanReadsAsOneColumnAndTheGridDecides() throws {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("reject/pending-overlay-five-anchors.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        func strip(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                if (dictionary["layout"] as? [String: Any])?["span"] != nil { dictionary["layout"] = [String: Any]() }
                return dictionary.mapValues(strip)
            }
            if let list = value as? [Any] { return list.map(strip) }
            return value
        }
        object = try #require(strip(object) as? [String: Any])
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let publication = try HouseConfigSource.$scoped.withValue(HouseConfigSource.demoForLayout) { try ServerUICompositionPublication.decode(bytes) }
        let nodes = publication.document.pages[2].surface.components
        #expect(nodes.allSatisfy { $0.node.span == 1 })
    }

    // MARK: Badge rules

    @Test(arguments: [(JSONValue.number(0), nil), (.number(3), "3"), (.number(12.5), "12.5"), (.string("0"), nil), (.string(""), nil),
                      (.string("New"), "New"), (.bool(true), nil)] as [(JSONValue, String?)])
    func badgeTextFollowsTheValue(value: JSONValue, text: String?) {
        #expect(ServerUILayoutRules.badge(.literal(value), in: Reader()) == .text(text))
    }

    @Test func aBadgeThatIsLoadingKeepsWhatItShowedAndAnUnavailableOneDrawsNothing() {
        let operand = number("count")
        #expect(ServerUILayoutRules.badge(operand, in: Reader(loading: ["count"])) == .loading)
        #expect(ServerUILayoutRules.badge(operand, in: Reader()) == .text(nil))
        #expect(ServerUILayoutRules.badge(nil, in: Reader()) == .text(nil))
        #expect(ServerUILayoutRules.badge(operand, in: Reader(values: ["count": .string("4")])) == .text("4"))
    }

    // MARK: Progress and faces

    @Test(arguments: [(0.62, 0.62), (1.4, 1.0), (-0.3, 0.0), (0.0, 0.0), (1.0, 1.0)])
    func progressIsClamped(value: Double, expected: Double) {
        #expect(ServerUILayoutRules.progress(.literal(.number(value)), in: Reader()) == expected)
    }

    @Test func progressIsNilWhenLoadingUnavailableOrNotANumber() {
        #expect(ServerUILayoutRules.progress(number("level"), in: Reader(loading: ["level"])) == nil)
        #expect(ServerUILayoutRules.progress(number("level"), in: Reader()) == nil)
        #expect(ServerUILayoutRules.progress(.literal(.string("cleaning")), in: Reader()) == nil)
        #expect(ServerUILayoutRules.progress(nil, in: Reader()) == nil)
        #expect(ServerUILayoutRules.progress(number("level"), in: Reader(values: ["level": .string("0.5")])) == 0.5)
    }

    @Test func aConditionThatHoldsSetsItsFaceAndOneThatCannotBeAnsweredLeavesItToTheStyle() {
        let hot = ServerUIPredicate.numeric(sourceId: "temp", path: ["state"], above: .literal(.number(75)), below: nil)
        let look = ServerUITileLook(activeWhen: hot, filledWhen: nil, errorWhen: hot)
        #expect(ServerUILayoutRules.faces(look, in: Reader(values: ["temp": .string("80")])) == .init(active: true, filled: nil, error: true))
        #expect(ServerUILayoutRules.faces(look, in: Reader(values: ["temp": .string("50")])) == .init(active: false, filled: nil, error: false))
        #expect(ServerUILayoutRules.faces(look, in: Reader(loading: ["temp"])) == .init())
        #expect(ServerUILayoutRules.faces(.init(), in: Reader()) == .init())
    }

    // MARK: Tabs

    private func container(fallback: String?, hidden: Set<String> = []) -> D.LocalTabs {
        let rule = ServerUIVisibility(predicate: .state(sourceId: "gate", path: ["state"], values: ["on"]), whenUnknown: .hide)
        let tabs = ["controls", "rooms", "dock"].map {
            D.LocalTabs.TabContent(id: $0, label: $0, children: [], visibility: hidden.contains($0) ? rule : nil)
        }
        var value = D.LocalTabs(node: .init(id: "t", title: "t", span: 1), stateId: "s", tabs: tabs)
        value.fallbackTabId = fallback
        return value
    }

    @Test func aHiddenTabGivesWayToTheFallbackThenToTheFirstThatShows() {
        let off = Reader(values: ["gate": .string("off")])
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: "dock", hidden: ["rooms"]), requested: "rooms", in: off) == "dock")
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: nil, hidden: ["rooms"]), requested: "rooms", in: off) == "controls")
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: "rooms", hidden: ["rooms"]), requested: "rooms", in: off) == "controls")
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: nil, hidden: ["rooms"]), requested: "rooms", in: Reader(values: ["gate": .string("on")])) == "rooms")
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: nil, hidden: ["controls", "rooms", "dock"]), requested: "dock", in: off) == "controls")
    }

    @Test func aTabWhoseRuleCannotBeAnsweredFollowsItsPolicy() {
        // `whenUnknown: hide`, and no value for the gate: the tab is out, so the container falls back.
        #expect(ServerUILayoutRules.tabOnShow(container(fallback: "dock", hidden: ["rooms"]), requested: "rooms", in: Reader()) == "dock")
    }
}

extension HouseConfigSource {
    fileprivate static var demoForLayout: HouseConfigSource {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return source
    }
}
