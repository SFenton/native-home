import Foundation
@testable import HassCore
import HassTestSupport
import Testing

// MARK: - Helpers

/// Cells of a filled rectangle as flat `x, y` pairs.
func rectangleCells(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> [Int32] {
    var cells: [Int32] = []
    for y in minY...maxY { for x in minX...maxX { cells += [Int32(x), Int32(y)] } }
    return cells
}

func outlineCells(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> [Int32] {
    var cells = rectangleCells(minX, maxX, minY, minY) + rectangleCells(minX, maxX, maxY, maxY)
    for y in (minY + 1)..<maxY { cells += [Int32(minX), Int32(y), Int32(maxX), Int32(y)] }
    return cells
}

/// The web's focus fixture (`createFocusedMap`): three named rooms and an unnamed phantom segment.
func focusedFixture(entities: [ValetudoMap.Entity]? = nil) -> ValetudoMap {
    ValetudoMap(
        layers: [
            .init(type: "wall", pixels: outlineCells(19, 36, 19, 36) + outlineCells(0, 11, 14, 36)),
            .init(type: "segment", pixels: rectangleCells(20, 30, 20, 30), name: "Music Room", segmentId: "3"),
            .init(type: "segment", pixels: rectangleCells(31, 35, 24, 30), name: "Downstairs Hallway", segmentId: "10"),
            .init(type: "segment", pixels: rectangleCells(24, 35, 31, 35), name: "Downstairs Bathroom", segmentId: "12"),
            .init(type: "segment", pixels: rectangleCells(0, 10, 15, 35), segmentId: "4"),
        ],
        entities: entities ?? [.init(type: "robot_position", points: [125, 125]), .init(type: "charger_location", points: [125, 125])],
        pixelSize: 5, size: (500, 500))
}

let focusPolicy = VacuumConfig.MapFocus(maximumViewAreaRatio: 0.9, minimumExcludedAreaM2: 0, minimumExcludedFraction: 0, paddingCm: 15,
                                        requiredSegments: [.init(id: "3", name: "Music Room"), .init(id: "10", name: "Downstairs Hallway"),
                                                           .init(id: "12", name: "Downstairs Bathroom")],
                                        wallAssociationCm: 20)

/// Wraps raw deflate in a zlib stream (header + Adler-32) the way Valetudo writes it.
func zlib(_ data: Data) throws -> Data {
    let deflated = try (data as NSData).compressed(using: .zlib) as Data
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
    let adler = (b << 16) | a
    return Data([0x78, 0x9C]) + deflated + Data([UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
}

func pngChunk(_ type: String, _ payload: Data) -> Data {
    let length = UInt32(payload.count)
    return Data([UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        + Data(type.utf8) + payload + Data([0, 0, 0, 0])
}

/// A PNG carrying `json` in a `ValetudoMap` zTXt chunk (CRCs are not checked).
func valetudoPNG(_ json: String, keyword: String = "ValetudoMap") throws -> Data {
    let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    let text = Data(keyword.utf8) + Data([0, 0]) + (try zlib(Data(json.utf8)))
    return signature + pngChunk("IHDR", Data(count: 13)) + pngChunk("tEXt", Data("Comment\0hi".utf8)) + pngChunk("zTXt", text)
        + pngChunk("IEND", Data())
}

let sampleMapJSON = """
{"__class":"ValetudoMap","pixelSize":5,"size":{"x":500,"y":400},"metaData":{"version":2},
 "layers":[
  {"type":"floor","compressedPixels":[10,10,3]},
  {"type":"segment","pixels":[20,20,21,20],"metaData":{"segmentId":7,"name":" Kitchen ","active":true,"material":"tile"},
   "dimensions":{"x":{"min":20,"max":21},"y":{"min":20,"max":20}}},
  {"type":"wall","pixels":[]}
 ],
 "entities":[{"type":"robot_position","points":[100,105],"metaData":{"angle":45}},{"type":"path","points":[1,2,3,4]}]}
"""

// MARK: - Decoding

@Suite(.demoHouse)
struct ValetudoMapDecoderTests {
    @Test func decodesTheZTXtChunkOfACameraPNG() throws {
        let map = try ValetudoMapDecoder.map(fromPNG: try valetudoPNG(sampleMapJSON))
        #expect(map.pixelSize == 5)
        #expect(map.size.x == 500 && map.size.y == 400)
        #expect(map.version == 2)
        #expect(map.layers.count == 3)
        #expect(map.layers[0].pixels == [10, 10, 11, 10, 12, 10])
        let segment = map.layers[1]
        #expect(segment.segmentId == "7")
        #expect(segment.name == "Kitchen")
        #expect(segment.active)
        #expect(segment.material == .tile)
        #expect(segment.dimensions == .init(minX: 20, minY: 20, maxX: 21, maxY: 20))
        #expect(map.layers[2].hasPixelRepresentation && map.layers[2].pixels.isEmpty)
        #expect(map.robotPosition?.angle == 45)
        #expect(map.entities[1].points == [1, 2, 3, 4])
    }

    @Test func rejectsWhatIsNotAValetudoPNG() throws {
        #expect(throws: ValetudoMapDecoder.Failure.notPNG) { try ValetudoMapDecoder.map(fromPNG: Data("hello".utf8)) }
        #expect(throws: ValetudoMapDecoder.Failure.noMapData) { try ValetudoMapDecoder.map(fromPNG: try valetudoPNG(sampleMapJSON, keyword: "Other")) }
        #expect(throws: ValetudoMapDecoder.Failure.invalidMap) { try ValetudoMapDecoder.map(fromPNG: try valetudoPNG(#"{"__class":"Other"}"#)) }
        #expect(throws: ValetudoMapDecoder.Failure.inflateFailed) { try ValetudoMapDecoder.inflateZlib(Data([1, 2, 3])) }
        #expect(throws: ValetudoMapDecoder.Failure.inflateFailed) { try ValetudoMapDecoder.inflateZlib(Data(repeating: 7, count: 20)) }
    }

    @Test func defaultsMissingFields() throws {
        let map = try ValetudoMapDecoder.map(fromJSON: Data(#"{"__class":"ValetudoMap"}"#.utf8))
        #expect(map.pixelSize == 5)
        #expect(map.layers.isEmpty && map.entities.isEmpty)
        #expect(map.version == nil)
    }

    @Test func expandsRunLengthRows() {
        #expect(ValetudoMapDecoder.expand([5, 1, 2, 9, 9, 0, 7, 3, 1]) == [5, 1, 6, 1, 7, 3])
        #expect(ValetudoMapDecoder.expand([1, 2]).isEmpty)
    }
}

// MARK: - Map queries

@Suite(.demoHouse)
struct ValetudoMapQueryTests {
    @Test func boundsPreferDrawnCellsThenLegacyDimensionsThenSize() {
        var map = ValetudoMap(layers: [.init(type: "segment", pixels: [3, 4, 9, 2])], entities: [], pixelSize: 5, size: (100, 50))
        #expect(map.bounds == .init(minX: 3, minY: 2, maxX: 9, maxY: 4))
        map.layers = [.init(type: "floor", pixels: [], hasPixelRepresentation: false, dimensions: .init(minX: 1, minY: 1, maxX: 4, maxY: 5))]
        #expect(map.bounds == .init(minX: 1, minY: 1, maxX: 4, maxY: 5))
        map.layers = []
        #expect(map.bounds == .init(minX: 0, minY: 0, maxX: 20, maxY: 10))
        #expect(ValetudoMap.Bounds(minX: 0, minY: 0, maxX: 1, maxY: 2).area == 6)
    }

    @Test func findsSelectableRoomsByNormalisedSegmentName() throws {
        let map = ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId)
        let rooms = map.selectableRooms(Vacuums.mainFloor.zones)
        #expect(rooms.count == 11)
        let closet = try #require(rooms.first { $0.title == "Closet" })
        #expect(closet.title == "Closet")
        #expect(closet.segmentId == "9")
        let hit = ValetudoMap.room(at: closet.centroid, in: rooms)
        #expect(hit?.entityId == closet.entityId)
        #expect(ValetudoMap.room(at: (0, 0), in: rooms) == nil)
        #expect(map.selectableRooms([]).isEmpty)
    }

    @Test func reportedMapsKeepOnlyStaticEntities() {
        let map = ValetudoMap(layers: [], entities: [.init(type: "robot_position", points: [1, 1]), .init(type: "path", points: [1, 1, 2, 2]),
                                                     .init(type: "no_go_area", points: [])], pixelSize: 5, size: (1, 1))
        #expect(map.reportedOnly().entities.map(\.type) == ["robot_position", "no_go_area"])
    }

    @Test func fixturesCoverEveryVacuum() {
        for vacuum in Vacuums.all {
            let map = ValetudoMapFixtures.map(vacuum.vacuumMapId)
            #expect(map.robotPosition != nil)
            #expect(map.layers.contains { $0.type == "segment" })
            #expect(map.layers.contains { $0.type == "wall" })
        }
    }
}

// MARK: - Focus

@Suite(.demoHouse)
struct ValetudoMapFocusTests {
    @Test func productionMusicRoomPolicyFocusesThePhantomFixture() throws {
        let result = ValetudoMapFocus.resolve(ValetudoMapFixtures.map(Vacuums.musicRoom.vacuumMapId), policy: Vacuums.musicRoom.mapFocus)
        #expect(result.mode == .focused)
        #expect(result.excludedSegmentIds == ["4"])
        #expect(result.interactionBounds == .init(minX: 638, minY: 556, maxX: 781, maxY: 721))
        #expect(result.viewBounds == .init(minX: 634, minY: 552, maxX: 782, maxY: 722))
        #expect(result.excludedAreaM2 > 4)
    }

    @Test func focusesConnectedNamedSegments() throws {
        let result = ValetudoMapFocus.resolve(focusedFixture(), policy: focusPolicy)
        #expect(result.mode == .focused)
        #expect(result.reason == .focused)
        #expect(result.acceptedSegmentIds == ["3", "10", "12"])
        #expect(result.excludedSegmentIds == ["4"])
        #expect(result.interactionBounds == .init(minX: 20, minY: 20, maxX: 35, maxY: 35))
        #expect(result.viewBounds.minX > 11)
        let walls = try #require(result.renderWallCells)
        #expect(walls.contains(ValetudoMap.cellKey(19, 24)))
        #expect(!walls.contains(ValetudoMap.cellKey(11, 24)))
    }

    @Test func fallsBackWhenAnExcludedSegmentIsNamedOrActive() {
        var named = focusedFixture()
        named.layers[4].name = "Sunroom"
        let result = ValetudoMapFocus.resolve(named, policy: focusPolicy)
        #expect(result.reason == .namedSegmentExcluded)
        #expect(result.viewBounds == result.rawBounds)

        var active = focusedFixture()
        active.layers[4].active = true
        #expect(ValetudoMapFocus.resolve(active, policy: focusPolicy).reason == .activeSegmentExcluded)
    }

    @Test func diagonalNeighboursJoinOnlyWhenNamed() {
        var helper = focusedFixture()
        helper.layers.append(.init(type: "segment", pixels: [36, 36], segmentId: "6"))
        let dropped = ValetudoMapFocus.resolve(helper, policy: focusPolicy)
        #expect(dropped.mode == .focused)
        #expect(!dropped.acceptedSegmentIds.contains("6"))
        #expect(dropped.excludedSegmentIds == ["4", "6"])

        var pantry = focusedFixture()
        pantry.layers.append(.init(type: "segment", pixels: [36, 36], name: "Pantry", segmentId: "6"))
        let kept = ValetudoMapFocus.resolve(pantry, policy: focusPolicy)
        #expect(kept.acceptedSegmentIds.contains("6"))
        #expect(kept.excludedSegmentIds == ["4"])
    }

    @Test func anchorsAndRoutesMustStayInsideTheFocus() {
        let outside = focusedFixture(entities: [.init(type: "robot_position", points: [25, 125]), .init(type: "charger_location", points: [125, 125])])
        #expect(ValetudoMapFocus.resolve(outside, policy: focusPolicy).reason == .anchorOutsideFocus)

        let missing = focusedFixture(entities: [.init(type: "robot_position", points: [125, 125])])
        #expect(ValetudoMapFocus.resolve(missing, policy: focusPolicy).reason == .missingAnchor)

        var route = focusedFixture()
        route.entities.append(.init(type: "path", points: [125, 125, 25, 125]))
        #expect(ValetudoMapFocus.resolve(route, policy: focusPolicy).reason == .activeRouteExcluded)

        var zone = focusedFixture()
        zone.entities.append(.init(type: "active_zone", points: [-5, 65, 60, 65, 60, 185, -5, 185]))
        #expect(ValetudoMapFocus.resolve(zone, policy: focusPolicy).reason == .activeRouteExcluded)

        var noGo = focusedFixture()
        noGo.entities.append(.init(type: "no_go_area", points: [10, 90, 45, 90, 45, 140, 10, 140]))
        #expect(ValetudoMapFocus.resolve(noGo, policy: focusPolicy).mode == .focused)
    }

    @Test func identityAndConfigurationProblemsShowTheFullMap() {
        var renamed = focusedFixture()
        renamed.layers[1].name = "Different Room"
        #expect(ValetudoMapFocus.resolve(renamed, policy: focusPolicy).reason == .segmentNameMismatch)
        #expect(ValetudoMapFocus.resolve(focusedFixture(), policy: nil).reason == .unconfigured)

        var missing = focusPolicy
        missing.requiredSegments.append(.init(id: "99", name: nil))
        #expect(ValetudoMapFocus.resolve(focusedFixture(), policy: missing).reason == .missingRequiredSegment)

        var legacy = focusedFixture()
        legacy.version = 1
        #expect(ValetudoMapFocus.resolve(legacy, policy: focusPolicy).reason == .invalidMap)

        var overlapping = focusedFixture()
        overlapping.layers.append(.init(type: "segment", pixels: [20, 20], segmentId: "8"))
        #expect(ValetudoMapFocus.resolve(overlapping, policy: focusPolicy).reason == .overlappingSegments)

        var strict = focusPolicy
        strict.minimumExcludedAreaM2 = 1000
        #expect(ValetudoMapFocus.resolve(focusedFixture(), policy: strict).reason == .insufficientBenefit)
        strict = focusPolicy
        strict.maximumViewAreaRatio = 0.01
        #expect(ValetudoMapFocus.resolve(focusedFixture(), policy: strict).reason == .insufficientBenefit)
    }

    @Test func checksRectanglesAgainstUnpaddedBounds() {
        let bounds = ValetudoMap.Bounds(minX: 20, minY: 20, maxX: 35, maxY: 35)
        #expect(ValetudoMapFocus.rect(.init(x0: 20, x1: 36, y0: 20, y1: 36), isWithin: bounds))
        #expect(!ValetudoMapFocus.rect(.init(x0: 19, x1: 30, y0: 20, y1: 30), isWithin: bounds))
        #expect(!ValetudoMapFocus.rect(.init(x0: 20, x1: 30, y0: 20, y1: 37), isWithin: bounds))
    }

    @Test func pointInPolygonAndNearestSegment() {
        #expect(ValetudoMapFocus.pointInPolygon(5, 5, [0, 0, 10, 0, 10, 10, 0, 10]))
        #expect(!ValetudoMapFocus.pointInPolygon(15, 5, [0, 0, 10, 0, 10, 10, 0, 10]))
        #expect(ValetudoMapFocus.nearestSegment([10, 10], 5, [ValetudoMap.cellKey(2, 2): "a"], radius: 1) == "a")
        #expect(ValetudoMapFocus.nearestSegment([10], 5, [:], radius: 1) == nil)
    }
}

// MARK: - Geometry

@Suite(.demoHouse)
struct ValetudoMapGeometryTests {
    let map = ValetudoMapFixtures.map(Vacuums.mainFloor.vacuumMapId)
    var geometry: MapStageGeometry { MapStageGeometry(map: map, mapScale: 1.2) }
    let frame = CGSize(width: 359, height: 420)

    @Test func sharesTheRendererPadding() {
        let g = geometry
        #expect(g.minGridX == 558 && g.minGridY == 639 && g.maxGridX == 729 && g.maxGridY == 1028)
        #expect(g.pixelSize == 5)
        #expect(g.width == 172.5)
        #expect(g.height == 390)
    }

    @Test(arguments: [0.0, 90, 180, 270])
    func roundTripsPointsThroughARotatedViewport(rotation: Double) {
        let g = geometry
        let m = MapGeometry.matrix(g, frame: frame, viewport: .init(panX: -42, panY: 61, zoom: 3.4), rotation: rotation)
        for point in [MapPoint(x: 0, y: 0), .init(x: g.width / 2, y: g.height / 2), .init(x: g.width, y: g.height)] {
            let back = m.inverted.apply(m.apply(point))
            #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
        }
        #expect(m.scale > 0)
        #expect(MapGeometry.matrix(g, frame: .zero, viewport: .initial, rotation: rotation) == .identity)
    }

    @Test func reportsTheRotatedAspectRatio() {
        let g = geometry
        #expect(abs(MapGeometry.aspectRatio(g, rotation: 0) - g.width / g.height) < 1e-9)
        #expect(abs(MapGeometry.aspectRatio(g, rotation: 90) - g.height / g.width) < 1e-9)
        let aspectFrame = CGSize(width: 200 * MapGeometry.aspectRatio(g, rotation: 0), height: 200)
        let m = MapGeometry.matrix(g, frame: aspectFrame, viewport: .initial, rotation: 0)
        #expect(abs(g.width * m.scale - Double(aspectFrame.width)) < 1e-6)
    }

    @Test func keepsWorldCoordinatesExactWithFocusedBounds() {
        let g = geometry
        let focused = MapStageGeometry(map: map, mapScale: 1.2, bounds: .init(minX: g.minGridX + 20, minY: g.minGridY + 30,
                                                                              maxX: g.maxGridX - 21, maxY: g.maxGridY - 31))
        let m = MapGeometry.matrix(focused, frame: frame, viewport: .init(panX: 17, panY: -11, zoom: 2.8), rotation: 180)
        let world = MapPoint(x: focused.minGridX + 12, y: focused.minGridY + 18)
        let back = MapGeometry.gridPoint(focused, matrix: m, framePoint: MapGeometry.framePoint(focused, matrix: m, gridPoint: world))
        #expect(abs(back.x - world.x) < 1e-9 && abs(back.y - world.y) < 1e-9)
        let rect = MapGridRect(x0: world.x, x1: world.x + 8, y0: world.y, y1: world.y + 6)
        #expect(rect.serviceData(pixelSize: focused.pixelSize) == rect.serviceData(pixelSize: g.pixelSize))
    }

    @Test func anchorsZoomUnderRotation() {
        let g = geometry
        let anchor = MapPoint(x: g.width / 3, y: g.height / 4)
        let viewport = MapGeometry.viewport(g, frame: frame, anchor: anchor, at: .init(x: 240, y: 130), zoom: 5, rotation: 180)
        let rendered = MapGeometry.matrix(g, frame: frame, viewport: viewport, rotation: 180).apply(anchor)
        #expect(abs(rendered.x - 240) < 1e-8 && abs(rendered.y - 130) < 1e-8)
        #expect(MapGeometry.viewport(g, frame: frame, anchor: anchor, at: .init(x: 0, y: 0), zoom: 50, rotation: 0).zoom == 10)
    }

    @Test func clampKeepsAQuarterOfTheMapVisible() {
        let g = geometry
        let far = MapGeometry.clamp(g, frame: frame, viewport: .init(panX: 10_000, panY: -10_000, zoom: 1), rotation: 0)
        #expect(far.panX < 10_000 && far.panY > -10_000)
        let other = MapGeometry.clamp(g, frame: frame, viewport: .init(panX: -10_000, panY: 10_000, zoom: 1), rotation: 0)
        #expect(other.panX > -10_000 && other.panY < 10_000)
        #expect(MapGeometry.clamp(g, frame: frame, viewport: .initial, rotation: 0) == .initial)
    }

    @Test func createsTranslatesAndResizesRectangles() {
        let g = geometry
        let drawn = MapGeometry.rect(g, from: .init(x: 600, y: 700), to: .init(x: 602, y: 701), minimum: 5)
        #expect(drawn == .init(x0: 600, x1: 605, y0: 700, y1: 705))
        let backwards = MapGeometry.rect(g, from: .init(x: 600, y: 700), to: .init(x: 598, y: 699), minimum: 5)
        #expect(backwards == .init(x0: 595, x1: 600, y0: 695, y1: 700))
        #expect(MapGeometry.translate(g, drawn, by: .init(x: -1000, y: 1000)) == .init(x0: 558, x1: 563, y0: 1023, y1: 1028))
        let rect = MapGridRect(x0: 600, x1: 620, y0: 700, y1: 720)
        #expect(MapGeometry.resize(g, rect, corner: .a, to: .init(x: 595, y: 695), minimum: 5) == .init(x0: 595, x1: 620, y0: 695, y1: 720))
        #expect(MapGeometry.resize(g, rect, corner: .b, to: .init(x: 625, y: 695), minimum: 5) == .init(x0: 600, x1: 625, y0: 695, y1: 720))
        #expect(MapGeometry.resize(g, rect, corner: .c, to: .init(x: 625, y: 725), minimum: 5) == .init(x0: 600, x1: 625, y0: 700, y1: 725))
        #expect(MapGeometry.resize(g, rect, corner: .d, to: .init(x: 595, y: 725), minimum: 5) == .init(x0: 595, x1: 620, y0: 700, y1: 725))
        #expect(MapGeometry.resize(g, rect, corner: .a, to: .init(x: 619, y: 719), minimum: 5) == .init(x0: 615, x1: 620, y0: 715, y1: 720))
        #expect(MapGeometry.resize(g, rect, corner: .c, to: .init(x: 601, y: 701), minimum: 5) == .init(x0: 600, x1: 605, y0: 700, y1: 705))
    }

    @Test func defaultRectangleAndDimensions() {
        let g = geometry
        let rect = MapGeometry.defaultRect(g)
        #expect(rect.x1 - rect.x0 == 30 && rect.y1 - rect.y0 == 30)
        let size = rect.dimensionsCm(pixelSize: g.pixelSize)
        #expect(size.width == 150 && size.height == 150)
        #expect(MapGridRect(x0: 5, x1: 1, y0: 9, y1: 2).normalized == .init(x0: 1, x1: 5, y0: 2, y1: 9))
        #expect(MapGridRect(x0: 10, x1: 2, y0: 4, y1: 8).serviceData(pixelSize: 5)
            == ["x_min_cm": .number(10), "x_max_cm": .number(50), "y_min_cm": .number(20), "y_max_cm": .number(40)])
        #expect(MapGridRect.Corner.allCases.map { rect.point($0) }.count == 4)
    }
}

// MARK: - Style

@Suite(.demoHouse)
struct ValetudoMapStyleTests {
    @Test func materialAccentsFollowTheWebPatterns() {
        #expect(ValetudoMapStyle.accent(.tile, x: 6, y: 1) == .dark)
        #expect(ValetudoMapStyle.accent(.tile, x: 5, y: 1) == nil)
        #expect(ValetudoMapStyle.accent(.wood, x: 4, y: 4) == .dark)
        #expect(ValetudoMapStyle.accent(.woodHorizontal, x: 1, y: 5) == .dark)
        #expect(ValetudoMapStyle.accent(.woodHorizontal, x: 12, y: 12) == .dark)
        #expect(ValetudoMapStyle.accent(.woodVertical, x: 5, y: 1) == .dark)
        #expect(ValetudoMapStyle.accent(.woodVertical, x: 12, y: 12) == .dark)
        #expect(ValetudoMapStyle.accent(.carpet, x: 2, y: 3) == .light)
        #expect(ValetudoMapStyle.accent(.carpetLow, x: 4, y: 8) == .light)
        #expect(ValetudoMapStyle.accent(.carpetHigh, x: 9, y: 2) == .light)
        #expect(ValetudoMapStyle.accent(.generic, x: 0, y: 0) == nil)
        #expect(ValetudoMapStyle.accent(nil, x: 0, y: 0) == nil)
        #expect(ValetudoMapStyle.color(.light).alpha == 0.17)
        #expect(ValetudoMapStyle.color(.dark).alpha == 0.24)
    }

    @Test func entityStylesAndSegmentColors() {
        for type in ["active_zone", "carpet", "no_go_area", "no_mop_area", "ramp"] {
            #expect(ValetudoMapStyle.entityStyle(type)?.shape == .polygon)
        }
        for type in ["curtain", "threshold", "virtual_wall"] { #expect(ValetudoMapStyle.entityStyle(type)?.shape == .line) }
        #expect(ValetudoMapStyle.entityStyle("obstacle")?.icon == .obstacle)
        #expect(ValetudoMapStyle.entityStyle("go_to_target")?.icon == .target)
        #expect(ValetudoMapStyle.entityStyle("robot_position") == nil)
        #expect(ValetudoMapStyle.segment(7) == ValetudoMapStyle.segment(0))
        #expect(MapRGBA(255, 0, 0, 0.5) == MapRGBA(255, 0, 0, 0.5))
        #expect(ValetudoMapStyle.wall.alpha == 0.82)
    }
}
