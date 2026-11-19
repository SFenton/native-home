#if os(iOS)
import HassDesign
import UIKit

// MARK: - Preference action rows

/// The two button rows of the Appearance and About sections that do not push: Reset to Default (a text button in the action ink, no
/// glyph) and Version (the canonical Version row: the `info.circle` glyph, the build text on the trailing edge, a tap copies it;
/// [settings-version-row](../../../../../../.agents/design/settings-version-row.md)). Both are one ``UKRowButton`` around the module
/// row and draw no chevron: a chevron means a row pushes ([settings-section](../../../../../../.agents/patterns/settings-section.md)).
@MainActor
final class UKServerUIPreferenceRow: UKRowButton, UKSettingsKinded {
    /// What the row is.
    enum Kind {
        /// A text button in the action ink; dimmed and disabled while there is nothing to reset.
        case textButton
        /// The Version row: the glyph, the title and the trailing build text.
        case value
    }

    /// The trailing text of a ``Kind/value`` row, as shown and as copied.
    var value: String = "" { didSet { refresh() } }
    /// What VoiceOver reads for a ``Kind/value`` row instead of the shown text (`2610.26.01, build 57, commit 42edc57`).
    var spokenValue: String?
    /// What VoiceOver reads after the label.
    var hint: String? { didSet { accessibilityHint = hint } }
    private let kind: Kind

    /// Reset is a text button, Version a link row (it has a glyph column): each takes its kind's padding and content insets.
    var settingsRowKind: UKSettingsRowKind { kind == .value ? .link : .textButton }

    init(title: String, kind: Kind, identifier: String) {
        self.kind = kind
        var content = kind == .value ? UKRowView.versionContent(title: title, text: nil) : UKRowContent(title, style: .form)
        content.minHeight = HassTokens.minTarget
        content.outerInsets = (kind == .value ? UKSettingsRowKind.link : .textButton).contentInsets
        if kind == .textButton { content.titleInk = UKDesignInk.action }
        super.init(UKRowView(content))
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var accessibilityValue: String? {
        get { kind == .value ? spokenValue ?? super.accessibilityValue : super.accessibilityValue }
        set {}
    }

    override var isEnabled: Bool {
        didSet { row.alpha = kind == .textButton && !isEnabled ? 0.5 : 1 }
    }

    private func refresh() {
        var content = row.rowContent
        content.value = value.isEmpty ? nil : value
        row.update(content, accessory: row.accessory)
    }
}
#endif
