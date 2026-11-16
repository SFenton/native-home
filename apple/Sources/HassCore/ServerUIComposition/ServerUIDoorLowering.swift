import Foundation

// MARK: - `door-tile` lowered onto `state-tile`

/// What a `door-tile` node authors, read once and handed to ``ServerUIDoorLowering``.
///
/// The node type stays decodable (`sh.security-door@1`, `sh.tiles@1`, `sh.bindings@1`), but nothing draws it: the compiler lowers
/// it to a `state-tile` over the built-in `garage-door` or `lock` style, so the app has one tile for doors, blinds, alarms and the
/// rest (`.agents/patterns/state-tile.md`).
struct ServerUIDoorTileProps: Equatable, Sendable {
    typealias D = ServerUICompositionDocument

    let node: D.Node
    let sourceId: String
    let kind: D.DoorKind
    let states: [D.DoorStateAppearance]
    let fallback: D.AlarmAppearance
    let loadingText: String
    let hiddenText: String
    let unavailableText: String
    let errorText: String
    let sendingOpenText: String
    let sendingCloseText: String
    let openLabel: String
    let closeLabel: String
    let reverseLabel: String
}

/// The compile-time rewrite of a `door-tile` into a `state-tile` and the saved style that carries its authored words.
///
/// What the door authored is kept where the generic tile has a place for it:
/// - **icon and text per state** become the style's rules, and the state's own `active` and `error` flags set the rule's;
/// - **the open, close and reverse labels** become the verbs of the disc (Reverse is the disc a moving door shows where its cover
///   does not support Stop);
/// - **the sending words** become the request's pending words, the error text its error words;
/// - **the unavailable and fallback appearances** become the unknown rule and the fallback rule.
///
/// What the generic tile does not carry is dropped, and the equivalence test names each: the authored `loadingText` and `hiddenText`
/// (the tile reads "Unavailable" while values load and while a screenshot hides them) and the authored RGB fills (the tile uses its
/// family fill, lit while active).
enum ServerUIDoorLowering {
    typealias D = ServerUICompositionDocument

    /// The entity and kind a `security-door@1` data source names.
    struct Source: Equatable, Sendable {
        let entityId: String
        let kind: D.DoorKind
    }

    /// The `security-door@1` sources of a raw `dataSources` array, by id. A source whose entity is not a literal id is left out, and the
    /// compiler's own reference check then refuses the tile that names it.
    static func sources(in dataSources: JSONValue?) -> [String: Source] {
        var result: [String: Source] = [:]
        for item in dataSources?.array ?? [] where item["model"]?.string == "security-door@1" {
            guard let id = item["id"]?.string, let entity = item["inputs"]?["entityId"]?["value"]?.string,
                  let kind = item["inputs"]?["kind"]?.string.flatMap(D.DoorKind.init(rawValue:)) else { continue }
            result[id] = Source(entityId: entity, kind: kind)
        }
        return result
    }

    /// The id the lowered tile's saved style carries in the document's style library.
    static func styleId(for node: D.Node) -> String { "\(node.id).door" }

    /// The `state-tile` and the saved style a door lowers to.
    /// - Parameters:
    ///   - props: What the door authored.
    ///   - entityId: The entity its source names.
    static func lower(_ props: ServerUIDoorTileProps, entityId: String) -> (tile: D.StateTile, style: ServerUIStateStyleLibrary.Entry) {
        let base = props.kind == .lock ? StateStyle.lock : StateStyle.garageDoor
        let style = derive(base, props)
        var tile = D.StateTile(node: props.node, icon: props.fallback.icon,
                               binding: ServerUIStateTileBinding(entityId: entityId, styleId: style.id, builtIn: base.id, overrides: []))
        tile.parts.subtitle = loadingSubtitle(props)
        return (tile, .init(style: style, base: base.id))
    }

