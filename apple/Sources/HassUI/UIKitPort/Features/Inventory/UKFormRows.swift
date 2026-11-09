#if os(iOS)
import HassCore
import HassDesign
import UIKit

// Rows of the inventory item editor and the Add Item sheet that a ``UKFormRowKind`` has no case for: each is made once and kept by its
// screen (a form reload would replace a control the person is using), and told what to show.

/// A switch row (`Toggle`, or `ActionToggle` when `actionOnly`): the title, an optional arc while a change runs, and the switch, which carries the
/// row's identifier and label. An action toggle reports a tap and stays where it was until the model says otherwise. The canonical row
/// (``UKRowView``, form metrics) with the switch in its accessory slot.
final class UKFormSwitchRow: UKRowView {
    var onToggle: (Bool) -> Void = { _ in }
    private let toggle = UISwitch()
    private let busy: UKArcSpinnerView
    private let actionOnly: Bool
    private var shown = false

    init(title: String, identifier: String, actionOnly: Bool = false, busyLabel: String? = nil) {
        self.actionOnly = actionOnly
        busy = UKArcSpinnerView(.inline, label: busyLabel ?? title)
        super.init(.init(title, style: .form))
        busy.color = UKDesignInk.primary
        busy.isHidden = true
        busy.isAccessibilityElement = false
        toggle.accessibilityIdentifier = identifier
        toggle.accessibilityLabel = title
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        let accessory = UIStackView(arrangedSubviews: [busy, toggle])
        accessory.axis = .horizontal
        accessory.alignment = .center
        accessory.spacing = HassTokens.Spacing.s
        setAccessory(accessory)
        isTextAccessible = false
        accessibilityElements = [toggle]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func changed() {
        if actionOnly {
            // The switch shows the model's value: put it back, then report the tap.
            let wanted = toggle.isOn
            toggle.setOn(shown, animated: false)
            onToggle(wanted)
        } else {
            shown = toggle.isOn
            onToggle(toggle.isOn)
        }
    }

    /// Shows the model's value.
    func show(isOn: Bool, isEnabled: Bool = true, label accessibilityLabel: String? = nil, isBusy: Bool = false) {
        shown = isOn
        if toggle.isOn != isOn { toggle.setOn(isOn, animated: window != nil) }
        toggle.isEnabled = isEnabled
        if let accessibilityLabel { toggle.accessibilityLabel = accessibilityLabel }
        busy.isHidden = !isBusy
    }
}

/// A text row that acts (Reset Changes, Save Changes, Delete, Scan Barcode Again): the title in `ink`, an optional glyph or arc at the
/// trailing edge, 44 pt at least. It wraps at large text. A ``UKRowButton`` around the canonical row.
final class UKFormActionRow: UKRowButton {
    private let trailing = UIImageView()
    private let busy: UKArcSpinnerView
    private let ink: UIColor
    private let bold: Bool

    init(title: String, ink: UIColor, bold: Bool = false, identifier: String, busyLabel: String = "Busy") {
        busy = UKArcSpinnerView(.inline, label: busyLabel)
        self.ink = ink
        self.bold = bold
        var content = UKRowContent(title, style: .form)
        content.titleInk = ink
        content.titleWeight = bold ? .bold : nil
        super.init(UKRowView(content))
        trailing.tintColor = ink
        trailing.isHidden = true
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        busy.isHidden = true
        let accessory = UIStackView(arrangedSubviews: [trailing, busy])
        accessory.axis = .horizontal
        accessory.alignment = .center
        row.setAccessory(accessory)
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the row's state.
    func show(title: String? = nil, label: String? = nil, symbol: String? = nil, isBusy: Bool = false, isEnabled: Bool = true) {
        if let title {
            var content = row.rowContent
            content.title = title
            row.update(content, accessory: row.accessory)
        }
        trailing.isHidden = symbol == nil || isBusy
        if let symbol { trailing.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body))) }
        busy.isHidden = !isBusy
        self.isEnabled = isEnabled
        alpha = isEnabled ? 1 : 0.4
        spokenLabelOverride = label
    }

    /// What VoiceOver reads when it is not the title.
    private var spokenLabelOverride: String?

    override var accessibilityLabel: String? {
        get { spokenLabelOverride ?? row.rowContent.title }
        set {}
    }
}

