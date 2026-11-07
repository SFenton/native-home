import Foundation

/// An sRGB color with alpha, platform-neutral so render rules test on macOS.
public struct MapRGBA: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    /// Components 0...255, alpha 0...1 (CSS `rgba`).
    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red / 255; self.green = green / 255; self.blue = blue / 255; self.alpha = alpha
    }
}

/// How the map draws (web `renderValetudoMap` and `ValetudoMapCard.utils.ts`).
public enum ValetudoMapStyle {
    /// Behind the map.
    public static let background = MapRGBA(6, 12, 18, 0.56)
    /// Wall cells.
    public static let wall = MapRGBA(236, 244, 255, 0.82)
    /// The robot while live.
    public static let liveRobot = MapRGBA(248, 250, 252)
    /// The dock icon and its halo.
    public static let dock = MapRGBA(102, 187, 106)
    public static let dockHalo = MapRGBA(18, 56, 30, 0.76)
    /// The default icon halo.
    public static let halo = MapRGBA(8, 16, 24, 0.72)
    /// The icon ring.
    public static let ring = MapRGBA(255, 255, 255, 0.86)
    /// Travelled and predicted paths.
    public static let path = MapRGBA(255, 255, 255, 0.72)
    public static let predictedPath = MapRGBA(255, 255, 255, 0.36)

    /// Segment fills, cycled in layer order.
    public static let segments: [MapRGBA] = [
        MapRGBA(61, 176, 145, 0.78), MapRGBA(73, 152, 220, 0.78), MapRGBA(158, 130, 226, 0.78),
        MapRGBA(235, 154, 87, 0.78), MapRGBA(106, 190, 92, 0.78), MapRGBA(226, 115, 141, 0.78),
        MapRGBA(88, 175, 205, 0.78),
    ]

    /// The fill for the segment at `index` among segments.
    public static func segment(_ index: Int) -> MapRGBA { segments[index % segments.count] }

    /// Material texture on a cell: light on carpet, dark on hard floors.
    public enum Accent: Sendable, Equatable { case light, dark }

    /// The accent color.
    public static func color(_ accent: Accent) -> MapRGBA {
        accent == .light ? MapRGBA(255, 255, 255, 0.17) : MapRGBA(5, 12, 18, 0.24)
    }

    /// Whether a cell gets a material accent (`valetudoMapMaterialAccent`).
    public static func accent(_ material: ValetudoMap.Material?, x: Int, y: Int) -> Accent? {
        switch material {
        case .tile: x % 6 == 0 || y % 6 == 0 ? .dark : nil
        case .wood: (x + y) % 8 == 0 ? .dark : nil
        case .woodHorizontal: y % 5 == 0 || (y % 10 == 2 && x % 12 == 0) ? .dark : nil
        case .woodVertical: x % 5 == 0 || (x % 10 == 2 && y % 12 == 0) ? .dark : nil
        case .carpet: ((x >> 1) + y) % 4 == 0 ? .light : nil
        case .carpetLow: x % 4 == 0 && y % 4 == 0 ? .light : nil
        // JS `%` keeps the sign, so a negative difference never matches 0 unless it is a multiple of 7.
        case .carpetHigh: (x + y) % 4 == 0 || (x - y) % 7 == 0 ? .light : nil
        case .generic, nil: nil
        }
    }

    /// One entity type's drawing.
    public struct EntityStyle: Equatable, Sendable {
        public enum Shape: Sendable { case line, point, polygon }
        public enum Icon: Sendable { case obstacle, target }
        public var shape: Shape
        public var stroke: MapRGBA
        public var fill: MapRGBA?
        public var halo: MapRGBA?
        public var icon: Icon?
        /// Dash lengths in screen points.
        public var dash: [Double] = []
    }

