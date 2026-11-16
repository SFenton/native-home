#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - A toggle row's own parts

/// What a bound toggle row shows that follows the house: the line under the title, the tint of its glyph and whether the last call failed.
///
/// The structure that does not change (the symbol, the metrics, the face, the hint and the failure words) lives in
/// ``UKServerUIControlSpec/Row``, so a change here redraws in place and never rebuilds the row.
struct UKServerUIRowDetails: Equatable {
    /// The line under the title, or `nil` for none.
    var subtitle: String?
    /// The tint of the leading glyph, or `nil` for the row's secondary ink.
    var glyph: UIColor?
    /// Whether the last call from the row failed, so its failure words show under it.
    var failed = false
    /// The subtitle is still loading: the row keeps the line it showed.
    var keepsSubtitle = false
}

extension UKServerUIControlSpec {
    /// The parts of a bound toggle drawn as a row (`sh.bound-row-parts@1`, `sh.check-face@1`); a toggle with none is the plain switch row.
    struct Row: Equatable {
        /// The node's `icon`, in the glyph column; set only when a glyph is authored (a switch face only).
        var symbol: String?
        /// Unset keeps the module row.
        var metrics: ServerUIRowParts.Metrics?
        var isCheck = false
        var checkTint: ServerUIRowParts.CheckTint?
        /// What VoiceOver reads after the label while the row can be used.
        var hint: String?
        /// Said under the row after a call that failed.
        var failureText: String?
        /// Whether a line under the title is authored, so the row is the 60 pt one even before its text arrives.
        var hasSubtitle = false
    }
}

// MARK: - The row

/// A bound toggle drawn with its own parts: the module row whose whole width is the switch (``UKModuleToggleRow``), or the check row
/// (``UKCheckRow``), with a caption under it after a failed call.
///
/// It draws what it is given and reports intent: a tap sends the opposite of the value the row shows, and the row shows a new value
/// only when ``show(_:)`` hands it one, so Home Assistant stays the source of truth.
@MainActor
final class UKServerUIRowToggle {
    /// The host's content: the row, and under it the failure caption.
    let view = UIStackView()
    /// The element a test or VoiceOver reaches: the row, or the check row's toggle.
    let control: UIView
    private let spec: UKServerUIControlSpec
    private let row: UKServerUIControlSpec.Row
    private let moduleRow: UKModuleToggleRow?
    private let checkRow: UKCheckRow?
    private let caption = UILabel.uk(.footnote, ink: UKDesignInk.error)
    private let captionHolder = UIView()
    private var isOn = false
    private var available = true
    private var ruleEnabled = true
    private var details = UKServerUIRowDetails()
    private var announcedFailure = false

    /// - Parameters:
    ///   - spec: The control's title, identifier and unavailable words.
    ///   - row: What the row draws beyond its title.
    ///   - surface: The surface the row sits on.
    ///   - send: Reports that the person asked for a value.
    init(spec: UKServerUIControlSpec, row: UKServerUIControlSpec.Row, surface: TileSurface, send: @escaping (Bool) -> Void) {
        self.spec = spec
        self.row = row
        let ask = Ask(send)
        if row.isCheck {
            let title = UILabel.uk(.body, ink: UKDesignInk.primary)
            title.text = spec.title
            let check = UKCheckRow(content: title)
            check.surface = surface
            check.toggle.accessibilityLabel = spec.title
            check.toggle.accessibilityIdentifier = spec.identifier + ".value"
            check.onToggle = { ask.fire() }
            checkRow = check
            moduleRow = nil
            control = check.toggle
            view.addArrangedSubview(check)
        } else {
            let module = UKModuleToggleRow(spec.title, subtitle: nil, symbol: row.symbol, isOn: false, hint: row.hint, surface: surface) {
                ask.fire()
            }
            module.accessibilityIdentifier = spec.identifier + ".value"
            moduleRow = module
            checkRow = nil
            control = module
            view.addArrangedSubview(module)
        }
        ask.isOn = { [weak self] in self?.isOn ?? false }
        view.axis = .vertical
        caption.numberOfLines = 0
        caption.isAccessibilityElement = true
        caption.accessibilityIdentifier = spec.identifier + ".failure"
        caption.accessibilityTraits = .staticText
        caption.translatesAutoresizingMaskIntoConstraints = false
        captionHolder.addSubview(caption)
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: captionHolder.topAnchor, constant: HassTokens.Spacing.xs),
            caption.bottomAnchor.constraint(equalTo: captionHolder.bottomAnchor, constant: -HassTokens.Spacing.xs),
            caption.leadingAnchor.constraint(equalTo: captionHolder.leadingAnchor, constant: HassTokens.Spacing.l),
            caption.trailingAnchor.constraint(equalTo: captionHolder.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        captionHolder.isHidden = true
        view.addArrangedSubview(captionHolder)
        render(animated: false)
    }

