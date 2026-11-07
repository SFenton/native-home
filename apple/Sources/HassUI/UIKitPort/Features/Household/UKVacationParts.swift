#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Section

/// A titled block of an away page (`AwaySection`: web `section` + `SectionHeader` + `Description`). Direction G's header: 20 Bold
/// on the wallpaper, and 15 Semibold secondary inside a sheet over its inset list.
@MainActor
final class UKAwaySectionView: UIView {
    private var headerLabel: UILabel?
    private let stack = UIStackView.ukColumn(spacing: HassTokens.Spacing.s)

    init(title: String? = nil, description: String? = nil, surface: TileSurface, content: [UIView] = []) {
        super.init(frame: .zero)
        addSubview(stack)
        stack.ukPin(to: self)
        if let title {
            if surface == .sheet {
                let header = UKFormText.header(title, style: .subheadline)
                header.font = .ukFont(.subheadline, weight: .semibold)
                headerLabel = header
                stack.addArrangedSubview(UKHouseholdPaddedView(header, insets: UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l)))
            } else {
                let header = UILabel.uk(.title3, weight: .bold, ink: UKInk.primary)
                header.text = title
                header.accessibilityTraits = .header
                headerLabel = header
                stack.addArrangedSubview(header)
            }
        }
        if let description {
            let label = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
            label.text = description
            stack.addArrangedSubview(label)
        }
        content.forEach(stack.addArrangedSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTitle(_ title: String) { headerLabel?.text = title }
}

// MARK: - Buttons

/// A full-width action button (`AwayActionButton`, web `FieldActionButton`). The prominent one is the screen's primary capsule;
/// the rest are bordered in the action tint, or G's red when destructive.
@MainActor
enum UKAwayButtons {
    /// The prominent button: `#0071E3` with a white label. Off dims it; the reason is spoken as its hint.
    static func prominent(title: String, identifier: String, isEnabled: Bool = true, disabledReason: String? = nil, isBusy: Bool = false,
                          busyTitle: String? = nil, action: @escaping () -> Void) -> UKPrimaryButton {
        let button = UKPrimaryButton(title, isBusy: isBusy, busyTitle: busyTitle, action: action)
        button.accessibilityIdentifier = identifier
        button.isEnabled = isEnabled
        button.accessibilityHint = isEnabled ? "" : disabledReason ?? ""
        return button
    }

    /// A bordered button. The tint fills the capsule, so the label is plain ink on it (a destructive one stays red).
    static func bordered(title: String, destructive: Bool, identifier: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.buttonSize = .large
        configuration.baseForegroundColor = destructive ? UKDesignInk.danger : UKDesignInk.primary
        configuration.baseBackgroundColor = destructive ? UKDesignInk.danger : UKDesignInk.action
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .ukFont(.body)
            return attributes
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = identifier
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        return button
    }
}

// MARK: - Checklist row

/// One pre-vacation task (`VacationChecklistRow`, web `CheckboxRow`): a circle that turns into a green check, as in Reminders. The
/// shared ``UKCheckRow`` (pattern `check-row.md`): the title starts 16 + 24 + 14 pt in, where the list insets its hairlines.
@MainActor
final class UKVacationChecklistRow: UIView {
    private let titleLabel = UILabel.uk(.body, ink: UKDesignInk.primary)
    private let checkRow: UKCheckRow
    private let onTap: () -> Void