    /// The style for an entity type, or `nil` for types drawn elsewhere (robot, dock, paths) or not at all.
    public static func entityStyle(_ type: String) -> EntityStyle? {
        switch type {
        case "active_zone": .init(shape: .polygon, stroke: MapRGBA(128, 222, 234, 0.72), fill: MapRGBA(77, 208, 225, 0.16))
        case "carpet": .init(shape: .polygon, stroke: MapRGBA(255, 213, 79, 0.62), fill: MapRGBA(255, 193, 7, 0.12), dash: [3, 3])
        case "curtain": .init(shape: .line, stroke: MapRGBA(128, 222, 234, 0.86), dash: [2, 3])
        case "go_to_target": .init(shape: .point, stroke: MapRGBA(128, 222, 234), halo: MapRGBA(16, 54, 68, 0.78), icon: .target)
        case "no_go_area": .init(shape: .polygon, stroke: MapRGBA(255, 138, 128, 0.76), fill: MapRGBA(239, 83, 80, 0.22))
        case "no_mop_area": .init(shape: .polygon, stroke: MapRGBA(144, 202, 249, 0.76), fill: MapRGBA(33, 150, 243, 0.2))
        case "obstacle": .init(shape: .point, stroke: MapRGBA(255, 202, 107), halo: MapRGBA(80, 48, 8, 0.8), icon: .obstacle)
        case "ramp": .init(shape: .polygon, stroke: MapRGBA(206, 147, 216, 0.78), fill: MapRGBA(171, 71, 188, 0.16), dash: [5, 3])
        case "threshold": .init(shape: .line, stroke: MapRGBA(255, 183, 77, 0.9), dash: [6, 4])
        case "virtual_wall": .init(shape: .line, stroke: MapRGBA(255, 112, 103, 0.9))
        default: nil
        }
    }
}

/// Synthetic maps for the gallery, hosted tests and screenshots (web `createMockValetudoMap`), never the real house.
public enum ValetudoMapFixtures {
    struct Box { var id: String?; var name: String?; var minX: Int, maxX: Int, minY: Int, maxY: Int }

