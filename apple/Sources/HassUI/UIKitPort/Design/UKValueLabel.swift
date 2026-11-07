#if os(iOS)
import UIKit

/// A value or count beside a row's main text (a stock count, a stepper's value, a person's Home/Away): it wraps, but never takes more
/// than ``maxShare`` of its row.
///
/// A plain wrapping label that also refuses to shrink claims the whole row while a self-sizing cell is measured, and its neighbour then
/// wraps a letter a line: the row came out very tall (owner, 2026-10-31: Expired Food and Food Spaces rows). This label reports a
/// definite size instead: its text measured at most ``maxShare`` of ``widthReference``, so short text stays on one line at its natural
/// width and long text, or text at accessibility sizes, wraps inside its share. Give it `.required` horizontal compression resistance
/// and hugging as usual; the main text takes the rest of the row.
///
/// ```swift
/// let count = UKValueLabel(.body, ink: UKDesignInk.secondary, monospacedDigit: true)
/// count.widthReference = row
/// ```
final class UKValueLabel: UILabel {
    /// The view whose width the share is taken of (the row). Until it has a width the label measures as if unbounded.
    weak var widthReference: UIView? { didSet { invalidateIntrinsicContentSize() } }
    /// The most of ``widthReference``'s width the label may take.
    var maxShare: CGFloat = 0.5 { didSet { invalidateIntrinsicContentSize() } }
    private var referenceWidth: CGFloat = 0

    init(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, ink: UIColor, monospacedDigit: Bool = false) {
        super.init(frame: .zero)
        font = .ukFont(style, weight: weight, monospacedDigit: monospacedDigit)
        adjustsFontForContentSizeCategory = true
        textColor = ink
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var cap: CGFloat {
        guard let width = widthReference?.bounds.width, width > 0 else { return .greatestFiniteMagnitude }
        return (width * maxShare).rounded(.down)
    }

    override var intrinsicContentSize: CGSize {
        let cap = cap
        let fitted = sizeThatFits(CGSize(width: cap, height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(min(fitted.width, cap)), height: ceil(fitted.height))
    }

    override var text: String? { didSet { invalidateIntrinsicContentSize() } }
    override var font: UIFont! { didSet { invalidateIntrinsicContentSize() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The row's width settles during layout (a cell measured at its proposed width, a rotation): measure again at the new share.
        let width = widthReference?.bounds.width ?? 0
        if width != referenceWidth {
            referenceWidth = width
            invalidateIntrinsicContentSize()
        }
    }
}
#endif
