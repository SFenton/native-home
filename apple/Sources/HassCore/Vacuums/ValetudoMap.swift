import Foundation

/// A Valetudo map as the robot exports it, read from the zTXt chunk of the map camera's PNG
/// (web `ValetudoMapCard.utils.ts`).
///
/// Coordinates: layer pixels are grid cells; entity points are centimetres (`grid × pixelSize`).
public struct ValetudoMap: Sendable, Equatable {
    /// Floor materials Valetudo can tag a segment with.
    public enum Material: String, Sendable { case carpet, carpetHigh = "carpet_high", carpetLow = "carpet_low", generic, tile, wood
        case woodHorizontal = "wood_horizontal", woodVertical = "wood_vertical" }

    public struct Layer: Sendable, Equatable {
        /// `floor`, `segment` or `wall`.
        public var type: String
        /// Expanded cells as flat `x, y` pairs.
        public var pixels: [Int32]
        /// Whether the layer carried pixels at all (dimension-only layers count only for legacy bounds).
        public var hasPixelRepresentation: Bool
        public var dimensions: Bounds?
        public var name: String?
        public var segmentId: String?
        public var active: Bool
        public var material: Material?

        public init(type: String, pixels: [Int32], hasPixelRepresentation: Bool = true, dimensions: Bounds? = nil,
                    name: String? = nil, segmentId: String? = nil, active: Bool = false, material: Material? = nil) {
            self.type = type
            self.pixels = pixels
            self.hasPixelRepresentation = hasPixelRepresentation
            self.dimensions = dimensions
            self.name = name
            self.segmentId = segmentId
            self.active = active
            self.material = material
        }

        /// Number of cells.
        public var cellCount: Int { pixels.count / 2 }
    }

    public struct Entity: Sendable, Equatable {
        /// e.g. `robot_position`, `charger_location`, `path`, `no_go_area`.
        public var type: String
        /// Flat `x, y` pairs in centimetres.
        public var points: [Double]
        /// Heading for the robot, in degrees.
        public var angle: Double?

        public init(type: String, points: [Double], angle: Double? = nil) {
            self.type = type
            self.points = points
            self.angle = angle
        }
    }

