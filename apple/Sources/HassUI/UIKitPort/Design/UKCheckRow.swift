#if os(iOS)
import HassDesign
import UIKit

/// The touch target of a ``UKCheckRow``: presses like a plain button (the row dims while it is held).
final class UKCheckToggle: UIControl {
    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? CGFloat(HassTokens.ControlState.pressedOpacity) : 1 } }
    }
}

/// The check variant of the canonical row (``UKRowView``; ``CheckRow``, `.agents/patterns/check-row.md`, `rows.md`): a check circle the
/// size of the title in the leading slot, the caller's text block, and an optional trailing accessory.
///
/// It adds no layout of its own: the chores rows (a task with a due line and an edit button), the vacation checklist and the climate
/// room-rule pages are a ``UKRowView`` with a `check` leading slot, a `textView` and a ``toggle`` as the row's tap target (everything
/// left of the accessory, so the accessory is its own VoiceOver element and tap target). It draws no card and no separator: a module
/// (``UKModuleListView``) or a form cell draws them. The row carries the 16 pt margin itself, so its text starts where the module's
/// hairlines do (16 + 24 + 14 pt).
///
/// ```swift
/// let row = UKCheckRow(content: titleLabel)
/// row.setChecked(true, checkedTint: UKDesignInk.success, uncheckedTint: UKDesignInk.secondary)
/// row.onToggle = { toggle() }
/// row.setAccessory(editButton, trailingInset: CheckRowMetrics.iconAccessoryTrailingInset)
/// ```
@MainActor
final class UKCheckRow: UKRowView {
    /// The touch target left of the accessory; callers set its accessibility label, value, hint, traits and identifier.
    let toggle = UKCheckToggle()
    /// For a row that binds itself to observable state.
    let bag = UKObservationBag()
    /// What a tap on the toggle does (after the tap haptic).
    var onToggle: (() -> Void)?
    /// The text block beside the circle.
    let content: UIView

    init(content: UIView) {
        self.content = content
        var model = UKRowContent("")
        model.check = .init(isChecked: false, checkedTint: UKDesignInk.success, uncheckedTint: UKDesignInk.secondary)
        model.verticalPadding = CheckRowMetrics.verticalPadding
        super.init(model, textView: content)
        accessoryTrailingInset = CheckRowMetrics.plainTrailingInset
        content.isUserInteractionEnabled = false
        installTapTarget(toggle)
        toggle.addAction(UIAction { [weak self] _ in
            UKTapFeedback.tap()
            self?.onToggle?()
        }, for: .touchUpInside)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setAccessory(_ view: UIView?, trailingInset: CGFloat? = nil) {
        super.setAccessory(view, trailingInset: trailingInset ?? CheckRowMetrics.plainTrailingInset)
    }
}
#endif
