import Foundation

// MARK: - Looks that follow a rule or an entity

/// What a look slot gives: the look, or "not yet" (the slot keeps what it showed).
public enum ServerUILookResult<Look: Equatable & Sendable>: Equatable, Sendable {
    case value(Look)
    case loading
}

/// A `conditional` look, tone or action (`sh.rules@1`, `sh.action-rules@1`): the first case whose condition holds, else `otherwise`.
public struct ServerUIConditional<Value: Equatable & Sendable>: Equatable, Sendable {
    /// One case: the condition and what it gives.
    public struct Case: Equatable, Sendable {
        public let when: ServerUIPredicate
        public let then: Value

        /// Creates a case.
        public init(when: ServerUIPredicate, then: Value) {
            self.when = when
            self.then = then
        }
    }

    public let cases: [Case]
    public let otherwise: Value

    /// Creates a conditional.
    public init(cases: [Case], otherwise: Value) {
        self.cases = cases
        self.otherwise = otherwise
    }

    /// Which case the rule uses (``ServerUIRule``).
    public func pick(_ environment: some ServerUIReading) -> ServerUIRulePick {
        ServerUIRule.pick(count: cases.count) { cases[$0].when.evaluate(environment) }
    }

    /// The value a look or tone slot has now. A stalled rule shows `otherwise` until it can answer, so a rule on a look never blanks it.
    public func resolve(_ environment: some ServerUIReading) -> Value {
        if case .matched(let index) = pick(environment) { return cases[index].then }
        return otherwise
    }
}

/// Resolvers for the slots that follow an entity's text: a color, a symbol name, a text, a badge and a progress.
public enum ServerUILooks {
    /// The color a `bound-color` slot draws: `nil` is the fallback.
    ///
    /// The value is read as text. Loading is "not yet"; text that is a tier 1 color (``ServerUIColorText``) becomes the clamped color of
    /// `role`; anything else (unavailable, a number, a name, alpha 0) is the fallback.
    public static func boundColor(_ value: ServerUIOperand, role: ServerUIColorText.Role,
                                  in environment: some ServerUIReading) -> ServerUILookResult<ServerUIRGB?> {
        let found = value.evaluate(environment)
        if found == .loading { return .loading }
        guard case .string(let text)? = found.json, let parsed = ServerUIColorText.parse(text) else { return .value(nil) }
        return .value(ServerUIColorText.clamped(parsed, role: role))
    }

    /// The symbol name a `bound-symbol` slot draws: `nil` is the fallback.
    ///
    /// The value is read as text. Loading is "not yet"; text of 1 to 80 characters the app can draw is the symbol; anything else is the fallback.
    public static func boundSymbol(_ value: ServerUIOperand, in environment: some ServerUIReading) -> ServerUILookResult<String?> {
        let found = value.evaluate(environment)
        if found == .loading { return .loading }
        guard case .string(let raw)? = found.json else { return .value(nil) }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let drawn = !name.isEmpty && name.utf16.count <= 80 && environment.drawsSymbol(name)
        return .value(drawn ? name : nil)
    }

    /// What a text slot gives: its value, "not yet" (`loading`: the slot keeps what it showed) or, with no fallback, `unavailable`.
    ///
    /// A fallback is drawn only when the value is unavailable, never while loading.
    public static func text(_ value: ServerUIOperand, fallback: String?, in environment: some ServerUIReading) -> ServerUIReadResult {
        let result = value.evaluate(environment)
        if result == .unavailable, let fallback { return .value(.string(fallback)) }
        return result
    }

    /// The text a badge draws, `nil` when it draws nothing (`sh.badges@1`).
    ///
    /// A badge draws nothing when it is `none`, empty, 0 (the number, or text that reads as 0) or unavailable, and is "not yet" while
    /// loading, so the badge keeps what it showed. A number prints as ``ServerUIOperand/scalarText(_:)`` prints it.
    public static func badge(_ value: ServerUIOperand?, in environment: some ServerUIReading) -> ServerUILookResult<String?> {
        guard let value else { return .value(nil) }
        let found = value.evaluate(environment)
        if found == .loading { return .loading }
        switch found.json {
        case .string?, .number?:
            let text = (found.json.flatMap(ServerUIOperand.scalarText) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .value(text.isEmpty || JSONValue.string(text).finiteNumber == 0 ? nil : text)
        default: return .value(nil)
        }
    }

    /// The fill of a state tile's progress (`sh.tile-parts@1`): the operand's number clamped to 0 through 1, or `nil` for no progress.
    ///
    /// Anything that is not a number, a value that is loading and a value that is unavailable draw no progress.
    public static func progress(_ value: ServerUIOperand?, in environment: some ServerUIReading) -> Double? {
        guard let value, case .number(let number)? = value.evaluate(environment).json, number.isFinite else { return nil }
        return min(1, max(0, number))
    }
}
