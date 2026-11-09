#if os(iOS)
import UIKit

/// Self-sizing cells that cannot be measured early (owner, 2026-10-30: App Icon, Home Assistant Settings and the Food rows showed one
/// word a line and a very tall row). A cell that is sized while its list or sheet is still taking its width (zero, or the width of
/// a sheet that is still presenting) wraps its labels to nothing and reports a huge height, and the layout keeps that height until
/// something reconfigures the cell. Two parts, used together by every list or grid of self-sizing cells:
/// - ``UKWidthAwareCollectionView`` drops the layout's measured heights whenever its width changes;
/// - ``UIKit/UICollectionViewCell/ukFitted(_:)`` measures a cell at the width the layout proposes, with its layout pass redone.
final class UKWidthAwareCollectionView: UICollectionView {
    private var laidOutWidth: CGFloat = 0

    /// A drag that begins on a tap control scrolls the page: a `UIControl` (a Quick Links tile) otherwise keeps its touch, and at AX5,
    /// where one tile fills the window, the page could not be scrolled from the tiles (the web page scrolls under a pressed tile). The
    /// system's continuous controls keep their drags; the port's own sliders and dials track with pan recognizers, which this does not touch.
    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UISlider || view is UISwitch || view is UIStepper || view is UITextField || view is UITextView || view is UIDatePicker {
            return super.touchesShouldCancel(in: view)
        }
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width.rounded()
        guard width != laidOutWidth else { return }
        let first = laidOutWidth == 0
        laidOutWidth = width
        // The first width is the one the first measurement used; a later one means the rows were measured at another.
        if !first { collectionViewLayout.invalidateLayout() }
    }
}

extension UICollectionViewCell {
    /// `layoutAttributes` with the height this cell needs at the width the layout proposes (the system's fitting, with the cell's own layout
    /// redone first so labels re-wrap at that width). Call from `preferredLayoutAttributesFitting`.
    func ukFitted(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
        let width = layoutAttributes.size.width
        guard width > 1 else { return attributes }
        bounds.size.width = width
        contentView.setNeedsLayout()
        setNeedsLayout()
        layoutIfNeeded()
        let fitted = systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                             withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        attributes.size = CGSize(width: width, height: ceil(fitted.height))
        return attributes
    }
}
#endif
