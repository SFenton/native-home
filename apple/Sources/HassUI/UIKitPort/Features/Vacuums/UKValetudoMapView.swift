#if os(iOS)
import CoreGraphics
import HassCore
import HassDesign
import UIKit

/// Draws a Valetudo map (`ValetudoMapCanvas`) in direction G's look with Core Animation layers instead of a redrawn canvas.
///
/// The floor, segments and walls are one nearest-neighbour image per map (``ValetudoMapScene/cells``) on a `stage` layer, and every
/// room has its selected-colour mask as a layer that is only shown or hidden. Pan and zoom set one affine transform on the stage;
/// the vectors keep their on-screen width by changing `lineWidth` when the scale changes, and the icons, robot, dock, area, handles
/// and room order badges are placed in screen space from the same matrix. Nothing is redrawn while a map moves.
@MainActor
final class UKValetudoMapView: UIView {
    /// The prepared map; setting it rebuilds the layers.
    var scene: ValetudoMapScene? { didSet { rebuild() } }
    var viewport = MapViewport.initial { didSet { if viewport != oldValue { applyViewport() } } }
    /// Selected rooms and their cleaning order: shown white with numbered badges.
    var roomOrders: [String: Int] = [:] { didSet { if roomOrders != oldValue { applyRoomState() } } }
    /// Rooms the coordinator skips on automatic cleans: hatched.
    var skippedRooms: Set<String> = [] { didSet { if skippedRooms != oldValue { applyRoomState() } } }
    /// The area to outline.
    var area: MapGridRect? { didSet { if area != oldValue { applyArea() } } }
    /// Draw corner handles on the area.
    var showsHandles = false { didSet { if showsHandles != oldValue { applyArea() } } }

