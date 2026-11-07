import CoreGraphics
import HassCore
import HassDesign
import SwiftUI

/// A decoded map prepared for drawing: geometry, focus, rooms, the cell image and the room masks.
struct ValetudoMapScene {
    let map: ValetudoMap
    let provenance: ValetudoMapProvenance
    let rotation: Double
    let focus: ValetudoMapFocus
    /// Drawing geometry (the focus view when focused).
    let geometry: MapStageGeometry
    /// Where an area may be drawn.
    let interactionGeometry: MapStageGeometry
    let rooms: [ValetudoMap.SelectableRoom]
    let cells: CGImage?
    /// One mask per drawn selectable room, keyed by its zone's entity id.
    let masks: [String: RoomMask]

    /// A room's cells as an opaque image in the selected colour, and where it sits on the stage.
    struct RoomMask {
        var image: CGImage
        /// The image's frame in stage cells.
        var rect: CGRect
        /// The room's bounds in grid cells, to test whether its name fits.
        var gridBounds: CGRect
    }

    init(map: ValetudoMap, vacuum: VacuumConfig, provenance: ValetudoMapProvenance) {
        self.map = map
        self.provenance = provenance
        rotation = vacuum.mapRotationDegrees
        focus = ValetudoMapFocus.resolve(map, policy: vacuum.mapFocus)
        let focused = focus.mode == .focused
        geometry = MapStageGeometry(map: map, mapScale: vacuum.mapScale, bounds: focused ? focus.viewBounds : nil)
        interactionGeometry = MapStageGeometry(map: map, mapScale: vacuum.mapScale, bounds: focused ? focus.interactionBounds : nil)
        rooms = vacuum.mapRoomSelection ? map.selectableRooms(vacuum.zones) : []
        cells = Self.rasterise(map, geometry: geometry, focus: focused ? focus : nil)
        var masks: [String: RoomMask] = [:]
        for room in rooms {
            if focused, !(room.segmentId.map(focus.acceptedSegmentIds.contains) ?? false) { continue }
            if let mask = Self.mask(room, geometry: geometry) { masks[room.entityId] = mask }
        }
        self.masks = masks
    }

    /// Width over height, for the frame.
    var aspectRatio: Double { MapGeometry.aspectRatio(geometry, rotation: rotation) }

    /// The local → frame transform.
    func matrix(size: CGSize, viewport: MapViewport) -> Affine {
        MapGeometry.matrix(geometry, frame: size, viewport: viewport, rotation: rotation)
    }

    /// The room under a frame point.
    func room(at point: CGPoint, size: CGSize, viewport: MapViewport = .initial) -> ValetudoMap.SelectableRoom? {
        let grid = MapGeometry.gridPoint(geometry, matrix: matrix(size: size, viewport: viewport), framePoint: .init(x: point.x, y: point.y))
        return ValetudoMap.room(at: (grid.x, grid.y), in: rooms)
    }

    // MARK: - Palette

    /// Direction G's map colours (mockup n6 `data-map`): a cool neutral ramp of rooms on a `#262628` card.
    enum Palette {
        /// The card and everything outside the rooms.
        static let ground = MapRGBA(38, 38, 40)
        /// Walls: the dark seams between rooms.
        static let wall = MapRGBA(30, 31, 34)
        /// Floor that belongs to no room.
        static let floor = MapRGBA(58, 63, 70)
        /// Room fills, cycled in layer order so neighbours differ slightly.
        static let rooms: [MapRGBA] = [
            MapRGBA(80, 86, 95), MapRGBA(90, 97, 107), MapRGBA(69, 75, 84), MapRGBA(86, 93, 102), MapRGBA(75, 81, 89),
            MapRGBA(64, 70, 78), MapRGBA(94, 101, 111), MapRGBA(77, 83, 92), MapRGBA(87, 94, 104), MapRGBA(71, 77, 85),
        ]
        /// A selected room.
        static let selected = MapRGBA(237, 239, 242)
        /// Stripes over a skipped room.
        static let hatch = MapRGBA(20, 21, 24, 0.75)
        /// Ink of an order badge's disc.
        static let labelOnSelected = MapRGBA(28, 28, 30)
        /// Travelled and predicted paths.
        static let path = MapRGBA(138, 144, 153, 0.9)
        static let predictedPath = MapRGBA(138, 144, 153, 0.45)
        /// The dock.
        static let dock = MapRGBA(201, 205, 211)
        /// The robot: a white disc with a dark ring and centre, on a soft halo; grey once reported from memory.
        static let robot = MapRGBA(255, 255, 255)
        static let reportedRobot = MapRGBA(138, 144, 153)
        static let robotInk = MapRGBA(28, 28, 30)
        static let robotHalo = MapRGBA(255, 255, 255, 0.22)

