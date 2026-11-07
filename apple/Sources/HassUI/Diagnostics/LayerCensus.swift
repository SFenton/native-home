#if os(iOS) && DEBUG
import UIKit

/// Debug-only layer-tree census (`FENTON_LAYER_CENSUS=1` with the scroll cost autorun): walks every window's CALayer tree after the
/// page settles and writes one `LAYERCENSUS` line of counts that cost the render server (masks, offscreen shadows, group opacity,
/// rasterisation, gradients, shapes, effects, big non-opaque layers, animations). SwiftUI renders through CALayers too, so the same
/// probe reads both apps and the counts can be diffed. Also counts the same facts for the front scroll view's subtree alone.
@MainActor
enum LayerCensus {
    struct Counts {
        var layers = 0, hidden = 0, masks = 0, clipRounded = 0, clipPlain = 0, shadowNoPath = 0, shadowPath = 0, groupOpacity = 0
        var rasterized = 0, gradients = 0, shapes = 0, effects = 0, backdrops = 0, bigNonOpaque = 0, animations = 0, replicators = 0
        var visibleDrawing = 0, bgLayers = 0, blendedArea = 0.0, opaqueArea = 0.0
        var emitters = 0, transforms3D = 0, borders = 0, textLayers = 0, contentsLayers = 0

        var line: String {
            "layers=\(layers) hidden=\(hidden) masks=\(masks) clipRounded=\(clipRounded) clipPlain=\(clipPlain) shadowNoPath=\(shadowNoPath) "
                + "shadowPath=\(shadowPath) groupOpacity=\(groupOpacity) rasterized=\(rasterized) gradients=\(gradients) shapes=\(shapes) "
                + "effects=\(effects) backdrops=\(backdrops) bigNonOpaque=\(bigNonOpaque) animations=\(animations) replicators=\(replicators) "
                + "visibleDrawing=\(visibleDrawing) bgLayers=\(bgLayers) blendedScreens=\(String(format: "%.2f", blendedArea)) opaqueScreens=\(String(format: "%.2f", opaqueArea)) "
                + "emitters=\(emitters) borders=\(borders) textLayers=\(textLayers) contents=\(contentsLayers)"
        }
    }

