import SwiftUI

/// Colour arithmetic for the tinted glass ground.
enum FinishColor {
    /// Several translucent `0xRRGGBB` layers, bottom first, flattened into one colour that composites the same way: fewer
    /// layers per tile (a layer is real cost on a page of 120 tiles, `.agents/testing/apple/performance.md`).
    static func flatten(_ layers: [(rgb: UInt32, opacity: Double)]) -> Color {
        let (r, g, b, a) = premultiplied(layers)
        guard a > 0 else { return .clear }
        return Color(.sRGB, red: r / a, green: g / a, blue: b / a, opacity: a)
    }

    /// The layers' premultiplied red, green, blue and combined alpha (`over` compositing, bottom first).
    static func premultiplied(_ layers: [(rgb: UInt32, opacity: Double)]) -> (Double, Double, Double, Double) {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for layer in layers {
            let o = max(0, min(1, layer.opacity))
            r = Double((layer.rgb >> 16) & 0xFF) / 255 * o + r * (1 - o)
            g = Double((layer.rgb >> 8) & 0xFF) / 255 * o + g * (1 - o)
            b = Double(layer.rgb & 0xFF) / 255 * o + b * (1 - o)
            a = o + a * (1 - o)
        }
        return (r, g, b, a)
    }
}
