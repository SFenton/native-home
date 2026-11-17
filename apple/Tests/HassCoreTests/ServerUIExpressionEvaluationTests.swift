import Foundation
import Testing
@testable import HassCore

// MARK: - Evaluation of operands, predicates, visibility and calls

/// A reader over fixed values, so evaluation is checked without a store.
private struct Reader: ServerUIReading {
    var values: [String: JSONValue] = [:]
    var loading: Set<String> = []
    var viewer: ServerUIViewer? = ServerUIViewer(userId: "u1", isAdmin: true, personEntityId: "person.demo_resident")
    var person: ServerUIReadResult = .value(.string("home"))
    var controlValue: JSONValue?

    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        if loading.contains(sourceId) { return .loading }
        guard var value = values[sourceId] else { return .unavailable }
        if path == ["state"] { return .value(value) }
        for segment in path {
            guard let next = value[segment] else { return .unavailable }
            value = next
        }
        return .value(value)
    }
    func viewerPersonState() -> ServerUIReadResult { person }
}

private func literal(_ value: JSONValue) -> ServerUIOperand { .literal(value) }
private func read(_ id: String, _ path: [String] = ["state"], as kind: ServerUICompositionDocument.ScalarKind = .string) -> ServerUIOperand {
    .read(sourceId: id, path: path, as: kind)
}

@Suite struct ServerUIOperandEvaluationTests {
    @Test func readsCoerceToTheKindAskedFor() {
        let reader = Reader(values: ["temp": .string("72.5"), "fan": .string("on"),
                                     "attrs": .object(["attributes": .object(["percentage": .number(40)])])])
        #expect(read("fan").evaluate(reader) == .value(.string("on")))
        #expect(read("temp", as: .number).evaluate(reader) == .value(.number(72.5)))
        #expect(read("fan", as: .number).evaluate(reader) == .unavailable)
        #expect(read("fan", as: .boolean).evaluate(reader) == .unavailable)
        #expect(read("ghost").evaluate(reader) == .unavailable)
        #expect(ServerUIOperand.read(sourceId: "attrs", path: ["attributes", "percentage"], as: .number).evaluate(reader) == .value(.number(40)))
    }

    @Test func aLoadingSourceKeepsAnExpressionLoadingNotUnavailable() {
        let reader = Reader(values: ["a": .string("1")], loading: ["b"])
        let both = ServerUIOperand.list([read("ghost"), read("b")])
        #expect(both.evaluate(reader) == .loading)
        #expect(ServerUIOperand.list([read("ghost")]).evaluate(reader) == .unavailable)
    }

    @Test func formatFillsHolesAndFormatsNumbersWithoutALocale() {
        let reader = Reader(values: ["done": .string("3"), "total": .string("7.5")])
        let text = ServerUIOperand.format(
            pattern: "{done} of {total} done, {raw}",
            args: ["done": read("done", as: .number), "total": read("total", as: .number), "raw": literal(.number(2.5))],
            formats: ["done": .number(.init(maximumFractionDigits: 0)), "total": .number(.init(maximumFractionDigits: 1))])
        #expect(text.evaluate(reader) == .value(.string("3 of 7.5 done, 2.5")))
        #expect(ServerUINumberFormat(maximumFractionDigits: 2).text(2.5) == "2.5")
        #expect(ServerUINumberFormat(maximumFractionDigits: 0).text(-0.2) == "0")
        #expect(ServerUINumberFormat(maximumFractionDigits: 9).maximumFractionDigits == 6)
        let missing = ServerUIOperand.format(pattern: "{a}", args: ["a": read("ghost")], formats: [:])
        #expect(missing.evaluate(reader) == .unavailable)
    }

    @Test func mapPicksTheFirstMatchingCase() {
        let reader = Reader(values: ["mode": .string("heat")])
        let map = ServerUIOperand.map(
            of: read("mode"),
            cases: [.init(equals: .string("cool"), then: literal(.string("Cooling"))),
                    .init(equals: .string("heat"), then: literal(.string("Heating")))],
            otherwise: read("mode"))
        #expect(map.evaluate(reader) == .value(.string("Heating")))
        #expect(map.evaluate(Reader(values: ["mode": .string("auto")])) == .value(.string("auto")))
        #expect(map.evaluate(Reader()) == .unavailable)
        // A number matches its text and a flag matches true/false.
        let number = ServerUIOperand.map(of: literal(.number(3)), cases: [.init(equals: .string("3"), then: literal(.bool(true)))],
                                         otherwise: literal(.bool(false)))
        #expect(number.evaluate(reader) == .value(.bool(true)))
    }

