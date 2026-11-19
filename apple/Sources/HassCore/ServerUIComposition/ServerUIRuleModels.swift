import Foundation

// MARK: - Rules on controls, actions, looks and strings (`sh.rules@1`, `sh.enabled-when@1`, `sh.action-rules@1`)

/// `enabledWhen` (`sh.enabled-when@1`): a condition and what to do while it cannot be answered. Both are authored, never implied.
public struct ServerUIEnabledRule: Equatable, Sendable {
    public let condition: ServerUIPredicate
    public let whenUnknown: ServerUIEnabledUnknown

    /// Creates a rule.
    public init(condition: ServerUIPredicate, whenUnknown: ServerUIEnabledUnknown) {
        self.condition = condition
        self.whenUnknown = whenUnknown
    }

    /// Whether the control is enabled now (``ServerUIControlRules/isEnabled(_:whenUnknown:previous:in:)``). `previous` is the last
    /// answer, which `keep` repeats while the condition cannot be answered.
    public func isEnabled(previous: Bool?, in environment: some ServerUIReading) -> Bool {
        ServerUIControlRules.isEnabled(condition, whenUnknown: whenUnknown, previous: previous, in: environment)
    }

    /// Whether a node's rule lets it act now; a node with no rule always can.
    public static func allows(_ rule: ServerUIEnabledRule?, previous: Bool?, in environment: some ServerUIReading) -> Bool {
        rule?.isEnabled(previous: previous, in: environment) ?? true
    }
}

/// An action chosen by rule (`sh.action-rules@1`): the first case whose condition holds runs its action, else `otherwise`.
///
/// One level: a case holds a plain action, never another rule. `otherwise` is an action or `nil` for "do nothing". The rule is
/// resolved at gesture time from the house as it is then, never observed, so a tap runs what the screen showed it would.
public struct ServerUIActionRule: Equatable, Sendable {
    /// One case: the condition and the plain action it runs.
    public struct Case: Equatable, Sendable {
        public let when: ServerUIPredicate
        public let then: ServerUICompositionDocument.Action

        /// Creates a case.
        public init(when: ServerUIPredicate, then: ServerUICompositionDocument.Action) {
            self.when = when
            self.then = then
        }
    }

    public let cases: [Case]
    /// What runs when no case holds; `nil` runs nothing.
    public let otherwise: ServerUICompositionDocument.Action?

    /// Creates a rule.
    public init(cases: [Case], otherwise: ServerUICompositionDocument.Action?) {
        self.cases = cases
        self.otherwise = otherwise
    }

    /// Which case the rule uses (``ServerUIRule``).
    public func pick(_ environment: some ServerUIReading) -> ServerUIRulePick {
        ServerUIRule.pick(count: cases.count) { cases[$0].when.evaluate(environment) }
    }

    /// The plain action to run now, or `nil` to run nothing. A case that cannot be answered yet stands before any that holds, so the
    /// rule does nothing rather than run a later case in its place.
    public func resolve(_ environment: some ServerUIReading) -> ServerUICompositionDocument.Action? {
        switch pick(environment) {
        case .matched(let index): cases[index].then
        case .otherwise: otherwise
        case .stalled: nil
        }
    }

    /// Every plain action the rule can run.
    public var actions: [ServerUICompositionDocument.Action] { cases.map(\.then) + [otherwise].compactMap { $0 } }

    /// The source ids the conditions read.
    public var sourceIds: Set<String> { cases.reduce(into: Set<String>()) { $0.formUnion($1.when.sourceIds) } }
}

extension ServerUICompositionDocument.Action {
    /// The plain action this slot runs now: itself, or what its rule picks (`nil` for a rule that runs nothing).
    public func resolved(_ environment: some ServerUIReading) -> ServerUICompositionDocument.Action? {
        if case .conditional(let rule) = self { return rule.resolve(environment) }
        return self
    }

    /// The plain actions this slot can run: itself, or every action its rule holds.
    public var plainActions: [ServerUICompositionDocument.Action] {
        if case .conditional(let rule) = self { return rule.actions }
        return [self]
    }
}

// MARK: - A look that follows a rule or an entity

