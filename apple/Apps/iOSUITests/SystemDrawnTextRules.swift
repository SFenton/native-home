import CoreGraphics
import Foundation

/// Pure rules that decide whether a string text recognition read with no accessibility element is drawn by the system or is a
/// misreading of a glyph beside text the app does label. Kept free of XCUITest so a unit test can pin each rule.
enum SystemDrawnTextRules {
    /// A compact date picker's time chip: "9:00 AM", or "9:00AM" (the iPad's chips draw no space, and recognition reads none).
    static func isTimeChip(_ text: String) -> Bool {
        text.range(of: "^[0-9]{1,2}:[0-9]{2} ?[AP]M$", options: .regularExpression) != nil
    }

    /// Whether `frame` lies on one of `pickers`' frames (the system draws the chips inside the picker's own frame).
    static func isInsidePicker(_ frame: CGRect, pickers: [CGRect]) -> Bool {
        pickers.contains { $0.insetBy(dx: -4, dy: -4).intersects(frame) }
    }

    /// The system compact date picker's time chip: a time string on a date picker's frame. Recognition reads these with no element
    /// (iPad Vacation audits on CI, 2026-11-13: "9:00AM", "6:00PM").
    static func isPickerTime(_ text: String, frame: CGRect, pickers: [CGRect]) -> Bool {
        isTimeChip(text) && isInsidePicker(frame, pickers: pickers)
    }

    /// Whether `text` is a label's text read with the info glyph in front ("i alex away" for the notice "Alex Away"): a leading "i"
    /// and a space, then at least four characters that equal one of `labels` or start it as whole words. Both sides are lowercased
    /// and whitespace-squeezed by the caller.
    static func isInfoGlyphMisread(_ text: String, labels: [String]) -> Bool {
        guard text.hasPrefix("i ") else { return false }
        let rest = String(text.dropFirst(2))
        guard rest.count >= 4 else { return false }
        return labels.contains { label in
            guard label.hasPrefix(rest) else { return false }
            // Whole words: the label ends there or the next character is not a letter or digit ("alex away, since 9").
            return label.dropFirst(rest.count).first.map { !$0.isLetter && !$0.isNumber } ?? true
        }
    }
}
