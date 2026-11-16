import Foundation

// MARK: - Authored state styles (`sh.state-style@1`)

/// The capability name the Studio and the app negotiate state styles under.
public let serverUIStateStyleCapability = "sh.state-style@1"

/// A document's style library: the saved styles a `state-tile` applies by id, decoded into the L7a ``StateStyle`` values.
///
/// The wire shape is `{ "type": "state-styles@1", "styles": [{ id, name, base?, domain, actionId?, togglesDisc?, drawsErrorDisc?,
/// rules, fallback, request? }] }`; a rule is `{ states, class, active, icon?, text?, indicator?, colour?, action? }` and the
/// fallback is a rule that names no state (`docs/native-composition.md`, State styles in the Studio repository). The decoder only
/// reads what the shape check has already approved; a gap at run time degrades the tile and never rejects the layout.
public struct ServerUIStateStyleLibrary: Equatable, Sendable {
    /// A saved style and the built-in style it was made from.
    public struct Entry: Equatable, Sendable {
        /// The style the tile resolves through.
        public let style: StateStyle
        /// The built-in style id it duplicates, or nil for a style made from nothing.
        public let base: String?
    }

    /// The saved styles, in document order.
    public let entries: [Entry]

    /// An empty library: built-in styles only.
    public static let empty = ServerUIStateStyleLibrary(entries: [])

    init(entries: [Entry]) { self.entries = entries }

    /// Whether any style carries a per-state fill or hidden words, which need `sh.state-style-fills@1`.
    public var usesFills: Bool {
        entries.contains { $0.style.hiddenWords != nil || $0.style.rules.contains { $0.fill != nil } }
    }

    /// The saved style with `id`.
    public func style(id: String) -> StateStyle? { entries.first { $0.style.id == id }?.style }
}

/// What a `state-tile` binds: the entity, a library style by id, the tile's own built-in style, and per-state overrides.
public struct ServerUIStateTileBinding: Equatable, Sendable {
    /// One state's override of single layers; a nil layer is untouched.
    public struct Override: Equatable, Sendable {
        /// The Home Assistant state.
        public let state: String
        /// The icon layer (an SF Symbol name).
        public let icon: String?
        /// The text layer.
        public let text: String?
        /// The indicator layer.
        public let indicator: StateIndicator?
        /// The colour layer.
        public let colour: StateColour?
    }

    /// The entity the tile reads and calls, `domain.object`.
    public let entityId: String
    /// The library style to apply.
    public let styleId: String?
    /// The tile's own built-in style: used when ``styleId`` is unknown or the device lacks the capability.
    public let builtIn: String?
    /// The per-state overrides.
    public let overrides: [Override]

    /// The style the tile shows, or nil when none resolves (no authored style, no built-in): the tile then draws the unknown look.
    ///
    /// An unknown style id falls back to the tile's built-in style, and a device without the capability (`capability` false) uses
    /// the built-in style alone: neither rejects the layout. Overrides apply to whichever style resolved.
    /// - Parameters:
    ///   - library: The document's library, if it carries one.
    ///   - capability: Whether this device negotiated ``serverUIStateStyleCapability``.
    public func resolve(in library: ServerUIStateStyleLibrary?, capability: Bool = true) -> StateStyle? {
        let authored = capability ? styleId.flatMap { library?.style(id: $0) } : nil
        guard let style = authored ?? builtIn.flatMap({ StateStyle.builtIn(id: $0) }) else { return nil }
        return capability ? style.applying(overrides) : style
    }
}

/// A tile whose look comes from a state style.
extension ServerUICompositionDocument {
    /// The authored state tile.
    public struct StateTile: Equatable, Sendable {
        public let node: Node
        public let icon: Symbol
        public let binding: ServerUIStateTileBinding
        /// The tile's own subtitle, progress and buttons (`sh.tile-parts@1`).
        public var parts = ServerUITileParts()
        /// Where a tap on the tile goes (`sh.tile-parts@1`).
        public var action: Action? = nil
        /// The conditions that decide the tile's faces (`sh.tile-look@1`).
        public var look = ServerUITileLook()
    }
}

// MARK: - Overrides

extension StateStyle {
    /// A copy of the style with `overrides` applied layer by layer. A state that shares a rule with others is split off so the
    /// override touches it alone; a state no rule names gets a rule made from the fallback. An icon override also replaces the
    /// glyph of the state's action, which is what the disc draws.
    public func applying(_ overrides: [ServerUIStateTileBinding.Override]) -> StateStyle {
        guard !overrides.isEmpty else { return self }
        var rules = self.rules
        for item in overrides {
            let index = rules.firstIndex { !$0.states.isEmpty && $0.states.contains(item.state) }
            var rule: StateRule
            if let index {
                if rules[index].states.count == 1 { rule = rules[index]; rules[index] = Self.layered(rule, item); continue }
                rule = rules[index]
                rules[index].states.removeAll { $0 == item.state }
                rule.states = [item.state]
                rules.insert(Self.layered(rule, item), at: index + 1)
            } else {
                rule = rules[rules.count - 1]
                rule.states = [item.state]
                rules.insert(Self.layered(rule, item), at: rules.count - 1)
            }
        }
        return replacingRules(rules)
    }