    /// Hands a tap the value the row shows now, so the ask is for the opposite.
    private final class Ask {
        var isOn: () -> Bool = { false }
        private let send: (Bool) -> Void
        init(_ send: @escaping (Bool) -> Void) { self.send = send }
        func fire() { send(!isOn()) }
    }

    // MARK: Showing

    /// Shows the value Home Assistant reports.
    func show(_ isOn: Bool) {
        let changed = self.isOn != isOn
        self.isOn = isOn
        render(animated: changed)
    }

    /// Shows what follows the house: the subtitle, the glyph tint and a failed call.
    func update(_ details: UKServerUIRowDetails?) {
        var next = details ?? UKServerUIRowDetails()
        if next.keepsSubtitle { next.subtitle = self.details.subtitle }
        next.keepsSubtitle = false
        guard next != self.details else { return }
        self.details = next
        render(animated: false)
    }

    /// Whether the value can be read now; while it cannot, the row says so and cannot be used.
    func setAvailable(_ available: Bool) {
        guard self.available != available else { return }
        self.available = available
        render(animated: false)
    }

    /// `enabledWhen`: while it says no the row cannot be used.
    func setRuleEnabled(_ enabled: Bool) {
        guard ruleEnabled != enabled else { return }
        ruleEnabled = enabled
        render(animated: false)
    }

    /// Whether the row can be used now.
    var isEnabled: Bool { available && ruleEnabled }

    // MARK: Drawing

    private func render(animated: Bool) {
        let enabled = isEnabled
        // The unavailable words stand in for the hint while the row cannot be used; a switch row with no hint stays without one.
        let hint: String? = row.isCheck ? (enabled ? row.hint : spec.unavailableText)
            : (row.hint == nil ? nil : (enabled ? row.hint : spec.unavailableText))
        if let moduleRow {
            let words = available ? details.subtitle : spec.unavailableText
            var content = UKRowContent(spec.title, subtitle: words?.isEmpty == false ? words : nil, symbol: row.symbol, glyph: details.glyph,
                                       glyphOpacity: enabled ? 1 : 0.4, style: row.metrics == .form ? .form : .module)
            content.identifier = spec.identifier
            moduleRow.row.update(content, accessory: moduleRow.row.accessory)
            moduleRow.setOn(isOn, animated: animated)
            moduleRow.isEnabled = enabled
            moduleRow.hint = hint
        }
        if let checkRow {
            let action = row.checkTint == .action
            checkRow.setChecked(isOn, checkedTint: action ? UKInk.action : UKDesignInk.success,
                                uncheckedTint: action ? UKDesignSurface.secondaryInSheet : UKDesignInk.secondary,
                                dimmed: !enabled, animated: animated)
            checkRow.toggle.isEnabled = enabled
            checkRow.toggle.accessibilityHint = hint
            checkRow.toggle.accessibilityTraits = !enabled ? [.button, .notEnabled] : isOn ? [.button, .selected] : .button
            checkRow.toggle.accessibilityValue = available ? nil : spec.unavailableText
        }
        let words = details.failed ? row.failureText : nil
        let showing = words != nil
        if captionHolder.isHidden == showing {
            captionHolder.isHidden = !showing
            view.setNeedsLayout()
        }
        caption.text = words
        // Said by its text; set outright so the words are read even where UIKit has not derived a default label.
        caption.accessibilityLabel = words
        // VoiceOver hears the failure once, when it first appears.
        if let words, !announcedFailure { UIAccessibility.post(notification: .announcement, argument: words) }
        announcedFailure = showing
    }
}
#endif
