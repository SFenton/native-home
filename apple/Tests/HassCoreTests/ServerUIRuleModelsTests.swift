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
private let red = D.TileFill.solidRGB(red: 255, green: 0, blue: 0)
private let green = D.TileFill.solidRGB(red: 0, green: 255, blue: 0)

@Suite struct ServerUIEnabledRuleTests {
    @Test(arguments: [(ServerUIEnabledUnknown.enabled, true), (.disabled, false), (.keep, true)])
    func unknownFollowsTheAuthoredChoice(choice: ServerUIEnabledUnknown, expected: Bool) {
        let rule = ServerUIEnabledRule(condition: when("a", "on"), whenUnknown: choice)
        #expect(rule.isEnabled(previous: nil, in: House()) == expected)
    }

    @Test func keepRepeatsThePreviousAnswerAndLoadingIsUnknown() {
        let rule = ServerUIEnabledRule(condition: when("a", "on"), whenUnknown: .keep)
        let loading = House(loading: ["a"])
        #expect(rule.isEnabled(previous: false, in: loading) == false)
        #expect(rule.isEnabled(previous: true, in: loading))
    }

    @Test func aKnownAnswerWins() {
        let rule = ServerUIEnabledRule(condition: when("a", "on"), whenUnknown: .enabled)
        #expect(rule.isEnabled(previous: nil, in: House(values: ["a": "off"])) == false)
        #expect(rule.isEnabled(previous: nil, in: House(values: ["a": "on"])))
        #expect(ServerUIEnabledRule.allows(nil, previous: nil, in: House()))
    }
}

@Suite struct ServerUIActionRuleTests {
    private let rule = ServerUIActionRule(
        cases: [.init(when: when("a", "on"), then: .back), .init(when: when("b", "on"), then: .dismiss(scope: .canonical))], otherwise: .selectTab(tabId: "home"))

    @Test func firstHoldingCaseRuns() {
        #expect(rule.resolve(House(values: ["a": "on", "b": "on"])) == .back)
        #expect(rule.resolve(House(values: ["a": "off", "b": "on"])) == .dismiss(scope: .canonical))
    }

    @Test func noCaseRunsOtherwiseAndNilOtherwiseRunsNothing() {
        let off = House(values: ["a": "off", "b": "off"])
        #expect(rule.resolve(off) == .selectTab(tabId: "home"))
        #expect(ServerUIActionRule(cases: rule.cases, otherwise: nil).resolve(off) == nil)
    }

    @Test func anUnknownCaseAboveATrueOneDoesNothing() {
        #expect(rule.resolve(House(values: ["b": "on"])) == nil)
        #expect(rule.resolve(House(values: ["b": "on"], loading: ["a"])) == nil)
    }

    @Test func plainActionsAreTheirOwnResolution() {
        #expect(D.Action.back.resolved(House()) == .back)
        #expect(D.Action.conditional(rule).resolved(House(values: ["a": "on"])) == .back)
        #expect(D.Action.conditional(rule).plainActions.count == 3)
        #expect(rule.sourceIds == ["a", "b"])
    }
}

@Suite struct ServerUIDynamicLookTests {
    private let symbol = D.Symbol(name: "sun.max", rendering: .canonical, unavailable: .canonical)

    @Test func conditionalFillPicksACaseAndFallsBackWhenUnknown() {
        let look = ServerUIDynamicLook<D.TileFill>.conditional([.init(when: when("a", "on"), then: green)])
        #expect(look.resolve(base: red, role: .fill, in: House(values: ["a": "on"])) == .value(green))
        #expect(look.resolve(base: red, role: .fill, in: House(values: ["a": "off"])) == .value(red))
        #expect(look.resolve(base: red, role: .fill, in: House()) == .value(red))
    }

    @Test func boundColorLoadingKeepsAndUnavailableFallsBack() {
        let look = ServerUIDynamicLook<D.TileFill>.bound(.read(sourceId: "c", path: ["state"], as: .string))
        #expect(look.resolve(base: red, role: .fill, in: House(loading: ["c"])) == .loading)
        #expect(look.resolve(base: red, role: .fill, in: House()) == .value(red))
    }

    @Test func boundSymbolLoadingKeepsAndNameRenamesTheFallback() {
        let look = ServerUIDynamicLook<D.Symbol>.bound(.read(sourceId: "s", path: ["state"], as: .string))
        #expect(look.resolve(base: symbol, in: House(loading: ["s"])) == .loading)
        #expect(look.resolve(base: symbol, in: House(values: ["s": "moon"])) == .value(symbol.renamed("moon")))
        #expect(look.resolve(base: symbol, in: House()) == .value(symbol))
    }

    @Test func aLoadingSlotKeepsWhatWasShown() {
        let appearance = D.StatusAppearance(icon: symbol, fill: red, glyph: nil, iconRule: nil,
                                            fillRule: .bound(.read(sourceId: "c", path: ["state"], as: .string)), glyphRule: nil)
        let shown = ServerUIResolvedAppearance(icon: symbol, fill: green, glyph: nil)
        #expect(appearance.resolve(in: House(loading: ["c"]), keeping: shown).fill == green)
        #expect(appearance.resolve(in: House(loading: ["c"])).fill == red)
        #expect(appearance.isDynamic)
    }
}

@Suite struct ServerUIStringResolverTests {
    private func resolve(_ value: D.StringValue, _ house: House) -> ServerUIReadResult {
        ServerUIStringResolver.resolve(value, read: { _ in .unavailable }, in: house)
    }

    @Test func fallbackStandsInForUnavailableNeverForLoading() {
        let operand = ServerUIOperand.read(sourceId: "a", path: ["state"], as: .string)
        let value = D.StringValue.expression(operand, fallback: "n/a")
        #expect(resolve(value, House()) == .value(.string("n/a")))
        #expect(resolve(value, House(loading: ["a"])) == .loading)
        #expect(resolve(value, House(values: ["a": "hi"])) == .value(.string("hi")))
        #expect(resolve(.expression(operand, fallback: nil), House()) == .unavailable)
        #expect(resolve(.literal("x"), House()) == .value(.string("x")))
    }
}

@Suite struct ServerUIConfirmWhenTests {
    private func call(_ when: ServerUIPredicate?) -> ServerUICallService {
        ServerUICallService(domain: "light", service: "turn_off",
                            confirmation: .additional(style: .alert, title: "t", message: "m", confirmLabel: "Yes", cancelLabel: "No",
                                                      destructive: false),
                            confirmWhen: when)
    }

    @Test func noWhenAsksAndATrueOrUnknownWhenAsks() {
        #expect(call(nil).asksConfirmation(of: nil, in: House()))
        #expect(call(when("a", "on")).asksConfirmation(of: nil, in: House(values: ["a": "on"])))
        #expect(call(when("a", "on")).asksConfirmation(of: nil, in: House()))
        #expect(call(when("a", "on")).asksConfirmation(of: nil, in: House(loading: ["a"])))
    }

    @Test func aFalseWhenHoldsTheQuestionBack() {
        #expect(call(when("a", "on")).asksConfirmation(of: nil, in: House(values: ["a": "off"])) == false)
    }
}
