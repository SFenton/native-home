import CoreGraphics
import Foundation
@testable import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// How a Valetudo map becomes pixels and room hit-targets for the vacuum page: the cell image, the selectable-room masks, the
/// focused view and the tap-to-room mapping.
@Suite(.demoHouse)
struct ValetudoMapSceneTests {
    private func rectangle(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> [Int32] {
        var cells: [Int32] = []
        for y in minY...maxY { for x in minX...maxX { cells += [Int32(x), Int32(y)] } }
        return cells
    }

    /// The Music Room, the Hallway and an unnamed segment, inside a wall ring, on a floor.
    private func map(entities: [ValetudoMap.Entity] = []) -> ValetudoMap {
        ValetudoMap(
            layers: [
                .init(type: "floor", pixels: rectangle(18, 37, 18, 37)),
                .init(type: "wall", pixels: rectangle(19, 36, 19, 19) + rectangle(19, 36, 36, 36)),
                .init(type: "segment", pixels: rectangle(20, 30, 20, 30), name: "Studio", segmentId: "3"),
                .init(type: "segment", pixels: rectangle(31, 35, 24, 30), name: "Downstairs Hallway", segmentId: "10"),
                .init(type: "segment", pixels: rectangle(0, 3, 0, 3), segmentId: "4"),
                .init(type: "segment", pixels: [], segmentId: "5"),
            ],
            entities: entities, pixelSize: 5, size: (500, 500))
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return bytes
    }

    @Test func theSceneRasterisesTheCellsAndKeepsAMaskForEachSelectableRoom() throws {
        let scene = ValetudoMapScene(map: map(), vacuum: Vacuums.musicRoom, provenance: .live)
        let cells = try #require(scene.cells)
        #expect(cells.width == Int(scene.geometry.width.rounded(.up)) && cells.height == Int(scene.geometry.height.rounded(.up)))
        #expect(scene.rotation == Vacuums.musicRoom.mapRotationDegrees)
        #expect(scene.provenance == .live)
        #expect(!scene.rooms.isEmpty && scene.masks.count == scene.rooms.count)
        for room in scene.rooms {
            let mask = try #require(scene.masks[room.entityId])
            #expect(mask.gridBounds.width * mask.gridBounds.height >= CGFloat(room.cells.count))
            #expect(mask.image.width == Int(mask.gridBounds.width))
        }
        #expect(scene.aspectRatio > 0)
    }

    @Test func aRoomIsFilledWithItsPaletteColourAndTheGroundIsLeftTransparent() throws {
        let scene = ValetudoMapScene(map: map(), vacuum: Vacuums.musicRoom, provenance: .live)
        let cells = try #require(scene.cells)
        let minX = Int(scene.geometry.minGridX), minY = Int(scene.geometry.minGridY)
        let inRoom = pixel(cells, 25 - minX, 25 - minY)
        let expected = ValetudoMapScene.Palette.room(0)
        #expect(inRoom[3] == 255)
        #expect(abs(Int(inRoom[0]) - Int((expected.red * 255).rounded())) <= 1)
        let wall = pixel(cells, 25 - minX, 19 - minY)
        #expect(wall[3] == 255 && wall[0] == UInt8((ValetudoMapScene.Palette.wall.red * 255).rounded()))
        #expect(pixel(cells, 0, 0)[3] == 255, "Cell 18,18 is floor")
        #expect(ValetudoMapScene.Palette.room(10).red == ValetudoMapScene.Palette.room(0).red, "The ramp cycles")
    }

    @Test func tappingARoomFindsItAndTappingOutsideFindsNone() throws {
        let scene = ValetudoMapScene(map: map(), vacuum: Vacuums.musicRoom, provenance: .live)
        let size = CGSize(width: 400, height: 400)
        let music = try #require(scene.rooms.first { $0.title.contains("Studio") })
        let matrix = scene.matrix(size: size, viewport: .initial)
        let frame = matrix.apply(.init(x: 25.5 - scene.geometry.minGridX, y: 25.5 - scene.geometry.minGridY))
        let hit = scene.room(at: CGPoint(x: frame.x, y: frame.y), size: size)
        #expect(hit?.entityId == music.entityId)
        #expect(scene.room(at: CGPoint(x: 1, y: 1), size: size) == nil)
    }

    @Test func aVacuumWithoutRoomSelectionHasNoRoomsOrMasks() {
        let scene = ValetudoMapScene(map: map(), vacuum: Vacuums.theaterRoom, provenance: .reported)
        #expect(scene.rooms.isEmpty && scene.masks.isEmpty && scene.provenance == .reported)
    }

    @Test func aFocusedMapDropsTheSegmentsOutsideTheFocusAndTheWallsAwayFromIt() throws {
        let focused = ValetudoMapScene(map: map(entities: [.init(type: "robot_position", points: [125, 125])]),
                                       vacuum: Vacuums.musicRoom, provenance: .live)
        if focused.focus.mode == .focused {
            #expect(focused.masks.keys.allSatisfy { id in
                focused.rooms.first { $0.entityId == id }.flatMap(\.segmentId).map(focused.focus.acceptedSegmentIds.contains) ?? false
            })
        }
        // Whatever the policy decides, a mask never exists for a room the scene does not list.
        #expect(Set(focused.masks.keys).isSubset(of: Set(focused.rooms.map(\.entityId))))
    }

    @Test func aHugeMapIsNotRasterised() {
        let huge = ValetudoMap(layers: [.init(type: "floor", pixels: [0, 0, 5000, 5000])], entities: [], pixelSize: 5, size: (50_000, 50_000))
        let geometry = MapStageGeometry(map: huge, mapScale: 2.4)
        #expect(ValetudoMapScene.rasterise(huge, geometry: geometry, focus: nil) == nil)
    }

    @Test func aRoomWithNoCellsHasNoMask() {
        let scene = ValetudoMapScene(map: map(), vacuum: Vacuums.musicRoom, provenance: .live)
        let empty = ValetudoMap.SelectableRoom(entityId: "x", title: "x", centroid: (0, 0), cells: [], segmentId: nil)
        #expect(ValetudoMapScene.mask(empty, geometry: scene.geometry) == nil)
    }
}
