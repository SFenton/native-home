import HassDesign
import SwiftUI

/// One measured value: a title, the headline value and a detail line.
struct PerformanceRow {
    enum Tone { case neutral, good, warning, bad }

    var title: String
    var value: String
    var detail: String
    var tone: Tone = .neutral


    /// The tone as a word, spoken after the value; nil for a neutral one. Tone is never colour alone.
    static func toneWord(_ tone: Tone) -> String? {
        switch tone {
        case .neutral: nil
        case .good: "good"
        case .warning: "fair"
        case .bad: "poor"
        }
    }

    /// The glyph drawn beside the value: a triangle for a bad value, a circle for a fair one; none otherwise.
    static func toneSymbol(_ tone: Tone) -> String? {
        switch tone {
        case .neutral, .good: nil
        case .warning: "exclamationmark.circle"
        case .bad: "exclamationmark.triangle.fill"
        }
    }

    /// `value, tone. detail` for VoiceOver.
    static func spokenValue(value: String, detail: String, tone: Tone) -> String {
        let head = toneWord(tone).map { "\(value), \($0)" } ?? value
        return "\(head). \(detail)"
    }


    private var color: Color {
        switch tone {
        // Only a bad value takes color, and it also has a glyph and a spoken word (never color alone, HIG Color).
        case .neutral, .good, .warning: HassTokens.Ink.primary
        case .bad: HassTokens.Ink.danger
        }
    }
}
