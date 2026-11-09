#if os(iOS)
import HassDesign
import UIKit

// Controls whose value belongs to a controller, not to the view (`ControllerControls`;
// `.agents/patterns/optimistic-actions.md`). Each shows the value it is given and reports intent through `send`; none keeps a
// copy, so a rejected command leaves the old value on screen: after `send` the control puts its shown value back until the
// controller hands it the new one.

/// A switch that shows a controller's value and sends the requested one (`ControllerToggle`).
///
/// ```swift
/// let toggle = UKControllerToggle(isOn: model.isOn) { model.set($0) }
/// bag.observe { toggle.show(box.state?.state == "on") }
/// ```
public final class UKControllerToggle: UISwitch {
    private let send: (Bool) -> Void
    private var shown: Bool

    /// The value the controller reports.
    public func show(_ isOn: Bool) {
        shown = isOn
        setOn(isOn, animated: window != nil)
    }

    public init(isOn: Bool, send: @escaping (Bool) -> Void) {
        self.send = send
        shown = isOn
        super.init(frame: .zero)
        super.isOn = isOn
        addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func changed() {
        let requested = super.isOn
        send(requested)
        // Show the controller's value again until it echoes the request.
        setOn(shown, animated: true)
    }
}

/// A switch for a controller that toggles itself (`ActionToggle`): a tap reports intent, the value it shows comes only from
/// ``show(_:)``.
public final class UKActionToggle: UISwitch {
    private let action: () -> Void
    private var shown: Bool

    public func show(_ isOn: Bool) {
        shown = isOn
        setOn(isOn, animated: window != nil)
    }

    public init(isOn: Bool, action: @escaping () -> Void) {
        self.action = action
        shown = isOn
        super.init(frame: .zero)
        super.isOn = isOn
        addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func changed() {
        action()
        setOn(shown, animated: true)
    }
}

/// A stepper that shows a controller's value and sends the requested one (`ControllerStepper`). The label shows the value;
/// the plus and minus buttons send `value ± step` within the range.
public final class UKControllerStepper: UIView {
    public let range: ClosedRange<Int>
    public let step: Int
    private let send: (Int) -> Void
    private let stepper = UIStepper()
    private let label = UILabel()
    private let format: (Int) -> String
    private var shown: Int

    public init(value: Int, in range: ClosedRange<Int>, step: Int, title: String? = nil, format: @escaping (Int) -> String = { "\($0)" },
                send: @escaping (Int) -> Void) {
        self.range = range
        self.step = step
        self.send = send
        self.format = format
        shown = value
        super.init(frame: .zero)
        label.font = UKFont.preferred(.body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(HassTokens.RGB.Ink.primary)
        label.numberOfLines = 0
        stepper.minimumValue = Double(range.lowerBound)
        stepper.maximumValue = Double(range.upperBound)
        stepper.stepValue = Double(step)
        stepper.value = Double(value)
        stepper.addAction(UIAction { [weak self] _ in self?.changed() }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, stepper])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        addSubview(row)
        row.ukPin(to: self)
        label.text = title.map { "\($0), \(format(value))" } ?? format(value)
        self.title = title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var title: String?

    /// The value the controller reports.
    public func show(_ value: Int) {
        shown = value
        stepper.value = Double(value)
        label.text = title.map { "\($0), \(format(value))" } ?? format(value)
    }

    private func changed() {
        send(Int(stepper.value))
        stepper.value = Double(shown)
    }
}

/// A picker that shows a controller's selection and sends the chosen one (`ControllerPicker`): a menu button.
public final class UKControllerPicker<Value: Hashable>: UIButton {
    public let titleText: String
    private let options: [Value]
    private let optionTitle: (Value) -> String
    private let send: (Value) -> Void
    private var shown: Value

    public init(_ title: String, options: [Value], optionTitle: @escaping (Value) -> String, selection: Value, send: @escaping (Value) -> Void) {
        titleText = title
        self.options = options
        self.optionTitle = optionTitle
        self.send = send
        shown = selection
        super.init(frame: .zero)
        showsMenuAsPrimaryAction = true
        show(selection)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The selection the controller reports.
    public func show(_ selection: Value) {
        shown = selection
        var configuration = UIButton.Configuration.plain()
        configuration.title = optionTitle(selection)
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = HassTokens.Spacing.s
        self.configuration = configuration
        accessibilityLabel = titleText
        accessibilityValue = optionTitle(selection)
        menu = UIMenu(children: options.map { option in
            UIAction(title: optionTitle(option), state: option == selection ? .on : .off) { [weak self] _ in self?.send(option) }
        })
    }
}
#endif