    @Test func mathIsTotal() {
        let reader = Reader()
        func math(_ op: ServerUIOperand.MathOp, _ numbers: [Double]) -> ServerUIReadResult {
            ServerUIOperand.math(op, numbers.map { literal(.number($0)) }).evaluate(reader)
        }
        #expect(math(.add, [1, 2, 3]) == .value(.number(6)))
        #expect(math(.subtract, [5, 2]) == .value(.number(3)))
        #expect(math(.multiply, [2, 4]) == .value(.number(8)))
        #expect(math(.divide, [9, 3]) == .value(.number(3)))
        #expect(math(.divide, [1, 0]) == .unavailable)
        #expect(math(.min, [4, 2]) == .value(.number(2)) && math(.max, [4, 2]) == .value(.number(4)))
        #expect(math(.round, [2.456, 2]) == .value(.number(2.46)))
        #expect(math(.round, [2.5]) == .value(.number(3)))
        #expect(math(.round, [2.5, 9]) == .unavailable)
        #expect(math(.clamp, [95, 0, 80]) == .value(.number(80)) && math(.clamp, [5, 9, 1]) == .unavailable)
        #expect(math(.scale, [50, 0, 100, 0, 255]) == .value(.number(127.5)))
        #expect(math(.scale, [1, 4, 4, 0, 1]) == .unavailable)
        #expect(math(.subtract, [1]) == .unavailable)
        #expect(ServerUIOperand.math(.add, [literal(.string("x")), literal(.number(1))]).evaluate(reader) == .unavailable)
    }

    @Test func objectsListsViewerAndControlResolve() {
        let reader = Reader(values: ["fan": .string("on")], controlValue: .number(40))
        let object = ServerUIOperand.object(["pct": .control, "who": .viewer(.userId), "admin": .viewer(.isAdmin), "fan": read("fan")])
        #expect(object.evaluate(reader) == .value(.object(["pct": .number(40), "who": .string("u1"), "admin": .bool(true), "fan": .string("on")])))
        #expect(ServerUIOperand.control.evaluate(Reader()) == .unavailable)
        #expect(ServerUIOperand.viewer(.userId).evaluate(Reader(viewer: nil)) == .loading)
        #expect(ServerUIOperand.viewer(.personEntityId).evaluate(reader) == .value(.string("person.demo_resident")))
        #expect(ServerUIOperand.list([literal(.string("a")), .control]).evaluate(reader) == .value(.array([.string("a"), .number(40)])))
        #expect(object.sourceIds == ["fan"] && object.usesControl && object.readsViewer)
        #expect(ServerUIOperand.list([literal(.number(1))]).usesControl == false)
    }
}

@Suite struct ServerUIPredicateEvaluationTests {
    private let on = ServerUIPredicate.state(sourceId: "fan", path: ["state"], values: ["on"])

    @Test func stateAndNumericAnswerYesNoOrUnknown() {
        let reader = Reader(values: ["fan": .string("on"), "temp": .string("71"), "limit": .string("70")])
        #expect(on.evaluate(reader) == .yes)
        #expect(on.evaluate(Reader(values: ["fan": .string("off")])) == .no)
        #expect(on.evaluate(Reader()) == .unknown)
        let above = ServerUIPredicate.numeric(sourceId: "temp", path: ["state"], above: literal(.number(70)), below: nil)
        #expect(above.evaluate(reader) == .yes)
        let between = ServerUIPredicate.numeric(sourceId: "temp", path: ["state"], above: literal(.number(60)), below: literal(.number(65)))
        #expect(between.evaluate(reader) == .no)
        // Either bound may read another entity.
        let relative = ServerUIPredicate.numeric(sourceId: "temp", path: ["state"], above: read("limit", as: .number), below: nil)
        #expect(relative.evaluate(reader) == .yes && relative.sourceIds == ["temp", "limit"])
        #expect(relative.evaluate(Reader(values: ["temp": .string("71")])) == .unknown)
        #expect(above.evaluate(Reader(values: ["temp": .string("warm")])) == .unknown)
        // A number or a flag compares as text.
        #expect(ServerUIPredicate.state(sourceId: "n", path: ["state"], values: ["3"]).evaluate(Reader(values: ["n": .number(3)])) == .yes)
        #expect(ServerUIPredicate.state(sourceId: "b", path: ["state"], values: ["true"]).evaluate(Reader(values: ["b": .bool(true)])) == .yes)
    }

    @Test func combinatorsFollowThreeValuedLogic() {
        let reader = Reader(values: ["fan": .string("on")])
        let unknown = ServerUIPredicate.state(sourceId: "ghost", path: ["state"], values: ["x"])
        let off = ServerUIPredicate.state(sourceId: "fan", path: ["state"], values: ["off"])
        #expect(ServerUIPredicate.all([on, unknown]).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.all([off, unknown]).evaluate(reader) == .no)
        #expect(ServerUIPredicate.any([off, unknown]).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.any([on, unknown]).evaluate(reader) == .yes)
        #expect(ServerUIPredicate.not(unknown).evaluate(reader) == .unknown)
        #expect(ServerUIPredicate.not(on).evaluate(reader) == .no)
        #expect(ServerUIPredicate.all([on, .not(off)]).sourceIds == ["fan"])
    }