    init(title: String, onTap: @escaping () -> Void) {
        self.onTap = onTap
        titleLabel.text = title
        checkRow = UKCheckRow(content: titleLabel)
        super.init(frame: .zero)
        titleLabel.isUserInteractionEnabled = false
        checkRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkRow)
        NSLayoutConstraint.activate([
            checkRow.topAnchor.constraint(equalTo: topAnchor), checkRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            checkRow.leadingAnchor.constraint(equalTo: leadingAnchor), checkRow.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        checkRow.onToggle = { [weak self] in self?.onTap() }
        checkRow.toggle.isAccessibilityElement = true
        checkRow.toggle.accessibilityLabel = title
        checkRow.toggle.accessibilityTraits = [.button, .toggleButton]
        isAccessibilityElement = false
        accessibilityElements = [checkRow.toggle]
        update(isChecked: false, isUnavailable: false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The identifier lands on the toggle, the element VoiceOver and XCUITest find. This container reads back none: with one it was a
    /// second, valueless "Other" element a query by identifier found before the toggle.
    override var accessibilityIdentifier: String? {
        get { nil }
        set { checkRow.toggle.accessibilityIdentifier = newValue }
    }

    /// Shows the task's state. Only the glyph dims while unavailable; the title keeps its contrast.
    func update(isChecked: Bool, isUnavailable: Bool, animated: Bool = true) {
        checkRow.setChecked(isChecked, checkedTint: UKDesignInk.success, uncheckedTint: UKDesignInk.secondary, dimmed: isUnavailable, animated: animated)
        checkRow.toggle.isEnabled = !isUnavailable
        checkRow.toggle.accessibilityValue = isUnavailable ? "Unavailable" : isChecked ? "Checked" : "Not checked"
        checkRow.toggle.accessibilityTraits = isUnavailable ? [.button, .toggleButton, .notEnabled] : [.button, .toggleButton]
    }
}

// MARK: - Date fields

/// The vacation's start and end, each one date-and-time picker, with the range error (`VacationDateFields`, web
/// `VacationDateControls`).
@MainActor
final class UKVacationDateFieldsView: UIView {
    private let stack = UIStackView.ukColumn(spacing: HassTokens.Spacing.m)
    private let identifierPrefix: String
    private let fields: UKScheduleDateFields
    private let error = UKInlineAlertView(Vacation.Copy.dateRangeError, severity: .error)
    private let onChange: (Vacation.DateRange, Bool) -> Void

    /// - Parameters:
    ///   - commitDelay: Quiet time before a change is reported (inline dates write to Home Assistant).
    ///   - onChange: The new range and whether the end changed.
    init(range: Vacation.DateRange, invalid: Bool, identifierPrefix: String, commitDelay: Duration?,
         onChange: @escaping (Vacation.DateRange, Bool) -> Void) {
        self.identifierPrefix = identifierPrefix
        self.onChange = onChange
        fields = UKScheduleDateFields(fields: Self.makeFields(range, prefix: identifierPrefix, onChange: onChange), commitDelay: commitDelay)
        super.init(frame: .zero)
        addSubview(stack)
        stack.ukPin(to: self)
        let description = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
        description.text = Vacation.Copy.datesDescription
        stack.addArrangedSubview(description)
        error.accessibilityIdentifier = "\(identifierPrefix).error"
        error.isHidden = !invalid
        stack.addArrangedSubview(error)
        stack.addArrangedSubview(fields)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Each picker stops at the other's value, so Ends cannot be set before Starts (HIG Pickers).
    private static func makeFields(_ range: Vacation.DateRange, prefix: String,
                                   onChange: @escaping (Vacation.DateRange, Bool) -> Void) -> [ScheduleDateField] {
        [
            ScheduleDateField(Vacation.Copy.starts, .dateAndTime, range.start, id: "\(prefix).start") {
                onChange(Vacation.DateRange(start: $0, end: range.end), false)
            }.limited(to: range.end.date()),
            ScheduleDateField(Vacation.Copy.ends, .dateAndTime, range.end, id: "\(prefix).end") {
                onChange(Vacation.DateRange(start: range.start, end: $0), true)
            }.limited(from: range.start.date()),
        ]
    }

    /// Shows the controller's range; a pick the controller moved is dropped.
    func update(range: Vacation.DateRange, invalid: Bool) {
        error.isHidden = !invalid
        fields.update(fields: Self.makeFields(range, prefix: identifierPrefix, onChange: onChange))
    }
}
#endif
