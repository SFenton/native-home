import Foundation

/// Crops a map to the configured rooms when the rest of the floor is stray exploration
/// (web `ValetudoMapFocus.ts`). Any doubt falls back to the full map.
public struct ValetudoMapFocus: Sendable, Equatable {
    public enum Mode: Sendable { case focused, full }
    public enum Reason: String, Sendable {
        case activeRouteExcluded = "active-route-excluded", activeSegmentExcluded = "active-segment-excluded"
        case anchorOutsideFocus = "anchor-outside-focus", focused, insufficientBenefit = "insufficient-benefit"
        case invalidMap = "invalid-map", missingAnchor = "missing-anchor", missingRequiredSegment = "missing-required-segment"
        case namedSegmentExcluded = "named-segment-excluded", overlappingSegments = "overlapping-segments"
        case segmentNameMismatch = "segment-name-mismatch", unconfigured
    }

    public var mode: Mode
    public var reason: Reason
    public var acceptedSegmentIds: Set<String>
    public var excludedSegmentIds: [String]
    public var excludedAreaM2: Double
    /// Where drawing is allowed.
    public var interactionBounds: ValetudoMap.Bounds
    /// What the frame shows.
    public var viewBounds: ValetudoMap.Bounds
    public var rawBounds: ValetudoMap.Bounds
    /// Wall cells drawn when focused; `nil` draws every wall.
    public var renderWallCells: Set<Int>?

    static let directions = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    static let routeTypes: Set<String> = ["active_zone", "go_to_target", "path", "predicted_path"]

    private static func full(_ raw: ValetudoMap.Bounds, _ ids: Set<String>, _ reason: Reason) -> ValetudoMapFocus {
        .init(mode: .full, reason: reason, acceptedSegmentIds: ids, excludedSegmentIds: [], excludedAreaM2: 0,
              interactionBounds: raw, viewBounds: raw, rawBounds: raw, renderWallCells: nil)
    }

