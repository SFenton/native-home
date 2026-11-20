#if os(iOS)
import HassCore
import UIKit

// MARK: - The tab navigator follows the page on top

/// Hides and returns the tab navigator with the page on top of the selected stack (`sh.page-chrome-hide@1`, `sh.tabs-visibility@1`).
///
/// The rule is ``ServerUIChromeHide/hidesTabs(hides:visibility:depth:)``. One system call draws it on every family: the iPhone floating bar, the iPad
/// top bar and the Duo rail (`setTabBarHidden(_:animated:)`). A page in a sheet never decides: sheets show no tab bar.
extension UKServerUIRenderer {
    /// Whether the tab navigator hides while `page` is the top page of its stack.
    func hidesTabs(whileTop page: UKServerUIPage?) -> Bool {
        guard let page, page.presentationID == nil else { return false }
        let hides = publication.document.pages.first { $0.id == page.surfaceID }?.hides
        return ServerUIChromeHide.hidesTabs(hides: hides, visibility: publication.document.navigation.tabsVisibility, depth: page.depth)
    }

    /// Whether the page opened last in the selected stack hides the tabs. In columns that page is the one that decides.
    var selectedPageHidesTabs: Bool {
        hidesTabs(whileTop: logicalStacks[navigation.snapshot.selection]?.last)
    }

    /// Whether the tab navigator is hidden now.
    var tabBarIsHidden: Bool {
        if UKGlassEra.hasIOS18, #available(iOS 18.0, *) { return tabController.isTabBarHidden }
        return tabController.tabBar.isHidden
    }

    /// Sets the bar's visibility, with the system animation unless `animated` is false or Reduce Motion is on.
    func setTabBarHidden(_ hidden: Bool, animated: Bool) {
        if UKGlassEra.hasIOS18, #available(iOS 18.0, *) {
            guard tabController.isTabBarHidden != hidden else { return }
            tabController.setTabBarHidden(hidden, animated: animated && !UKMotion.reduceMotion)
        } else { tabController.tabBar.isHidden = hidden }
    }

    /// Starts the bar's move alongside a push or a pop that is about to show `page`, and puts it back if the person cancels the swipe.
    /// - Parameters:
    ///   - page: The page the stack is about to show.
    ///   - animated: Whether the stack animates to it.
    ///   - coordinator: The stack's transition, when it has one.
    func tabBarFollows(_ page: UKServerUIPage, animated: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?) {
        // Only the selected stack decides: another tab's stack may be syncing behind it.
        guard !publication.document.navigation.tabs.isEmpty, page.root == navigation.snapshot.selection else { return }
        let before = tabBarIsHidden
        // A page that shows columns stands for the page opened last in them.
        let top = page.wantsColumns ? logicalStacks[page.root]?.last ?? page : page
        setTabBarHidden(hidesTabs(whileTop: top), animated: animated)
        coordinator?.notifyWhenInteractionChanges { [weak self] context in
            if context.isCancelled { self?.setTabBarHidden(before, animated: true) }
        }
    }

    /// Makes the bar match the page that settled on top, after a push, a pop or a cancelled swipe.
    func settleTabBar() {
        guard !publication.document.navigation.tabs.isEmpty else { return }
        setTabBarHidden(selectedPageHidesTabs, animated: false)
    }
}
#endif
