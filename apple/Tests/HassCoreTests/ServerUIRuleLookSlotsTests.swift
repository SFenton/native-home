import Foundation
import Testing
@testable import HassCore

private struct House: ServerUIReading {
    var values: [String: String] = [:]
    var loading: Set<String> = []
    var viewer: ServerUIViewer? { nil }
    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        if loading.contains(sourceId) { return .loading }
        return values[sourceId].map { .value(.string($0)) } ?? .unavailable
    }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

private typealias D = ServerUICompositionDocument
private func when(_ id: String, _ state: String) -> ServerUIPredicate { .state(sourceId: id, path: ["state"], values: [state]) }
private func text(_ id: String) -> ServerUIOperand { .read(sourceId: id, path: ["state"], as: .string) }
private let red = D.TileFill.solidRGB(red: 255, green: 0, blue: 0)
private let green = D.TileFill.solidRGB(red: 0, green: 255, blue: 0)
private let sun = D.Symbol(name: "sun.max", rendering: .canonical, unavailable: .canonical)

/// Fails if: a look slot does not name the sources its rule reads (the renderer would never re-resolve it), a rule answers the wrong
/// case, or a slot still loading drops what it showed instead of keeping it.
@Suite struct ServerUIRuleLookSlotsTests {
    @Test func aLookRuleNamesTheSourcesItReads() {
        let conditional = ServerUIDynamicLook<D.TileFill>.conditional([
            .init(when: when("a", "on"), then: green), .init(when: when("b", "on"), then: red)])
        #expect(conditional.sourceIds == ["a", "b"])
        #expect(ServerUIDynamicLook<D.TileFill>.bound(text("c")).sourceIds == ["c"])
    }

    @Test func aStatusLookResolvesEverySlotByItsRule() {
        let appearance = D.StatusAppearance(
            icon: sun, fill: red, glyph: red,
            iconRule: .conditional([.init(when: when("a", "on"), then: D.Symbol(name: "moon", rendering: .canonical, unavailable: .canonical))]),
            fillRule: .conditional([.init(when: when("a", "on"), then: green)]),
            glyphRule: .conditional([.init(when: when("a", "on"), then: green)]))
        #expect(appearance.ruleSourceIds == ["a"])
        let on = appearance.resolve(in: House(values: ["a": "on"]))
        #expect(on.icon.name == "moon" && on.fill == green && on.glyph == green)
        let off = appearance.resolve(in: House(values: ["a": "off"]))
        #expect(off == ServerUIResolvedAppearance(icon: sun, fill: red, glyph: red))
    }

    @Test func aLoadingIconAndGlyphKeepWhatWasShownAndOtherwiseTheirOwnValue() {
        let appearance = D.StatusAppearance(
            icon: sun, fill: red, glyph: red,
            iconRule: .bound(text("i")), fillRule: nil, glyphRule: .bound(text("g")))
        let house = House(loading: ["i", "g"])
        let shownIcon = D.Symbol(name: "moon", rendering: .canonical, unavailable: .canonical)
        let shown = ServerUIResolvedAppearance(icon: shownIcon, fill: green, glyph: green)
        let kept = appearance.resolve(in: house, keeping: shown)
        #expect(kept.icon == shownIcon && kept.glyph == green && kept.fill == red)
        let fresh = appearance.resolve(in: house)
        #expect(fresh.icon == sun && fresh.glyph == red)
        #expect(appearance.ruleSourceIds == ["i", "g"])
    }

    @Test func aGlyphRuleWithNoGlyphDrawsNone() {
        let appearance = D.StatusAppearance(icon: sun, fill: red, glyph: nil, iconRule: nil, fillRule: nil,
                                            glyphRule: .conditional([.init(when: when("a", "on"), then: green)]))
        #expect(appearance.resolve(in: House(values: ["a": "on"])).glyph == nil)
        #expect(appearance.isDynamic)
    }

    @Test func aTileAndARoomStateResolveTheirFillByRuleAndKeepItWhileLoading() {
        let rule = ServerUIDynamicLook<D.TileFill>.conditional([.init(when: when("a", "on"), then: green)])
        let bound = ServerUIDynamicLook<D.TileFill>.bound(text("c"))
        let plain = D.TilePresentation(layout: .standard, titleLines: 1, fill: red, bodyHint: nil)
        #expect(plain.resolvedFill(in: House()) == red)
        var tile = plain
        tile.fillRule = rule
        #expect(tile.resolvedFill(in: House(values: ["a": "on"])) == green)
        tile.fillRule = bound
        #expect(tile.resolvedFill(in: House(loading: ["c"]), keeping: green) == green)
        #expect(tile.resolvedFill(in: House(loading: ["c"])) == red)

        var room = D.RoomStateColor(state: "on", fill: red)
        #expect(room.resolvedFill(in: House()) == red)
        room.fillRule = rule
        #expect(room.resolvedFill(in: House(values: ["a": "on"])) == green)
        room.fillRule = bound
        #expect(room.resolvedFill(in: House(loading: ["c"]), keeping: green) == green)
        #expect(room.resolvedFill(in: House(loading: ["c"])) == red)
    }

    @Test func aPillToneFollowsItsRuleAndNamesTheSourcesItReads() {
        var pill = D.StatusPill(node: .init(id: "p", title: "P", span: 1), icon: sun, value: .literal("v"), detail: .literal("d"),
                                tone: .neutral, unavailableText: "n/a")
        #expect(pill.resolvedTone(in: House()) == .neutral)
        #expect(pill.toneSourceIds.isEmpty)
        pill.toneCases = [.init(when: when("a", "on"), then: .danger)]
        #expect(pill.resolvedTone(in: House(values: ["a": "on"])) == .danger)
        #expect(pill.resolvedTone(in: House(values: ["a": "off"])) == .neutral)
        #expect(pill.toneSourceIds == ["a"])
    }

    @Test func aStringNamesTheSourcesItReads() {
        let source = D.Read(sourceId: "r", path: ["state"], kind: .string)
        #expect(ServerUIStringResolver.sourceIds(.literal("x")).isEmpty)
        #expect(ServerUIStringResolver.sourceIds(.read(source, fallback: nil)) == ["r"])
        #expect(ServerUIStringResolver.sourceIds(.expression(text("e"), fallback: nil)) == ["e"])
    }

    @Test func aTileIsEmptyOnlyWithNoPartAndNoCondition() {
        #expect(ServerUITileParts().isEmpty)
        #expect(!ServerUITileParts(subtitle: .literal("s")).isEmpty)
        #expect(!ServerUITileParts(progress: text("p")).isEmpty)
        #expect(ServerUITileLook().isEmpty)
        #expect(!ServerUITileLook(activeWhen: when("a", "on")).isEmpty)
        #expect(!ServerUITileLook(filledWhen: when("a", "on")).isEmpty)
        #expect(!ServerUITileLook(errorWhen: when("a", "on")).isEmpty)
    }
}
