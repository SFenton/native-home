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
        let tile = D.StateTile(node: props.node, icon: props.fallback.icon,
                               binding: ServerUIStateTileBinding(entityId: entityId, styleId: style.id, builtIn: base.id, overrides: []))
        return (tile, .init(style: style, base: base.id))
    }

    // MARK: Deriving the style

    private static func derive(_ base: StateStyle, _ props: ServerUIDoorTileProps) -> StateStyle {
        var rules = base.rules.map { rule -> StateRule in
            var rule = rule
            if var action = rule.action {
                // Stop keeps its word; Reverse, the disc of a cover that cannot stop, takes the authored one.
                if action.requiresFeature == nil { action.verb = verb(for: action.service, props) }
                action.otherwise?.verb = props.reverseLabel
                rule.action = action
            }
            guard let authored = rule.states.compactMap({ state in props.states.first { $0.state == state } }).first else { return rule }
            rule.glyph = authored.appearance.icon.name
            rule.words = authored.appearance.text
            rule.isActive = authored.active
            if authored.error { rule.stateClass = .error }
            // The disc draws the state's own symbol, except a moving garage door's, which keeps Stop or Reverse.
            if rule.action?.requiresFeature == nil { rule.action?.symbol = authored.appearance.icon.name }
            return rule
        }
        let icon = props.fallback.icon.name
        for index in rules.indices where rules[index].stateClass == .unknown {
            rules[index].glyph = icon
            rules[index].action?.symbol = icon
            rules[index].words = rules[index].states.isEmpty ? props.fallback.text : props.unavailableText
        }
        var request = base.request
        if base.id == StateStyle.garageDoor.id {
            request?.pendingWords["open_cover"] = props.sendingOpenText
            request?.pendingWords["close_cover"] = props.sendingCloseText
        }
        request?.errorWords = props.errorText
        return StateStyle(id: styleId(for: props.node), name: props.node.title, domain: base.domain, actionId: base.actionId,
                          rules: rules, request: request, togglesDisc: base.togglesDisc, drawsErrorDisc: base.drawsErrorDisc)
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
