#if os(iOS)
import HassDesign
import UIKit

/// A ``UKRowView`` whose whole row is the switch (``ModuleToggleRow``): tapping the title, the subtitle or the switch
/// flips it, so the target is the row's 52 or 60 pt rather than the system switch's 51 x 31. VoiceOver gets one element, a
/// switch named by the title with the state as its value; the drawn switch is only the look. The action runs with the state the
/// row shows (ask for the opposite), never the state it was asked to become, so a controller stays the source of truth.
///
/// ```swift
/// let row = UKModuleToggleRow("Automatic Cleaning", symbol: "sparkles", isOn: model.auto, hint: "Turns automatic cleaning on or off.") {
///     model.setAuto(!model.auto)
/// }
/// // when the model changes: row.setOn(model.auto)
/// ```
final class UKModuleToggleRow: UKRowButton {
    private let switchView = UISwitch()
    private let hint: String?

    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, glyph: UIColor? = nil, glyphOpacity: CGFloat = 1,
         isOn: Bool, hint: String? = nil, surface: TileSurface = .page, action: @escaping () -> Void) {
        self.hint = hint
        switchView.isOn = isOn
        switchView.isUserInteractionEnabled = false
        let row = UKRowView(.init(title, subtitle: subtitle, symbol: symbol, glyph: glyph, glyphOpacity: glyphOpacity),
                                  accessory: switchView, surface: surface)
        super.init(row, onTap: action)
    }

    /// Shows the new state (the switch glides, as the system's does).
    func setOn(_ isOn: Bool, animated: Bool = true) {
        switchView.setOn(isOn, animated: animated && window != nil)
    }

    var isOn: Bool { switchView.isOn }

    override var accessibilityLabel: String? {
        get { row.rowContent.title }
        set {}
    }

    override var accessibilityValue: String? {
        get { switchView.isOn ? "1" : "0" }
        set {}
    }

    /// A switch to assistive technologies and to UI tests (the toggle trait; a plain button would not read its state).
    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? [.button, .toggleButton] : [.button, .toggleButton, .notEnabled] }
        set {}
    }

    override var accessibilityHint: String? {
        get { hint }
        set {}
    }
}
#endif
