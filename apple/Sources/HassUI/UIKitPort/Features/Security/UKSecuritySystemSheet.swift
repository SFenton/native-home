#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One child with insets around it, sized at its natural height: the page padding the Security views sit in.
@MainActor
final class UKSecurityInsetView: UIView, UKGridMeasuring {
    let child: UIView
    var insets: UIEdgeInsets

    init(_ child: UIView, insets: UIEdgeInsets) {
        self.child = child
        self.insets = insets
        super.init(frame: .zero)
        addSubview(child)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - insets.left - insets.right)
        let height = (child as? UKGridMeasuring)?.gridHeight(forWidth: inner) ?? child.sizeThatFits(CGSize(width: inner, height: CGFloat.greatestFiniteMagnitude)).height
        return height + insets.top + insets.bottom
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        child.frame = bounds.inset(by: insets)
    }
}

/// The security system sheet (web `SecurityControls.tsx` in the `#security-system` modal; SwiftUI `SecuritySystemSheet` +
/// `SecurityControls`): the alarm card in a scrolling page, titled "Security System". Shared by the Security sheet and the Security
/// System detail in Quick Links.
///
/// Disarming asks first, since it opens the house (HIG: Alerts). Tapping the current mode does nothing.
@MainActor
final class UKSecuritySystemViewController: UKPageViewController, UKSheetFitting {
    private let scroll: UKColumnScrollView
    private let card: UKAlarmPanelView

    var sheetFitScrollView: UIScrollView? { scroll }

    /// - Parameter context: The page's context; the sheet takes the copy with the sheet surface.
    init(context: UKContext, caller: any HassServiceCalling) {
        let sheetContext = context.with { $0.surface = .sheet }
        var presenter: () -> UIViewController? = { nil }
        card = UKAlarmPanelView(context: sheetContext, caller: caller) { presenter() }
        let host = UKAlarmCardHost(card: card, avoidsHinge: false)
        // `.padding()` around the card, which is capped and centred.
        let padded = UKSecurityInsetView(host, insets: UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l,
                                                                    bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        scroll = UKColumnScrollView(content: padded)
        super.init(context: sheetContext, title: "Security System")
        presenter = { [weak self] in self }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: scroll)
    }
}
#endif