    private static func layered(_ rule: StateRule, _ item: ServerUIStateTileBinding.Override) -> StateRule {
        var rule = rule
        if let icon = item.icon {
            rule.glyph = icon
            rule.action?.symbol = icon
        }
        if let text = item.text { rule.words = text }
        if let indicator = item.indicator { rule.indicator = indicator }
        if let colour = item.colour { rule.colour = colour }
        return rule
    }
}

// MARK: - Decoding

/// Reads a style library and a tile binding out of validated JSON, and checks what the shape cannot say.
///
/// Issues carry the pointers the Studio compiler reports (`src/shared/composition/state-styles.ts`), so both sides name the same
/// first issue for the shared corpus.
enum ServerUIStateStyles {
    typealias Issue = ServerUICompositionError

    // MARK: Library

    static func decodeLibrary(_ json: JSONValue, at pointer: String) -> (library: ServerUIStateStyleLibrary, issues: [Issue]) {
        var issues: [Issue] = []
        var entries: [ServerUIStateStyleLibrary.Entry] = []
        for (index, item) in (json["styles"]?.array ?? []).enumerated() {
            let path = "\(pointer)/styles/\(index)"
            let rules = (item["rules"]?.array ?? []).enumerated().map { offset, rule in
                checkRule(rule, at: "\(path)/rules/\(offset)", issues: &issues)
                return decodeRule(rule)
            }
            let fallback = item["fallback"] ?? .object([:])
            checkRule(fallback, at: "\(path)/fallback", issues: &issues, isFallback: true)
            var fallbackRule = decodeRule(fallback)
            fallbackRule.states = []
            if let request = item["request"] { checkRequest(request, at: "\(path)/request", issues: &issues) }
            let id = item["id"]?.string ?? ""
            let style = StateStyle(
                id: id, name: item["name"]?.string ?? id, domain: item["domain"]?.string ?? "", actionId: item["actionId"]?.string ?? id,
                rules: rules + [fallbackRule], request: item["request"].map(decodeRequest),
                togglesDisc: item["togglesDisc"]?.bool ?? false, drawsErrorDisc: item["drawsErrorDisc"]?.bool ?? false,
                hiddenWords: item["hiddenWords"]?.string)
            entries.append(.init(style: style, base: item["base"]?.string))
        }
        return (ServerUIStateStyleLibrary(entries: entries), issues)
    }

    /// The rule's class, indicator, colour and action agree: the unknown states are the unknown class, the arc never meets an action, and
    /// a colour token sits only on a resting or in-progress state (it is cosmetic, so a warning, error or unknown state keeps its class face).
    private static func checkRule(_ rule: JSONValue, at path: String, issues: inout [Issue], isFallback: Bool = false) {
        let stateClass = rule["class"]?.string
        let names = (rule["states"]?.array ?? []).compactMap(\.string)
        if names.contains(where: { $0 == "unavailable" || $0 == "unknown" }), stateClass != StateClass.unknown.rawValue {
            issues.append(Issue(.invalidCombination, path + "/class"))
        }
        if rule["indicator"]?.string == StateIndicator.arcSpinner.rawValue,
           rule["action"] != nil || stateClass == StateClass.unknown.rawValue {
            issues.append(Issue(.invalidCombination, path + "/indicator"))
        }
        if rule["colour"] != nil, !acceptsColour(stateClass) { issues.append(Issue(.invalidCombination, path + "/colour")) }
        if let action = rule["action"], action["otherwise"] != nil, action["requiresFeature"] == nil {
            issues.append(Issue(.invalidCombination, path + "/action/otherwise"))
        }
    }

    /// Whether a state of the class named `rawClass` may carry a colour token: resting and in-progress only.
    private static func acceptsColour(_ rawClass: String?) -> Bool {
        rawClass == StateClass.resting.rawValue || rawClass == StateClass.inProgress.rawValue
    }

    private static func checkRequest(_ request: JSONValue, at path: String, issues: inout [Issue]) {
        let script = request["script"]?.string, timer = request["errorTimer"]?.string
        if (script == nil) != (timer == nil) { issues.append(Issue(.invalidCombination, path + (script == nil ? "/script" : "/errorTimer"))) }
        if let script, !script.hasPrefix("script.") { issues.append(Issue(.invalidCombination, path + "/script")) }
        if let timer, !timer.hasPrefix("timer.") { issues.append(Issue(.invalidCombination, path + "/errorTimer")) }
    }

    private static func decodeRule(_ rule: JSONValue) -> StateRule {
        let fill = rule["fill"].flatMap(decodeFill)
        var decoded = StateRule((rule["states"]?.array ?? []).compactMap(\.string),
                  rule["class"]?.string.flatMap(StateClass.init(rawValue:)) ?? .unknown,
                  active: rule["active"]?.bool ?? false, glyph: rule["icon"]?.string, words: rule["text"]?.string,
                  indicator: rule["indicator"]?.string.flatMap(StateIndicator.init(rawValue:)),
                  action: rule["action"].map(decodeAction),
                  colour: rule["colour"]?.string.flatMap(StateColour.init(rawValue:)), fill: fill?.light)
        decoded.fillDark = fill?.dark
        return decoded
    }