/// How a look slot follows a rule or an entity's text (`sh.rules@1`). The slot's own value is the `otherwise` of a conditional, or the
/// fallback of a bound slot, so a renderer that draws only that value still draws a complete look.
public enum ServerUIDynamicLook<Value: Equatable & Sendable>: Equatable, Sendable {
    /// The first case whose condition holds gives its exact value; a case that cannot be answered yet stops the rule at `otherwise`.
    case conditional([ServerUIConditional<Value>.Case])
    /// The operand's text names the value: a color (`bound-color`) or an SF Symbol name (`bound-symbol`).
    case bound(ServerUIOperand)

    /// The source ids the rule reads.
    public var sourceIds: Set<String> {
        switch self {
        case .conditional(let cases): cases.reduce(into: Set<String>()) { $0.formUnion($1.when.sourceIds) }
        case .bound(let operand): operand.sourceIds
        }
    }
}

public extension ServerUIDynamicLook where Value == ServerUICompositionDocument.TileFill {
    /// The fill to draw: a conditional gives an exact case (never clamped), a bound color is parsed and clamped for `role`
    /// (``ServerUILooks/boundColor(_:role:in:)``). `base` is the `otherwise` or the fallback; `loading` means "keep what was shown".
    func resolve(base: Value, role: ServerUIColorText.Role, in environment: some ServerUIReading) -> ServerUILookResult<Value> {
        switch self {
        case .conditional(let cases):
            return .value(ServerUIConditional(cases: cases, otherwise: base).resolve(environment))
        case .bound(let operand):
            switch ServerUILooks.boundColor(operand, role: role, in: environment) {
            case .loading: return .loading
            case .value(let rgb): return .value(rgb.map { .solidRGB(red: $0.red, green: $0.green, blue: $0.blue) } ?? base)
            }
        }
    }
}

public extension ServerUIDynamicLook where Value == ServerUICompositionDocument.Symbol {
    /// The symbol to draw: a conditional gives an exact case, a bound symbol the named one when the app can draw it
    /// (``ServerUILooks/boundSymbol(_:in:)``). `base` is the `otherwise` or the fallback.
    func resolve(base: Value, in environment: some ServerUIReading) -> ServerUILookResult<Value> {
        switch self {
        case .conditional(let cases):
            return .value(ServerUIConditional(cases: cases, otherwise: base).resolve(environment))
        case .bound(let operand):
            switch ServerUILooks.boundSymbol(operand, in: environment) {
            case .loading: return .loading
            case .value(let name): return .value(name.map { base.renamed($0) } ?? base)
            }
        }
    }
}

extension ServerUICompositionDocument.Symbol {
    /// The same symbol under another name (a bound symbol keeps its fallback's rendering and gap policy).
    func renamed(_ name: String) -> Self { Self(name: name, rendering: rendering, unavailable: unavailable) }
}

/// What a status look draws: the three slots after their rules have answered.
public struct ServerUIResolvedAppearance: Equatable, Sendable {
    public var icon: ServerUICompositionDocument.Symbol
    public var fill: ServerUICompositionDocument.TileFill
    public var glyph: ServerUICompositionDocument.TileFill?

    /// Creates a resolved look.
    public init(icon: ServerUICompositionDocument.Symbol, fill: ServerUICompositionDocument.TileFill,
                glyph: ServerUICompositionDocument.TileFill?) {
        self.icon = icon
        self.fill = fill
        self.glyph = glyph
    }
}

public extension ServerUICompositionDocument.StatusAppearance {
    /// Whether any slot follows a rule or an entity.
    var isDynamic: Bool { iconRule != nil || fillRule != nil || glyphRule != nil }