    private let stage = CALayer()
    private let cellsLayer = CALayer()
    private let overlay = CALayer()
    private let areaFill = CAShapeLayer()
    private let areaStroke = CAShapeLayer()
    private var handleLayers: [CAShapeLayer] = []
    private var maskLayers: [String: CALayer] = [:]
    private var hatchLayers: [String: CAShapeLayer] = [:]
    private var vectors: [(layer: CAShapeLayer, width: CGFloat, minimum: CGFloat, dash: [Double])] = []
    private var markers: [(layer: CALayer, point: CGPoint)] = []
    /// The order badges over the selected rooms. The map draws no room names (owner, 2026-10-28, reversing 2026-10-24).
    private var names: [String: (badge: UILabel, _: Void)] = [:]
    private var appliedScale: Double = 0
    private var appliedSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        stage.anchorPoint = .zero
        stage.position = .zero
        layer.addSublayer(stage)
        layer.addSublayer(overlay)
        cellsLayer.magnificationFilter = .nearest
        cellsLayer.minificationFilter = .nearest
        cellsLayer.zPosition = 0
        stage.addSublayer(cellsLayer)
        for shape in [areaFill, areaStroke] {
            shape.fillColor = nil
            overlay.addSublayer(shape)
        }
        areaStroke.lineWidth = 2
        areaStroke.lineJoin = .miter
        isAccessibilityElement = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: UKValetudoMapView, _) in
            view.restyleLabels()
            view.applyArea()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Colours

    static func color(_ rgba: MapRGBA) -> UIColor {
        UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    private func cg(_ rgba: MapRGBA) -> CGColor { Self.color(rgba).cgColor }

    // MARK: Build

    private func local(_ x: Double, _ y: Double) -> CGPoint {
        guard let scene else { return .zero }
        return CGPoint(x: x / scene.geometry.pixelSize - scene.geometry.minGridX, y: y / scene.geometry.pixelSize - scene.geometry.minGridY)
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        maskLayers.values.forEach { $0.removeFromSuperlayer() }
        hatchLayers.values.forEach { $0.removeFromSuperlayer() }
        vectors.forEach { $0.layer.removeFromSuperlayer() }
        markers.forEach { $0.layer.removeFromSuperlayer() }
        names.values.forEach { $0.badge.removeFromSuperview() }
        maskLayers = [:]
        hatchLayers = [:]
        vectors = []
        markers = []
        names = [:]
        appliedScale = 0
        backgroundColor = Self.color(ValetudoMapScene.Palette.ground)
        guard let scene else {
            cellsLayer.contents = nil
            applyArea()
            return
        }
        stage.bounds = CGRect(x: 0, y: 0, width: scene.geometry.width, height: scene.geometry.height)
        stage.masksToBounds = scene.focus.mode == .focused
        cellsLayer.contents = scene.cells
        cellsLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(scene.cells?.width ?? 0), height: CGFloat(scene.cells?.height ?? 0))
        for (entityId, mask) in scene.masks {
            let layer = CALayer()
            layer.contents = mask.image
            layer.frame = mask.rect
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.zPosition = 1
            layer.isHidden = true
            stage.addSublayer(layer)
            maskLayers[entityId] = layer
        }
        buildVectors(scene)
        buildMarkers(scene)
        buildNames(scene)
        applyRoomState()
        applyViewport(force: true)
    }

    private func buildVectors(_ scene: ValetudoMapScene) {
        func path(_ entity: ValetudoMap.Entity, closed: Bool) -> CGPath? {
            let points = entity.points
            guard points.count >= (closed ? 6 : 4) else { return nil }
            let path = CGMutablePath()
            path.move(to: local(points[0], points[1]))
            var index = 2
            while index + 1 < points.count {
                path.addLine(to: local(points[index], points[index + 1]))
                index += 2
            }
            if closed { path.closeSubpath() }
            return path
        }
        func add(_ cgPath: CGPath, stroke: MapRGBA, fill: MapRGBA?, width: CGFloat, minimum: CGFloat, round: Bool, dash: [Double]) {
            let shape = CAShapeLayer()
            shape.frame = stage.bounds
            shape.path = cgPath
            shape.fillColor = fill.map(cg)
            shape.strokeColor = cg(stroke)
            shape.lineCap = round ? .round : .butt
            shape.lineJoin = round ? .round : .miter
            shape.zPosition = 3
            stage.addSublayer(shape)
            vectors.append((shape, width, minimum, dash))
        }
        for entity in scene.map.entities where entity.type == "path" || entity.type == "predicted_path" {
            guard let line = path(entity, closed: false) else { continue }
            let color = entity.type == "path" ? ValetudoMapScene.Palette.path : ValetudoMapScene.Palette.predictedPath
            add(line, stroke: color, fill: nil, width: 2.2, minimum: 0.25, round: true, dash: [])
        }
        for entity in scene.map.entities {
            guard let style = ValetudoMapStyle.entityStyle(entity.type), style.shape != .point,
                  let shape = path(entity, closed: style.shape == .polygon) else { continue }
            if style.shape == .polygon {
                add(shape, stroke: style.stroke, fill: style.fill, width: 2, minimum: 0.2, round: false, dash: style.dash)
            } else {
                add(shape, stroke: style.stroke, fill: nil, width: 3, minimum: 0.3, round: true, dash: style.dash)
            }
        }
    }

    private func framePointLocal(_ entity: ValetudoMap.Entity) -> CGPoint? {
        guard entity.points.count >= 2 else { return nil }
        return local(entity.points[0], entity.points[1])
    }

    private func buildMarkers(_ scene: ValetudoMapScene) {
        let ring = ValetudoMapStyle.ring
        for entity in scene.map.entities {
            guard let style = ValetudoMapStyle.entityStyle(entity.type), style.shape == .point, let icon = style.icon,
                  let point = framePointLocal(entity) else { continue }
            let size: CGFloat = icon == .obstacle ? 15 : 18
            let node = Self.iconLayer(symbol: icon == .obstacle ? "exclamationmark.circle.fill" : "mappin", size: size,
                                      color: Self.color(style.stroke), halo: cg(style.halo ?? ValetudoMapStyle.halo), ring: cg(ring))
            overlay.addSublayer(node)
            markers.append((node, point))
        }
        for entity in scene.map.entities {
            guard let point = framePointLocal(entity) else { continue }
            if entity.type == "charger_location" {
                let dock = CAShapeLayer()
                dock.path = UIBezierPath(roundedRect: CGRect(x: -5, y: -10, width: 10, height: 20), cornerRadius: 3.5).cgPath
                dock.fillColor = cg(ValetudoMapScene.Palette.dock)
                dock.strokeColor = cg(ValetudoMapScene.Palette.wall)
                dock.lineWidth = 1.2
                overlay.addSublayer(dock)
                markers.append((dock, point))
            } else if entity.type == "robot_position" {
                let robot = Self.robotLayer(reported: scene.provenance == .reported)
                overlay.addSublayer(robot)
                markers.append((robot, point))
            }
        }
    }

    private static func circle(_ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
    }

    private static func robotLayer(reported: Bool) -> CALayer {
        let group = CALayer()
        func shape(_ radius: CGFloat, fill: MapRGBA?, stroke: MapRGBA? = nil, width: CGFloat = 0) {
            let layer = CAShapeLayer()
            layer.path = circle(radius)
            layer.fillColor = fill.map { color($0).cgColor }
            layer.strokeColor = stroke.map { color($0).cgColor }
            layer.lineWidth = width
            group.addSublayer(layer)
        }
        let palette = ValetudoMapScene.Palette.self
        shape(15, fill: palette.robotHalo)
        shape(9, fill: reported ? palette.reportedRobot : palette.robot, stroke: palette.robotInk, width: 2.2)
        shape(3, fill: palette.robotInk)
        return group
    }

    /// A pin or obstacle: a halo disc, a ring and the symbol.
    private static func iconLayer(symbol: String, size: CGFloat, color: UIColor, halo: CGColor, ring: CGColor) -> CALayer {
        let group = CALayer()
        let radius = size * 0.62
        let disc = CAShapeLayer()
        disc.path = circle(radius)
        disc.fillColor = halo
        disc.strokeColor = ring
        disc.lineWidth = max(1.5, size * 0.08)
        group.addSublayer(disc)
        let configuration = UIImage.SymbolConfiguration(pointSize: size * 0.85, weight: .regular)
        if let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) {
            let bitmap = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let fitted = image.size
                let factor = min(size / fitted.width, size / fitted.height)
                let drawn = CGSize(width: fitted.width * factor, height: fitted.height * factor)
                image.draw(in: CGRect(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2, width: drawn.width, height: drawn.height))
            }
            let glyph = CALayer()
            glyph.contents = bitmap.cgImage
            glyph.contentsScale = bitmap.scale
            glyph.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            group.addSublayer(glyph)
        }
        return group
    }

    private func buildNames(_ scene: ValetudoMapScene) {
        for room in scene.rooms where scene.masks[room.entityId] != nil {
            let badge = UILabel()
            badge.isAccessibilityElement = false
            badge.textAlignment = .center
            badge.layer.masksToBounds = true
            badge.isHidden = true
            addSubview(badge)
            names[room.entityId] = (badge, ())
        }
        restyleLabels()
    }

    private func restyleLabels() {
        for (_, pair) in names {
            pair.badge.font = .ukFont(.caption1, weight: .bold)
            pair.badge.textColor = .white
            pair.badge.backgroundColor = Self.color(ValetudoMapScene.Palette.labelOnSelected)
            pair.badge.layer.cornerRadius = 11
        }
        positionOverlay()
    }

    // MARK: Room state

    private func applyRoomState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let scene else { return }
        for (entityId, layer) in maskLayers { layer.isHidden = roomOrders[entityId] == nil }
        for (entityId, mask) in scene.masks where skippedRooms.contains(entityId) && hatchLayers[entityId] == nil {
            let hatch = CAShapeLayer()
            hatch.frame = mask.rect
            hatch.strokeColor = cg(ValetudoMapScene.Palette.hatch)
            hatch.fillColor = nil
            hatch.zPosition = 2
            let clip = CALayer()
            clip.contents = mask.image
            clip.frame = CGRect(origin: .zero, size: mask.rect.size)
            clip.magnificationFilter = .nearest
            clip.minificationFilter = .nearest
            hatch.mask = clip
            stage.addSublayer(hatch)
            hatchLayers[entityId] = hatch
            applyHatchGeometry(hatch, rect: mask.rect)
        }
        for (entityId, hatch) in hatchLayers { hatch.isHidden = !skippedRooms.contains(entityId) }
        restyleLabels()
    }

    /// 45 degree stripes over a room, clipped to its cells by the layer's mask.
    private func applyHatchGeometry(_ hatch: CAShapeLayer, rect: CGRect) {
        let scale = max(appliedScale, 0.01)
        let step = 7 / scale
        let path = CGMutablePath()
        var offset = -rect.height
        while offset < rect.width {
            path.move(to: CGPoint(x: offset, y: rect.height))
            path.addLine(to: CGPoint(x: offset + rect.height, y: 0))
            offset += step
        }
        hatch.path = path
        hatch.lineWidth = 2.4 / scale
    }

    // MARK: Viewport

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != appliedSize { applyViewport(force: true) }
    }

    private func applyViewport(force: Bool = false) {
        guard let scene, bounds.width > 0, bounds.height > 0 else { return }
        appliedSize = bounds.size
        let m = scene.matrix(size: bounds.size, viewport: viewport)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.setAffineTransform(CGAffineTransform(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.e, ty: m.f))
        let scale = max(m.scale, 0.01)
        if force || abs(scale - appliedScale) > 1e-6 {
            appliedScale = scale
            for vector in vectors {
                vector.layer.lineWidth = max(vector.minimum, vector.width / scale)
                vector.layer.lineDashPattern = vector.dash.isEmpty ? nil : vector.dash.map { NSNumber(value: $0 / scale) }
            }
            for (entityId, hatch) in hatchLayers {
                if let mask = scene.masks[entityId] { applyHatchGeometry(hatch, rect: mask.rect) }
            }
        }
        positionOverlay()
        CATransaction.commit()
    }

    /// Places the screen-space pieces from the current matrix.
    private func positionOverlay() {
        guard let scene, bounds.width > 0 else { return }
        let m = scene.matrix(size: bounds.size, viewport: viewport)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for marker in markers {
            let frame = m.apply(MapPoint(x: marker.point.x, y: marker.point.y))
            marker.layer.position = CGPoint(x: frame.x, y: frame.y)
        }
        let badge: CGFloat = 22
        for room in scene.rooms {
            guard let pair = names[room.entityId] else { continue }
            let center = MapGeometry.framePoint(scene.geometry, matrix: m, gridPoint: .init(x: room.centroid.x + 0.5, y: room.centroid.y + 0.5))
            if let order = roomOrders[room.entityId] {
                pair.badge.isHidden = false
                pair.badge.text = "\(order)"
                pair.badge.bounds = CGRect(x: 0, y: 0, width: badge, height: badge)
                pair.badge.center = CGPoint(x: center.x, y: center.y)
            } else {
                pair.badge.isHidden = true
            }
        }
        positionArea(matrix: m)
        CATransaction.commit()
    }

    // MARK: Area

    private func applyArea() {
        guard let scene, bounds.width > 0 else {
            areaFill.path = nil
            areaStroke.path = nil
            handleLayers.forEach { $0.isHidden = true }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionArea(matrix: scene.matrix(size: bounds.size, viewport: viewport))
        CATransaction.commit()
    }

    private func positionArea(matrix m: Affine) {
        guard let scene, let area else {
            areaFill.path = nil
            areaStroke.path = nil
            handleLayers.forEach { $0.isHidden = true }
            return
        }
        let points = MapGridRect.Corner.allCases.map { corner -> CGPoint in
            let p = MapGeometry.framePoint(scene.geometry, matrix: m, gridPoint: area.point(corner))
            return CGPoint(x: p.x, y: p.y)
        }
        let outline = CGMutablePath()
        outline.addLines(between: points)
        outline.closeSubpath()
        let action = UKDesignInk.action.resolvedColor(with: traitCollection)
        areaFill.path = outline
        areaFill.fillColor = action.withAlphaComponent(0.22).cgColor
        areaStroke.path = outline
        areaStroke.strokeColor = action.cgColor
        while handleLayers.count < points.count {
            let handle = CAShapeLayer()
            handle.path = Self.circle(8)
            handle.lineWidth = 2
            overlay.addSublayer(handle)
            handleLayers.append(handle)
        }
        for (index, handle) in handleLayers.enumerated() {
            handle.isHidden = !showsHandles || index >= points.count
            guard index < points.count else { continue }
            handle.fillColor = UIColor.white.cgColor
            handle.strokeColor = UKDesignInk.actionFill.cgColor
            handle.position = points[index]
        }
    }
}
#endif