    /// A `solid-rgb` fill as `red << 16 | green << 8 | blue`, or a `solid-appearance` as its light and its dark member; the shape check has
    /// already made it exact. `dark` is nil for a single colour.
    private static func decodeFill(_ fill: JSONValue) -> (light: UInt32, dark: UInt32?)? {
        func packed(_ value: JSONValue) -> UInt32? {
            guard let red = value["red"]?.number, let green = value["green"]?.number, let blue = value["blue"]?.number else { return nil }
            return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
        }
        if fill["type"]?.string == "solid-appearance" {
            guard let light = fill["light"].flatMap(packed), let dark = fill["dark"].flatMap(packed) else { return nil }
            return (light, dark)
        }
        return packed(fill).map { ($0, nil) }
    }

    private static func decodeAction(_ action: JSONValue) -> StateAction {
        StateAction(
            verb: action["verb"]?.string ?? "", symbol: action["icon"]?.string ?? "circle", service: action["service"]?.string,
            confirmation: action["confirmation"].map {
                .init(title: $0["title"]?.string ?? "", message: $0["message"]?.string ?? "", confirmVerb: $0["confirmVerb"]?.string ?? "")
            },
            requiresFeature: action["requiresFeature"]?.number.map { Int($0) },
            otherwise: action["otherwise"].map {
                .init(verb: $0["verb"]?.string ?? "", symbol: $0["icon"]?.string ?? "circle", service: $0["service"]?.string)
            },
            isTappable: action["tappable"]?.bool ?? true)
    }

    private static func decodeRequest(_ request: JSONValue) -> StateRequest {
        func seconds(_ key: String) -> Duration { .seconds(Int(request[key]?.number ?? 0)) }
        var words: [String: String] = [:]
        for item in request["pendingWords"]?.array ?? [] {
            if let service = item["service"]?.string, let text = item["text"]?.string { words[service] = text }
        }
        return StateRequest(
            lockout: seconds("lockoutSeconds"), ackTimeout: seconds("ackTimeoutSeconds"), settleTimeout: seconds("settleTimeoutSeconds"),
            errorHold: seconds("errorHoldSeconds"), onTimeout: request["onTimeout"]?.string.flatMap(StateRequest.OnTimeout.init(rawValue:)) ?? .error,
            pendingWords: words, errorWords: request["errorWords"]?.string ?? "Error",
            script: request["script"]?.string, errorTimer: request["errorTimer"]?.string)
    }

    // MARK: Tile binding

    static func decodeBinding(_ json: JSONValue, at pointer: String, library: ServerUIStateStyleLibrary?) -> (binding: ServerUIStateTileBinding, issues: [Issue]) {
        var issues: [Issue] = []
        let overrides = (json["overrides"]?.array ?? []).map { item in
            ServerUIStateTileBinding.Override(
                state: item["state"]?.string ?? "", icon: item["icon"]?.string, text: item["text"]?.string,
                indicator: item["indicator"]?.string.flatMap(StateIndicator.init(rawValue:)),
                colour: item["colour"]?.string.flatMap(StateColour.init(rawValue:)))
        }
        let binding = ServerUIStateTileBinding(
            entityId: json["entityId"]?.string ?? "", styleId: json["styleId"]?.string, builtIn: json["builtIn"]?.string, overrides: overrides)
        if binding.styleId == nil, binding.builtIn == nil { issues.append(Issue(.invalidCombination, pointer)) }
        let authored = binding.styleId.flatMap { library?.style(id: $0) }
        let domain = String(binding.entityId.prefix { $0 != "." })
        if let authored, authored.domain != domain { issues.append(Issue(.invalidCombination, pointer + "/entityId")) }
        let builtIn = binding.builtIn.flatMap { StateStyle.builtIn(id: $0) }
        if let builtIn, builtIn.domain != domain { issues.append(Issue(.invalidCombination, pointer + "/builtIn")) }
        let effective = authored ?? builtIn
        var seen = Set<String>()
        for (index, item) in overrides.enumerated() {
            let path = "\(pointer)/overrides/\(index)"
            if !seen.insert(item.state).inserted { issues.append(Issue(.invalidCombination, path + "/state")) }
            if item.icon == nil, item.text == nil, item.indicator == nil, item.colour == nil { issues.append(Issue(.invalidCombination, path)) }
            if item.indicator == .arcSpinner, let effective {
                let rule = effective.rule(for: item.state)
                if rule.action != nil || rule.stateClass == .unknown { issues.append(Issue(.invalidCombination, path + "/indicator")) }
            }
            if item.colour != nil, let effective, !acceptsColour(effective.rule(for: item.state).stateClass.rawValue) {
                issues.append(Issue(.invalidCombination, path + "/colour"))
            }
        }
        return (binding, issues)
    }
}
