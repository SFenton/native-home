import Foundation

// MARK: - Decoding rule-shaped values

/// Decodes the values that follow a rule or an entity (`sh.rules@1`): an authored string, a `conditional` or bound fill and symbol, and
/// a tone chosen by rule. It works on a document the shape has already validated, so a field it cannot read stops that value only.
///
/// The compiler keeps the one decoder per value and folds its diagnostics, source references and capability needs into the compile
/// (`absorb`). Nothing here knows the compiler's private state, so the hooks in `ServerUICompositionCompiler` stay a line or two each.
struct ServerUIRuleDecoder {
    typealias D = ServerUICompositionDocument

    /// The expression parser every operand and condition passes through; the compiler reads its references and needs afterwards.
    private(set) var parser = ServerUIExpressionParser()
    private(set) var issues: [ServerUICompositionError] = []
    /// Capabilities (without `sh.` and `@1`) the decoded values need.
    private(set) var needs: Set<String> = []

    var parserFacts: ServerUIExpressionParser { parser }

    // MARK: Strings

    /// A text slot of type `expr`: any operand that gives text, a number or a boolean, never a list or an object.
    mutating func expression(_ json: JSONValue, at pointer: String) -> ServerUICompositionDocument.StringValue? {
        needs.insert("rules")
        guard let raw = json["value"], let operand = parser.operand(raw, at: pointer + "/value") else { return nil }
        if ServerUIExpressionParser.kind(operand) == .structure { issues.append(.init(.bindingType, pointer + "/value")) }
        return .expression(operand, fallback: json["fallback"]?.string)
    }

    // MARK: Fills

    /// A fill slot: an exact fill (no rule), a `conditional` of exact fills, or a `bound-color` with an exact fallback.
    ///
    /// Returns the slot's own value (the `otherwise` or the fallback) and the rule that overrides it.
    mutating func fill(_ json: JSONValue, at pointer: String) -> (D.TileFill, ServerUIDynamicLook<D.TileFill>?)? {
        switch json["type"]?.string {
        case "conditional":
            needs.insert("rules")
            guard let otherwise = json["otherwise"].flatMap(Self.exactFill),
                  let cases = conditionalCases(json, at: pointer, then: Self.exactFill) else { return nil }
            return (otherwise, .conditional(cases))
        case "bound-color":
            needs.insert("rules")
            guard let operand = boundOperand(json, at: pointer), let fallback = json["fallback"].flatMap(Self.exactFill) else { return nil }
            return (fallback, .bound(operand))
        default:
            return Self.exactFill(json).map { ($0, nil) }
        }
    }

    // MARK: Symbols

    /// A symbol slot: an exact symbol, a `conditional` of symbols, or a `bound-symbol` with a fallback symbol.
    mutating func symbol(_ json: JSONValue, at pointer: String) -> (D.Symbol, ServerUIDynamicLook<D.Symbol>?)? {
        switch json["type"]?.string {
        case "conditional":
            needs.insert("rules"); needs.insert("symbols")
            guard let otherwise = json["otherwise"].flatMap(Self.exactSymbol),
                  let cases = conditionalCases(json, at: pointer, then: Self.exactSymbol) else { return nil }
            return (otherwise, .conditional(cases))
        case "bound-symbol":
            needs.insert("rules"); needs.insert("symbols")
            guard let operand = boundOperand(json, at: pointer), let fallback = json["fallback"].flatMap(Self.exactSymbol) else { return nil }
            return (fallback, .bound(operand))
        default:
            needs.insert("symbols")
            return Self.exactSymbol(json).map { ($0, nil) }
        }
    }

    // MARK: Tones

    /// A readout tone: one word, or a `conditional` whose cases each hold one.
    mutating func tone(_ json: JSONValue, at pointer: String) -> (D.StatusPill.Tone, [ServerUIConditional<D.StatusPill.Tone>.Case])? {
        if let word = json.string { return D.StatusPill.Tone(rawValue: word).map { ($0, []) } }
        needs.insert("rules")
        let tone: (JSONValue) -> D.StatusPill.Tone? = { $0.string.flatMap(D.StatusPill.Tone.init(rawValue:)) }
        guard let otherwise = json["otherwise"].flatMap(tone), let cases = conditionalCases(json, at: pointer, then: tone) else { return nil }
        return (otherwise, cases)
    }

    // MARK: Pieces

    /// The cases of a rule, each condition parsed as a document condition.
    private mutating func conditionalCases<Value: Equatable & Sendable>(
        _ json: JSONValue, at pointer: String, then: (JSONValue) -> Value?
    ) -> [ServerUIConditional<Value>.Case]? {
        guard let items = json["cases"]?.array else { return nil }
        var cases: [ServerUIConditional<Value>.Case] = []
        for (index, item) in items.enumerated() {
            let at = pointer + "/cases/\(index)"
            guard let raw = item["when"], let when = parser.predicate(raw, at: at + "/when"),
                  let value = item["then"].flatMap(then) else { continue }
            cases.append(.init(when: when, then: value))
        }
        return cases.count == items.count ? cases : nil
    }

    /// A bound color's or symbol's value: an operand that gives text.
    private mutating func boundOperand(_ json: JSONValue, at pointer: String) -> ServerUIOperand? {
        guard let raw = json["value"], let operand = parser.operand(raw, at: pointer + "/value") else { return nil }
        // The text an entity gives: a number, a boolean or a structure is not a color or a symbol name.
        if let kind = ServerUIExpressionParser.kind(operand), kind != .string { issues.append(.init(.bindingType, pointer + "/value")) }
        return operand
    }

    private static func exactFill(_ json: JSONValue) -> D.TileFill? {
        switch json["type"]?.string {
        case "standard": return .standard
        case "solid-rgb":
            guard let red = json["red"]?.number, let green = json["green"]?.number, let blue = json["blue"]?.number else { return nil }
            return .solidRGB(red: Int(red), green: Int(green), blue: Int(blue))
        default: return nil
        }
    }

    private static func exactSymbol(_ json: JSONValue) -> D.Symbol? {
        guard let name = json["name"]?.string, let rendering = json["rendering"]?.string.flatMap(D.Policy.init(rawValue:)),
              let unavailable = json["unavailable"]?.string.flatMap(D.Policy.init(rawValue:)) else { return nil }
        return D.Symbol(name: name, rendering: rendering, unavailable: unavailable)
    }
}
