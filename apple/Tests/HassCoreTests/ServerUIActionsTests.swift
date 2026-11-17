import Foundation
import Testing
@testable import HassCore

// MARK: - Generic actions, bound controls and rules: grammar

/// The closed operand and predicate grammar, `call-service`, `bound-control` and `visibleWhen`/`selectedWhen`
/// (`.agents/patterns` records follow in the docs lane). Must-reject cases name the pointer the Studio's corpus will share.
@Suite struct ServerUIActionsGrammarTests {
    private typealias P = ServerUICompositionPublication
    private typealias E = ServerUICompositionError
    private typealias D = ServerUICompositionDocument

    static let fanSource = """
    {"id":"guest-fan","kind":"ha-entity","entityId":{"type":"literal","value":"fan.demo_bath_fan"}}
    """
    static let tempSource = """
    {"id":"temp","kind":"ha-entity","entityId":{"type":"literal","value":"sensor.demo_bath_temperature"}}
    """

    /// The shared fixture with `components` as the third page's body, two extra `ha-entity` sources and `extra` capabilities.
    private func publication(_ components: String, extra: [String], localState: String? = nil,
                             tweak: (inout [String: JSONValue]) -> Void = { _ in }) throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        guard case .object(var root) = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)),
              case .object(var document)? = root["document"], case .array(var pages)? = document["pages"],
              case .object(var page) = pages[2], case .array(var sources)? = document["dataSources"] else { throw E(.invalidValue, "") }
        let decoder = JSONDecoder()
        page["components"] = try decoder.decode(JSONValue.self, from: Data(components.utf8))
        pages[2] = .object(page)
        for source in [Self.fanSource, Self.tempSource] { sources.append(try decoder.decode(JSONValue.self, from: Data(source.utf8))) }
        document["pages"] = .array(pages)
        document["dataSources"] = .array(sources)
        if let localState { document["localState"] = try decoder.decode(JSONValue.self, from: Data(localState.utf8)) }
        root["document"] = .object(document)
        root["capabilities"] = .array((P.firstSliceCapabilities + extra).sorted().map(JSONValue.string))
        tweak(&root)
        return .object(root)
    }

    private func decode(_ value: JSONValue) throws -> P { try P.decode(JSONEncoder().encode(value)) }

    private func accept(_ components: String, extra: [String], localState: String? = nil) throws -> D.Page {
        try #require(decode(publication(components, extra: extra, localState: localState)).document.pages.last)
    }

    private func reject(_ components: String, extra: [String], _ code: E.Code, _ pointer: String,
                        localState: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let value = try publication(components, extra: extra, localState: localState)
        #expect(throws: E(code, pointer), sourceLocation: sourceLocation) { try decode(value) }
    }

    // MARK: Builders

    private static func button(_ action: String, id: String = "go") -> String {
        """
        {"id":"\(id)","title":"Go","type":"primary-button","layout":{"span":1},"props":{},"action":\(action)}
        """
    }
    private static let simpleCall = """
    {"type":"call-service","domain":"fan","service":"turn_on","target":{"entity_id":{"type":"literal","value":"fan.demo_bath_fan"}}}
    """
    private static let callCapabilities = ["sh.primary-button@1", "sh.call-service@1", "sh.operands@1"]

    // MARK: call-service

    @Test func acceptsAnyDomainAndServiceWithTargetDataOptimisticAndConfirmation() throws {
        let call = """
        {"type":"call-service","domain":"climate","service":"set_temperature",
         "target":{"entity_id":{"type":"read","from":{"type":"source","sourceId":"guest-fan","path":["state"]},"as":"entity-id","missing":"unavailable"},
                   "area_id":{"type":"list","items":[{"type":"literal","value":"demo_area"}]}},
         "data":{"type":"object","fields":{"temperature":{"type":"math","op":"clamp","args":[{"type":"control"},{"type":"literal","value":60},{"type":"literal","value":80}]},
                                           "label":{"type":"format","pattern":"{n} degrees","args":{"n":{"type":"literal","value":70}}}}},
         "optimistic":[{"sourceId":"guest-fan","value":"on","revertAfterSeconds":2,"failsOnTimeout":false}],
         "confirmation":{"type":"additional","style":"alert","title":"Set it?","message":"Warms the room.","confirmLabel":"Set","cancelLabel":"Cancel","destructive":false,"exemptUserIds":["u1"]},
         "feedback":"policy"}
        """
        // `control` is only meaningful on a control's own call, so this one goes on a bound stepper.
        let stepper = """
        {"id":"temp-step","title":"Temperature","type":"bound-control","layout":{"span":1},
         "props":{"kind":"stepper","value":{"type":"read","from":{"type":"source","sourceId":"temp","path":["state"]},"as":"number","missing":"unavailable"},
                  "range":{"min":60,"max":80,"step":1},"unavailableText":"No reading"},
         "action":\(call)}
        """
        let page = try accept("[\(stepper)]", extra: ["sh.bound-control@1", "sh.call-service@1", "sh.operands@1"])
        guard case .boundControl(let control) = try #require(page.surface.components.first),
              let action = control.action else { Issue.record("not a bound control"); return }
        #expect(action.domain == "climate" && action.service == "set_temperature")
        #expect(Set(action.target.keys) == ["entity_id", "area_id"])
        #expect(Set(action.data.keys) == ["temperature", "label"])
        #expect(action.optimistic == [.init(sourceId: "guest-fan", value: "on", revertAfterSeconds: 2, failsOnTimeout: false)])
        #expect(action.exemptUserIds == ["u1"])
        #expect(action.sourceIds == ["guest-fan"])
        #expect(control.sourceIds == ["temp"])
    }

    @Test func aButtonCarriesAnyServiceAndRequiresExactlyTheCapabilitiesItUses() throws {
        let page = try accept("[\(Self.button(Self.simpleCall))]", extra: Self.callCapabilities)
        guard case .button(let button) = try #require(page.surface.components.first),
              case .callService(let call) = button.action else { Issue.record("not a call"); return }
        #expect(call.domain == "fan" && call.service == "turn_on")
        let value = try publication("[\(Self.button(Self.simpleCall))]", extra: ["sh.primary-button@1", "sh.operands@1"])
        #expect(throws: E(.capabilityManifestMismatch, "/capabilities")) { try decode(value) }
        let extra = try publication("[\(Self.button(Self.simpleCall))]", extra: Self.callCapabilities + ["sh.visible-when@1"])
        #expect(throws: E(.capabilityManifestMismatch, "/capabilities")) { try decode(extra) }
    }

    @Test func rejectsMalformedServiceCalls() throws {
        func call(_ edit: (String) -> String) -> String { Self.button(edit(Self.simpleCall)) }
        let c = Self.callCapabilities
        let base = "/document/pages/2/components/0/action"
        try reject("[\(call { $0.replacingOccurrences(of: "\"fan\"", with: "\"Fan\"") })]", extra: c, .invalidValue, base + "/domain")
        try reject("[\(call { $0.replacingOccurrences(of: "turn_on", with: "turn on") })]", extra: c, .invalidValue, base + "/service")
        try reject("[\(call { $0.replacingOccurrences(of: "\"entity_id\"", with: "\"entityid\"") })]", extra: c,
                   .unknownField, base + "/target/entityid")
        try reject("[\(call { $0.replacingOccurrences(of: "{\"type\":\"literal\",\"value\":\"fan.demo_bath_fan\"}", with: "{\"type\":\"literal\",\"value\":3}") })]",
                   extra: c, .invalidValue, base + "/target/entity_id/value")
        try reject("[\(call { $0.replacingOccurrences(of: "\"service\":\"turn_on\"", with: "\"service\":{\"type\":\"literal\",\"value\":\"x\"}") })]",
                   extra: c, .invalidValue, base + "/service")
        try reject("[\(call { $0.replacingOccurrences(of: "}}}", with: "}},\"extra\":1}") })]", extra: c, .unknownField, base + "/extra")
        try reject("[\(call { $0.replacingOccurrences(of: "}}}", with: "}},\"data\":{\"type\":\"object\",\"fields\":{\"entity_id\":{\"type\":\"literal\",\"value\":\"x\"}}}}") })]",
                   extra: c, .invalidCombination, base + "/target/entity_id")
        try reject("[\(call { $0.replacingOccurrences(of: "}}}", with: "}},\"optimistic\":[{\"sourceId\":\"nope\",\"value\":\"on\",\"revertAfterSeconds\":2,\"failsOnTimeout\":false}]}") })]",
                   extra: c, .invalidReference, base + "/optimistic/0/sourceId")
        try reject("[\(call { $0.replacingOccurrences(of: "}}}", with: "}},\"optimistic\":[{\"sourceId\":\"source-power\",\"value\":\"on\",\"revertAfterSeconds\":2,\"failsOnTimeout\":false}]}") })]",
                   extra: c, .bindingType, base + "/optimistic/0/sourceId")
        try reject("[\(call { $0.replacingOccurrences(of: "}}}", with: "}},\"data\":{\"type\":\"literal\",\"value\":{}}}") })]",
                   extra: c, .invalidValue, base + "/data")
        // A control value exists only on a control's own call.
        try reject("[\(call { $0.replacingOccurrences(of: "\"fan.demo_bath_fan\"}", with: "\"x\"}").replacingOccurrences(of: "}}}", with: "}},\"data\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"control\"}}}}") })]",
                   extra: c, .invalidCombination, base + "/data/fields/v")
    }

    @Test func rejectsReadsThatDoNotResolveToAnHAEntitySource() throws {
        func data(_ operand: String) -> String {
            Self.button("""
            {"type":"call-service","domain":"light","service":"turn_on","data":{"type":"object","fields":{"x":\(operand)}}}
            """)
        }
        func read(_ source: String, _ path: String, as kind: String = "string") -> String {
            "{\"type\":\"read\",\"from\":{\"type\":\"source\",\"sourceId\":\"\(source)\",\"path\":\(path)},\"as\":\"\(kind)\",\"missing\":\"unavailable\"}"
        }
        let c = Self.callCapabilities
        let at = "/document/pages/2/components/0/action/data/fields/x"
        try reject("[\(data(read("ghost", "[\"state\"]")))]", extra: c, .invalidReference, at + "/from/sourceId")
        _ = try accept("[\(data(read("source-power", "[\"isOn\"]", as: "boolean")))]", extra: c)
        try reject("[\(data(read("guest-fan", "[\"brightness\"]")))]", extra: c, .invalidReference, at + "/from/path")
        try reject("[\(data(read("guest-fan", "[\"__proto__\"]")))]", extra: c, .invalidReference, at + "/from/path/0")
        try reject("[\(data(read("guest-fan", "[\"state\"]", as: "boolean")))]", extra: c, .bindingType, at + "/as")
        _ = try accept("[\(data(read("guest-fan", "[\"attributes\",\"percentage\"]", as: "number")))]", extra: c)
    }

    @Test func boundsExpressionDepthSizeAndText() throws {
        var deep = "{\"type\":\"literal\",\"value\":1}"
        for _ in 0..<8 { deep = "{\"type\":\"math\",\"op\":\"add\",\"args\":[\(deep),{\"type\":\"literal\",\"value\":1}]}" }
        func call(_ operand: String) -> String {
            Self.button("{\"type\":\"call-service\",\"domain\":\"x\",\"service\":\"y\",\"data\":{\"type\":\"object\",\"fields\":{\"v\":\(operand)}}}")
        }
        // Depth 9 (the object itself is level 1, so eight nested adds reach level 10).
        let at = "/document/pages/2/components/0/action/data/fields/v"
        let rejected = try publication("[\(call(deep))]", extra: Self.callCapabilities)
        let error = try #require(throws: E.self) { try decode(rejected) }
        #expect(error.code == .limitExceeded && error.pointer.hasPrefix(at + "/args/0"))
        var shallow = "{\"type\":\"literal\",\"value\":1}"
        for _ in 0..<6 { shallow = "{\"type\":\"math\",\"op\":\"add\",\"args\":[\(shallow),{\"type\":\"literal\",\"value\":1}]}" }
        _ = try accept("[\(call(shallow))]", extra: Self.callCapabilities)
        let wide = "{\"type\":\"list\",\"items\":[\((0..<65).map { _ in "{\"type\":\"literal\",\"value\":1}" }.joined(separator: ","))]}"
        try reject("[\(call(wide))]", extra: Self.callCapabilities, .limitExceeded, at + "/items")
        let long = String(repeating: "x", count: 2_001)
        try reject("[\(call("{\"type\":\"literal\",\"value\":\"\(long)\"}"))]", extra: Self.callCapabilities, .limitExceeded, at + "/value")
    }

    @Test func checksOperandShapesAndArities() throws {
        func call(_ operand: String) -> String {
            Self.button("{\"type\":\"call-service\",\"domain\":\"x\",\"service\":\"y\",\"data\":{\"type\":\"object\",\"fields\":{\"v\":\(operand)}}}")
        }
        let c = Self.callCapabilities
        let at = "/document/pages/2/components/0/action/data/fields/v"
        try reject("[\(call("{\"type\":\"math\",\"op\":\"divide\",\"args\":[{\"type\":\"literal\",\"value\":1}]}"))]", extra: c, .invalidCombination, at + "/args")
        try reject("[\(call("{\"type\":\"math\",\"op\":\"pow\",\"args\":[]}"))]", extra: c, .unknownVariant, at + "/op")
        try reject("[\(call("{\"type\":\"format\",\"pattern\":\"{a} {b}\",\"args\":{\"a\":{\"type\":\"literal\",\"value\":1}}}"))]", extra: c, .invalidReference, at + "/pattern")
        try reject("[\(call("{\"type\":\"format\",\"pattern\":\"{a\",\"args\":{\"a\":{\"type\":\"literal\",\"value\":1}}}"))]", extra: c, .invalidValue, at + "/pattern")
        try reject("[\(call("{\"type\":\"map\",\"of\":{\"type\":\"literal\",\"value\":1},\"cases\":[],\"otherwise\":{\"type\":\"literal\",\"value\":1}}"))]", extra: c, .limitExceeded, at + "/cases")
        try reject("[\(call("{\"type\":\"template\",\"value\":\"{{ states('x') }}\"}"))]", extra: c, .unknownVariant, at + "/type")
        try reject("[\(call("{\"type\":\"viewer\",\"field\":\"token\"}"))]", extra: c, .unknownVariant, at + "/field")
        try reject("[\(call("{\"type\":\"literal\",\"value\":null}"))]", extra: c, .invalidValue, at + "/value")
        _ = try accept("[\(call("{\"type\":\"map\",\"of\":{\"type\":\"viewer\",\"field\":\"isAdmin\"},\"cases\":[{\"equals\":true,\"then\":{\"type\":\"literal\",\"value\":\"a\"}}],\"otherwise\":{\"type\":\"literal\",\"value\":\"b\"}}"))]", extra: c)
    }

    // MARK: visibleWhen and selectedWhen

    private static let isOn = """
    {"type":"state","sourceId":"guest-fan","path":["state"],"in":["on"]}
    """

    @Test func visibleWhenIsPerNodeWithAnUnknownPolicyAndItsOwnCapability() throws {
        let node = """
        {"id":"timer","title":"Timer","type":"text","layout":{"span":1},
         "visibleWhen":{"type":"all","of":[\(Self.isOn),{"type":"viewer","isAdmin":true},{"type":"not","of":{"type":"viewer-person","in":["away"]}},
                                            {"type":"numeric","sourceId":"temp","path":["state"],"above":{"type":"literal","value":70}}]},
         "whenUnknown":"hide",
         "props":{"value":{"type":"literal","value":"Timer"},"style":"body","unavailableText":"None"}}
        """
        let page = try accept("[\(node)]", extra: ["sh.visible-when@1", "sh.operands@1"])
        let visibility = try #require(page.surface.components.first?.node.visibleWhen)
        #expect(visibility.whenUnknown == .hide)
        #expect(visibility.predicate.sourceIds == ["guest-fan", "temp"])
        #expect(visibility.predicate.readsViewer)
        let plain = node.replacingOccurrences(of: "\"whenUnknown\":\"hide\",", with: "")
        let defaulted = try accept("[\(plain)]", extra: ["sh.visible-when@1", "sh.operands@1"])
        #expect(defaulted.surface.components.first?.node.visibleWhen?.whenUnknown == .keep)
        let at = "/document/pages/2/components/0"
        try reject("[\(node.replacingOccurrences(of: "\"visibleWhen\"", with: "\"visibleWhenX\""))]", extra: ["sh.visible-when@1"], .unknownField, at + "/visibleWhenX")
        try reject("[{\"id\":\"t\",\"title\":\"T\",\"type\":\"text\",\"layout\":{\"span\":1},\"whenUnknown\":\"show\",\"props\":{\"value\":{\"type\":\"literal\",\"value\":\"T\"},\"style\":\"body\",\"unavailableText\":\"None\"}}]",
                   extra: [], .invalidCombination, at + "/whenUnknown")
    }

    @Test func rejectsBadPredicates() throws {
        func node(_ predicate: String) -> String {
            """
            [{"id":"t","title":"T","type":"text","layout":{"span":1},"visibleWhen":\(predicate),
              "props":{"value":{"type":"literal","value":"T"},"style":"body","unavailableText":"None"}}]
            """
        }
        let c = ["sh.visible-when@1", "sh.operands@1"]
        let at = "/document/pages/2/components/0/visibleWhen"
        try reject(node("{\"type\":\"state\",\"sourceId\":\"nope\",\"path\":[\"state\"],\"in\":[\"on\"]}"), extra: c, .invalidReference, at + "/sourceId")
        try reject(node("{\"type\":\"state\",\"sourceId\":\"source-power\",\"path\":[\"state\"],\"in\":[\"on\"]}"), extra: c, .invalidReference, at + "/path")
        try reject(node("{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"state\"],\"in\":[]}"), extra: c, .limitExceeded, at + "/in")
        try reject(node("{\"type\":\"numeric\",\"sourceId\":\"temp\",\"path\":[\"state\"]}"), extra: c, .invalidCombination, at)
        try reject(node("{\"type\":\"viewer\"}"), extra: c, .invalidCombination, at)
        try reject(node("{\"type\":\"all\",\"of\":[]}"), extra: c, .limitExceeded, at + "/of")
        try reject(node("{\"type\":\"time\",\"after\":\"22:00\"}"), extra: c, .unknownVariant, at + "/type")
        try reject(node("{\"type\":\"numeric\",\"sourceId\":\"temp\",\"path\":[\"state\"],\"above\":{\"type\":\"control\"}}"),
                   extra: c, .invalidCombination, at + "/above")
        var nested = isOnJSON
        for _ in 0..<8 { nested = "{\"type\":\"not\",\"of\":\(nested)}" }
        let error = try #require(throws: E.self) { try decode(publication(node(nested), extra: c)) }
        #expect(error.code == .limitExceeded)
    }
    private var isOnJSON: String { Self.isOn }

    @Test func tabsAndLocalTabsCarryRules() throws {
        let localState = """
        [{"id":"panel","type":"choice","initial":"a","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}]
        """
        let tabs = """
        {"id":"tabs","title":"Tabs","type":"local-tabs","layout":{"span":1},
         "props":{"stateId":"panel","transition":"canonical-swap@1","scopeProviderId":null,"automatic":[{"tabId":"b","selectedWhen":\(Self.isOn)}]},
         "tabs":[{"id":"a","label":"A","children":[]},{"id":"b","label":"B","children":[]}]}
        """.replacingOccurrences(of: "\"scopeProviderId\":null,", with: "")
        let page = try accept("[\(tabs)]", extra: ["sh.local-tabs@1", "sh.local-state@1", "sh.selected-when@1"], localState: localState)
        guard case .localTabs(let value) = try #require(page.surface.components.first) else { Issue.record("not tabs"); return }
        #expect(value.automatic.map(\.tabId) == ["b"])
        try reject("[\(tabs.replacingOccurrences(of: "\"tabId\":\"b\"", with: "\"tabId\":\"zzz\""))]",
                   extra: ["sh.local-tabs@1", "sh.local-state@1", "sh.selected-when@1"], .invalidReference,
                   "/document/pages/2/components/0/props/automatic/0/tabId", localState: localState)
    }

    @Test func navigationTabsCanBeHiddenByARule() throws {
        let value = try publication("[]", extra: ["sh.visible-when@1"]) { root in
            guard case .object(var document)? = root["document"], case .object(var navigation)? = document["navigation"],
                  case .array(var tabs)? = navigation["tabs"], case .object(var tab) = tabs[1] else { return }
            tab["visibleWhen"] = .object(["type": .string("viewer"), "isAdmin": .bool(true)])
            tabs[1] = .object(tab)
            navigation["tabs"] = .array(tabs)
            document["navigation"] = .object(navigation)
            root["document"] = .object(document)
        }
        let plan = try decode(value)
        #expect(plan.document.navigation.tabs[1].visibleWhen?.predicate == .viewer(isAdmin: true, userIds: nil))
        #expect(plan.document.navigation.tabs[0].visibleWhen == nil)
    }

    // MARK: bound-control

    private static func control(_ props: String, _ extra: String = "", id: String = "c") -> String {
        "{\"id\":\"\(id)\",\"title\":\"Fan\",\"type\":\"bound-control\",\"layout\":{\"span\":1},\"props\":\(props)\(extra)}"
    }
    private static func call(_ service: String) -> String {
        "{\"type\":\"call-service\",\"domain\":\"fan\",\"service\":\"\(service)\",\"target\":{\"entity_id\":{\"type\":\"literal\",\"value\":\"fan.demo_bath_fan\"}}}"
    }
    private static let boundCapabilities = ["sh.bound-control@1", "sh.call-service@1", "sh.operands@1"]

    @Test func compilesEveryKindOfBoundControl() throws {
        let toggle = Self.control("{\"kind\":\"toggle\",\"surface\":\"tile\",\"isOn\":\(Self.isOn),\"unavailableText\":\"Unavailable\"}",
                                  ",\"icon\":{\"type\":\"sf-symbol\",\"name\":\"fan\",\"rendering\":\"canonical\",\"unavailable\":\"reject\"},\"onAction\":\(Self.call("turn_on")),\"offAction\":\(Self.call("turn_off"))",
                                  id: "t")
        let slider = Self.control("{\"kind\":\"slider\",\"value\":{\"type\":\"read\",\"from\":{\"type\":\"source\",\"sourceId\":\"guest-fan\",\"path\":[\"attributes\",\"percentage\"]},\"as\":\"number\",\"missing\":\"unavailable\"},\"unavailableText\":\"Unavailable\"}",
                                  ",\"action\":{\"type\":\"call-service\",\"domain\":\"fan\",\"service\":\"set_percentage\",\"target\":{\"entity_id\":{\"type\":\"literal\",\"value\":\"fan.demo_bath_fan\"}},\"data\":{\"type\":\"object\",\"fields\":{\"percentage\":{\"type\":\"control\"}}}}",
                                  id: "s")
        let choice = Self.control("{\"kind\":\"choice\",\"options\":[{\"id\":\"low\",\"label\":\"Low\",\"selectedWhen\":{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"attributes\",\"preset\"],\"in\":[\"low\"]},\"action\":\(Self.call("low"))},{\"id\":\"high\",\"label\":\"High\",\"selectedWhen\":{\"type\":\"state\",\"sourceId\":\"guest-fan\",\"path\":[\"attributes\",\"preset\"],\"in\":[\"high\"]},\"action\":\(Self.call("high"))}],\"unavailableText\":\"Unavailable\"}",
                                  id: "ch")
        let button = Self.control("{\"kind\":\"button\",\"unavailableText\":\"Unavailable\"}", ",\"action\":\(Self.call("toggle"))", id: "b")
        let page = try accept("[\(toggle),\(slider),\(choice),\(button)]", extra: Self.boundCapabilities + ["sh.selected-when@1"])
        let controls: [D.BoundControl] = page.surface.components.compactMap { if case .boundControl(let value) = $0 { value } else { nil } }
        #expect(controls.map(\.kind) == [.toggle, .slider, .choice, .button])
        #expect(controls[0].surface == .tile && controls[0].actions.count == 2 && controls[0].icon?.name == "fan")
        #expect(controls[1].range == nil && controls[1].valueFormat == nil && controls[1].action != nil)
        #expect(controls[2].options.map(\.id) == ["low", "high"] && controls[2].sourceIds == ["guest-fan"])
        #expect(controls[3].actions.count == 1)
    }

    @Test func rejectsBoundControlsThatDoNotFitTheirKind() throws {
        let c = Self.boundCapabilities + ["sh.selected-when@1"]
        let at = "/document/pages/2/components/0"
        let props = "{\"kind\":\"toggle\",\"isOn\":\(Self.isOn),\"unavailableText\":\"Unavailable\"}"
        try reject("[\(Self.control(props, ",\"onAction\":\(Self.call("turn_on"))"))]", extra: c, .missingRequired, at + "/offAction")
        try reject("[\(Self.control(props, ",\"onAction\":\(Self.call("turn_on")),\"offAction\":\(Self.call("turn_off")),\"action\":\(Self.call("x"))"))]",
                   extra: c, .invalidCombination, at + "/action")
        try reject("[\(Self.control("{\"kind\":\"toggle\",\"unavailableText\":\"Unavailable\"}", ",\"onAction\":\(Self.call("a")),\"offAction\":\(Self.call("b"))"))]",
                   extra: c, .missingRequired, at + "/props/isOn")
        try reject("[\(Self.control("{\"kind\":\"button\",\"surface\":\"tile\",\"unavailableText\":\"U\"}", ",\"action\":\(Self.call("x"))"))]",
                   extra: c, .invalidCombination, at + "/props/surface")
        try reject("[\(Self.control("{\"kind\":\"stepper\",\"value\":{\"type\":\"literal\",\"value\":1},\"range\":{\"min\":0,\"max\":10,\"step\":3},\"unavailableText\":\"U\"}", ",\"action\":\(Self.call("x"))"))]",
                   extra: c, .invalidValue, at + "/props/range")
        try reject("[\(Self.control("{\"kind\":\"stepper\",\"value\":{\"type\":\"literal\",\"value\":1},\"range\":{\"min\":0,\"max\":10,\"step\":1},\"format\":\"no hole\",\"unavailableText\":\"U\"}", ",\"action\":\(Self.call("x"))"))]",
                   extra: c, .invalidValue, at + "/props/format")
        try reject("[\(Self.control("{\"kind\":\"button\",\"unavailableText\":\"U\"}", ",\"action\":{\"type\":\"call-service\",\"domain\":\"a\",\"service\":\"b\",\"data\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"control\"}}}}"))]",
                   extra: c, .invalidCombination, at + "/action/data/fields/v")
    }

    // MARK: Containers that lay children out themselves

    private static let hiddenText = """
    {"id":"t","title":"T","type":"text","layout":{"span":1},"visibleWhen":{"type":"viewer","isAdmin":true},
     "props":{"value":{"type":"literal","value":"T"},"style":"body","unavailableText":"None"}}
    """

    private static func section(style: String, _ children: String) -> String {
        """
        [{"id":"s","title":"S","type":"section","layout":{"span":1},"props":{"header":"S","footer":"","style":"\(style)","density":"thin","hasGlyphs":false,"spacing":{"type":"token","name":"m"}},
          "children":[\(children)]}]
        """
    }

    @Test func aRuleHidesAChildInPlaceOnlyWhereTheContainerCanLetItGo() throws {
        let c = ["sh.section@1", "sh.visible-when@1"]
        let page = try accept(Self.section(style: "plain", Self.hiddenText), extra: c)
        #expect(page.surface.components.first?.childComponents.first?.node.visibleWhen != nil)
        let ruled = Self.control("{\"kind\":\"toggle\",\"isOn\":\(Self.isOn),\"unavailableText\":\"Unavailable\"}",
                                 ",\"visibleWhen\":{\"type\":\"viewer\",\"isAdmin\":true},\"onAction\":\(Self.call("turn_on")),\"offAction\":\(Self.call("turn_off"))", id: "r")
        try reject(Self.section(style: "module-list", ruled), extra: c + Self.boundCapabilities, .invalidCombination,
                   "/document/pages/2/components/0/children/0/visibleWhen")
        let grid = """
        [{"id":"g","title":"G","type":"tile-grid","layout":{"span":1},"props":{"minimum":"tile@1","maxColumns":2,"spacing":{"type":"token","name":"m"},"equalRowHeights":false,"shortRow":"share","fold":"page"},
          "children":[\(Self.hiddenText)]}]
        """
        _ = try accept(grid, extra: ["sh.visible-when@1"])
    }

    @Test func aBoundToggleRowFitsAModuleListButAButtonDoesNot() throws {
        let toggle = Self.control("{\"kind\":\"toggle\",\"isOn\":\(Self.isOn),\"unavailableText\":\"Unavailable\"}",
                                  ",\"onAction\":\(Self.call("turn_on")),\"offAction\":\(Self.call("turn_off"))", id: "t")
        let button = Self.control("{\"kind\":\"button\",\"unavailableText\":\"U\"}", ",\"action\":\(Self.call("x"))", id: "b")
        let c = Self.boundCapabilities + ["sh.section@1"]
        _ = try accept(Self.section(style: "module-list", toggle), extra: c)
        try reject(Self.section(style: "module-list", button), extra: c, .invalidCombination,
                   "/document/pages/2/components/0/children/0/type")
    }
}
