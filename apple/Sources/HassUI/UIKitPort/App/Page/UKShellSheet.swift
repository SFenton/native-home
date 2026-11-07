#if os(iOS)
import HassDesign
import UIKit

/// Presents any page as an app modal, through the one class every modal goes through (``UKHassModalController``): detents that follow
/// the content (or full height), the grabber, the iPad form and page sizes, the Duo's full-height rule and leading-half placement
/// (``UKSheetPlacement``), pose changes under an open sheet and the safe-area rule (``UKSheetSafeArea``). It used to carry a second,
/// parallel implementation of those (`UKSheetNavigationController`); that is gone (owner, 2026-10-31: every modal on one path).
///
/// The page has no Close and no title of its own from the container (the page draws its header), and the sheet follows the system
/// appearance while the pages behind stay dark.
@MainActor
enum UKShellSheet {
    @discardableResult
    static func present(_ page: UIViewController, from presenter: UIViewController, width: HassSheetWidth, height: HassSheetHeight,
                        animated: Bool = true, completion: (() -> Void)? = nil) -> UKHassModalController {
        // A page handed over already in a navigation controller (it has no business being one) presents its first page.
        let root = (page as? UINavigationController)?.viewControllers.first ?? page
        var options = UKHassModalOptions(title: nil, fitKey: "UKShellSheet.\(type(of: root))")
        options.showsClose = false
        options.width = width
        options.height = height
        let modal = UKHassModalController(root: root, options: options)
        // The same transparent bar as the shell's, so the sheet's own ground shows to the top edge (`modalChrome()`).
        UKNavigationBarStyle.apply(to: modal.navigationBar, large: false)
        modal.overrideUserInterfaceStyle = UKSystemAppearance.style(for: presenter.view)
        modal.present(from: presenter, animated: animated, completion: completion)
        return modal
    }
}

/// A navigation bar with no band of its own (`HeaderBackgroundHidden`): the page fades its content out instead.
enum UKNavigationBarStyle {
    @MainActor
    static func apply(to bar: UINavigationBar, large: Bool) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.prefersLargeTitles = large
        bar.tintColor = nil
    }
}
#endif