    /// Inclusive grid bounds.
    public struct Bounds: Sendable, Equatable {
        public var minX: Double, minY: Double, maxX: Double, maxY: Double
        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
        }
        /// Cells covered.
        public var area: Double { max(0, maxX - minX + 1) * max(0, maxY - minY + 1) }
    }

    public var layers: [Layer]
    public var entities: [Entity]
    public var pixelSize: Double
    public var size: (x: Double, y: Double)
    public var version: Int?

    public init(layers: [Layer], entities: [Entity], pixelSize: Double, size: (x: Double, y: Double), version: Int? = 2) {
        self.layers = layers
        self.entities = entities
        self.pixelSize = pixelSize
        self.size = size
        self.version = version
    }

    public static func == (lhs: ValetudoMap, rhs: ValetudoMap) -> Bool {
        lhs.layers == rhs.layers && lhs.entities == rhs.entities && lhs.pixelSize == rhs.pixelSize
            && lhs.size == rhs.size && lhs.version == rhs.version
    }

    /// The robot's reported position.
    public var robotPosition: Entity? { entities.first { $0.type == "robot_position" && $0.points.count >= 2 } }

    // MARK: - Bounds

    /// Grid bounds of everything drawable (`valetudoMapBounds`).
    public var bounds: Bounds {
        var drawable: [Bounds] = []
        var legacy: [Bounds] = []
        for layer in layers {
            if layer.hasPixelRepresentation {
                if let bounds = Self.pixelBounds(layer.pixels) { drawable.append(bounds) }
            } else if let dimensions = layer.dimensions, dimensions.minX <= dimensions.maxX, dimensions.minY <= dimensions.maxY {
                legacy.append(dimensions)
            }
        }
        let all = drawable.isEmpty ? legacy : drawable
        guard let first = all.first else {
            return .init(minX: 0, minY: 0, maxX: max(1, (size.x / pixelSize).rounded(.up)), maxY: max(1, (size.y / pixelSize).rounded(.up)))
        }
        return all.dropFirst().reduce(first) {
            .init(minX: min($0.minX, $1.minX), minY: min($0.minY, $1.minY), maxX: max($0.maxX, $1.maxX), maxY: max($0.maxY, $1.maxY))
        }
    }

    static func pixelBounds(_ pixels: [Int32]) -> Bounds? {
        guard pixels.count >= 2 else { return nil }
        var minX = Int32.max, minY = Int32.max, maxX = Int32.min, maxY = Int32.min
        var index = 0
        while index + 1 < pixels.count {
            let x = pixels[index], y = pixels[index + 1]
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            index += 2
        }
        return .init(minX: Double(minX), minY: Double(minY), maxX: Double(maxX), maxY: Double(maxY))
    }

    // MARK: - Rooms

    /// A zone found on the map by its segment name, for tap-to-select and order badges.
    public struct SelectableRoom: Sendable, Equatable {
        public var entityId: String
        public var title: String
        /// The segment cell closest to the segment's mean.
        public var centroid: (x: Double, y: Double)
        public var cells: Set<Int>
        public var segmentId: String?

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.entityId == rhs.entityId && lhs.centroid == rhs.centroid && lhs.cells == rhs.cells && lhs.segmentId == rhs.segmentId
        }
    }

    /// A cell's key (`valetudoMapPixelKey`).
    public static func cellKey(_ x: Int, _ y: Int) -> Int { x * 100_000 + y }

    /// The vacuum's zones that match a named segment (`selectableValetudoRooms`).
    public func selectableRooms(_ zones: [VacuumConfig.Zone]) -> [SelectableRoom] {
        func normalized(_ text: String) -> String {
            text.trimmed.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let zonesByName = Dictionary(zones.map { (normalized($0.segmentName), $0) }, uniquingKeysWith: { first, _ in first })
        return layers.compactMap { layer in
            guard layer.type == "segment", let name = layer.name, let zone = zonesByName[normalized(name)], layer.pixels.count >= 2 else { return nil }
            var sumX = 0.0, sumY = 0.0
            var cells = Set<Int>(minimumCapacity: layer.cellCount)
            var index = 0
            while index + 1 < layer.pixels.count {
                let x = Int(layer.pixels[index]), y = Int(layer.pixels[index + 1])
                sumX += Double(x); sumY += Double(y)
                cells.insert(Self.cellKey(x, y))
                index += 2
            }
            let count = Double(layer.cellCount)
            let meanX = sumX / count, meanY = sumY / count
            var best = (x: Double(layer.pixels[0]), y: Double(layer.pixels[1]))
            var bestDistance = Double.infinity
            index = 0
            while index + 1 < layer.pixels.count {
                let x = Double(layer.pixels[index]), y = Double(layer.pixels[index + 1])
                let distance = (x - meanX) * (x - meanX) + (y - meanY) * (y - meanY)
                if distance < bestDistance { best = (x, y); bestDistance = distance }
                index += 2
            }
            return SelectableRoom(entityId: zone.entityId, title: zone.title, centroid: best, cells: cells, segmentId: layer.segmentId)
        }
    }

    /// The room under a grid point (`valetudoRoomAtGridPoint`).
    public static func room(at point: (x: Double, y: Double), in rooms: [SelectableRoom]) -> SelectableRoom? {
        let candidates = [(Int(point.x.rounded(.down)), Int(point.y.rounded(.down))),
                          (Int(point.x.rounded()), Int(point.y.rounded()))]
        return rooms.first { room in candidates.contains { room.cells.contains(cellKey($0.0, $0.1)) } }
    }

    /// Entity types still drawn on a last-reported map (`REPORTED_MAP_VISIBLE_ENTITY_TYPES`).
    public static let reportedVisibleEntityTypes: Set<String> = [
        "carpet", "curtain", "no_go_area", "no_mop_area", "ramp", "robot_position", "threshold", "virtual_wall",
    ]

    /// The map without transient entities, for a map that is no longer live.
    public func reportedOnly() -> ValetudoMap {
        var copy = self
        copy.entities = entities.filter { Self.reportedVisibleEntityTypes.contains($0.type) }
        return copy
    }
}

// MARK: - Decoding

public enum ValetudoMapDecoder {
    public enum Failure: Error, Equatable {
        case notPNG
        case noMapData
        case invalidMap
        case inflateFailed
    }