        /// The fill for the segment at `index` among segments.
        static func room(_ index: Int) -> MapRGBA { rooms[index % rooms.count] }
    }

    // MARK: - Raster

    /// One premultiplied RGBA pixel per cell, alpha-blended in layer order (`renderValetudoMap` layer pass), in the
    /// flat G palette (no material texture).
    static func rasterise(_ map: ValetudoMap, geometry: MapStageGeometry, focus: ValetudoMapFocus?) -> CGImage? {
        let width = Int(geometry.width.rounded(.up)), height = Int(geometry.height.rounded(.up))
        guard width > 0, height > 0, width * height < 16_000_000 else { return nil }
        var buffer = [Double](repeating: 0, count: width * height * 4)
        func blend(_ x: Int, _ y: Int, _ color: MapRGBA) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let index = (y * width + x) * 4
            let a = color.alpha, keep = 1 - a
            buffer[index] = color.red * a + buffer[index] * keep
            buffer[index + 1] = color.green * a + buffer[index + 1] * keep
            buffer[index + 2] = color.blue * a + buffer[index + 2] * keep
            buffer[index + 3] = a + buffer[index + 3] * keep
        }
        let minX = Int(geometry.minGridX), minY = Int(geometry.minGridY)
        var segmentIndex = 0
        for layer in map.layers where !layer.pixels.isEmpty {
            let isSegment = layer.type == "segment"
            let color = layer.type == "wall" ? Palette.wall : isSegment ? Palette.room(segmentIndex) : Palette.floor
            if isSegment { segmentIndex += 1 }
            if let focus, isSegment, !(layer.segmentId.map(focus.acceptedSegmentIds.contains) ?? false) { continue }
            var index = 0
            while index + 1 < layer.pixels.count {
                let sx = Int(layer.pixels[index]), sy = Int(layer.pixels[index + 1])
                index += 2
                if let walls = focus?.renderWallCells, layer.type == "wall", !walls.contains(ValetudoMap.cellKey(sx, sy)) { continue }
                blend(sx - minX, sy - minY, color)
            }
        }
        return image(width: width, height: height, bytes: buffer.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) })
    }

    /// A room's mask: its cells, opaque, in ``Palette/selected``, cropped to the room's bounds.
    static func mask(_ room: ValetudoMap.SelectableRoom, geometry: MapStageGeometry) -> RoomMask? {
        let points = room.cells.map { (x: $0 / 100_000, y: $0 % 100_000) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let width = maxX - minX + 1, height = maxY - minY + 1
        guard width * height < 4_000_000 else { return nil }
        let color = Palette.selected
        let pixel: [UInt8] = [color.red, color.green, color.blue].map { UInt8(($0 * 255).rounded()) } + [255]
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for point in points {
            let index = ((point.y - minY) * width + (point.x - minX)) * 4
            bytes.replaceSubrange(index..<(index + 4), with: pixel)
        }
        guard let image = image(width: width, height: height, bytes: bytes) else { return nil }
        let rect = CGRect(x: CGFloat(minX - Int(geometry.minGridX)), y: CGFloat(minY - Int(geometry.minGridY)),
                          width: CGFloat(width), height: CGFloat(height))
        return RoomMask(image: image, rect: rect, gridBounds: CGRect(x: minX, y: minY, width: width, height: height))
    }

    private static func image(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
