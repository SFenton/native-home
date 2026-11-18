import CoreGraphics
import Foundation

// MARK: - Swipe to adjust: the pure maths

/// The maths of swiping a tile to adjust a number (`sh.tile-swipe@1`, `.agents/patterns/tile-swipe.md`): where the finger is as a value, the snap,
/// the clamp, the right-to-left mirror, the detent lines that tick, the step of VoiceOver's increment, and the bubble's text, size and place.
///
/// It generalises ``BrightnessTile``'s percent maths (0 to 100 by 1, a tick every 10) to any range. It takes plain numbers, so `HassDesign`
/// needs no `HassCore`; the document's own type is `ServerUITileSwipe`.
public struct TileSwipe: Equatable, Sendable {
    /// The smallest value.
    public let min: Double
    /// The largest value.
    public let max: Double
    /// The step the value snaps to.
    public let step: Double
    /// The spacing of the haptic ticks and of VoiceOver's increment and decrement: a multiple of ``step``.
    public let detent: Double

    private static let epsilon = 1e-9

    /// Creates a swipe over `min...max` by `step`, ticking every `detent`.
    public init(min: Double, max: Double, step: Double, detent: Double) {
        self.min = min
        self.max = max
        self.step = step
        self.detent = detent
    }

    /// The brightness swipe of a light: 0 to 100 by 1, a tick every 10.
    public static let brightness = TileSwipe(min: 0, max: 100, step: 1, detent: 10)

    /// The distance between the ends.
    public var span: Double { max - min }

    // MARK: Mapping

    /// `value` pulled into the range and snapped to the step.
    public func snapped(_ value: Double) -> Double {
        let clamped = Swift.min(max, Swift.max(min, value))
        let steps = ((clamped - min) / step).rounded()
        let snapped = Swift.min(max, min + steps * step)
        return (snapped * 1e6).rounded() / 1e6
    }

    /// The value for a touch at `x` across a tile `width` wide. Absolute: the finger is the band's edge. In a right-to-left layout the map
    /// mirrors, so the minimum stays on the leading edge (HIG Right to left: flip progress controls).
    public func value(atX x: CGFloat, width: CGFloat, isRightToLeft: Bool = false) -> Double {
        guard width > 0 else { return min }
        var fraction = Double(x / width)
        if isRightToLeft { fraction = 1 - fraction }
        fraction = Swift.min(1, Swift.max(0, fraction))
        return snapped(min + fraction * span)
    }

    /// Where `value` sits in the range, 0 to 1 from the minimum.
    public func fraction(of value: Double) -> Double {
        guard span > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (value - min) / span))
    }

    /// The x of the band's edge for `value` across a tile `width` wide, mirrored in a right-to-left layout.
    public func edge(of value: Double, width: CGFloat, isRightToLeft: Bool = false) -> CGFloat {
        let fraction = CGFloat(fraction(of: value))
        return width * (isRightToLeft ? 1 - fraction : fraction)
    }

    // MARK: Detents

    /// The detent lines, the two ends included: `min + k * detent`, then `max` when the last line falls short of it.
    public var lines: [Double] {
        guard detent > 0, span > 0 else { return [min] }
        var found: [Double] = []
        var line = min
        while line < max - Self.epsilon {
            found.append((line * 1e6).rounded() / 1e6)
            line += detent
        }
        found.append(max)
        return found
    }

    /// The number of the last line at or below `value`.
    public func lineIndex(of value: Double) -> Int {
        let all = lines
        return all.lastIndex { $0 <= value + Self.epsilon } ?? 0
    }

    /// Whether moving from `previous` to `value` crosses a detent line, in either direction. `nil` (the first sample) never does.
    public func crossesDetent(from previous: Double?, to value: Double) -> Bool {
        guard let previous else { return false }
        return lineIndex(of: previous) != lineIndex(of: value)
    }

    /// The value one detent up or down from `value`, clamped to the range and snapped: VoiceOver's increment and decrement.
    public func adjusted(_ value: Double, up: Bool) -> Double {
        snapped(value + (up ? detent : -detent))
    }

    // MARK: Release

    /// The value a release sends: `nil` when the drag ended where the tile already shows (`shown`), so nothing is sent.
    public func commit(_ value: Double, shown: Double) -> Double? {
        abs(value - shown) < Self.epsilon ? nil : value
    }

    // MARK: Words

    /// The number as the bubble writes it: whole numbers plain, a step with decimals to its own digits.
    public func formatted(_ value: Double) -> String {
        let digits = Swift.max(Self.decimals(step), Self.decimals(min))
        return String(format: "%.\(digits)f", value)
    }

    /// The bubble's text: `format` with `{value}` replaced, else the plain number. A light's bubble reads `zeroWord` ("Off") at the minimum.
    public func bubbleText(_ value: Double, format: String?, zeroWord: String? = nil) -> String {
        if let zeroWord, value <= min + Self.epsilon { return zeroWord }
        let number = formatted(value)
        guard let format else { return number }
        return format.replacingOccurrences(of: "{value}", with: number)
    }

    private static func decimals(_ value: Double) -> Int {
        for digits in 0...3 where abs(value * pow(10, Double(digits)) - (value * pow(10, Double(digits))).rounded()) < 1e-6 { return digits }
        return 3
    }
}

