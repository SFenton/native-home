import CoreGraphics
import Foundation

/// A point in map grid cells or view points.
public struct MapPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A rectangle in global grid cells (web `MapGridRect`).
public struct MapGridRect: Equatable, Sendable {
    public var x0: Double, x1: Double, y0: Double, y1: Double
    public init(x0: Double, x1: Double, y0: Double, y1: Double) { self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1 }

    /// With `x0 ≤ x1` and `y0 ≤ y1`.
    public var normalized: MapGridRect {
        .init(x0: min(x0, x1), x1: max(x0, x1), y0: min(y0, y1), y1: max(y0, y1))
    }

    /// Width and height in centimetres (`mapGridRectDimensionsCm`).
    public func dimensionsCm(pixelSize: Double) -> (width: Double, height: Double) {
        (((x1 - x0) * pixelSize).rounded(), ((y1 - y0) * pixelSize).rounded())
    }

    /// The zone script's service data (`mapGridRectToServiceData`).
    public func serviceData(pixelSize: Double) -> [String: JSONValue] {
        let n = normalized
        return [
            "x_min_cm": .number((n.x0 * pixelSize).rounded()),
            "x_max_cm": .number((n.x1 * pixelSize).rounded()),
            "y_min_cm": .number((n.y0 * pixelSize).rounded()),
            "y_max_cm": .number((n.y1 * pixelSize).rounded()),
        ]
    }

    /// One of the four resize handles: A top-left, B top-right, C bottom-right, D bottom-left.
    public enum Corner: String, CaseIterable, Sendable { case a, b, c, d }

    /// A corner's point.
    public func point(_ corner: Corner) -> MapPoint {
        switch corner {
        case .a: .init(x: x0, y: y0)
        case .b: .init(x: x1, y: y0)
        case .c: .init(x: x1, y: y1)
        case .d: .init(x: x0, y: y1)
        }
    }
}

/// A 2-D affine transform `[a c e; b d f]` (web `AffineMatrix`).
public struct Affine: Equatable, Sendable {
    public var a, b, c, d, e, f: Double
    public init(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f
    }

    public static let identity = Affine(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
    static func translation(_ x: Double, _ y: Double) -> Affine { .init(a: 1, b: 0, c: 0, d: 1, e: x, f: y) }
    static func scale(_ s: Double) -> Affine { .init(a: s, b: 0, c: 0, d: s, e: 0, f: 0) }
    static func rotation(degrees: Double) -> Affine {
        let r = degrees * .pi / 180
        return .init(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), e: 0, f: 0)
    }

    /// `self × other` (apply `other` first).
    public func then(_ other: Affine) -> Affine {
        .init(a: a * other.a + c * other.b, b: b * other.a + d * other.b,
              c: a * other.c + c * other.d, d: b * other.c + d * other.d,
              e: a * other.e + c * other.f + e, f: b * other.e + d * other.f + f)
    }

    public func apply(_ p: MapPoint) -> MapPoint { .init(x: a * p.x + c * p.y + e, y: b * p.x + d * p.y + f) }

    public var inverted: Affine {
        let det = a * d - b * c
        guard abs(det) > .ulpOfOne else { return .identity }
        return .init(a: d / det, b: -b / det, c: -c / det, d: a / det, e: (c * f - d * e) / det, f: (b * e - a * f) / det)
    }

    /// Uniform scale factor.
    public var scale: Double { hypot(a, b) }
}

/// The drawn part of a map in local units (web `ValetudoMapStageGeometry`).
public struct MapStageGeometry: Equatable, Sendable {
    public var bounds: ValetudoMap.Bounds
    public var width: Double, height: Double
    public var minGridX: Double, minGridY: Double, maxGridX: Double, maxGridY: Double
    public var pixelSize: Double

    /// `valetudoMapStageGeometry`.
    public init(map: ValetudoMap, mapScale: Double, bounds: ValetudoMap.Bounds? = nil) {
        let bounds = bounds ?? map.bounds
        let scale = max(1, mapScale)
        let pixelWidth = max(1, ((bounds.maxX - bounds.minX + 2) * scale).rounded(.up))
        let pixelHeight = max(1, ((bounds.maxY - bounds.minY + 2) * scale).rounded(.up))
        self.bounds = bounds
        width = pixelWidth / scale
        height = pixelHeight / scale
        minGridX = bounds.minX
        minGridY = bounds.minY
        maxGridX = bounds.maxX + 1
        maxGridY = bounds.maxY + 1
        pixelSize = map.pixelSize
    }
}