/// A labelled text field row (`LabeledContent("Name") { TextField … }`): the label leading, the field trailing and right-aligned. The
/// canonical row with the field as its expanding accessory.
final class UKFormFieldRow: UKRowView, UITextFieldDelegate {
    let field = UITextField()
    var onChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}

    init(title: String, placeholder: String, identifier: String, accessibilityLabel: String, numeric: Bool = false, labelHidden: Bool = false,
         maxFieldWidth: CGFloat? = nil) {
        super.init(.init(labelHidden ? "" : title, style: .form))
        field.placeholder = placeholder
        field.font = .ukFont(.body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UKDesignInk.primary
        field.textAlignment = .right
        field.autocorrectionType = .no
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = accessibilityLabel
        field.delegate = self
        if numeric {
            field.keyboardType = .decimalPad
            field.ukAddKeyboardDone()
        }
        field.addAction(UIAction { [weak self] _ in self?.onChange(self?.field.text ?? "") }, for: .editingChanged)
        if let maxFieldWidth {
            field.widthAnchor.constraint(lessThanOrEqualToConstant: maxFieldWidth).isActive = true
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        }
        setAccessory(field)
        expandsAccessory = true
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the model's text unless the person is typing it.
    func show(_ text: String) {
        if field.text != text, !field.isFirstResponder { field.text = text }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        onSubmit()
        return true
    }
}

/// A date row (`DatePicker("Expires", selection:, displayedComponents: .date)`): the label (with an optional note under it) and the
/// compact picker, in the canonical row's accessory slot.
final class UKFormDateRow: UKRowView {
    var onChange: (Date) -> Void = { _ in }
    private let picker = UIDatePicker()

    init(title: String, identifier: String, accessibilityLabel: String) {
        super.init(.init(title, style: .form))
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        picker.accessibilityIdentifier = identifier
        picker.accessibilityLabel = accessibilityLabel
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange(self.picker.date)
        }, for: .valueChanged)
        setAccessory(picker)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(date: Date, isEnabled: Bool = true, note text: String? = nil, label accessibilityLabel: String? = nil) {
        if picker.date != date { picker.setDate(date, animated: false) }
        picker.isEnabled = isEnabled
        var content = rowContent
        content.subtitle = text
        update(content, accessory: accessory)
        if let accessibilityLabel { picker.accessibilityLabel = accessibilityLabel }
    }
}

/// A stepper row (`Stepper { LabeledContent("Quantity", value:) }`): the label, the value in secondary ink and the system stepper, which
/// carries the identifier and the spoken label and value. The canonical row with a value and the stepper as its accessory.
class UKFormStepperRow: UKRowView {
    var onChange: (Double) -> Void = { _ in }
    let stepper = UIStepper()
    private let showsValue: Bool

    init(title: String, identifier: String, showsValue: Bool = true, symbol: String? = nil, glyph: UIColor? = nil) {
        self.showsValue = showsValue
        super.init(.init(title, value: showsValue ? " " : nil, symbol: symbol, glyph: glyph, style: .form))
        stepper.stepValue = 1
        stepper.accessibilityIdentifier = identifier
        stepper.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onChange(self.stepper.value)
        }, for: .valueChanged)
        stepper.setContentHuggingPriority(.required, for: .horizontal)
        setAccessory(stepper)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(current: Double, minimum: Double, maximum: Double, display: String, isEnabled: Bool, label accessibilityLabel: String) {
        stepper.minimumValue = minimum
        stepper.maximumValue = maximum
        if stepper.value != current { stepper.value = current }
        stepper.isEnabled = isEnabled
        if showsValue {
            var content = rowContent
            content.value = display
            update(content, accessory: accessory)
        }
        stepper.accessibilityLabel = accessibilityLabel
        stepper.accessibilityValue = display
    }
}
#endif
