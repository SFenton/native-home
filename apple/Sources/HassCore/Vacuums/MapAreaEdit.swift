import CoreGraphics
import Foundation

/// What a drag on the area editor's map does, and the VoiceOver edits that stand in for it (web `ValetudoMapCard`
/// pointer handling). Pure, so the editor view only routes gesture values here.
public enum MapAreaEdit {
    // MARK: - Drags

    /// What the current drag does, decided when it starts.
    public enum Gesture: Equatable, Sendable {
        /// Draw mode: a new rectangle from `anchor`.
        case draw(anchor: MapPoint)
        /// Inside the area: move it.
        case move(origin: MapGridRect, start: MapPoint)
        /// On a corner handle: resize from that corner.
        case resize(corner: MapGridRect.Corner, origin: MapGridRect)
        /// Anywhere else: pan the map.
        case pan(origin: MapViewport, start: CGPoint)
    }

    /// Chooses the drag's job from where it started.
    /// - Parameters:
    ///   - start: The start point in grid cells.
    ///   - location: The start point in frame points (for panning).
    ///   - drawMode: Draw is selected.
    ///   - area: The current area, if any.
    ///   - corner: The resize handle within reach of the start, if any.
    ///   - viewport: The viewport when the drag started.
    public static func begin(start: MapPoint, location: CGPoint, drawMode: Bool, area: MapGridRect?,
                             corner: MapGridRect.Corner?, viewport: MapViewport) -> Gesture {
        if drawMode { return .draw(anchor: start) }
        if let area, let corner { return .resize(corner: corner, origin: area) }
        if let area, start.x >= area.x0, start.x <= area.x1, start.y >= area.y0, start.y <= area.y1 {
            return .move(origin: area, start: start)
        }
        return .pan(origin: viewport, start: location)
    }

    /// The result of one drag update: a draft area, or a new viewport.
    public struct Step: Equatable, Sendable {
        public var draft: MapGridRect?
        public var viewport: MapViewport?
    }

    /// Applies a drag update.
    /// - Parameters:
    ///   - gesture: The drag's job from ``begin(start:location:drawMode:area:corner:viewport:)``.
    ///   - current: The current point in grid cells.
    ///   - location: The current point in frame points.
    ///   - stage: The drawn map's geometry (for panning).
    ///   - interaction: The editable geometry (for area limits).
    ///   - frame: The map frame's size.
    ///   - rotation: The map's rotation in degrees.
    ///   - minimum: The smallest side in cells.
    public static func update(_ gesture: Gesture, current: MapPoint, location: CGPoint, stage: MapStageGeometry,
                              interaction: MapStageGeometry, frame: CGSize, rotation: Double, minimum: Double) -> Step {
        switch gesture {
        case let .draw(anchor):
            return Step(draft: MapGeometry.rect(interaction, from: anchor, to: current, minimum: minimum))
        case let .move(origin, start):
            return Step(draft: MapGeometry.translate(interaction, origin, by: .init(x: current.x - start.x, y: current.y - start.y)))
        case let .resize(corner, origin):
            return Step(draft: MapGeometry.resize(interaction, origin, corner: corner, to: current, minimum: minimum))
        case let .pan(origin, start):
            var next = origin
            next.panX += location.x - start.x
            next.panY += location.y - start.y
            return Step(viewport: MapGeometry.clamp(stage, frame: frame, viewport: next, rotation: rotation))
        }
    }

    // MARK: - VoiceOver

    /// The map's accessibility actions, which replace dragging for VoiceOver.
    public enum Nudge: CaseIterable, Sendable {
        case left, right, up, down, larger, smaller

        /// The action's name.
        public var title: String {
            switch self {
            case .left: "Move area left"
            case .right: "Move area right"
            case .up: "Move area up"
            case .down: "Move area down"
            case .larger: "Make area larger"
            case .smaller: "Make area smaller"
            }
        }
    }

    /// Moves or resizes `rect` by half the minimum side (at least 2 cells), kept inside the map.
    public static func nudge(_ rect: MapGridRect, _ nudge: Nudge, interaction: MapStageGeometry, minimum: Double) -> MapGridRect {
        let step = max(2, minimum / 2)
        switch nudge {
        case .left: return MapGeometry.translate(interaction, rect, by: .init(x: -step, y: 0))
        case .right: return MapGeometry.translate(interaction, rect, by: .init(x: step, y: 0))
        case .up: return MapGeometry.translate(interaction, rect, by: .init(x: 0, y: -step))
        case .down: return MapGeometry.translate(interaction, rect, by: .init(x: 0, y: step))
        case .larger: return MapGeometry.resize(interaction, rect, corner: .c, to: .init(x: rect.x1 + step, y: rect.y1 + step), minimum: minimum)
        case .smaller: return MapGeometry.resize(interaction, rect, corner: .c, to: .init(x: rect.x1 - step, y: rect.y1 - step), minimum: minimum)
        }
    }

    /// The area VoiceOver's Draw starts from: centred, at least 30 cells or the minimum side.
    public static func voiceOverStart(_ interaction: MapStageGeometry, minimum: Double) -> MapGridRect {
        MapGeometry.defaultRect(interaction, size: max(30, minimum))
    }
}
