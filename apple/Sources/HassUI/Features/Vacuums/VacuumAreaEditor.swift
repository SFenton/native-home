import HassCore
import HassDesign
import SwiftUI

// MARK: - Editing math

extension ValetudoMapScene {
    /// Where a pinch started: the zoom then, the map point under the fingers and their frame point.
    typealias PinchStart = (zoom: Double, anchor: MapPoint, at: MapPoint)

    /// The smallest area side in cells (the vacuum's `minimumSizeCm`, 25 cm by default).
    func minimumAreaCells(_ vacuum: VacuumConfig) -> Double {
        ((vacuum.areaCleaning?.minimumSizeCm ?? 25) / interactionGeometry.pixelSize).rounded(.up)
    }

    /// The grid cell under a frame point.
    func gridPoint(_ point: CGPoint, size: CGSize, viewport: MapViewport) -> MapPoint {
        MapGeometry.gridPoint(geometry, matrix: matrix(size: size, viewport: viewport), framePoint: .init(x: point.x, y: point.y))
    }

    /// The resize handle nearest a frame point and within 22 pt (the web's hit radius) of it. On a small area the hit
    /// circles overlap at zoom 1, so the nearest wins, not the first in the list.
    func corner(near point: CGPoint, of rect: MapGridRect, size: CGSize, viewport: MapViewport) -> MapGridRect.Corner? {
        let m = matrix(size: size, viewport: viewport)
        let framePoints = MapGridRect.Corner.allCases.map { corner in
            (corner: corner, point: MapGeometry.framePoint(geometry, matrix: m, gridPoint: rect.point(corner)))
        }
        return Self.nearestCorner(to: point, in: framePoints.map { ($0.corner, CGPoint(x: $0.point.x, y: $0.point.y)) }, radius: 22)
    }

    /// The corner whose frame point is closest to `point`, if within `radius`; ties go to the earlier corner.
    static func nearestCorner(to point: CGPoint, in corners: [(MapGridRect.Corner, CGPoint)], radius: Double) -> MapGridRect.Corner? {
        corners
            .map { (corner: $0.0, distance: hypot(Double($0.1.x - point.x), Double($0.1.y - point.y))) }
            .filter { $0.distance <= radius }
            .min { $0.distance < $1.distance }?.corner
    }

    /// The viewport after zooming by `factor` about the frame's centre (the map's VoiceOver Zoom In and Zoom Out).
    func zoomed(_ viewport: MapViewport, by factor: Double, size: CGSize) -> MapViewport {
        let start = pinchStart(at: CGPoint(x: size.width / 2, y: size.height / 2), size: size, viewport: viewport)
        return pinched(start, magnification: factor, size: size)
    }

    /// One drag update: the drag's job (chosen on its first update, then kept) and what it changes.
    func drag(_ gesture: MapAreaEdit.Gesture?, from start: CGPoint, to location: CGPoint, size: CGSize, viewport: MapViewport,
              drawMode: Bool, area: MapGridRect?, minimum: Double) -> (MapAreaEdit.Gesture, MapAreaEdit.Step) {
        let job = gesture ?? MapAreaEdit.begin(
            start: gridPoint(start, size: size, viewport: viewport), location: start, drawMode: drawMode, area: area,
            corner: area.flatMap { corner(near: start, of: $0, size: size, viewport: viewport) }, viewport: viewport)
        let step = MapAreaEdit.update(job, current: gridPoint(location, size: size, viewport: viewport), location: location,
                                      stage: geometry, interaction: interactionGeometry, frame: size, rotation: rotation, minimum: minimum)
        return (job, step)
    }

    /// Starts a pinch at a frame point.
    func pinchStart(at point: CGPoint, size: CGSize, viewport: MapViewport) -> PinchStart {
        let at = MapPoint(x: point.x, y: point.y)
        return (viewport.zoom, matrix(size: size, viewport: viewport).inverted.apply(at), at)
    }

    /// The viewport after magnifying from `start`, keeping the pinched point under the fingers.
    func pinched(_ start: PinchStart, magnification: Double, size: CGSize) -> MapViewport {
        MapGeometry.viewport(geometry, frame: size, anchor: start.anchor, at: start.at, zoom: start.zoom * magnification, rotation: rotation)
    }
}