    /// The source ids the slots' rules read.
    var ruleSourceIds: Set<String> {
        [iconRule?.sourceIds, fillRule?.sourceIds, glyphRule?.sourceIds].compactMap { $0 }.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// The look to draw now. A slot whose value is still loading keeps what `previous` showed for it (and its own value when nothing
    /// was shown); a slot with no rule draws its own value.
    func resolve(in environment: some ServerUIReading, keeping previous: ServerUIResolvedAppearance? = nil) -> ServerUIResolvedAppearance {
        var out = ServerUIResolvedAppearance(icon: icon, fill: fill, glyph: glyph)
        if let iconRule {
            switch iconRule.resolve(base: icon, in: environment) {
            case .value(let value): out.icon = value
            case .loading: out.icon = previous?.icon ?? icon
            }
        }
        if let fillRule {
            switch fillRule.resolve(base: fill, role: .fill, in: environment) {
            case .value(let value): out.fill = value
            case .loading: out.fill = previous?.fill ?? fill
            }
        }
        if let glyphRule, let base = glyph {
            switch glyphRule.resolve(base: base, role: .glyph, in: environment) {
            case .value(let value): out.glyph = value
            case .loading: out.glyph = previous?.glyph ?? base
            }
        }
        return out
    }
}

public extension ServerUICompositionDocument.TilePresentation {
    /// The fill to draw now; `previous` is what the slot showed, kept while a bound color is loading.
    func resolvedFill(in environment: some ServerUIReading, keeping previous: ServerUICompositionDocument.TileFill? = nil)
        -> ServerUICompositionDocument.TileFill {
        guard let fillRule else { return fill }
        switch fillRule.resolve(base: fill, role: .fill, in: environment) {
        case .value(let value): return value
        case .loading: return previous ?? fill
        }
    }
}

public extension ServerUICompositionDocument.RoomStateColor {
    /// The fill to draw now; `previous` is what the slot showed, kept while a bound color is loading.
    func resolvedFill(in environment: some ServerUIReading, keeping previous: ServerUICompositionDocument.TileFill? = nil)
        -> ServerUICompositionDocument.TileFill {
        guard let fillRule else { return fill }
        switch fillRule.resolve(base: fill, role: .fill, in: environment) {
        case .value(let value): return value
        case .loading: return previous ?? fill
        }
    }
}

public extension ServerUICompositionDocument.StatusPill {
    /// The tone to draw now: the first case of the rule that holds, else ``tone``. A rule that cannot answer yet shows ``tone``.
    func resolvedTone(in environment: some ServerUIReading) -> Tone {
        toneCases.isEmpty ? tone : ServerUIConditional(cases: toneCases, otherwise: tone).resolve(environment)
    }

    /// The source ids the tone rule reads.
    var toneSourceIds: Set<String> { toneCases.reduce(into: Set<String>()) { $0.formUnion($1.when.sourceIds) } }
}

// MARK: - Strings

/// What a text slot gives, once for every slot kind: a literal, a read, or an operand with an optional fallback.
public enum ServerUIStringResolver {
    /// The text to draw, "not yet" (`loading`: the slot keeps what it showed) or `unavailable` (the slot draws its own words).
    ///
    /// `read` resolves the typed read of a source (the app reads it through its bindings); an `expression` is evaluated against
    /// `environment`. A number or a boolean is drawn as text; a list or an object is unavailable. A fallback stands in only for
    /// `unavailable`, never for `loading`.
    public static func resolve(_ value: ServerUICompositionDocument.StringValue, read: (ServerUICompositionDocument.Read) -> ServerUIReadResult,
                               in environment: some ServerUIReading) -> ServerUIReadResult {
        switch value {
        case .literal(let text): return .value(.string(text))
        case .read(let source, let fallback, _): return text(of: read(source), fallback: fallback)
        case .expression(let operand, let fallback, _): return text(of: operand.evaluate(environment), fallback: fallback)
        }
    }

    /// The text of an expression's result, for a caller that got the result another way (a shared ``DerivedValue``): the same rules
    /// as ``resolve(_:read:in:)``.
    public static func text(of result: ServerUIReadResult, fallback: String?) -> ServerUIReadResult {
        switch result {
        case .loading: return .loading
        case .unavailable: return fallback.map { .value(.string($0)) } ?? .unavailable
        case .value(let value):
            guard let text = ServerUIOperand.scalarText(value) else { return fallback.map { .value(.string($0)) } ?? .unavailable }
            return .value(.string(text))
        }
    }

    /// The source ids an expression reads (a `read` is resolved by the app's bindings and named by the document's own read list).
    public static func sourceIds(_ value: ServerUICompositionDocument.StringValue) -> Set<String> {
        switch value {
        case .literal: []
        case .read(let source, _, _): [source.sourceId]
        case .expression(let operand, _, _): operand.sourceIds
        }
    }
}
