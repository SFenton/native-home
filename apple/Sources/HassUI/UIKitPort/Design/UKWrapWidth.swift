#if os(iOS)
import UIKit

/// The one rule for a label that may wrap: it wraps at a width taken from something whose width is fixed by its own constraints
/// or frame (a host, a cell's fitted width, the window), never from its own content or its own last width.
///
/// A `numberOfLines = 0` label with automatic `preferredMaxLayoutWidth` wraps at the width it was last laid out at. When the label's
/// container takes its width from the label (a centred or leading-aligned stack, a capsule that hugs its title), width feeds wrap
/// and wrap feeds width: a layout loop (a folded iPhone Duo rotated to portrait hung the app: ``UKOfflineChipView``), or at best a
/// wrap that sticks at a width it had once. Give the label an explicit `preferredMaxLayoutWidth` from the reference instead:
///
/// ```swift
/// override func layoutSubviews() {
///     super.layoutSubviews()
///     UKWrapWidth.set(label, in: self, reserving: 2 * inset + glyphWidth + spacing)
/// }
/// ```
///
/// Writes only when the value changes, so a settled layout does no work. Until the reference has a width nothing is written and the
/// label measures as it would unbounded; the next pass (the reference's width settles during layout) corrects it.
@MainActor
enum UKWrapWidth {
    /// Sets `label` to wrap at `width`. Returns whether it changed.
    @discardableResult
    static func set(_ label: UILabel, to width: CGFloat) -> Bool {
        let width = width.rounded(.down)
        guard width > 1, abs(label.preferredMaxLayoutWidth - width) > 0.5 else { return false }
        label.preferredMaxLayoutWidth = width
        label.invalidateIntrinsicContentSize()
        return true
    }

    /// Sets each label to wrap within `reference`'s width less `reserved` (insets, glyphs and spacing beside the label).
    /// `reference` must be a view whose width does not come from these labels.
    @discardableResult
    static func set(_ labels: [UILabel], in reference: UIView, reserving reserved: CGFloat = 0) -> Bool {
        var changed = false
        for label in labels where set(label, to: reference.bounds.width - reserved) { changed = true }
        return changed
    }

    @discardableResult
    static func set(_ label: UILabel, in reference: UIView, reserving reserved: CGFloat = 0) -> Bool {
        set([label], in: reference, reserving: reserved)
    }

    /// The room a stack's other visible arranged views take beside `label`: their widths plus the spacing between all the visible ones.
    /// For the `reserving` of a label that shares a horizontal stack with a glyph or spinner.
    static func reserved(besides label: UILabel, in stack: UIStackView) -> CGFloat {
        let visible = stack.arrangedSubviews.filter { !$0.isHidden }
        let others = visible.filter { $0 !== label }.reduce(CGFloat(0)) { $0 + max($1.intrinsicContentSize.width, 0) }
        return others + stack.spacing * CGFloat(max(visible.count - 1, 0))
    }

    /// Sets `label` to wrap within a vertical, fill-aligned stack's content width (its width less its layout margins): that stack's
    /// width is decided by the stack's own constraints, and the label fills it.
    @discardableResult
    static func set(_ label: UILabel, inFillStack stack: UIStackView) -> Bool {
        let margins = stack.isLayoutMarginsRelativeArrangement ? stack.layoutMargins.left + stack.layoutMargins.right : 0
        return set(label, to: stack.bounds.width - margins)
    }
}

/// A plain container (a holder for a centred column, a padded cell) that keeps its wrapping labels at its own width less `reserved`.
/// Use it where a view has no subclass of its own to call ``UKWrapWidth`` from `layoutSubviews`. Its width must come from its parent.
final class UKWrapHost: UIView {
    var labels: [UILabel] = [] { didSet { setNeedsLayout() } }
    var reserved: CGFloat = 0 { didSet { setNeedsLayout() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapWidth.set(labels, in: self, reserving: reserved)
    }
}
#endif
