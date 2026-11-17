import Foundation

// MARK: - Swipe to adjust (`sh.tile-swipe@1`)

/// What a tile says about adjusting a number by a horizontal drag (`sh.tile-swipe@1`). Absent means the tile has no recogniser, no adjustable
/// trait and no hint: it is the tile it always was.
///
/// The tile tracks the finger absolutely (the band's edge is where the finger is), sends one call when the finger lifts, and the bubble always
/// names the value the release will send (`.agents/patterns/tile-swipe.md`). The pure drag maths is `TileSwipe` in `HassDesign`.
public struct ServerUITileSwipe: Equatable, Sendable {
    /// The most steps a range may hold: 100 steps is 1.5 points of travel a step on the narrowest tile (150 points).
    public static let maximumSteps = 100
    /// The most detents (haptic ticks and VoiceOver steps) a range may hold: 6 points between ticks on the narrowest tile.
    public static let maximumDetents = 25

    /// The tiles that take a swipe.
    public enum Tile: Sendable { case lightGroup, state }

    /// The haptic spacing: a tick at each detent line, or none.
    public enum Haptic: String, Sendable, CaseIterable { case detent, none }

    /// The span the drag covers and the step it snaps to.
    public struct Range: Equatable, Sendable {
        public let min: Double
        public let max: Double
        public let step: Double

        /// Creates a range.
        public init(min: Double, max: Double, step: Double) {
            self.min = min
            self.max = max
            self.step = step
        }

        /// How many whole steps the range holds, tolerating the float noise of decimals (0.5 over 60 to 85 is 50).
        public var steps: Double { ((max - min) / step * 1e6).rounded() / 1e6 }
    }

    /// The range.
    public let range: Range
    /// The number the tile shows now. A state tile's own; a light group tile's source owns it.
    public var value: ServerUIOperand?
    /// The call a release sends, whose `control` carries the committed number. A light group tile's source owns it.
    public var action: ServerUICallService?
    /// The authored detent; `nil` takes ``detent``'s default.
    public var authoredDetent: Double?
    /// The haptic spacing.
    public var haptic: Haptic = .detent
    /// Whether the tile draws its band, at rest and in a drag. The bubble is always drawn.
    public var showsBand = true
    /// The bubble and spoken value, with `{value}` for the number. Absent on a light group tile, whose words are its own.
    public var format: String?
    /// What is adjusted, for VoiceOver ("Swipe up or down to adjust position."). A light group tile is fixed to "brightness".
    public var label: String?

    /// Creates a swipe.
    public init(range: Range) { self.range = range }

    /// The default detent: a tenth of the span, rounded up to a multiple of `step`.
    public static func defaultDetent(_ range: Range) -> Double {
        let raw = (range.max - range.min) / 10
        return ((raw / range.step - 1e-9).rounded(.up)) * range.step
    }

    /// The detent in force: the authored one, else the default.
    public var detent: Double { authoredDetent ?? Self.defaultDetent(range) }

    /// One problem the shape of a swipe has that the document's grammar cannot say, as a code at a pointer below `props/swipe`.
    struct Problem: Equatable {
        let code: ServerUICompositionError.Code
        let at: String
    }

    /// The checks of the range, the detent and the fields that belong to one tile type only. The checks that need the call or the value operand
    /// (the call uses `control`, asks nothing first, the value is a number) are the compiler's.
    static func problems(range: Range, detent: Double?, format: String?, present: Set<String>, tile: Tile) -> [Problem] {
        var found: [Problem] = []
        let span = range.max - range.min
        if !(range.min < range.max) { found.append(.init(code: .invalidValue, at: "/range/max")) } else if !(range.step > 0) {
            found.append(.init(code: .invalidValue, at: "/range/step"))
        } else {
            if range.steps > Double(maximumSteps) { found.append(.init(code: .limitExceeded, at: "/range/step")) }
            if let detent {
                if !(detent > 0) || detent > span + 1e-9 || !isMultiple(detent, of: range.step) {
                    found.append(.init(code: .invalidValue, at: "/detent"))
                } else if span / detent > Double(maximumDetents) + 1e-6 {
                    found.append(.init(code: .limitExceeded, at: "/detent"))
                }
            }
        }
        if let format, formatProblem(format) { found.append(.init(code: .invalidValue, at: "/format")) }
        switch tile {
        case .lightGroup:
            for key in ["value", "action", "format", "label"] where present.contains(key) { found.append(.init(code: .invalidCombination, at: "/\(key)")) }
            if range.min != 0 || range.max != 100 || range.step != 1 { found.append(.init(code: .invalidValue, at: "/range")) }
        case .state:
            for key in ["value", "action", "label"] where !present.contains(key) { found.append(.init(code: .missingRequired, at: "/\(key)")) }
        }
        return found
    }

    /// Whether `value` is a multiple of `step`, tolerating float noise.
    static func isMultiple(_ value: Double, of step: Double) -> Bool {
        abs(value / step - (value / step).rounded()) < 1e-6
    }

    /// Whether a bubble format is refused: it must hold `{value}` and no other token.
    static func formatProblem(_ format: String) -> Bool {
        let tokens = ServerUIStateWords.tokens(in: format)
        if tokens.isEmpty || tokens.contains(where: { $0 != "{value}" }) { return true }
        return format.replacingOccurrences(of: "{value}", with: "").contains { $0 == "{" || $0 == "}" }
    }
}
