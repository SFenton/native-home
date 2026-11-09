import CoreGraphics
@testable import HassDesign
import Testing

/// Parity with `ha-sfenton-react-dash@9ac2a46:src/components/hass/circularDialGeometry.ts`.
struct ThermostatDialGeometryTests {
    let geometry = ThermostatDialGeometry(min: 45, max: 95, step: 0.5)

    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 }

    @Test func endsAndMiddleSitWhereTheWebDrawsThem() {
        // Web: min at (17.96%, 82.04%), max at (82.04%, 82.04%), middle at top centre, on a 320 viewBox.
        #expect(close(geometry.point(for: 45, side: 320), CGPoint(x: 57.47, y: 262.53)))
        #expect(close(geometry.point(for: 95, side: 320), CGPoint(x: 262.53, y: 262.53)))
        #expect(close(geometry.point(for: 70, side: 320), CGPoint(x: 160, y: 15)))
        #expect(geometry.degrees(for: 45) == 135)
        #expect(geometry.degrees(for: 95) == 405)
    }

    @Test func valuesOutsideTheRangeClampToTheEnds() {
        #expect(geometry.fraction(of: 20) == 0)
        #expect(geometry.fraction(of: 120) == 1)
        #expect(geometry.fraction(of: 70) == 0.5)
    }

    @Test func pointsMapBackToValues() {
        #expect(geometry.rawValue(at: CGPoint(x: 160, y: 0), side: 320) == 70)
        #expect(geometry.value(at: CGPoint(x: 320, y: 160), side: 320) == 86.5)
        for value in stride(from: 45.0, through: 95.0, by: 0.5) {
            #expect(geometry.value(at: geometry.point(for: value, side: 300), side: 300) == value)
        }
    }

    @Test func theBottomGapSnapsToTheNearerEnd() {
        #expect(geometry.value(at: CGPoint(x: 155, y: 320), side: 320) == 45)
        #expect(geometry.value(at: CGPoint(x: 165, y: 320), side: 320) == 95)
    }

    @Test func snappingFollowsTheStepAndClamps() {
        #expect(geometry.snapped(72.26) == 72.5)
        #expect(geometry.snapped(72.24) == 72)
        #expect(geometry.snapped(100) == 95)
        #expect(geometry.snapped(10) == 45)
        let celsius = ThermostatDialGeometry(min: 7, max: 35, step: 0.1)
        #expect(celsius.snapped(21.04) == 21)
        #expect(celsius.snapped(21.06) == 21.1)
    }

    @Test func onlyTheRingBandAcceptsTouches() {
        #expect(geometry.isOnRing(CGPoint(x: 160, y: 15), side: 320))
        #expect(geometry.isOnRing(CGPoint(x: 160, y: 15 + 32), side: 320))
        #expect(!geometry.isOnRing(CGPoint(x: 160, y: 15 + 33), side: 320))
        #expect(!geometry.isOnRing(CGPoint(x: 160, y: 160), side: 320))
        #expect(!geometry.isOnRing(.zero, side: 0))
    }

    @Test func degenerateInputsStayUsable() {
        let broken = ThermostatDialGeometry(min: 70, max: 60, step: 0)
        #expect(broken.max == 71)
        #expect(broken.step == 0.5)
        #expect(broken.rawValue(at: .zero, side: 0) == 70)
    }
}