/// Pan and zoom of the map frame.
public struct MapViewport: Equatable, Sendable {
    public var panX: Double, panY: Double, zoom: Double
    public init(panX: Double = 0, panY: Double = 0, zoom: Double = 1) { self.panX = panX; self.panY = panY; self.zoom = zoom }
    public static let initial = MapViewport()
    public static let zoomRange: ClosedRange<Double> = 1...10
}

/// Map ↔ view transforms and rectangle editing (web `ValetudoMapGeometry.ts`).
public enum MapGeometry {
    static func rotatedSize(_ g: MapStageGeometry, _ degrees: Double) -> (width: Double, height: Double) {
        let r = degrees * .pi / 180
        let c = abs(cos(r)), s = abs(sin(r))
        return (g.width * c + g.height * s, g.width * s + g.height * c)
    }

    /// Width over height of the rotated stage.
    public static func aspectRatio(_ g: MapStageGeometry, rotation: Double) -> Double {
        let size = rotatedSize(g, rotation)
        return size.width > 0 && size.height > 0 ? size.width / size.height : 1
    }

    /// Local stage units → frame points (`mapViewportMatrix`).
    public static func matrix(_ g: MapStageGeometry, frame: CGSize, viewport: MapViewport, rotation: Double) -> Affine {
        let fw = Double(frame.width), fh = Double(frame.height)
        guard fw > 0, fh > 0 else { return .identity }
        let rotated = rotatedSize(g, rotation)
        let fit = min(fw / max(rotated.width, 1), fh / max(rotated.height, 1))
        return Affine.translation(fw / 2 + viewport.panX, fh / 2 + viewport.panY)
            .then(.rotation(degrees: rotation))
            .then(.scale(fit * viewport.zoom))
            .then(.translation(-g.width / 2, -g.height / 2))
    }

    /// Keeps at least a quarter of the map on screen (`clampMapViewport`).
    public static func clamp(_ g: MapStageGeometry, frame: CGSize, viewport: MapViewport, rotation: Double, minimumVisible: Double = 0.25) -> MapViewport {
        let m = matrix(g, frame: frame, viewport: viewport, rotation: rotation)
        let corners = [MapPoint(x: 0, y: 0), .init(x: g.width, y: 0), .init(x: g.width, y: g.height), .init(x: 0, y: g.height)].map(m.apply)
        let left = corners.map(\.x).min() ?? 0, right = corners.map(\.x).max() ?? 0
        let top = corners.map(\.y).min() ?? 0, bottom = corners.map(\.y).max() ?? 0
        let fw = Double(frame.width), fh = Double(frame.height)
        let visibleX = min(fw, right - left) * minimumVisible
        let visibleY = min(fh, bottom - top) * minimumVisible
        var result = viewport
        if right < visibleX { result.panX += visibleX - right }
        if left > fw - visibleX { result.panX -= left - (fw - visibleX) }
        if bottom < visibleY { result.panY += visibleY - bottom }
        if top > fh - visibleY { result.panY -= top - (fh - visibleY) }
        return result
    }

    /// Zooms keeping `anchor` (local units) under `point` (frame points) (`viewportForAnchor`).
    public static func viewport(_ g: MapStageGeometry, frame: CGSize, anchor: MapPoint, at point: MapPoint, zoom: Double, rotation: Double) -> MapViewport {
        let zoom = min(MapViewport.zoomRange.upperBound, max(MapViewport.zoomRange.lowerBound, zoom))
        let rendered = matrix(g, frame: frame, viewport: .init(zoom: zoom), rotation: rotation).apply(anchor)
        return clamp(g, frame: frame, viewport: .init(panX: point.x - rendered.x, panY: point.y - rendered.y, zoom: zoom), rotation: rotation)
    }

    /// Frame point → global grid.
    public static func gridPoint(_ g: MapStageGeometry, matrix: Affine, framePoint: MapPoint) -> MapPoint {
        let local = matrix.inverted.apply(framePoint)
        return .init(x: local.x + g.minGridX, y: local.y + g.minGridY)
    }

