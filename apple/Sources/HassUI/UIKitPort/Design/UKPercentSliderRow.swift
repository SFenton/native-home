#if os(iOS)
import HassDesign
import UIKit

/// A labelled 0...100 slider in steps of 5 that shows and speaks its value (`PercentSliderRow`; web `RangeField`).
///
/// The row holds the value it is shown (``value``), like the binding it replaces; set it from the model and receive the person's
/// changes through ``onChange``. One tick of haptic per 5% detent while dragging. One adjustable accessibility element for the row:
/// the visible title and value belong to it.
///
/// ```swift
/// let row = UKPercentSliderRow("Brightness", value: 40, identifier: "light.brightness") { model.setBrightness($0) }
/// row.isEnabled = !model.isBusy
/// ```
final class UKPercentSliderRow: UKRowView {
    let title: String
    let identifier: String
    var onChange: (Double) -> Void
    /// The value shown, 0...100.
    var value: Double {
        didSet {
            guard value != oldValue else { return }
            slider.value = Float(value)
            show()
        }
    }
    var isEnabled = true {
        didSet {
            slider.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.5
        }
    }

    private let slider = UISlider()
    private let feedback = UISelectionFeedbackGenerator()

    init(_ title: String, value: Double, identifier: String, onChange: @escaping (Double) -> Void) {
        self.title = title
        self.value = value
        self.identifier = identifier
        self.onChange = onChange
        super.init(UKRowContent(title, value: "\(Int(value))%", style: .form))
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = Float(value)
        slider.addAction(UIAction { [weak self] _ in self?.slid() }, for: .valueChanged)
        // The title and value are the row's line; the slider is its body. The whole row is one adjustable element.
        setBody(slider)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = title
        accessibilityIdentifier = identifier
        show()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// One element for the row: its children are hidden from assistive technologies.
    override var accessibilityElements: [Any]? {
        get { nil }
        set {}
    }

    private func show() {
        var content = rowContent
        content.value = "\(Int(value))%"
        update(content)
        accessibilityValue = "\(Int(value)) percent"
    }

    private func slid() {
        let snapped = (Double(slider.value) / 5).rounded() * 5
        slider.value = Float(snapped)
        guard snapped != value else { return }
        value = snapped
        // One tick per 5% detent while dragging, like the brightness tile (owner, 2026-10-24).
        feedback.selectionChanged()
        onChange(snapped)
    }

    private func adjust(increment: Bool) {
        guard isEnabled else { return }
        let adjusted = PercentSliderRow.adjusted(value, increment: increment)
        guard adjusted != value else { return }
        value = adjusted
        onChange(adjusted)
    }

    override func accessibilityIncrement() { adjust(increment: true) }
    override func accessibilityDecrement() { adjust(increment: false) }
}
#endif
