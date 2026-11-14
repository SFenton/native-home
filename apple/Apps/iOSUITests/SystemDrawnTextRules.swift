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

    /// `text` without a leading glyph that recognition read as one lowercase letter ("i Alex Away" for the notice's info glyph and
    /// "Alex Away"), or `nil` when it does not start that way. The caller still requires the rest to be in a label.
    static func droppingLeadingGlyphLetter(_ text: String) -> String? {
        guard text.range(of: "^[a-z] [^ ]", options: .regularExpression) != nil else { return nil }
        return String(text.dropFirst(2))
    }
}