    /// Extracts the map from a Valetudo camera PNG (`extractValetudoMapFromPngBytes`).
    public static func map(fromPNG data: Data) throws -> ValetudoMap {
        let bytes = [UInt8](data)
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { throw Failure.notPNG }
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let start = offset + 8
            let end = min(bytes.count, start + length)
            offset = start + length + 4
            if type == "IEND" { break }
            guard type == "zTXt", let separator = bytes[start..<end].firstIndex(of: 0) else { continue }
            let keyword = String(decoding: bytes[start..<separator], as: UTF8.self)
            guard keyword == "ValetudoMap", separator + 1 < end, bytes[separator + 1] == 0 else { continue }
            let compressed = Data(bytes[(separator + 2)..<end])
            return try map(fromJSON: try inflateZlib(compressed))
        }
        throw Failure.noMapData
    }

    /// Inflates zlib data (2-byte header, raw deflate, Adler-32 trailer).
    static func inflateZlib(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw Failure.inflateFailed }
        let deflate = data.subdata(in: (data.startIndex + 2)..<(data.endIndex - 4))
        do {
            return try (deflate as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw Failure.inflateFailed
        }
    }

    /// Parses Valetudo map JSON.
    public static func map(fromJSON data: Data) throws -> ValetudoMap {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["__class"] as? String == "ValetudoMap" else { throw Failure.invalidMap }
        let pixelSize = (object["pixelSize"] as? NSNumber)?.doubleValue ?? 5
        let size = object["size"] as? [String: Any]
        let metaData = object["metaData"] as? [String: Any]
        let layers = (object["layers"] as? [[String: Any]] ?? []).map(layer)
        let entities = (object["entities"] as? [[String: Any]] ?? []).map { entity -> ValetudoMap.Entity in
            let meta = entity["metaData"] as? [String: Any]
            return .init(type: entity["type"] as? String ?? "",
                         points: (entity["points"] as? [NSNumber] ?? []).map(\.doubleValue),
                         angle: (meta?["angle"] as? NSNumber)?.doubleValue)
        }
        return ValetudoMap(layers: layers, entities: entities, pixelSize: pixelSize,
                           size: ((size?["x"] as? NSNumber)?.doubleValue ?? 0, (size?["y"] as? NSNumber)?.doubleValue ?? 0),
                           version: (metaData?["version"] as? NSNumber)?.intValue)
    }

    private static func layer(_ object: [String: Any]) -> ValetudoMap.Layer {
        var pixels: [Int32] = []
        let hasPixels = object["pixels"] != nil || object["compressedPixels"] != nil
        if let raw = object["pixels"] as? [NSNumber], !raw.isEmpty {
            pixels = raw.map { $0.int32Value }
        } else if let compressed = object["compressedPixels"] as? [NSNumber] {
            pixels = expand(compressed.map { $0.int32Value })
        }
        let meta = object["metaData"] as? [String: Any]
        let segmentId: String? = (meta?["segmentId"] as? String) ?? (meta?["segmentId"] as? NSNumber)?.stringValue
        var dimensions: ValetudoMap.Bounds?
        if let dims = object["dimensions"] as? [String: Any], let x = dims["x"] as? [String: Any], let y = dims["y"] as? [String: Any],
           let minX = (x["min"] as? NSNumber)?.doubleValue, let maxX = (x["max"] as? NSNumber)?.doubleValue,
           let minY = (y["min"] as? NSNumber)?.doubleValue, let maxY = (y["max"] as? NSNumber)?.doubleValue {
            dimensions = .init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        }
        let name = (meta?["name"] as? String).flatMap { $0.trimmed.isEmpty ? nil : $0.trimmed }
        return .init(type: object["type"] as? String ?? "", pixels: pixels, hasPixelRepresentation: hasPixels,
                     dimensions: dimensions, name: name, segmentId: segmentId,
                     active: meta?["active"] as? Bool ?? false,
                     material: (meta?["material"] as? String).flatMap(ValetudoMap.Material.init(rawValue:)))
    }

    /// Run-length rows `[x, y, count, …]` to flat cells (`expandValetudoLayerPixels`).
    public static func expand(_ compressed: [Int32]) -> [Int32] {
        var pixels: [Int32] = []
        var index = 0
        while index + 2 < compressed.count {
            let startX = compressed[index], y = compressed[index + 1], count = compressed[index + 2]
            if count > 0 {
                pixels.reserveCapacity(pixels.count + Int(count) * 2)
                for offset in 0..<count { pixels.append(startX + offset); pixels.append(y) }
            }
            index += 3
        }
        return pixels
    }
}