    @Test func viewerPredicatesNeedBothFactsWhenBothAreGiven() {
        let admin = ServerUIPredicate.viewer(isAdmin: true, userIds: nil)
        #expect(admin.evaluate(Reader()) == .yes)
        #expect(admin.evaluate(Reader(viewer: ServerUIViewer(userId: "u2", isAdmin: false))) == .no)
        #expect(admin.evaluate(Reader(viewer: nil)) == .unknown)
        #expect(admin.evaluate(Reader(viewer: ServerUIViewer(userId: "u2", isAdmin: nil))) == .unknown)
        let both = ServerUIPredicate.viewer(isAdmin: true, userIds: ["u9"])
        #expect(both.evaluate(Reader()) == .no)
        #expect(ServerUIPredicate.viewer(isAdmin: nil, userIds: ["u1", "u9"]).evaluate(Reader()) == .yes)
        let home = ServerUIPredicate.viewerPerson(values: ["home"])
        #expect(home.evaluate(Reader()) == .yes)
        #expect(home.evaluate(Reader(person: .value(.string("not_home")))) == .no)
        #expect(home.evaluate(Reader(person: .loading)) == .unknown)
        #expect(home.readsViewer && !on.readsViewer)
    }

    @Test func visibilityAppliesTheUnknownPolicy() {
        let unknown = Reader()
        let shown = Reader(values: ["fan": .string("on")])
        let hidden = Reader(values: ["fan": .string("off")])
        for policy in ServerUIVisibility.WhenUnknown.allCases {
            let rule = ServerUIVisibility(predicate: on, whenUnknown: policy)
            #expect(rule.isShown(shown, previous: false))
            #expect(!rule.isShown(hidden, previous: true))
        }
        let show = ServerUIVisibility(predicate: on, whenUnknown: .show)
        let hide = ServerUIVisibility(predicate: on, whenUnknown: .hide)
        let keep = ServerUIVisibility(predicate: on)
        #expect(show.isShown(unknown, previous: false) && !hide.isShown(unknown, previous: true))
        #expect(keep.isShown(unknown, previous: false) == false && keep.isShown(unknown, previous: true) && keep.isShown(unknown, previous: nil))
        #expect(keep.whenUnknown == .keep)
        #expect(ServerUISelection(on).isSelected(shown) && !ServerUISelection(on).isSelected(unknown))
    }
}

@Suite struct ServerUICallServiceResolutionTests {
    private func call(data: [String: ServerUIOperand] = [:], target: [String: ServerUIOperand] = [:],
                      confirmation: ServerUICompositionDocument.Confirmation = .policy, exempt: [String] = []) -> ServerUICallService {
        ServerUICallService(domain: "fan", service: "set_percentage", target: target, data: data, confirmation: confirmation, exemptUserIds: exempt)
    }

    @Test func resolvesTargetAndDataAtGestureTime() throws {
        let reader = Reader(values: ["fan": .string("fan.demo_bath_fan")], controlValue: .number(40))
        let resolved = try #require(call(data: ["percentage": .control, "note": .literal(.string("hi"))],
                                         target: ["entity_id": read("fan", as: .entityID),
                                                  "area_id": .list([.literal(.string("a")), .literal(.string("b"))])]).resolve(reader))
        #expect(resolved.domain == "fan" && resolved.service == "set_percentage")
        #expect(resolved.data == ["percentage": .number(40), "note": .string("hi"), "entity_id": .string("fan.demo_bath_fan"),
                                  "area_id": .array([.string("a"), .string("b")])])
    }

    @Test func anUnreadableOrNonIdentifierOperandSendsNothing() {
        let reader = Reader(controlValue: .number(40))
        #expect(call(data: ["x": read("ghost")]).resolve(reader) == nil)
        #expect(call(target: ["entity_id": read("ghost", as: .entityID)]).resolve(reader) == nil)
        #expect(call(target: ["entity_id": .literal(.number(3))]).resolve(reader) == nil)
        #expect(call(target: ["entity_id": .list([])]).resolve(reader) == nil)
        #expect(call(target: ["entity_id": .literal(.string(""))]).resolve(reader) == nil)
        #expect(call(data: ["x": .control]).resolve(Reader()) == nil)
    }

    @Test func confirmationHonoursPerUserExemptions() {
        let ask = ServerUICompositionDocument.Confirmation.additional(
            style: .alert, title: "Sure?", message: nil, confirmLabel: "Yes", cancelLabel: "Cancel", destructive: true)
        let plain = call()
        #expect(!plain.asksConfirmation(of: ServerUIViewer(userId: "u1"), in: Reader()))
        let guarded = call(confirmation: ask, exempt: ["owner"])
        #expect(guarded.asksConfirmation(of: ServerUIViewer(userId: "u1"), in: Reader()))
        #expect(guarded.asksConfirmation(of: nil, in: Reader()))
        #expect(!guarded.asksConfirmation(of: ServerUIViewer(userId: "owner"), in: Reader()))
    }

    @Test func listsEveryReadAndOptimisticSource() {
        let service = ServerUICallService(
            domain: "a", service: "b", target: ["entity_id": read("one", as: .entityID)], data: ["x": read("two")],
            optimistic: [.init(sourceId: "three", value: "on", revertAfterSeconds: 2, failsOnTimeout: false)])
        #expect(service.sourceIds == ["one", "two", "three"])
    }
}
