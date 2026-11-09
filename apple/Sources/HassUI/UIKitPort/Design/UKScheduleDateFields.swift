#if os(iOS)
import HassDesign
import UIKit

/// Date and time pickers for schedules (`ScheduleDateFields`; `.agents/patterns/schedule-date-fields.md`): one labelled compact
/// date picker per field on a material row, two per row when the width allows (a column needs 320 pt).
///
/// Fields that write to Home Assistant on change pass a `commitDelay`: the picker shows the new value at once and reports it only
/// after the person stops scrolling the wheels, so one adjustment is one service call. Leaving the screen inside the quiet period
/// reports the pick instead of losing it. Rebind a field's saved value with ``update(fields:)`` (an echo or another device
/// drops a pending pick).
///
/// ```swift
/// let fields = UKScheduleDateFields(fields: [
///     ScheduleDateField(label: "Starts", part: .dateAndTime, value: start, identifier: "schedule.start") { send(start: $0) },
/// ], commitDelay: .seconds(1))
/// bag.observe { fields.update(fields: makeFields(box.state)) }
/// ```
public final class UKScheduleDateFields: UIView {
    public private(set) var fields: [ScheduleDateField]
    public let commitDelay: Duration?
    private var pickers: [UKScheduleDatePicker] = []
    private let rows = UIStackView()
    private var columns = 0

    /// A column's minimum width, and the most columns (`DynamicGridLayout(minCellWidth: 320, maxColumns: 2)`).
    static let minCellWidth: CGFloat = 320
    static let maxColumns = 2

    public init(fields: [ScheduleDateField], commitDelay: Duration? = nil) {
        self.fields = fields
        self.commitDelay = commitDelay
        super.init(frame: .zero)
        rows.axis = .vertical
        rows.spacing = HassTokens.Spacing.s
        addSubview(rows)
        rows.ukPin(to: self)
        pickers = fields.map { UKScheduleDatePicker(field: $0, commitDelay: commitDelay) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Hands the pickers their saved values (and bounds) again.
    public func update(fields newFields: [ScheduleDateField]) {
        fields = newFields
        for (picker, field) in zip(pickers, newFields) { picker.update(field: field) }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let spacing = HassTokens.Spacing.s
        let wanted = max(1, min(Self.maxColumns, Int(((bounds.width + spacing) / (Self.minCellWidth + spacing)).rounded(.down))))
        guard wanted != columns else { return }
        columns = wanted
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for start in stride(from: 0, to: pickers.count, by: wanted) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = spacing
            row.distribution = .fillEqually
            row.alignment = .top
            for offset in 0..<wanted {
                row.addArrangedSubview(start + offset < pickers.count ? pickers[start + offset] : UIView())
            }
            rows.addArrangedSubview(row)
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

/// One picker, showing the picked value at once while a delayed commit is pending (`ScheduleDatePicker` with its
/// `ScheduleDateControl`).
final class UKScheduleDatePicker: UIView {
    private(set) var field: ScheduleDateField
    private let commitDelay: Duration?
    private let titleLabel = UILabel()
    private let picker = UIDatePicker()
    private let stack = UIStackView()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    /// What the picker shows: the saved value, or the person's pick until Home Assistant echoes it.
    private var picked: Date
    private var unsent = UnsentPick()
    private var commitTask: Task<Void, Never>?

    init(field: ScheduleDateField, commitDelay: Duration?) {
        self.field = field
        self.commitDelay = commitDelay
        picked = field.value
        super.init(frame: .zero)
        material.layer.cornerRadius = HassTokens.Radius.chip
        material.layer.cornerCurve = .continuous
        material.clipsToBounds = true
        addSubview(material)
        material.ukPin(to: self)
        titleLabel.font = UKFont.preferred(.body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor(HassTokens.RGB.Ink.primary)
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        picker.preferredDatePickerStyle = .compact
        picker.addAction(UIAction { [weak self] _ in self?.pickChanged() }, for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(picker)
        stack.spacing = HassTokens.Spacing.s
        material.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: material.contentView.topAnchor, constant: HassTokens.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: material.contentView.bottomAnchor, constant: -HassTokens.Spacing.xs),
            stack.leadingAnchor.constraint(equalTo: material.contentView.leadingAnchor, constant: HassTokens.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: material.contentView.trailingAnchor, constant: -HassTokens.Spacing.m),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        configure()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }


    private func configure() {
        titleLabel.text = field.label
        switch field.part {
        case .date: picker.datePickerMode = .date
        case .time: picker.datePickerMode = .time
        case .dateAndTime: picker.datePickerMode = .dateAndTime
        }
        picker.minimumDate = field.bounds?.lowerBound == .distantPast ? nil : field.bounds?.lowerBound
        picker.maximumDate = field.bounds?.upperBound == .distantFuture ? nil : field.bounds?.upperBound
        picker.setDate(picked, animated: false)
        picker.accessibilityLabel = field.label
        picker.accessibilityIdentifier = field.identifier
    }

    /// The saved value moved (an echo or another device): drop the pick.
    func update(field newField: ScheduleDateField) {
        let moved = newField.value != field.value
        field = newField
        if moved {
            commitTask?.cancel()
            unsent.discard()
            picked = newField.value
        }
        configure()
    }

    private func pickChanged() {
        picked = picker.date
        guard picked != field.value else {
            commitTask?.cancel()
            unsent.discard()
            return
        }
        guard let commitDelay else {
            field.onChange(picked)
            return
        }
        unsent.hold(picked)
        commitTask?.cancel()
        let value = picked
        commitTask = Task { @MainActor [weak self] in
            // Reports the pick once the wheels stop, then falls back to the saved value if Home Assistant never echoes it.
            try? await Task.sleep(for: commitDelay)
            guard !Task.isCancelled, let self else { return }
            unsent.discard()
            field.onChange(value)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            picked = field.value
            picker.setDate(picked, animated: true)
        }
    }

    /// The screen closed inside the quiet period: report the pick now, so a change that triggers a service call is never lost.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window == nil, let value = unsent.take() else { return }
        commitTask?.cancel()
        field.onChange(value)
    }

    /// Label and picker side by side when the label fits on one line, else the picker drops below it (narrow iPad sheet
    /// columns, accessibility sizes); the label never truncates.
    override func layoutSubviews() {
        super.layoutSubviews()
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let available = bounds.width - HassTokens.Spacing.m * 2
        let labelWidth = titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
        let pickerWidth = picker.intrinsicContentSize.width
        let sideBySide = !accessibility && labelWidth + HassTokens.Spacing.s + pickerWidth <= available
        let axis: NSLayoutConstraint.Axis = sideBySide ? .horizontal : .vertical
        if stack.axis != axis {
            stack.axis = axis
            stack.alignment = sideBySide ? .center : .leading
            stack.arrangedSubviews[1].isHidden = !sideBySide
            setNeedsLayout()
        }
    }
}
#endif