    /// Global grid → frame point.
    public static func framePoint(_ g: MapStageGeometry, matrix: Affine, gridPoint: MapPoint) -> MapPoint {
        matrix.apply(.init(x: gridPoint.x - g.minGridX, y: gridPoint.y - g.minGridY))
    }

    static func clampPoint(_ g: MapStageGeometry, _ p: MapPoint) -> MapPoint {
        .init(x: min(g.maxGridX, max(g.minGridX, p.x.rounded())), y: min(g.maxGridY, max(g.minGridY, p.y.rounded())))
    }

    /// A rectangle from a drag, at least `minimum` cells per side (`mapGridRectFromPoints`).
    public static func rect(_ g: MapStageGeometry, from anchorPoint: MapPoint, to currentPoint: MapPoint, minimum: Double) -> MapGridRect {
        let anchor = clampPoint(g, anchorPoint), current = clampPoint(g, currentPoint)
        var r = MapGridRect(x0: anchor.x, x1: current.x, y0: anchor.y, y1: current.y).normalized
        if r.x1 - r.x0 < minimum {
            if current.x >= anchor.x {
                r.x1 = min(g.maxGridX, r.x0 + minimum); r.x0 = max(g.minGridX, r.x1 - minimum)
            } else {
                r.x0 = max(g.minGridX, r.x1 - minimum); r.x1 = min(g.maxGridX, r.x0 + minimum)
            }
        }
        if r.y1 - r.y0 < minimum {
            if current.y >= anchor.y {
                r.y1 = min(g.maxGridY, r.y0 + minimum); r.y0 = max(g.minGridY, r.y1 - minimum)
            } else {
                r.y0 = max(g.minGridY, r.y1 - minimum); r.y1 = min(g.maxGridY, r.y0 + minimum)
            }
        }
        return r
    }

    /// Moves a rectangle, keeping it on the map (`translateMapGridRect`).
    public static func translate(_ g: MapStageGeometry, _ r: MapGridRect, by delta: MapPoint) -> MapGridRect {
        let width = r.x1 - r.x0, height = r.y1 - r.y0
        let x0 = min(g.maxGridX - width, max(g.minGridX, (r.x0 + delta.x).rounded()))
        let y0 = min(g.maxGridY - height, max(g.minGridY, (r.y0 + delta.y).rounded()))
        return .init(x0: x0, x1: x0 + width, y0: y0, y1: y0 + height)
    }

    /// Drags one corner, keeping the minimum size (`resizeMapGridRectCorner`).
    public static func resize(_ g: MapStageGeometry, _ r: MapGridRect, corner: MapGridRect.Corner, to point: MapPoint, minimum: Double) -> MapGridRect {
        let p = clampPoint(g, point)
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        let x0 = min(r.x0, g.maxGridX - minimum), x1 = max(r.x1, g.minGridX + minimum)
        let y0 = min(r.y0, g.maxGridY - minimum), y1 = max(r.y1, g.minGridY + minimum)
        switch corner {
        case .a: return .init(x0: clamp(p.x, g.minGridX, x1 - minimum), x1: x1, y0: clamp(p.y, g.minGridY, y1 - minimum), y1: y1)
        case .b: return .init(x0: x0, x1: clamp(p.x, x0 + minimum, g.maxGridX), y0: clamp(p.y, g.minGridY, y1 - minimum), y1: y1)
        case .d: return .init(x0: clamp(p.x, g.minGridX, x1 - minimum), x1: x1, y0: y0, y1: clamp(p.y, y0 + minimum, g.maxGridY))
        case .c: return .init(x0: x0, x1: clamp(p.x, x0 + minimum, g.maxGridX), y0: y0, y1: clamp(p.y, y0 + minimum, g.maxGridY))
        }
    }

    /// A centred starting rectangle (`defaultMapGridRect`).
    public static func defaultRect(_ g: MapStageGeometry, size: Double = 30) -> MapGridRect {
        let width = min(size, g.maxGridX - g.minGridX), height = min(size, g.maxGridY - g.minGridY)
        let x0 = ((g.minGridX + g.maxGridX - width) / 2).rounded(), y0 = ((g.minGridY + g.maxGridY - height) / 2).rounded()
        return .init(x0: x0, x1: x0 + width, y0: y0, y1: y0 + height)
    }
}
