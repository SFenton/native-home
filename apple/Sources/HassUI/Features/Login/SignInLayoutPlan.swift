import CoreGraphics
import HassDesign

/// Where the sign-in screen puts its header and form inside the scroll view (`.agents/design/sign-in-layout.md`): one centred column, or two regions side by side. Pure geometry, so it is tested on the
/// Mac host; ``UKLoginViewController`` applies it as constraint constants.
///
/// The split follows ``SplitPolicy/geometry(container:isRegularWidth:hinge:)`` over the scroll view's frame in window coordinates,
/// never a device name, and an accessibility text size always gets the column.
struct SignInLayoutPlan: Equatable {
    /// A horizontal span in the scroll view's own coordinates, measured from its physical left edge.
    struct Span: Equatable {
        var x: CGFloat
        var width: CGFloat
    }

    /// Two regions rather than one column.
    let isSplit: Bool
    /// The header's box, margins included: the column, or the header centred in its region at most ``SignInStyle/columnWidth`` wide.
    let header: Span
    /// The form's box, margins included: the column, or the form centred in its region at most ``SignInStyle/columnWidth`` wide.
    let form: Span

    /// The frame the column-or-split decision reads: the scroll view's frame with the height the keyboard has not shortened.
    ///
    /// The scroll view ends at the keyboard, so its own height changes when a field takes focus; the decision must not, or a regular
    /// window taller than wide by less than the keyboard would flip to two regions as the keyboard rose. Width and position stay the
    /// scroll view's (the hinge band is measured against them); the height is the safe area's.
    /// - Parameters:
    ///   - scroll: The scroll view's frame in window coordinates.
    ///   - safeHeight: The height of the view's safe area, keyboard excluded.
    static func decisionFrame(scroll: CGRect, safeHeight: CGFloat) -> CGRect {
        CGRect(x: scroll.minX, y: scroll.minY, width: scroll.width, height: safeHeight)
    }

    /// Resolves the layout for a scroll view.
    /// - Parameters:
    ///   - container: The keyboard-free frame (``decisionFrame(scroll:safeHeight:)``) in window coordinates (the hinge band is measured against it, not the window).
    ///   - isRegularWidth: The horizontal size class is regular.
    ///   - hinge: The device's division frame in window coordinates, if any.
    ///   - isAccessibilityText: The content size category is an accessibility size.
    ///   - isRightToLeft: The layout direction is right to left: the header takes the physical right region.
    static func resolve(container: CGRect, isRegularWidth: Bool, hinge: CGRect?, isAccessibilityText: Bool, isRightToLeft: Bool) -> SignInLayoutPlan {
        let width = container.width
        if !isAccessibilityText,
           let geometry = SplitPolicy.geometry(container: container, isRegularWidth: isRegularWidth, hinge: hinge) {
            let left = Span(x: 0, width: geometry.leadingWidth)
            let right = Span(x: geometry.leadingWidth + geometry.bandWidth, width: geometry.trailingWidth)
            let headerRegion = isRightToLeft ? right : left
            let formRegion = isRightToLeft ? left : right
            // Both are `min(460, region)` wide and centred in their region, so the header's text measures what the form's does.
            func centred(in region: Span) -> Span {
                let width = min(SignInStyle.columnWidth, region.width)
                return Span(x: region.x + (region.width - width) / 2, width: width)
            }
            return SignInLayoutPlan(isSplit: true, header: centred(in: headerRegion), form: centred(in: formRegion))
        }
        let band = HingeAvoidance.band(in: container, hinge: hinge)
        let place = HingeAvoidance.placement(objectWidth: min(SignInStyle.columnWidth, width), containerWidth: width, band: band)
        let column = Span(x: place.x, width: place.width)
        return SignInLayoutPlan(isSplit: false, header: column, form: column)
    }
}
