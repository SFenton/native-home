import Foundation

// MARK: - Colors from text

/// A color as three channels, each 0 to 255.
public struct ServerUIRGB: Equatable, Sendable {
    public var red: Int
    public var green: Int
    public var blue: Int

    /// Creates a color from three channels.
    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`.
    var packed: Int { red * 65_536 + green * 256 + blue }

    init(packed value: Int) { self.init(red: value / 65_536 % 256, green: value / 256 % 256, blue: value % 256) }
}

/// The one color parser and the app's contrast clamp, for every place a document turns text into a color (`bound-color`, `sh.rules@1`).
///
/// **Tier 1 syntaxes** (what an entity's text may be): `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`; `rgb()` and `rgba()` with three channels
/// (a number from 0 to 255 or a percentage); `hsl()` and `hsla()` with a hue (a number or `deg`), a saturation and a lightness
/// (percentages). The comma form and the space form with an optional `/ alpha` both parse. Alpha is ignored, except that alpha 0 means
/// "no color". Anything else (a name, a list, a number out of range, a trailing word) is not a color. Rounding is half away from zero.
///
/// **The clamp** is a port of `ChipTint.fromWeb` (`HassDesign`, which `HassCore` cannot import): a color Home Assistant supplies is
/// scaled toward black until white text passes 4.5:1 on it, also under the chip's top highlight, and the color itself is lightened
/// toward white until the glyph keeps 3:1. It is deterministic, so the same text always gives the same chip. A conditional case holds a
/// literal fill and is never clamped.
public enum ServerUIColorText {
    /// What a bound color becomes in a slot: the chip's fill, or its glyph.
    public enum Role: String, Sendable { case fill, glyph }

    // MARK: Parsing

    /// Parses text as a tier 1 color, or `nil` when it is not one (or when its alpha is 0). Case and the spaces around the text do not matter.
    public static func parse(_ input: String) -> ServerUIRGB? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { return hex(String(text.dropFirst())) }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let name = String(text[..<open])
        let body = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name), !body.contains("("), !body.contains(")"),
              let found = tokens(body.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if let opacity = found.opacity {
            guard let value = alpha(opacity), value != 0 else { return nil }
        }
        if name.hasPrefix("rgb") {
            let channels = found.parts.map(channel)
            guard let red = channels[0], let green = channels[1], let blue = channels[2] else { return nil }
            return ServerUIRGB(red: red, green: green, blue: blue)
        }
        let hueToken = found.parts[0].hasSuffix("deg") ? String(found.parts[0].dropLast(3)) : found.parts[0]
        guard ServerUICompositionShape.matches(hueToken, "^[+-]?([0-9]+(\\.[0-9]+)?|\\.[0-9]+)$"), let hue = Double(hueToken),
              let saturation = percent(found.parts[1]), let lightness = percent(found.parts[2]) else { return nil }
        return hsl(hue: hue, saturation: saturation, lightness: lightness)
    }

    private static func isNumber(_ text: String) -> Bool {
        ServerUICompositionShape.matches(text, "^([0-9]+(\\.[0-9]+)?|\\.[0-9]+)$")
    }

    private static func channel(_ token: String) -> Int? {
        if token.hasSuffix("%") {
            let part = String(token.dropLast())
            guard isNumber(part), let value = Double(part), value <= 100 else { return nil }
            return Int((value * 255 / 100).rounded())
        }
        guard isNumber(token), let value = Double(token), value <= 255 else { return nil }
        return Int(value.rounded())
    }

    private static func alpha(_ token: String) -> Double? {
        if token.hasSuffix("%") {
            let part = String(token.dropLast())
            guard isNumber(part), let value = Double(part), value <= 100 else { return nil }
            return value / 100
        }
        guard isNumber(token), let value = Double(token), value <= 1 else { return nil }
        return value
    }

    private static func percent(_ token: String) -> Double? {
        guard token.hasSuffix("%") else { return nil }
        let part = String(token.dropLast())
        guard isNumber(part), let value = Double(part), value <= 100 else { return nil }
        return value / 100
    }

    private static func hex(_ body: String) -> ServerUIRGB? {
        guard [3, 4, 6, 8].contains(body.utf8.count), body.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        else { return nil }
        let digits: [String]
        if body.utf8.count <= 4 { digits = body.map { "\($0)\($0)" } }
        else {
            let characters = Array(body)
            digits = stride(from: 0, to: characters.count, by: 2).map { String(characters[$0...$0 + 1]) }
        }
        let values = digits.compactMap { Int($0, radix: 16) }
        if values.count == 4, values[3] == 0 { return nil }
        return ServerUIRGB(red: values[0], green: values[1], blue: values[2])
    }

    /// The tokens of a function's arguments: three, then an optional alpha, in the comma form or the space form with `/`.
    private static func tokens(_ body: String) -> (parts: [String], opacity: String?)? {
        if body.contains(",") {
            if body.contains("/") { return nil }
            let list = body.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return list.count == 3 || list.count == 4 ? (Array(list.prefix(3)), list.count == 4 ? list[3] : nil) : nil
        }
        let split = body.components(separatedBy: "/")
        if split.count > 2 { return nil }
        let parts = split[0].trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        let opacity = split.count == 2 ? split[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        guard parts.count == 3, split.count == 1 || !(opacity?.isEmpty ?? true) else { return nil }
        return (parts, opacity)
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> ServerUIRGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = ((hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch sector {
        case ..<1: (chroma, second, 0)
        case ..<2: (second, chroma, 0)
        case ..<3: (0, chroma, second)
        case ..<4: (0, second, chroma)
        case ..<5: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        let lift = lightness - chroma / 2
        func byte(_ value: Double) -> Int { Int(((value + lift) * 255).rounded()) }
        return ServerUIRGB(red: byte(r), green: byte(g), blue: byte(b))
    }

    // MARK: The app's clamp

    /// The share of a web color kept in the fill (`ChipTint.fillScale`).
    static let fillScale = 0.73
    /// The chip's top highlight opacity (`ChipTint.highlight`).
    static let highlight = 0.12
    /// Body text contrast (`ChipTint.textContrast`, WCAG 1.4.3).
    static let textContrast = 4.5
    /// Non-text contrast for the glyph (`ChipTint.glyphContrast`, WCAG 1.4.11).
    static let glyphContrast = 3.0

    /// `amount` of `a`, the rest `b`, per channel and rounded (`ColorFamily.mix`).
    static func mix(_ a: Int, _ b: Int, _ amount: Double) -> Int {
        func part(_ shift: Int) -> Int {
            let scale = 1 << shift
            let from = Double(a / scale % 256), to = Double(b / scale % 256)
            return Int((from * amount + to * (1 - amount)).rounded()) * scale
        }
        return part(16) + part(8) + part(0)
    }

    /// WCAG relative luminance of `0xRRGGBB` (`ChipTint.luminance`).
    static func luminance(_ value: Int) -> Double {
        func linear(_ shift: Int) -> Double {
            let c = Double(value / (1 << shift) % 256) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// WCAG contrast ratio between two `0xRRGGBB` colors (`ChipTint.contrast`).
    static func contrast(_ a: Int, _ b: Int) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The ground under the chip's text near the top, where the chip lays a 12% white highlight (`ChipTint.liftedFill`).
    static func liftedFill(_ fill: Int) -> Int { mix(0xFFFFFF, fill, highlight) }

    /// The chip tint for a web color (`ChipTint.fromWeb`): the fill is the color scaled toward black until white text reads on it, also
    /// under the highlight; the glyph is the color lightened toward white until it keeps 3:1.
    static func tint(_ color: Int) -> (fill: Int, glyph: Int) {
        var fill = mix(color, 0x000000, fillScale)
        while contrast(0xFFFFFF, liftedFill(fill)) < textContrast, fill != 0 { fill = mix(fill, 0x000000, 0.95) }
        func reads(_ glyph: Int) -> Bool {
            contrast(glyph, fill) >= glyphContrast && contrast(glyph, liftedFill(fill)) >= glyphContrast
        }
        var amount = 0.0, glyph = color
        while !reads(glyph), amount < 1 {
            amount += 0.05
            glyph = mix(0xFFFFFF, color, amount)
        }
        return (fill, glyph)
    }

    /// The clamped color a slot of `role` draws for text that parsed as `rgb`.
    public static func clamped(_ rgb: ServerUIRGB, role: Role) -> ServerUIRGB {
        let result = tint(rgb.packed)
        return ServerUIRGB(packed: role == .fill ? result.fill : result.glyph)
    }
}
