import CoreGraphics
import Foundation

/// Geometry of the 270° thermostat ring, ported from the web dial
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/circularDialGeometry.ts`).
///
/// The ring opens at the bottom: the minimum sits at 7:30 and the maximum at 4:30, sweeping clockwise.
/// Angles use SwiftUI's convention (0° points right, positive is clockwise because y grows downward).
public struct ThermostatDialGeometry: Equatable, Sendable {
    // MARK: - Constants

    /// Degrees the ring covers.
    public static let sweepDegrees: Double = 270
    /// Angle of the minimum value (web: -225°).
    public static let startDegrees: Double = 135
    /// Ring radius as a fraction of the dial's side (web: 145 / 320).
    public static let ringRadiusRatio: Double = 145.0 / 320.0
    /// Touch target around the ring and each handle (web: 64 px).
    public static let hitTarget: CGFloat = 64

    // MARK: - Inputs

    /// Smallest selectable value.
    public var min: Double
    /// Largest selectable value.
    public var max: Double
    /// Value increment (Home Assistant `target_temp_step`).
    public var step: Double

    /// Creates the geometry. A non-positive span or step falls back to a usable range.
    public init(min: Double, max: Double, step: Double) {
        self.min = min
        self.max = max > min ? max : min + 1
        self.step = step > 0 ? step : 0.5
    }

    // MARK: - Value ↔ angle

    /// Where `value` falls along the ring, from 0 (min) to 1 (max), clamped.
    public func fraction(of value: Double) -> Double {
        Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }

    /// The ring angle of `value`, in degrees.
    public func degrees(for value: Double) -> Double {
        Self.startDegrees + fraction(of: value) * Self.sweepDegrees
    }

    /// The point on the ring for `value`, in a square dial of side `side`.
    public func point(for value: Double, side: CGFloat) -> CGPoint {
        let radians = degrees(for: value) * .pi / 180
        let radius = Double(side) * Self.ringRadiusRatio
        let center = Double(side) / 2
        return CGPoint(x: center + cos(radians) * radius, y: center + sin(radians) * radius)
    }

    /// The unsnapped value under `point` (web `circularDialRawValueFromPoint`). Touches in the bottom gap
    /// snap to the nearer end.
    public func rawValue(at point: CGPoint, side: CGFloat) -> Double {
        guard side > 0 else { return min }
        let x = Double(2 * point.x / side - 1)
        let y = Double(2 * point.y / side - 1)
        let degrees = atan2(y, x) * 180 / .pi
        let angle = (degrees + 270).truncatingRemainder(dividingBy: 360) - 45
        let fraction = Swift.min(Swift.max(angle / Self.sweepDegrees, 0), 1)
        return rounded(min + (max - min) * fraction)
    }

    /// The value under `point`, snapped to ``step``.
    public func value(at point: CGPoint, side: CGFloat) -> Double {
        snapped(rawValue(at: point, side: side))
    }

    /// `value` snapped to the nearest ``step`` from ``min`` and clamped to the range.
    public func snapped(_ value: Double) -> Double {
        let stepped = min + ((value - min) / step).rounded() * step
        return rounded(Swift.min(Swift.max(stepped, min), max))
    }

    /// Whether `point` is within half a hit target of the ring (web `circularDialPointIsOnRing`).
    public func isOnRing(_ point: CGPoint, side: CGFloat, hitTarget: CGFloat = hitTarget) -> Bool {
        guard side > 0 else { return false }
        let distance = hypot(point.x - side / 2, point.y - side / 2)
        return abs(distance - side * CGFloat(Self.ringRadiusRatio)) <= hitTarget / 2
    }

    // MARK: - Private

    /// Trims floating-point noise the way the web's `toFixed(3)` does.
    private func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}
