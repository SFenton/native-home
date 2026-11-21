import Foundation
import Testing
@testable import HassCore

// MARK: - The expression evaluation corpus

/// Runs the Studio's expression evaluation corpus (`ContractCorpus/evaluation`, copied byte for byte) through the app's evaluator.
///
/// Each file is a subject (an operand, a condition, a look, a badge, an action rule, ...), an environment and the exact answer. The
/// Studio runs the same files in `tests/expression-corpus.test.ts`; the app must give each answer byte for byte, so a published rule
/// means the same thing on both sides. The subjects are parsed with the app's own parser, which also proves it accepts the grammar.
@Suite(.timeLimit(.minutes(2)))
struct ServerUIExpressionCorpusTests {
    /// One evaluation file.
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let subject: [String: JSONValue]
        let env: [String: JSONValue]
        let expected: JSONValue
        var testDescription: String { name }
    }

    nonisolated static let directory = ServerUIContractCorpusTests.directory.appendingPathComponent("evaluation", isDirectory: true)

    nonisolated static let cases: [Case] = {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let file = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let subject)? = file["subject"], case .object(let env)? = file["env"],
                  let expected = file["expected"] else { return nil }
            return Case(name: String(name.dropLast(5)), subject: subject, env: env, expected: expected)
        }
    }()

    @Test func theCorpusIsWholeAndNamedByItsFiles() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".json") }
        #expect(Self.cases.count == names.count, "a file did not decode")
        #expect(Self.cases.count >= 284 + 35 + 133 + 80)
        let answers = Set(Self.cases.compactMap { $0.expected["tri"]?.string })
        #expect(answers == ["yes", "no", "unknown"])
        let statuses = Set(Self.cases.compactMap { $0.expected["status"]?.string })
        #expect(statuses == ["value", "loading", "unavailable"])
    }

    /// The evaluation cases the Studio wrote for ids the app has not ingested, as the file-name test that picks them and the id each waits for. A case
    /// stays out of the run until its id is in ``ServerUIIngestedCapabilities``; from then on it must give its recorded answer like any other.
    ///
    /// The dial control and the dial text place are subjects the app does not evaluate yet. The spoken badge adds a `spoken` answer.
    nonisolated static let pendingIds: [(capability: String, picks: @Sendable (String) -> Bool)] = [
        ("sh.dial-control@1", { $0.hasPrefix("dialctl-") }),
        ("sh.dial-text-place@1", { $0.hasPrefix("dial-text-place-") }),
        ("sh.fold-sides@1", { $0.hasPrefix("fold-sides-") }),
        ("sh.badge-spoken@1", { $0.hasPrefix("badge-spoken-") }),
    ]

    /// Cases where the app and the Studio disagree on behaviour the app already ships, by case name, with the app's CURRENT answer in the shape the case
    /// files record. They are not waiting for an id: `badge-cap-unavailable-hides` uses no `spoken` field. A rule with no source loading and nothing
    /// to read gives no value in the Studio (`resolveBadge`, `evaluator.ts`), and `loading` in `ServerUILooks.badge`, which keeps what the badge showed.
    /// `theKnownDisagreementsStillDisagreeAsRecorded` fails when either side moves, which is the cue to resolve the case and delete the entry.
    nonisolated static let knownDisagreements: [String: JSONValue] = [
        "badge-cap-unavailable-hides": .object(["status": .string("loading")]),
    ]

    @Test(arguments: knownDisagreements.keys.sorted())
    func theKnownDisagreementsStillDisagreeAsRecorded(_ name: String) throws {
        let item = try #require(Self.cases.first { $0.name == name }, "\(name) is not in the corpus")
        let answer = try Self.answer(item)
        #expect(Self.canonical(answer) == Self.canonical(Self.knownDisagreements[name] ?? .null), "\(name): the app's answer moved to \(Self.canonical(answer))")
        #expect(Self.canonical(answer) != Self.canonical(item.expected), "\(name): the app now gives the Studio's answer; remove the entry")
    }

    /// Whether the case waits for an id the app has not ingested.
    nonisolated static func isHeldBackUntilIngested(_ name: String) -> Bool {
        pendingIds.contains { !ServerUIIngestedCapabilities.all.contains($0.capability) && $0.picks(name) }
    }

    /// Every held-back id still picks cases, so a renamed family cannot leave the gate holding nothing.
    @Test func everyHeldBackIdPicksSomeCases() {
        for entry in Self.pendingIds { #expect(Self.cases.contains { entry.picks($0.name) }, "\(entry.capability) picks no case") }
    }

    @Test(arguments: cases.filter { !isHeldBackUntilIngested($0.name) && knownDisagreements[$0.name] == nil })
    func giveTheRecordedAnswerByteForByte(_ item: Case) throws {
        let answer = try Self.answer(item)
        #expect(Self.canonical(answer) == Self.canonical(item.expected), "\(item.name): got \(Self.canonical(answer))")
    }

    // MARK: Environment

    /// The environment a case names, as the reader the evaluator sees.
    struct Environment: ServerUIReading {
        var reads: [String: ServerUIReadResult] = [:]
        /// What `readRaw` gives per source id; a source not listed has no entity.
        var raw: [String: ServerUIReadResult] = [:]
        /// What `readChanged` gives per source id; a source not listed has no entity.
        var changed: [String: ServerUIReadResult] = [:]
        var viewer: ServerUIViewer?
        /// What `viewerPersonState` gives (the state of the viewer's `person.*` entity); a case that names none has none.
        var viewerPerson: ServerUIReadResult = .unavailable
        var clock: ServerUIClock?
        var item: JSONValue?
        var index: Int?
        var parameters: [String: JSONValue] = [:]
        var isFlow = false
        var locale: Locale?
        var undrawn: Set<String> = []

        func read(sourceId: String, path: [String]) -> ServerUIReadResult {
            reads[([sourceId] + path).joined(separator: "/")] ?? .unavailable
        }
        func readRaw(sourceId: String) -> ServerUIReadResult { raw[sourceId] ?? .unavailable }
        func readChanged(sourceId: String) -> ServerUIReadResult { changed[sourceId] ?? .unavailable }
        func viewerPersonState() -> ServerUIReadResult { viewerPerson }
        func parameter(_ name: String) -> JSONValue? { parameters[name] }
        func drawsSymbol(_ name: String) -> Bool { !undrawn.contains(name) }
    }

    static func environment(_ env: [String: JSONValue]) -> Environment {
        var result = Environment()
        func status(_ entry: JSONValue) -> ServerUIReadResult {
            switch entry["status"]?.string {
            case "value": .value(entry["value"] ?? .null)
            case "loading": .loading
            default: .unavailable
            }
        }
        if case .object(let reads)? = env["reads"] { for (key, entry) in reads { result.reads[key] = status(entry) } }
        if case .object(let raw)? = env["raw"] { for (key, entry) in raw { result.raw[key] = status(entry) } }
        if case .object(let changed)? = env["changed"] { for (key, entry) in changed { result.changed[key] = status(entry) } }
        if let person = env["viewerPerson"] { result.viewerPerson = status(person) }
        if case .object(let viewer)? = env["viewer"] {
            result.viewer = ServerUIViewer(userId: viewer["userId"]?.string, isAdmin: viewer["isAdmin"]?.bool,
                                           personEntityId: viewer["personEntityId"]?.string)
        }
        if case .object(let clock)? = env["clock"], let now = clock["now"]?.string, let offset = clock["utcOffsetMinutes"]?.number {
            result.clock = ServerUIClock(now: now, utcOffsetMinutes: Int(offset))
        }
        result.item = env["item"]
        result.index = env["index"]?.number.map { Int($0) }
        if case .object(let parameters)? = env["params"] { result.parameters = parameters }
        result.isFlow = env["flow"]?.bool == true
        result.locale = env["locale"]?.string.map(Locale.init(identifier:))
        if case .array(let names)? = env["undrawnSymbols"] { result.undrawn = Set(names.compactMap(\.string)) }
        return result
    }

    // MARK: Subjects

    private static func operand(_ json: JSONValue?) throws -> ServerUIOperand {
        var parser = ServerUIExpressionParser(allowControl: true, evaluationOnly: true)
        let value = parser.operand(json ?? .null, at: "")
        try #require(parser.issues.isEmpty, "operand issues: \(parser.issues)")
        return try #require(value)
    }

    private static func predicate(_ json: JSONValue?) throws -> ServerUIPredicate {
        var parser = ServerUIExpressionParser(evaluationOnly: true)
        let value = parser.predicate(json ?? .null, at: "")
        try #require(parser.issues.isEmpty, "predicate issues: \(parser.issues)")
        return try #require(value)
    }

    private static func conditional(_ json: JSONValue) throws -> ServerUIConditional<JSONValue> {
        let cases = try (json["cases"]?.array ?? []).map {
            ServerUIConditional<JSONValue>.Case(when: try predicate($0["when"]), then: $0["then"] ?? .null)
        }
        return ServerUIConditional(cases: cases, otherwise: json["otherwise"] ?? .null)
    }

    private static func result(_ result: ServerUIReadResult) -> JSONValue {
        switch result {
        case .value(let value): .object(["status": .string("value"), "value": value])
        case .loading: .object(["status": .string("loading")])
        case .unavailable: .object(["status": .string("unavailable")])
        }
    }

    private static func pick(_ pick: ServerUIRulePick) -> JSONValue {
        switch pick {
        case .matched(let index): .number(Double(index))
        case .otherwise: .string("otherwise")
        case .stalled: .string("stalled")
        }
    }

    /// The answer the app's evaluator gives for a case, in the shape the case file records.
    static func answer(_ item: Case) throws -> JSONValue {
        let env = environment(item.env)
        let subject = item.subject
        if let stack = subject["stack"] { return try ServerUIStackLayoutTests.answer(stack) }
        if let chart = subject["chart"] { return try ServerUIChartCorpusAnswers.chart(chart, reader: env) }
        if let gauge = subject["gauge"] { return ServerUIChartCorpusAnswers.gauge(gauge) }
        if let page = subject["foldsides"] { return foldSidesAnswer(page) }
        if let dial = subject["dial"] { return try ServerUIDialCorpusAnswers.dial(dial) }
        if let arc = subject["arc"] { return try ServerUIDialCorpusAnswers.arc(arc) }
        if let condition = subject["condition"] {
            return .object(["tri": .string(try predicate(condition).evaluate(env).rawText)])
        }
        if let value = subject["operand"] { return result(try operand(value).evaluate(env)) }
        if let slot = subject["fill"] {
            let role: ServerUIColorText.Role = subject["role"]?.string == "glyph" ? .glyph : .fill
            if slot["type"]?.string == "bound-color" {
                switch ServerUILooks.boundColor(try operand(slot["value"]), role: role, in: env) {
                case .loading: return .object(["status": .string("loading")])
                case .value(let rgb?):
                    return .object(["status": .string("value"), "look": .object([
                        "type": .string("solid-rgb"), "red": .number(Double(rgb.red)), "green": .number(Double(rgb.green)),
                        "blue": .number(Double(rgb.blue))])])
                case .value(nil): return .object(["status": .string("value"), "look": slot["fallback"] ?? .null])
                }
            }
            let look = slot["type"]?.string == "conditional" ? try conditional(slot).resolve(env) : slot
            return .object(["status": .string("value"), "look": look])
        }
        if let slot = subject["symbol"] {
            if slot["type"]?.string == "bound-symbol" {
                switch ServerUILooks.boundSymbol(try operand(slot["value"]), in: env) {
                case .loading: return .object(["status": .string("loading")])
                case .value(let name?):
                    guard case .object(var fallback)? = slot["fallback"] else { return .null }
                    fallback["name"] = .string(name)
                    return .object(["status": .string("value"), "look": .object(fallback)])
                case .value(nil): return .object(["status": .string("value"), "look": slot["fallback"] ?? .null])
                }
            }
            let look = slot["type"]?.string == "conditional" ? try conditional(slot).resolve(env) : slot
            return .object(["status": .string("value"), "look": look])
        }
        if let slot = subject["text"] {
            if slot["type"]?.string == "expr" {
                return result(ServerUILooks.text(try operand(slot["value"]), fallback: slot["fallback"]?.string, in: env))
            }
            guard case .object(var plain) = slot else { return .null }
            let fallback = plain.removeValue(forKey: "fallback")?.string
            let value = try operand(.object(plain))
            return result(ServerUILooks.text(value, fallback: slot["type"]?.string == "literal" ? nil : fallback, in: env))
        }
        if let slot = subject["badge"] {
            let value: ServerUIOperand? = slot["type"]?.string == "value" ? try operand(slot["value"]) : nil
            switch ServerUILooks.badge(value, in: env) {
            case .loading: return .object(["status": .string("loading")])
            case .value(let text): return .object(["status": .string("value"), "text": text.map(JSONValue.string) ?? .null])
            }
        }
        if let rule = subject["enabled"] {
            let policy = ServerUIEnabledUnknown(rawValue: rule["whenUnknown"]?.string ?? "") ?? .keep
            let enabled = ServerUIControlRules.isEnabled(try predicate(rule["condition"]), whenUnknown: policy,
                                                         previous: subject["previous"]?.bool, in: env)
            return .object(["enabled": .bool(enabled)])
        }
        if let look = subject["faces"] {
            func optional(_ key: String) throws -> ServerUIPredicate? { try look[key].map(predicate) }
            let faces = ServerUIControlRules.tileFaces(active: try optional("activeWhen"), filled: try optional("filledWhen"),
                                                       error: try optional("errorWhen"), in: env)
            func flag(_ value: Bool?) -> JSONValue { value.map(JSONValue.bool) ?? .null }
            return .object(["faces": .object(["active": flag(faces.active), "filled": flag(faces.filled), "error": flag(faces.error)])])
        }
        if let rule = subject["action"] {
            guard rule["type"]?.string == "conditional" else { return .object(["pick": .string("plain"), "runs": rule["type"] ?? .null]) }
            let conditional = try conditional(rule)
            let picked = conditional.pick(env)
            let chosen: JSONValue? = switch picked {
            case .stalled: nil
            case .otherwise: conditional.otherwise
            case .matched(let index): conditional.cases[index].then
            }
            let runs = chosen?["type"]?.string == "none" ? nil : chosen?["type"]
            return .object(["pick": pick(picked), "runs": runs ?? .string("none")])
        }
        if let tone = subject["tone"] {
            if case .string = tone { return .object(["tone": tone]) }
            return .object(["tone": try conditional(tone).resolve(env)])
        }
        if let progress = subject["progress"] {
            let fill = ServerUILooks.progress(try operand(progress), in: env)
            return .object(["progress": fill.map(JSONValue.number) ?? .null])
        }
        if let rule = subject["tab"] {
            let tabs = try (rule["tabs"]?.array ?? []).map { tab -> ServerUIControlRules.Tab in
                let visibility = try tab["visibleWhen"].map {
                    ServerUIVisibility(predicate: try predicate($0),
                                       whenUnknown: ServerUIVisibility.WhenUnknown(rawValue: tab["whenUnknown"]?.string ?? "") ?? .keep)
                }
                return .init(id: tab["id"]?.string ?? "", visibility: visibility)
            }
            let shown = ServerUIControlRules.tabOnShow(tabs, requested: rule["requested"]?.string, fallback: rule["fallback"]?.string, in: env)
            return .object(["tab": shown.map(JSONValue.string) ?? .null])
        }
        if let rule = subject["asks"] {
            let when = try rule["when"].map(predicate)
            return .object(["asks": .bool(ServerUIControlRules.asksFirst(when, in: env))])
        }
        throw CorpusError.unknownSubject(item.name)
    }

    /// The `foldsides` subject (`sh.fold-sides@1`): a page's top-level components, and for each one that holds a slot its side and its width.
    static func foldSidesAnswer(_ page: JSONValue) -> JSONValue {
        let items = page["items"]?.array ?? []
        let inputs = items.map { item -> ServerUIFoldSides.Input in
            let type = item["bodyType"]?.string ?? item["type"]?.string ?? ""
            let kind: ServerUIFoldSides.Kind = switch type {
            case "status-rail": .strip
            case "notification-permission-banner": .staticallyHidden
            case "pinned-actions": .pinned
            default: .section
            }
            return .init(kind: kind, said: item["foldSide"]?.string.flatMap(ServerUIFoldSide.init(rawValue:)))
        }
        guard ServerUIFoldSides.usesFoldSides(switchedOn: page["foldSides"]?.string == "auto", items: inputs) else {
            return .object(["foldsides": .object(["active": .bool(false), "sides": .array([])])])
        }
        let geometry = page["geometry"]
        let inset = page["inset"]?.number ?? 0
        let sides = zip(items, ServerUIFoldSides.resolve(inputs)).compactMap { item, side -> JSONValue? in
            guard let side else { return nil }
            var entry: [String: JSONValue] = ["id": item["id"] ?? .null, "side": .string(side.rawValue)]
            if let geometry, let leading = geometry["leading"]?.number, let band = geometry["band"]?.number, let trailing = geometry["trailing"]?.number {
                let width = ServerUIFoldSides.width(of: side, leading: leading, band: band, trailing: trailing, inset: inset)
                entry["width"] = .number((width * 10).rounded() / 10)
            }
            return .object(entry)
        }
        return .object(["foldsides": .object(["active": .bool(true), "sides": .array(sides)])])
    }

    enum CorpusError: Error { case unknownSubject(String) }

    /// Sorted-key JSON, so two answers are compared as bytes.
    static func canonical(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? ""
    }
}

private extension ServerUITri {
    var rawText: String {
        switch self {
        case .yes: "yes"
        case .no: "no"
        case .unknown: "unknown"
        }
    }
}