    static func run() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var all = Counts()
        var scroll = Counts()
        var kinds: [String: Int] = [:]
        let front = ScrollCostDriver.frontScrollView()
        for window in scenes.flatMap(\.windows) where !window.isHidden {
            walk(window.layer, in: window.layer, screen: window.bounds.size, counts: &all, kinds: &kinds)
        }
        if let front {
            var ignored: [String: Int] = [:]
            walk(front.layer, in: front.layer, screen: front.bounds.size, counts: &scroll, kinds: &ignored)
        }
        let top = kinds.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        var text = "window: \(all.line)\nscroll: \(scroll.line)\nclasses: \(top)"
        if ProcessInfo.processInfo.environment["FENTON_LAYER_CENSUS_DETAIL"] == "1" {
            detail = []
            for window in scenes.flatMap(\.windows) where !window.isHidden { notable(window.layer, depth: 0, screen: window.bounds.size) }
            text += "\n" + detail.joined(separator: "\n")
        }
        return text
    }

    private static var detail: [String] = []

    private static func notable(_ layer: CALayer, depth: Int, screen: CGSize) {
        if layer.isHidden || layer.opacity == 0 { return }
        var tags: [String] = []
        if layer is CAGradientLayer { tags.append("gradient") }
        if layer is CAShapeLayer { tags.append("shape") }
        if layer.mask != nil { tags.append("mask") }
        if layer.masksToBounds { tags.append(layer.cornerRadius > 0 ? "clipRounded" : "clip") }
        if layer.shadowOpacity > 0 && layer.shadowRadius > 0 { tags.append(layer.shadowPath == nil ? "shadowNoPath" : "shadow") }
        if layer.allowsGroupOpacity && layer.opacity < 1 && !(layer.sublayers ?? []).isEmpty { tags.append("groupOpacity") }
        if layer.shouldRasterize { tags.append("rasterized") }
        if !(layer.animationKeys() ?? []).isEmpty { tags.append("anim:" + (layer.animationKeys() ?? []).joined(separator: "+")) }
        if layer.filters?.isEmpty == false || layer.backgroundFilters?.isEmpty == false || String(describing: type(of: layer)).contains("Backdrop") { tags.append("filter") }
        if !tags.isEmpty {
            let owner = (layer.delegate as? UIView).map { String(describing: type(of: $0)) } ?? "-"
            let b = layer.bounds
            detail.append("  d\(depth) \(String(describing: type(of: layer))) owner=\(owner) \(Int(b.width))x\(Int(b.height)) op=\(layer.opacity) \(tags.joined(separator: ","))")
        }
        for sub in layer.sublayers ?? [] { notable(sub, depth: depth + 1, screen: screen) }
    }

    private static func walk(_ layer: CALayer, in root: CALayer, screen: CGSize, counts: inout Counts, kinds: inout [String: Int]) {
        counts.layers += 1
        kinds[String(describing: type(of: layer)), default: 0] += 1
        if layer.isHidden || layer.opacity == 0 { counts.hidden += 1 }
        if layer.mask != nil { counts.masks += 1 }
        if layer.masksToBounds { if layer.cornerRadius > 0 { counts.clipRounded += 1 } else { counts.clipPlain += 1 } }
        if layer.shadowOpacity > 0 && layer.shadowRadius > 0 { if layer.shadowPath == nil { counts.shadowNoPath += 1 } else { counts.shadowPath += 1 } }
        if layer.allowsGroupOpacity && layer.opacity < 1 && !(layer.sublayers ?? []).isEmpty { counts.groupOpacity += 1 }
        if layer.shouldRasterize { counts.rasterized += 1 }
        if layer is CAGradientLayer { counts.gradients += 1 }
        if layer is CAShapeLayer { counts.shapes += 1 }
        if layer is CAReplicatorLayer { counts.replicators += 1 }
        if layer is CAEmitterLayer { counts.emitters += 1 }
        if layer is CATextLayer { counts.textLayers += 1 }
        if layer.borderWidth > 0 { counts.borders += 1 }
        if layer.contents != nil { counts.contentsLayers += 1 }
        let name = String(describing: type(of: layer))
        if name.contains("Backdrop") || name.contains("Filter") || (layer.filters?.isEmpty == false) || (layer.backgroundFilters?.isEmpty == false) {
            counts.backdrops += 1
        }
        if let delegate = layer.delegate as? UIView, delegate is UIVisualEffectView { counts.effects += 1 }
        let size = layer.bounds.size
        if size.width * size.height > 0.25 * screen.width * screen.height, !layer.isOpaque,
           layer.backgroundColor.map({ $0.alpha < 1 }) ?? (layer.contents != nil) {
            counts.bigNonOpaque += 1
        }
        counts.animations += layer.animationKeys()?.count ?? 0
        if !layer.isHidden, layer.opacity > 0 {
            let bg = layer.backgroundColor.map { $0.alpha > 0 } ?? false
            let draws = bg || layer.contents != nil || layer is CAShapeLayer || layer is CAGradientLayer || layer.borderWidth > 0
            if bg { counts.bgLayers += 1 }
            if draws {
                counts.visibleDrawing += 1
                let frame = layer.convert(layer.bounds, to: root).intersection(CGRect(origin: .zero, size: screen))
                if !frame.isNull, screen.width * screen.height > 0 {
                    let area = Double(frame.width * frame.height) / Double(screen.width * screen.height)
                    let solid = layer.isOpaque || (layer.backgroundColor.map { $0.alpha >= 1 } ?? false) && layer.opacity >= 1
                    if solid { counts.opaqueArea += area } else { counts.blendedArea += area * Double(layer.opacity) }
                }
            }
        }
        for sub in layer.sublayers ?? [] { walk(sub, in: root, screen: screen, counts: &counts, kinds: &kinds) }
    }
}
#endif
