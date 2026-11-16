import CoreGraphics
import Foundation
@testable import HassCore
import HassTestSupport
import Testing

// MARK: - Flipping a map

/// `sh.surface-orientation@1`: the flip follows the rotation, in screen space, through the one matrix.
@Suite(.demoHouse)
struct MapOrientationTests {
    let g = MapStageGeometry(map: ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId), mapScale: 1.2)
    let frame = CGSize(width: 359, height: 420)
    let both = MapOrientation(flipHorizontal: true, flipVertical: true)
    let horizontal = MapOrientation(flipHorizontal: true)
    let vertical = MapOrientation(flipVertical: true)

    private func matrix(_ flip: MapOrientation, rotation: Double = 0, viewport: MapViewport = .initial) -> Affine {
        MapGeometry.matrix(g, frame: frame, viewport: viewport, rotation: rotation, flip: flip)
    }

    private func close(_ a: MapPoint, _ b: MapPoint, _ tolerance: Double = 1e-6) -> Bool { abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance }

    @Test func noFlipIsTheMatrixItWas() {
        for rotation in [0.0, 90, 180, 33] {
            #expect(matrix(.none, rotation: rotation) == MapGeometry.matrix(g, frame: frame, viewport: .initial, rotation: rotation))
        }
        #expect(!MapOrientation.none.flips && horizontal.flips && vertical.flips && both.flips)
    }

    @Test func aHorizontalFlipMirrorsAboutTheCentreOfTheFrameAndKeepsTheRows() {
        let plain = matrix(.none), flipped = matrix(horizontal)
        for point in [MapPoint(x: 0, y: 0), .init(x: g.width, y: 0), .init(x: g.width / 3, y: g.height * 0.7)] {
            let a = plain.apply(point), b = flipped.apply(point)
            #expect(close(b, .init(x: Double(frame.width) - a.x, y: a.y)), "x mirrors about the frame's centre, y stays")
        }
    }

    @Test func aVerticalFlipMirrorsTopToBottom() {
        let plain = matrix(.none), flipped = matrix(vertical)
        let point = MapPoint(x: g.width * 0.2, y: g.height * 0.1)
        let a = plain.apply(point), b = flipped.apply(point)
        #expect(close(b, .init(x: a.x, y: Double(frame.height) - a.y)))
    }

    @Test func bothFlipsEqualAHalfTurn() {
        let flipped = matrix(both), turned = matrix(.none, rotation: 180)
        for point in [MapPoint(x: 0, y: 0), .init(x: g.width / 2, y: g.height / 5)] {
            #expect(close(flipped.apply(point), turned.apply(point)))
        }
    }

    @Test func theFlipIsLeftToRightOnScreenWhateverTheRotation() {
        // Rotation first, then the flip: a quarter turn with a horizontal flip is the quarter turn mirrored left to right on screen.
        let rotated = matrix(.none, rotation: 90), flipped = matrix(horizontal, rotation: 90)
        let point = MapPoint(x: g.width * 0.3, y: g.height * 0.8)
        let a = rotated.apply(point), b = flipped.apply(point)
        #expect(close(b, .init(x: Double(frame.width) - a.x, y: a.y)))
    }

    @Test func aFlipChangesNeitherTheScaleNorTheFit() {
        #expect(abs(matrix(both).scale - matrix(.none).scale) < 1e-9)
        #expect(abs(matrix(horizontal, rotation: 90).scale - matrix(.none, rotation: 90).scale) < 1e-9)
    }

    @Test func panStaysInScreenPoints() {
        let panned = matrix(horizontal, viewport: .init(panX: 20, panY: -10, zoom: 1))
        let still = matrix(horizontal)
        let point = MapPoint(x: 5, y: 5)
        #expect(close(panned.apply(point), .init(x: still.apply(point).x + 20, y: still.apply(point).y - 10)), "a pan to the right moves a flipped map right")
    }

    @Test func theInverseHoldsForANegativeDeterminant() {
        for flip in [horizontal, vertical, both] {
            let m = matrix(flip, rotation: 90, viewport: .init(panX: 7, panY: 3, zoom: 2))
            for point in [MapPoint(x: 10, y: 20), .init(x: g.width / 2, y: g.height / 2)] {
                #expect(close(m.inverted.apply(m.apply(point)), point, 1e-6))
            }
        }
        let m = matrix(horizontal)
        #expect(m.a * m.d - m.b * m.c < 0, "one flip reverses the orientation")
        let n = matrix(both)
        #expect(n.a * n.d - n.b * n.c > 0, "two flips are a turn")
    }

    @Test func aTapLandsOnTheCellItWasDrawnOver() {
        // The grid point under a frame point, through the inverse, is the point that was drawn there: hit-testing follows the flip.
        let flip = horizontal
        let m = matrix(flip)
        let grid = MapPoint(x: g.minGridX + g.width * 0.25, y: g.minGridY + g.height * 0.5)
        let frameAt = MapGeometry.framePoint(g, matrix: m, gridPoint: grid)
        let back = MapGeometry.gridPoint(g, matrix: m, framePoint: frameAt)
        #expect(close(back, grid))
        let plainAt = MapGeometry.framePoint(g, matrix: matrix(.none), gridPoint: grid)
        #expect(frameAt.x > Double(frame.width) / 2 && plainAt.x < Double(frame.width) / 2, "the left quarter of the map is drawn on the right")
    }

    @Test func clampAndViewportFollowTheFlip() {
        let far = MapViewport(panX: 10_000, panY: 0, zoom: 3)
        let clamped = MapGeometry.clamp(g, frame: frame, viewport: far, rotation: 0, flip: horizontal)
        #expect(clamped.panX < 10_000)
        let zoomed = MapGeometry.viewport(g, frame: frame, anchor: .init(x: g.width / 2, y: g.height / 2), at: .init(x: 100, y: 100), zoom: 2, rotation: 0, flip: both)
        let rendered = MapGeometry.matrix(g, frame: frame, viewport: zoomed, rotation: 0, flip: both).apply(.init(x: g.width / 2, y: g.height / 2))
        #expect(close(rendered, .init(x: 100, y: 100), 1e-3) || zoomed.panX != 0, "the anchor stays under the point, unless the clamp moved it")
    }

    @Test func aScreenStepIsAGridStepThroughTheInverseLinearPart() {
        let identity = MapGeometry.gridStep(matrix: .identity, screen: .init(x: -4, y: 2))
        #expect(identity == .init(x: -4, y: 2))
        let flipped = MapGeometry.gridStep(matrix: matrix(horizontal), screen: .init(x: 4, y: 0))
        #expect(flipped.x < 0 && abs(flipped.y) < 1e-9, "screen right is grid left on a mirrored map")
        let upsideDown = MapGeometry.gridStep(matrix: matrix(vertical), screen: .init(x: 0, y: 4))
        #expect(upsideDown.y < 0 && abs(upsideDown.x) < 1e-9)
        let quarter = MapGeometry.gridStep(matrix: matrix(.none, rotation: 90), screen: .init(x: 4, y: 0))
        #expect(abs(quarter.x) < 1e-9 && abs(quarter.y) > 0)
    }

    @Test func theAreaEditorMovesMeanScreenDirections() {
        let area = MapGridRect(x0: 600, x1: 620, y0: 700, y1: 720)
        func nudge(_ n: MapAreaEdit.Nudge, _ flip: MapOrientation) -> MapGridRect {
            MapAreaEdit.nudge(area, n, interaction: g, minimum: 10, screen: matrix(flip))
        }
        #expect(nudge(.left, .none) == .init(x0: 595, x1: 615, y0: 700, y1: 720), "no flip: grid directions, as before")
        #expect(nudge(.left, horizontal) == .init(x0: 605, x1: 625, y0: 700, y1: 720), "flipped: left on screen is grid right")
        #expect(nudge(.up, vertical) == .init(x0: 600, x1: 620, y0: 705, y1: 725))
        #expect(nudge(.up, horizontal) == .init(x0: 600, x1: 620, y0: 695, y1: 715), "the other axis is not mirrored")
        #expect(nudge(.larger, both) == MapAreaEdit.nudge(area, .larger, interaction: g, minimum: 10), "size edits grow the grid corner")
        // The drag clamp follows the flip too.
        let pan = MapAreaEdit.update(.pan(origin: .init(zoom: 3), start: .zero), current: .init(x: 0, y: 0), location: .init(x: 10_000, y: 0), stage: g,
                                     interaction: g, frame: frame, rotation: 0, flip: horizontal, minimum: 5)
        #expect((pan.viewport?.panX ?? 0) < 9_900)
    }

    @Test func theDescriptorCarriesTheFlipToTheConfiguration() throws {
        let plain = try ServerUIVacuumTests.descriptor()
        #expect(plain.orientation == nil && plain.configuration.mapOrientation == nil)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        json["orientation"] = ["flipHorizontal": true, "flipVertical": false]
        let flipped = try JSONDecoder().decode(ServerUIVacuumDescriptor.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(flipped.configuration.mapOrientation == MapOrientation(flipHorizontal: true, flipVertical: false))
    }
}
