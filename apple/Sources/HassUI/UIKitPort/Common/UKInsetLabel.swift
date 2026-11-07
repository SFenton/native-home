#if os(iOS)
import UIKit

/// A label with padding, for a badge drawn as a capsule behind its text.
final class UKInsetLabel: UILabel {
    var insets = UIEdgeInsets.zero { didSet { invalidateIntrinsicContentSize() } }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(CGSize(width: max(size.width - insets.left - insets.right, 0), height: max(size.height - insets.top - insets.bottom, 0)))
        return CGSize(width: fitted.width + insets.left + insets.right, height: fitted.height + insets.top + insets.bottom)
    }
}
#endif