    /// Resolves the focus for a map and policy (`resolveValetudoMapFocus`).
    public static func resolve(_ map: ValetudoMap, policy: VacuumConfig.MapFocus?) -> ValetudoMapFocus {
        let raw = map.bounds
        let segments = map.layers.filter { $0.type == "segment" && $0.segmentId != nil }
        let allIds = Set(segments.compactMap(\.segmentId))
        guard let policy, !policy.requiredSegments.isEmpty else { return full(raw, allIds, .unconfigured) }
        guard map.version == 2, map.pixelSize > 0, !segments.isEmpty else { return full(raw, allIds, .invalidMap) }

        var byId: [String: [ValetudoMap.Layer]] = [:]
        var cells: [Int: String] = [:]
        for segment in segments {
            guard let id = segment.segmentId else { continue }
            byId[id, default: []].append(segment)
            var index = 0
            while index + 1 < segment.pixels.count {
                let key = ValetudoMap.cellKey(Int(segment.pixels[index]), Int(segment.pixels[index + 1]))
                if let existing = cells[key], existing != id { return full(raw, allIds, .overlappingSegments) }
                cells[key] = id
                index += 2
            }
        }

        for required in policy.requiredSegments {
            guard let matching = byId[required.id], !matching.isEmpty else { return full(raw, allIds, .missingRequiredSegment) }
            if let name = required.name, !matching.contains(where: { $0.name == name }) { return full(raw, allIds, .segmentNameMismatch) }
        }

        // Segment ids stay the indivisible unit; diagonal contact keeps rooms that only touch by rasterization.
        var graph: [String: Set<String>] = Dictionary(uniqueKeysWithValues: allIds.map { ($0, []) })
        for (key, id) in cells {
            let x = key / 100_000, y = key - x * 100_000
            for (dx, dy) in directions {
                guard let neighbor = cells[ValetudoMap.cellKey(x + dx, y + dy)], neighbor != id else { continue }
                graph[id, default: []].insert(neighbor)
                graph[neighbor, default: []].insert(id)
            }
        }

        // Only named or active segments expand the focus.
        let expandable = Set(byId.filter { $0.value.contains { $0.name != nil || $0.active } }.keys)
        var accepted = Set<String>()
        for required in policy.requiredSegments {
            var queue = [required.id]
            accepted.insert(required.id)
            var index = 0
            while index < queue.count {
                for neighbor in graph[queue[index]] ?? [] where !accepted.contains(neighbor) && expandable.contains(neighbor) {
                    accepted.insert(neighbor)
                    queue.append(neighbor)
                }
                index += 1
            }
        }

        let excluded = allIds.subtracting(accepted).sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        let excludedSet = Set(excluded)
        for id in excluded {
            let layers = byId[id] ?? []
            if layers.contains(where: { $0.name != nil }) { return full(raw, allIds, .namedSegmentExcluded) }
            if layers.contains(where: \.active) { return full(raw, allIds, .activeSegmentExcluded) }
        }

        for type in ["robot_position", "charger_location"] {
            guard let entity = map.entities.first(where: { $0.type == type }) else { return full(raw, allIds, .missingAnchor) }
            guard let nearest = nearestSegment(entity.points, map.pixelSize, cells, radius: 3), accepted.contains(nearest) else {
                return full(raw, allIds, .anchorOutsideFocus)
            }
        }

        // Transient navigation validates the focus but never expands it.
        if map.entities.contains(where: { routeTypes.contains($0.type) && touchesExcluded($0, map.pixelSize, cells, excludedSet) }) {
            return full(raw, allIds, .activeRouteExcluded)
        }

        let totalCells = segments.reduce(0) { $0 + $1.cellCount }
        let excludedCells = segments.filter { excludedSet.contains($0.segmentId ?? "") }.reduce(0) { $0 + $1.cellCount }
        let excludedArea = Double(excludedCells) * map.pixelSize * map.pixelSize / 10_000
        let excludedFraction = totalCells > 0 ? Double(excludedCells) / Double(totalCells) : 0
        if excludedArea < (policy.minimumExcludedAreaM2 ?? 4) || excludedFraction < (policy.minimumExcludedFraction ?? 0.1) {
            return full(raw, allIds, .insufficientBenefit)
        }

        var interaction: ValetudoMap.Bounds?
        for segment in segments where accepted.contains(segment.segmentId ?? "") {
            guard let bounds = ValetudoMap.pixelBounds(segment.pixels) else { continue }
            interaction = interaction.map { union($0, bounds) } ?? bounds
        }
        guard let interactionBounds = interaction else { return full(raw, allIds, .invalidMap) }

        var core = interactionBounds
        var wallCells = Set<Int>()
        let wallRadius = max(1, Int(((policy.wallAssociationCm ?? 20) / map.pixelSize).rounded(.up)))
        for layer in map.layers where layer.type == "wall" {
            var index = 0
            while index + 1 < layer.pixels.count {
                let x = Int(layer.pixels[index]), y = Int(layer.pixels[index + 1])
                index += 2
                let ownership = wallOwnership(x, y, wallRadius, cells, accepted)
                if ownership == .excluded { continue }
                wallCells.insert(ValetudoMap.cellKey(x, y))
                if ownership == .accepted { core = union(core, .init(minX: Double(x), minY: Double(y), maxX: Double(x), maxY: Double(y))) }
            }
        }

        let padding = max(0, ((policy.paddingCm ?? 15) / map.pixelSize).rounded(.up))
        let view = ValetudoMap.Bounds(minX: max(raw.minX, core.minX - padding), minY: max(raw.minY, core.minY - padding),
                                      maxX: min(raw.maxX, core.maxX + padding), maxY: min(raw.maxY, core.maxY + padding))
        let ratio = raw.area > 0 ? view.area / raw.area : 1
        if ratio > (policy.maximumViewAreaRatio ?? 0.85) { return full(raw, allIds, .insufficientBenefit) }

        return .init(mode: .focused, reason: .focused, acceptedSegmentIds: accepted, excludedSegmentIds: excluded,
                     excludedAreaM2: excludedArea, interactionBounds: interactionBounds, viewBounds: view, rawBounds: raw,
                     renderWallCells: wallCells)
    }

    // MARK: - Helpers

    private static func union(_ a: ValetudoMap.Bounds, _ b: ValetudoMap.Bounds) -> ValetudoMap.Bounds {
        .init(minX: min(a.minX, b.minX), minY: min(a.minY, b.minY), maxX: max(a.maxX, b.maxX), maxY: max(a.maxY, b.maxY))
    }