    /// The words under the title while values load: the door's own phase read says `loading`, and any other answer is no answer, so the
    /// tile keeps the style's state words (a subtitle that cannot be read is not drawn).
    private static func loadingSubtitle(_ props: ServerUIDoorTileProps) -> D.StringValue {
        let phase = ServerUIOperand.read(sourceId: props.sourceId, path: ["phase"], as: .string)
        let silent = ServerUIOperand.read(sourceId: props.sourceId, path: ["words"], as: .string)
        return .expression(.map(of: phase, cases: [.init(equals: .string("loading"), then: .literal(.string(props.loadingText)))],
                                otherwise: silent), fallback: nil)
    }

    // MARK: Deriving the style

    private static func derive(_ base: StateStyle, _ props: ServerUIDoorTileProps) -> StateStyle {
        let icon = props.fallback.icon.name
        // One rule per state, so each state takes its own authored appearance (or the fallback's, where the door authored none).
        var rules: [StateRule] = []
        for rule in base.rules where rule.stateClass != .unknown {
            for state in rule.states {
                var single = rule
                single.states = [state]
                rules.append(styled(single, state: state, props, icon: icon))
            }
        }
        let unknown = base.rules.first { $0.stateClass == .unknown && !$0.states.isEmpty } ?? StateRule(["unavailable", "unknown"], .unknown)
        for states in [unknown.states, []] {
            var rule = unknown
            rule.states = states
            rule.glyph = icon
            rule.action?.symbol = icon
            rule.words = states.isEmpty ? props.fallback.text : props.unavailableText
            rule.fill = rgb(props.fallback.fill)
            if var action = rule.action { action.verb = verb(for: action.service, props); rule.action = action }
            rules.append(rule)
        }
        var request = base.request
        if base.id == StateStyle.garageDoor.id {
            request?.pendingWords["open_cover"] = props.sendingOpenText
            request?.pendingWords["close_cover"] = props.sendingCloseText
        }
        request?.errorWords = props.errorText
        return StateStyle(id: styleId(for: props.node), name: props.node.title, domain: base.domain, actionId: base.actionId,
                          rules: rules, request: request, togglesDisc: base.togglesDisc, drawsErrorDisc: base.drawsErrorDisc,
                          hiddenWords: props.hiddenText, keepsDiscWhenUnknown: true)
    }

    /// One state's rule with what the door authored for it. A state the door did not author reads as its fallback appearance and is
    /// not lit, as the door drew it, though it keeps the built-in's class.
    private static func styled(_ rule: StateRule, state: String, _ props: ServerUIDoorTileProps, icon: String) -> StateRule {
        var rule = rule
        let authored = props.states.first { $0.state == state }
        let appearance = authored?.appearance ?? props.fallback
        if var action = rule.action {
            // Stop keeps its word; Reverse, the disc of a cover that cannot stop, takes the authored one.
            if action.requiresFeature == nil { action.verb = verb(for: action.service, props) }
            action.otherwise?.verb = props.reverseLabel
            // The disc draws the state's own symbol; a moving garage door's Stop stays Stop, and its Reverse draws the state's symbol.
            if action.requiresFeature == nil { action.symbol = appearance.icon.name } else { action.otherwise?.symbol = appearance.icon.name }
            rule.action = action
        }
        rule.glyph = appearance.icon.name
        rule.words = appearance.text
        rule.fill = rgb(appearance.fill)
        if rule.isActive != (authored?.active ?? false) {
            // The tile follows the door's own flag; the disc keeps the style's reading.
            rule.discOn = rule.isActive
            rule.isActive = authored?.active ?? false
        }
        if authored?.error == true { rule.stateClass = .error }
        return rule
    }

    private static func rgb(_ fill: D.TileFill) -> UInt32? {
        guard case .solidRGB(let red, let green, let blue) = fill else { return nil }
        return UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    /// The disc's verb for the service it runs: the lock's pair, or the garage's open and close. A disc with no service reads as the
    /// door did, "Unlock" for a lock and the close label for a garage.
    private static func verb(for service: String?, _ props: ServerUIDoorTileProps) -> String {
        switch props.kind {
        case .lock: service == "lock" ? props.closeLabel : props.openLabel
        case .garage: service == "open_cover" ? props.openLabel : props.closeLabel
        }
    }
}