    static func rows(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> [Int32] {
        stride(from: minY, through: maxY, by: 1).flatMap { [Int32(minX), Int32($0), Int32(maxX - minX + 1)] }
    }

    static func outline(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> [Int32] {
        var rows = rows(minX, maxX, minY, minY) + rows(minX, maxX, maxY, maxY)
        for y in (minY + 1)..<maxY { rows += [Int32(minX), Int32(y), 1, Int32(maxX), Int32(y), 1] }
        return rows
    }

    static func layer(_ type: String, _ box: Box, pixels: [Int32]) -> ValetudoMap.Layer {
        ValetudoMap.Layer(type: type, pixels: ValetudoMapDecoder.expand(pixels),
                          dimensions: .init(minX: Double(box.minX), minY: Double(box.minY), maxX: Double(box.maxX), maxY: Double(box.maxY)),
                          name: box.name, segmentId: box.id)
    }

    /// The mock map for a vacuum's map id, chosen by the vacuum's shape in the document: one with many zones gets the
    /// multi-room floor map, the first small one the two-part map, any other the single room.
    public static func map(_ vacuumMapId: String) -> ValetudoMap {
        let vacuums = Vacuums.all
        if vacuums.first(where: { $0.vacuumMapId == vacuumMapId })?.zones.count ?? 0 > 4 { return mainFloor }
        if vacuums.first(where: { $0.zones.count <= 4 })?.vacuumMapId == vacuumMapId { return musicRoom }
        return simple(Box(minX: 637, maxX: 735, minY: 535, maxY: 688))
    }

    static var musicRoom: ValetudoMap {
        let segments = [
            Box(id: "3", name: "Studio", minX: 638, maxX: 781, minY: 556, maxY: 667),
            Box(id: "10", name: "Downstairs Hallway", minX: 710, maxX: 729, minY: 668, maxY: 713),
            Box(id: "12", name: "Bathroom 3", minX: 638, maxX: 709, minY: 668, maxY: 721),
            Box(id: "4", minX: 505, maxX: 630, minY: 545, maxY: 684),
        ]
        let wall = Box(minX: 504, maxX: 782, minY: 544, maxY: 722)
        return ValetudoMap(
            layers: [layer("wall", wall, pixels: outline(637, 782, 555, 722) + outline(504, 631, 544, 685))]
                + segments.map { layer("segment", $0, pixels: rows($0.minX, $0.maxX, $0.minY, $0.maxY)) },
            entities: [.init(type: "charger_location", points: [3230, 3275]), .init(type: "robot_position", points: [3230, 3275], angle: 90)],
            pixelSize: 5, size: (6554, 6554))
    }

    static var mainFloor: ValetudoMap {
        let bounds = Box(minX: 558, maxX: 728, minY: 639, maxY: 1027)
        let names = [("Dining Room", "1"), ("Living Room", "3"), ("Kitchen", "4"), ("Guest Bathroom", "5"), ("Gym", "7"),
                     ("Bathroom 1", "8"), ("Bedroom 1 Closet", "9"), ("Guest Room", "11"), ("Hallway", "12"),
                     ("Bedroom 1", "13"), ("Office", "14")]
        let inset = 5, columns = 4, rowCount = 3
        let width = (bounds.maxX - bounds.minX - inset * 2) / columns
        let height = (bounds.maxY - bounds.minY - inset * 2) / rowCount
        let rooms = names.enumerated().map { index, room -> Box in
            let column = index % columns, row = index / columns
            let minX = bounds.minX + inset + column * width, minY = bounds.minY + inset + row * height
            return Box(id: room.1, name: room.0, minX: minX, maxX: column == columns - 1 ? bounds.maxX - inset : minX + width - 1,
                       minY: minY, maxY: row == rowCount - 1 ? bounds.maxY - inset : minY + height - 1)
        }
        return ValetudoMap(
            layers: [ValetudoMap.Layer(type: "floor", pixels: [], hasPixelRepresentation: false,
                                       dimensions: .init(minX: 558, minY: 0, maxX: 728, maxY: 6554))]
                + rooms.map { layer("segment", $0, pixels: rows($0.minX, $0.maxX, $0.minY, $0.maxY)) }
                + [layer("wall", bounds, pixels: outline(bounds.minX, bounds.maxX, bounds.minY, bounds.maxY))],
            entities: [.init(type: "charger_location", points: [Double(bounds.minX + inset + 4) * 5, Double(bounds.minY + inset + 4) * 5]),
                       .init(type: "robot_position", points: [Double(bounds.minX + bounds.maxX) * 2.5, Double(bounds.minY + bounds.maxY) * 2.5], angle: 90)],
            pixelSize: 5, size: (6554, 6554))
    }

    static func simple(_ bounds: Box) -> ValetudoMap {
        let width = bounds.maxX - bounds.minX, height = bounds.maxY - bounds.minY
        let splitX = Int((Double(bounds.minX) + Double(width) * 0.54).rounded())
        let splitY = Int((Double(bounds.minY) + Double(height) * 0.48).rounded())
        let inset = max(3, Int((Double(min(width, height)) * 0.04).rounded()))
        let segments = [
            Box(minX: bounds.minX + inset, maxX: splitX - 1, minY: bounds.minY + inset, maxY: splitY - 1),
            Box(minX: splitX, maxX: bounds.maxX - inset, minY: bounds.minY + inset, maxY: splitY - 1),
            Box(minX: bounds.minX + inset, maxX: bounds.maxX - inset, minY: splitY, maxY: bounds.maxY - inset),
        ]
        let walls = rows(bounds.minX, bounds.maxX, bounds.minY, bounds.minY) + rows(bounds.minX, bounds.maxX, bounds.maxY, bounds.maxY)
            + rows(bounds.minX, bounds.minX, bounds.minY, bounds.maxY) + rows(bounds.maxX, bounds.maxX, bounds.minY, bounds.maxY)
        return ValetudoMap(
            layers: segments.map { layer("segment", $0, pixels: rows($0.minX, $0.maxX, $0.minY, $0.maxY)) } + [layer("wall", bounds, pixels: walls)],
            entities: [.init(type: "charger_location", points: [Double(bounds.minX + inset + 4) * 5, Double(bounds.minY + inset + 4) * 5]),
                       .init(type: "robot_position", points: [(Double(bounds.minX + bounds.maxX) * 2.5).rounded(), (Double(bounds.minY + bounds.maxY) * 2.5).rounded()], angle: 90)],
            pixelSize: 5, size: (6554, 6554))
    }
}