    static func nearestSegment(_ point: [Double], _ pixelSize: Double, _ cells: [Int: String], radius: Double) -> String? {
        guard point.count >= 2, pixelSize > 0 else { return nil }
        let gx = point[0] / pixelSize, gy = point[1] / pixelSize
        var best: (distance: Double, id: String)?
        for y in Int((gy - radius).rounded(.down))...Int((gy + radius).rounded(.up)) {
            for x in Int((gx - radius).rounded(.down))...Int((gx + radius).rounded(.up)) {
                guard let id = cells[ValetudoMap.cellKey(x, y)] else { continue }
                let distance = (Double(x) - gx) * (Double(x) - gx) + (Double(y) - gy) * (Double(y) - gy)
                if distance > radius * radius || (best.map { distance >= $0.distance } ?? false) { continue }
                best = (distance, id)
            }
        }
        return best?.id
    }

    private static func lineTouches(_ start: (Double, Double), _ end: (Double, Double), _ pixelSize: Double,
                                    _ cells: [Int: String], _ excluded: Set<String>) -> Bool {
        let sx = start.0 / pixelSize, sy = start.1 / pixelSize, ex = end.0 / pixelSize, ey = end.1 / pixelSize
        let steps = max(1, Int((max(abs(ex - sx), abs(ey - sy)) * 2).rounded(.up)))
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let point = [(sx + (ex - sx) * progress) * pixelSize, (sy + (ey - sy) * progress) * pixelSize]
            if let id = nearestSegment(point, pixelSize, cells, radius: 1), excluded.contains(id) { return true }
        }
        return false
    }

    private static func touchesExcluded(_ entity: ValetudoMap.Entity, _ pixelSize: Double, _ cells: [Int: String], _ excluded: Set<String>) -> Bool {
        let points = entity.points
        var index = 0
        while index + 1 < points.count {
            if let id = nearestSegment([points[index], points[index + 1]], pixelSize, cells, radius: 1), excluded.contains(id) { return true }
            index += 2
        }
        index = 0
        while index + 3 < points.count {
            if lineTouches((points[index], points[index + 1]), (points[index + 2], points[index + 3]), pixelSize, cells, excluded) { return true }
            index += 2
        }
        guard entity.type == "active_zone", points.count >= 6 else { return false }
        if lineTouches((points[points.count - 2], points[points.count - 1]), (points[0], points[1]), pixelSize, cells, excluded) { return true }
        for (key, id) in cells where excluded.contains(id) {
            let x = key / 100_000, y = key - x * 100_000
            if pointInPolygon((Double(x) + 0.5) * pixelSize, (Double(y) + 0.5) * pixelSize, points) { return true }
        }
        return false
    }

    static func pointInPolygon(_ x: Double, _ y: Double, _ points: [Double]) -> Bool {
        var inside = false
        var previous = points.count - 2
        var current = 0
        while current < points.count - 1 {
            let cx = points[current], cy = points[current + 1], px = points[previous], py = points[previous + 1]
            if (cy > y) != (py > y), x < (px - cx) * (y - cy) / (py - cy) + cx { inside.toggle() }
            previous = current
            current += 2
        }
        return inside
    }

    private enum Ownership { case accepted, shared, excluded }

    private static func wallOwnership(_ x: Int, _ y: Int, _ radius: Int, _ cells: [Int: String], _ accepted: Set<String>) -> Ownership {
        var acceptedDistance = Int.max, excludedDistance = Int.max
        for dy in -radius...radius {
            for dx in -radius...radius {
                let distance = dx * dx + dy * dy
                guard distance <= radius * radius, let id = cells[ValetudoMap.cellKey(x + dx, y + dy)] else { continue }
                if accepted.contains(id) { acceptedDistance = min(acceptedDistance, distance) }
                else { excludedDistance = min(excludedDistance, distance) }
            }
        }
        if acceptedDistance == .max { return .excluded }
        if acceptedDistance < excludedDistance { return .accepted }
        return acceptedDistance == excludedDistance ? .shared : .excluded
    }

    /// Whether a drawn rectangle stays inside bounds (`mapGridRectWithinBounds`).
    public static func rect(_ rect: MapGridRect, isWithin bounds: ValetudoMap.Bounds) -> Bool {
        let n = rect.normalized
        return n.x0 >= bounds.minX && n.x1 <= bounds.maxX + 1 && n.y0 >= bounds.minY && n.y1 <= bounds.maxY + 1
    }
}
