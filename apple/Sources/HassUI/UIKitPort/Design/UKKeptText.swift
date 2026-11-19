#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Kept text presentation (T-text-keep)

/// How text that a slot keeps while its value is unavailable (`sh.text-keep@1`) looks and sounds. A proposal under test: the Designer's
/// options A, B and C (`build/design/T-text-keep-options.md`) sit behind this one switch until one is picked and the others are removed.
enum ServerUIKeptTextTreatment: String, CaseIterable {
    /// Option A: kept text draws and speaks exactly as it does live.
    case plain
    /// Option B: drawn as live; VoiceOver adds ", last known" to the element's value.
    case spoken
    /// Option C: B, plus a leading clock glyph and, on a neutral ink, the unavailable grey.
    case marked

    /// The treatment in force: the launch variable `FENTON_GALLERY_KEPT_TEXT_TREATMENT` (a gallery setting a reused journey app can change),
    /// or the launch argument `-FentonKeptTextTreatment <name>`. Debug builds only; a release build is always ``plain``.
    static var current: Self {
        #if DEBUG
        let named = ProcessInfo.processInfo.environment["FENTON_GALLERY_KEPT_TEXT_TREATMENT"]
            ?? UserDefaults.standard.string(forKey: "FentonKeptTextTreatment")
        return named.flatMap(Self.init(rawValue:)) ?? .plain
        #else
        return .plain
        #endif
    }

    /// Whether VoiceOver hears the cue.
    var speaksCue: Bool { self != .plain }
    /// Whether the drawn text carries the glyph and the grey.
    var marksText: Bool { self == .marked }
}

/// The drawn and spoken form of kept text, in one place for every host (tile, status pill, row, text node).
@MainActor
enum UKKeptText {
    /// The glyph that marks kept text (option C).
    static let glyphName = "clock.arrow.circlepath"
    /// Between the glyph and the text.
    static let thinSpace = "\u{2009}"

    /// The value an element speaks: `spoken` (or its drawn text) with the cue once, when the treatment speaks it and something is kept.
    nonisolated static func spoken(_ spoken: String?, drawn: String, kept: Bool, treatment: ServerUIKeptTextTreatment = .current) -> String? {
        ServerUIKeptTextCue.value(spoken: spoken, drawn: drawn, kept: kept && treatment.speaksCue)
    }

    /// The value of an element that reads its text in its label (a row's title and subtitle): `spoken`, or the cue alone, with the cue once.
    nonisolated static func value(appendingTo spoken: String?, kept: Bool, treatment: ServerUIKeptTextTreatment = .current) -> String? {
        ServerUIKeptTextCue.value(appendingTo: spoken, kept: kept && treatment.speaksCue)
    }

    /// The ink kept text draws in: the unavailable grey on a neutral ink, the live ink otherwise (a filled or tinted ground, an authored
    /// colour). Increase Contrast keeps the live ink, which already adapts, and leaves the glyph to mark the text.
    static func ink(live: UIColor, neutral: Bool, traits: UITraitCollection, treatment: ServerUIKeptTextTreatment = .current) -> UIColor {
        guard treatment.marksText, neutral, traits.accessibilityContrast != .high else { return live }
        return UIColor(HassTokens.RGB.Ink.unavailable)
    }

    /// `text` led by the glyph and a thin space, in `font` and `ink`. The glyph is sized for `textStyle` at the traits' size category, so
    /// it scales with Dynamic Type. VoiceOver never reads it: the host speaks its own value or sets the label's accessibility label.
    static func marked(_ text: String, font: UIFont, textStyle: UIFont.TextStyle, ink: UIColor, traits: UITraitCollection) -> NSAttributedString {
        let configuration = UIImage.SymbolConfiguration(textStyle: textStyle, scale: .small).applying(UIImage.SymbolConfiguration(traitCollection: traits))
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: glyphName, withConfiguration: configuration)?.withTintColor(ink, renderingMode: .alwaysOriginal)
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: thinSpace + text))
        result.addAttributes([.font: font, .foregroundColor: ink], range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Sets a label's text, drawing it as kept text under option C.
    /// - Parameters:
    ///   - label: The label; its font is the text's font.
    ///   - text: The text, or `nil` for none.
    ///   - kept: Whether `text` is kept text.
    ///   - liveInk: The ink the text draws in live.
    ///   - neutral: Whether `liveInk` is a neutral that may step to the unavailable grey.
    ///   - textStyle: The text style the label's font follows, which sizes the glyph.
    ///   - glyph: Whether the text carries the glyph (a numeric count badge does not).
    static func apply(to label: UILabel, text: String?, kept: Bool, liveInk: UIColor, neutral: Bool, textStyle: UIFont.TextStyle,
                      glyph: Bool = true, treatment: ServerUIKeptTextTreatment = .current) {
        let traits = label.traitCollection
        guard kept, treatment.marksText, let text, !text.isEmpty else {
            if label.attributedText != nil { label.attributedText = nil }
            label.text = text
            label.textColor = liveInk
            return
        }
        let ink = ink(live: liveInk, neutral: neutral, traits: traits, treatment: treatment)
        label.textColor = ink
        if glyph {
            label.attributedText = marked(text, font: label.font, textStyle: textStyle, ink: ink, traits: traits)
        } else {
            label.attributedText = nil
            label.text = text
        }
    }
}
#endif
