#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Link row

extension UKRowView {
    /// One settings topic (``SettingsLinkRow``): an icon (or the app icon's preview), a title and a wrapping subtitle, and a chevron
    /// when the row pushes, in the grouped metrics. Pure drawing: the cell is the button.
    static func settingsLink(title: String, subtitle: String, symbol: String, showsChevron: Bool = false, appIcon: AppIconChoice? = nil) -> UKRowView {
        var content = UKRowContent(title, subtitle: subtitle, symbol: appIcon == nil ? symbol : nil, showsChevron: showsChevron, style: .grouped)
        content.leadingView = appIcon.map { UKAppIconPreviewView(choice: $0, side: 30) }
        return UKRowView(content)
    }

    /// The Version row (``VersionRow``): icon and title with the build text on the trailing edge, or under the title once it no longer
    /// fits beside it (long text sizes; the text wraps rather than truncates).
    static func version(text: String) -> UKRowView {
        UKRowView(.init("Version", value: text, symbol: "info.circle", style: .grouped))
    }
}

// MARK: - Row builders

/// The rows of the Settings list and its sheets, as list rows. Each builder fixes what the SwiftUI row sets: the tappable cell is
/// one VoiceOver element named "title, subtitle", with the SwiftUI identifier, hint and traits.
@MainActor
enum UKSettingsRows {
    /// A ``SettingsLinkRow`` inside a button or a `NavigationLink`.
    /// - Parameters:
    ///   - disclosure: The system's disclosure chevron (a `NavigationLink`); ``showsChevron`` draws the row's own.
    static func link(id: String, identifier: String, title: String, subtitle: String, symbol: String, showsChevron: Bool = false,
                     disclosure: Bool = false, appIcon: AppIconChoice? = nil, hint: String? = nil,
                     traits: UIAccessibilityTraits = .button, isEnabled: Bool = true, action: @escaping () -> Void) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: "link|\(title)|\(subtitle)|\(appIcon?.rawValue ?? "")|\(isEnabled)|\(showsChevron)|\(disclosure)", isEnabled: isEnabled, kind: .link, action: action) { cell in
            let view = UKRowView.settingsLink(title: title, subtitle: subtitle, symbol: symbol, showsChevron: showsChevron, appIcon: appIcon)
            cell.show(view)
            if disclosure { cell.accessories = [.disclosureIndicator()] }
            cell.makeElement(label: UKRowView.accessibilityLabel(title: title, subtitle: subtitle), hint: hint, traits: traits, identifier: identifier)
        }
    }

    /// A `Toggle` row: the title and the system switch. The switch is the element, named by the title.
    static func toggle(id: String, identifier: String, title: String, isOn: Bool, change: @escaping (Bool) -> Void) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: "toggle|\(title)|\(isOn)", kind: .control) { cell in
            let toggle = UISwitch()
            toggle.isOn = isOn
            toggle.accessibilityLabel = title
            toggle.accessibilityIdentifier = identifier
            toggle.addAction(UIAction { action in change((action.sender as? UISwitch)?.isOn ?? false) }, for: .valueChanged)
            let row = UKRowView(.init(title, style: .form), accessory: toggle)
            row.isTextAccessible = false
            cell.show(row, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
            cell.accessibilityElements = [toggle]
        }
    }

    /// A text button row ("Turn On Notifications", "Reset to Default"): the label in `ink`, a 44 pt row, the cell is the button.
    static func button(id: String, identifier: String, title: String, ink: UIColor = UKDesignInk.action, isEnabled: Bool = true,
                       hint: String? = nil, role: UIAccessibilityTraits = .button, action: @escaping () -> Void) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: "button|\(title)|\(isEnabled)", isEnabled: isEnabled, kind: .textButton, action: action) { cell in
            var content = UKRowContent(title, style: .form)
            content.titleInk = ink
            content.verticalPadding = 14
            cell.show(UKRowView(content), insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
                      minHeight: HassTokens.minTarget)
            cell.makeElement(label: title, hint: hint, traits: isEnabled ? role : role.union(.notEnabled), identifier: identifier)
        }
    }

    /// A row with any view (a slider row, a spinner, a strip), with its own accessibility elements.
    static func custom(id: String, signature: String, insets: NSDirectionalEdgeInsets = UKSettingsCell.defaultInsets, minHeight: CGFloat = 0,
                       kind: UKSettingsRowKind = .control, build: @escaping () -> UIView, elements: ((UIView) -> [Any])? = nil) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: signature, kind: kind) { cell in
            let view = build()
            cell.show(view, insets: insets, minHeight: minHeight)
            if let elements { cell.accessibilityElements = elements(view) }
        }
    }
}
#endif
