import CoreGraphics
import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// The area editor's drag jobs and VoiceOver edits, without gestures.
@Suite(.demoHouse)
struct MapAreaEditTests {
    let g = MapStageGeometry(map: ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId), mapScale: 1.2)
    let frame = CGSize(width: 359, height: 420)
    let area = MapGridRect(x0: 600, x1: 620, y0: 700, y1: 720)

    private func update(_ gesture: MapAreaEdit.Gesture, to current: MapPoint, at location: CGPoint = .zero) -> MapAreaEdit.Step {
        MapAreaEdit.update(gesture, current: current, location: location, stage: g, interaction: g, frame: frame, rotation: 0, minimum: 5)
    }

    @Test func drawModeAlwaysDraws() {
        let start = MapPoint(x: 610, y: 710)
        #expect(MapAreaEdit.begin(start: start, location: .zero, drawMode: true, area: area, corner: .a, viewport: .initial)
            == .draw(anchor: start), "draw wins even over a handle")
        let step = update(.draw(anchor: .init(x: 600, y: 700)), to: .init(x: 602, y: 701))
        #expect(step.draft == .init(x0: 600, x1: 605, y0: 700, y1: 705), "the minimum side applies")
        #expect(step.viewport == nil)
    }

    @Test func aHandleResizesAndTheInsideMoves() {
        #expect(MapAreaEdit.begin(start: .init(x: 600, y: 700), location: .zero, drawMode: false, area: area, corner: .a, viewport: .initial)
            == .resize(corner: .a, origin: area))
        let inside = MapPoint(x: 610, y: 710)
        let move = MapAreaEdit.begin(start: inside, location: .zero, drawMode: false, area: area, corner: nil, viewport: .initial)
        #expect(move == .move(origin: area, start: inside))
        #expect(update(move, to: .init(x: 615, y: 703)).draft == .init(x0: 605, x1: 625, y0: 693, y1: 713))
        #expect(update(.resize(corner: .c, origin: area), to: .init(x: 625, y: 725)).draft == .init(x0: 600, x1: 625, y0: 700, y1: 725))
    }

    @Test func outsideTheAreaOrWithoutOneThePanMoves() {
        let start = CGPoint(x: 100, y: 100)
        let outside = MapAreaEdit.begin(start: .init(x: 700, y: 900), location: start, drawMode: false, area: area, corner: nil, viewport: .initial)
        #expect(outside == .pan(origin: .initial, start: start))
        #expect(MapAreaEdit.begin(start: .init(x: 610, y: 710), location: start, drawMode: false, area: nil, corner: nil, viewport: .initial)
            == .pan(origin: .initial, start: start))
        let zoomed = MapViewport(zoom: 3)
        let step = update(.pan(origin: zoomed, start: start), to: .init(x: 0, y: 0), at: .init(x: 130, y: 80))
        #expect(step.draft == nil)
        #expect(step.viewport == .init(panX: 30, panY: -20, zoom: 3))
        let far = update(.pan(origin: .initial, start: start), to: .init(x: 0, y: 0), at: .init(x: 10_000, y: 100))
        #expect((far.viewport?.panX ?? 0) < 9_900, "panning is clamped to keep the map on screen")
    }

    @Test func voiceOverNudgesStepByHalfTheMinimum() {
        func nudge(_ n: MapAreaEdit.Nudge, minimum: Double = 10) -> MapGridRect {
            MapAreaEdit.nudge(area, n, interaction: g, minimum: minimum)
        }
        #expect(nudge(.left) == .init(x0: 595, x1: 615, y0: 700, y1: 720))
        #expect(nudge(.right) == .init(x0: 605, x1: 625, y0: 700, y1: 720))
        #expect(nudge(.up) == .init(x0: 600, x1: 620, y0: 695, y1: 715))
        #expect(nudge(.down) == .init(x0: 600, x1: 620, y0: 705, y1: 725))
        #expect(nudge(.larger) == .init(x0: 600, x1: 625, y0: 700, y1: 725))
        #expect(nudge(.smaller) == .init(x0: 600, x1: 615, y0: 700, y1: 715))
        #expect(nudge(.left, minimum: 1) == .init(x0: 598, x1: 618, y0: 700, y1: 720), "at least two cells")
        #expect(MapAreaEdit.Nudge.allCases.map(\.title) == ["Move area left", "Move area right", "Move area up", "Move area down",
                                                           "Make area larger", "Make area smaller"])
    }

    @Test func voiceOverDrawStartsFromACentredArea() {
        let start = MapAreaEdit.voiceOverStart(g, minimum: 5)
        #expect(start == MapGeometry.defaultRect(g, size: 30))
        let big = MapAreaEdit.voiceOverStart(g, minimum: 40)
        #expect(big.x1 - big.x0 == 40)
    }
}
