#if os(iOS)
import HassCore
import HassDesign
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Form rows

/// The placeholder ink of the todo fields: opaque (a translucent grey measured 2.9:1 on the sheet's cell), 4.5:1 or better in both
/// appearances.
enum UKTodoPlaceholder {
    static let ink = UIColor.ukDynamic(light: UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1), dark: UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1))
}

/// A single-line text field row of a todo form: body type, 44 pt tall at least, the field's own accessibility identifier.
@MainActor
final class UKTodoTextField: UITextField {
    private let placeholderLabel = UILabel.uk(.body, ink: UKTodoPlaceholder.ink, lines: 1)

    init(placeholder: String, identifier: String) {
        super.init(frame: .zero)
        font = .ukFont(.body)
        adjustsFontForContentSizeCategory = true
        textColor = UKDesignInk.primary
        accessibilityIdentifier = identifier
        accessibilityLabel = placeholder
        // The system placeholder is drawn lighter than any ink set for it and measured 2.9:1: a label stands in for it.
        placeholderLabel.text = placeholder
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addAction(UIAction { [weak self] _ in self?.updatePlaceholder() }, for: .editingChanged)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var text: String? {
        didSet { updatePlaceholder() }
    }

    /// The view to use as the form row: the field with its placeholder label laid over it as a sibling, so the accessibility audit
    /// sees an empty field and not the label's pixels as the field's text.
    lazy var rowView: UIView = {
        let container = UIView()
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        container.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor), bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor), trailingAnchor.constraint(equalTo: container.trailingAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()

    private func updatePlaceholder() { placeholderLabel.isHidden = !(text ?? "").isEmpty }
}

/// A growing text field row (`TextField(axis: .vertical).lineLimit(a...b)`): one line tall at first, growing with the text to
/// `maxLines`, then scrolling. The placeholder shows while it is empty.
@MainActor
final class UKTodoTextView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let placeholderLabel = UILabel.uk(.body, ink: UKTodoPlaceholder.ink)
    private let minLines: Int
    private let maxLines: Int
    /// Runs after every edit, with the new text.
    var onChange: ((String) -> Void)?
    /// Runs when the row's height changed, so the list can measure the cell again.
    var onHeightChange: (() -> Void)?
    private var lastHeight: CGFloat = 0
    /// A grouped `Form` row's padding above and below its text (a one-line row is 52 pt, a three-line one about 94 pt).
    private static let verticalInset: CGFloat = 15.5

    init(placeholder: String, identifier: String, lines: ClosedRange<Int>) {
        minLines = lines.lowerBound
        maxLines = lines.upperBound
        super.init(frame: .zero)
        textView.font = .ukFont(.body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UKDesignInk.primary
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: Self.verticalInset, left: 0, bottom: Self.verticalInset, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.accessibilityIdentifier = identifier
        textView.accessibilityLabel = placeholder
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = placeholder
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor), textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor), textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor), placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKTodoTextView, _) in view.invalidateIntrinsicContentSize() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        let line = textView.font?.lineHeight ?? 20
        let minimum = max(52, ceil(line * CGFloat(minLines)) + 2 * Self.verticalInset)
        let maximum = ceil(line * CGFloat(maxLines)) + 2 * Self.verticalInset
        let width = bounds.width > 0 ? bounds.width : 300
        let fitted = ceil(textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        return CGSize(width: UIView.noIntrinsicMetric, height: min(max(fitted, minimum), maximum))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = intrinsicContentSize.height
        textView.isScrollEnabled = textView.contentSize.height > height + 1
        if abs(height - lastHeight) > 0.5 {
            lastHeight = height
            invalidateIntrinsicContentSize()
            onHeightChange?()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        invalidateIntrinsicContentSize()
        onChange?(textView.text)
        onHeightChange?()
    }
}

/// A pop-up picker row (`Picker` in a `Form`): the title leading, the chosen option trailing with the pop-up chevrons, the whole row
/// opening the menu. One button to VoiceOver: label = title, value = the chosen option. The canonical row (form metrics) with a menu
/// button as its tap target.
@MainActor
final class UKTodoPickerRow: UKRowView {
    private let button = UIButton(type: .system)
    private let chevrons = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down",
                                                      withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small)))

    init(title: String, identifier: String) {
        super.init(.init(title, value: " ", style: .form))
        chevrons.tintColor = UKDesignInk.secondary
        chevrons.setContentHuggingPriority(.required, for: .horizontal)
        setAccessory(chevrons)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        installTapTarget(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the chosen option and the menu of all of them.
    func update(options: [DonetickTaskForm.Option], selected: String, choose: @escaping (String) -> Void) {
        let chosen = options.first { $0.value == selected }
        var content = rowContent
        content.value = chosen?.label ?? ""
        update(content, accessory: accessory)
        button.menu = UIMenu(children: options.map { option in
            UIAction(title: option.label, state: option.value == selected ? .on : .off) { _ in choose(option.value) }
        })
        button.accessibilityValue = chosen?.label
    }
}

/// A row with a leading label and a trailing control (`LabeledContent`, `DatePicker`): the canonical row (form metrics) with the
/// control as its accessory. Build a new one each time a row is needed; a row owns its control.
@MainActor
final class UKTodoLabeledRow: UKRowView {
    init(title: String, trailing: UIView) {
        super.init(.init(title, style: .form))
        trailing.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setAccessory(trailing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A full-row text button (a destructive Delete, a Choose Images row): the label in `ink`, an optional leading glyph. A ``UKRowButton``
/// around the canonical row.
@MainActor
final class UKTodoButtonRow: UKRowButton {
    /// The control itself, for a popover source.
    var button: UIControl { self }

    init(title: String, symbol: String? = nil, ink: UIColor, identifier: String, action: @escaping () -> Void) {
        var content = UKRowContent(title, symbol: symbol, glyph: ink, style: .form)
        content.titleInk = ink
        super.init(UKRowView(content), onTap: action)
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Base

/// A picked image: thumbnail, name and a remove button (``AdminTodoImageRow``).
@MainActor
final class UKAdminTodoImageRowView: UIView {
    init(image: AdminTodoUpload.Image, onRemove: @escaping () -> Void) {
        super.init(frame: .zero)
        let thumbnail = UIImageView(image: UIImage(data: image.data) ?? UIImage(systemName: "photo"))
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        thumbnail.layer.cornerCurve = .continuous
        thumbnail.isAccessibilityElement = false
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        let name = UILabel.uk(.body, ink: UKDesignInk.primary)
        name.text = image.filename
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3)), for: .normal)
        remove.tintColor = UKDesignInk.danger
        remove.accessibilityLabel = "Remove \(image.filename)"
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [thumbnail, name, UIView(), remove])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            thumbnail.widthAnchor.constraint(equalToConstant: 44), thumbnail.heightAnchor.constraint(equalToConstant: 44),
            remove.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            remove.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Rename admin to-do

#endif
