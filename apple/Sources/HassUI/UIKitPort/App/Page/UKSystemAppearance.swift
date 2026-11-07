#if os(iOS)
import HassDesign
import UIKit

/// The user's appearance for sheets: the shell and the galleries force dark for their pages, which hides it from their own
/// trait collection, so a sheet reads it from the screen (``SystemAppearance``, including the `FENTON_APPEARANCE` debug override).
enum UKSystemAppearance {
    /// Light or dark as the system (or the debug override) says.
    @MainActor
    static func style(for view: UIView? = nil) -> UIUserInterfaceStyle {
        let scheme: UIUserInterfaceStyle
        if let screen = view?.window?.windowScene?.screen {
            scheme = SystemAppearance.resolve(override: debugOverride, system: screen.traitCollection.userInterfaceStyle == .light ? .light : .dark) == .light ? .light : .dark
        } else {
            scheme = SystemAppearance.current() == .light ? .light : .dark
        }
        return scheme
    }

    private static var debugOverride: String? {
        SystemAppearance.debugOverride
    }
}
#endif