// MARK: - The bubble

/// The bubble that names the value a release will send (`.agents/patterns/tile-swipe.md`, "Swipe to adjust", the bubble bullets): a capsule over the band's edge, never under
/// the finger. These are the numbers the Studio uses for its "word does not fit" warning.
public enum TileSwipeBubble {
    /// The metrics of one text size.
    public struct Metrics: Equatable, Sendable {
        /// The capsule's height.
        public let height: CGFloat
        /// The capsule's least width, wide enough for "100%".
        public let minimumWidth: CGFloat
        /// The space before and after the text.
        public let horizontalPadding: CGFloat
        /// How far above the tile's top edge the capsule's centre sits; the capsule stays 8 pt clear of the tile.
        public let lift: CGFloat
    }

    /// Regular text sizes: today's 60 by 32 capsule, its centre 24 pt above the tile.
    public static let regular = Metrics(height: 32, minimumWidth: 60, horizontalPadding: 12, lift: 24)
    /// Accessibility text sizes: 44 pt tall, 84 pt wide at least, the centre 30 pt up so the gap stays 8 pt.
    public static let accessibility = Metrics(height: 44, minimumWidth: 84, horizontalPadding: 12, lift: 30)

    /// The least space kept between the capsule and the top of the visible scroll area.
    public static let topInset: CGFloat = 4

    /// The metrics for a text size.
    public static func metrics(isAccessibilitySize: Bool) -> Metrics { isAccessibilitySize ? accessibility : regular }

    /// The capsule's width for text `textWidth` wide: the least width up to the tile's width.
    public static func width(textWidth: CGFloat, tileWidth: CGFloat, metrics: Metrics) -> CGFloat {
        Swift.min(Swift.max(tileWidth, 0), Swift.max(metrics.minimumWidth, textWidth + 2 * metrics.horizontalPadding))
    }

    /// The capsule's centre across the tile: over the band's edge, kept whole inside the tile. At the ends it sits flush with the tile's edge.
    public static func centerX(edge: CGFloat, tileWidth: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        guard tileWidth > bubbleWidth else { return tileWidth / 2 }
        return Swift.min(tileWidth - bubbleWidth / 2, Swift.max(bubbleWidth / 2, edge))
    }

    /// How far to move the capsule down so it stays ``topInset`` inside the top of the scroll area, 0 when it already does.
    ///
    /// `tileTop` is the tile's top edge measured from the top of the visible area. The capsule never flips below the tile, where the hand is.
    public static func topShift(tileTop: CGFloat, metrics: Metrics) -> CGFloat {
        let top = tileTop - metrics.lift - metrics.height / 2
        return Swift.max(0, topInset - top)
    }
}

// MARK: - Where a drag starts

/// Whether a drag that is about to begin on a tile is the tile's swipe or the page's scroll (`.agents/patterns/tile-swipe.md`, "Not the swipe": a vertical start is the scroll's).
///
/// The recognizer asks as it is about to begin, with what it has seen of the touch so far. Velocity alone is the least reliable of the two: it
/// is read from the last few samples, so a first sample that leans sideways (a coarse driver, a pointer, a stylus, a stutter at touch down) can
/// say "horizontal" about a stroke that has gone up the page at 60 degrees. The way the finger has travelled since it went down is the stroke's
/// own shape. Both must agree before a tile takes the drag, so a steeper-than-diagonal stroke is always the scroll's.
public enum TileSwipeStart {
    /// Least travel, in points, before the translation says anything: a touch that has not moved yet is judged by its velocity alone.
    public static let travelFloor: CGFloat = 1

    /// Whether a tile's swipe may begin for a drag `translation` points from where the finger went down and moving at `velocity`.
    ///
    /// A drag begins as a swipe only when it is wider than it is tall by both measures (45 degrees is the line); the page's scroll takes the
    /// rest. A drag with no velocity at all never begins.
    public static func isHorizontal(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard abs(velocity.x) > abs(velocity.y) else { return false }
        let travelled = max(abs(translation.x), abs(translation.y))
        return travelled < travelFloor || abs(translation.x) > abs(translation.y)
    }
}
