import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A page with one tall scroll view, to drive the page base.
@MainActor
final class HostedScrollPage: UKPageViewController {
    let scroll = UIScrollView()
    var opened: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        let tall = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 3000))
        scroll.addSubview(tall)
        scroll.contentSize = CGSize(width: 393, height: 3000)
        install(scrollView: scroll)
    }

    override func openQuickLinks() { opened.append("quick") }
    override func openAccount() { opened.append("account") }
    override func openMenu() { opened.append("menu") }
}

@MainActor
final class UKHostedPageBaseTests: DemoHouseTestCase {
    private func context(menu: Bool = false, inBar: Bool = false) -> UKContext {
        var context = UKGalleryChrome.context()
        context.navigator = ShellNavigator()
        context.section = .home
        context.shell?.chrome = ShellChrome(showsMenuButton: menu, titleInHeader: !menu)
        context.shell?.headerEdgeCap = 96
        context.shell?.inVerticalBar = inBar
        return context
    }

    private func host(_ page: UIViewController, size: CGSize = CGSize(width: 393, height: 852)) -> (UINavigationController, UIWindow) {
        let navigation = UINavigationController(rootViewController: page)
        UKNavigationBarStyle.apply(to: navigation.navigationBar, large: true)
        return (navigation, HostedPage.show(navigation, size: size))
    }

    func testTheBarCarriesQuickLinksAndProfileThatAskTheNavigator() {
        let context = context()
        context.navigator?.profileName = "Alex Demo"
        let page = HostedScrollPage(context: context, title: "Climate")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        let items = page.navigationItem.rightBarButtonItems ?? []
        XCTAssertTrue(items.contains { $0.accessibilityIdentifier == "quickLinks.open" }, "Quick Links is on the bar")
        XCTAssertEqual(page.navigationItem.title ?? page.title, "Climate")
        let quick = items.first { $0.accessibilityIdentifier == "quickLinks.open" }
        quick?.primaryAction?.performWithSender(nil, target: nil)
        XCTAssertEqual(page.opened, ["quick"])
        XCTAssertEqual(page.headerProfileName, "Alex Demo")
    }

    /// Each page's bar items carry the same stable identifiers on iOS 26, so the bar treats Profile and Quick Links as the same
    /// items across a push and a pop instead of cross-fading them (a bar item cannot be shared between two pages: UIKit moves it).
    func testPagesCarryStableBarItemIdentifiersAndKeepTheirItemsAcrossPushAndPop() throws {
        let context = context()
        context.navigator?.profileName = "Alex Demo"
        let first = HostedScrollPage(context: context, title: "Climate")
        let second = HostedScrollPage(context: context, title: "Lights")
        let (navigation, window) = host(first)
        defer { window.isHidden = true }
        navigation.pushViewController(second, animated: false)
        HostedPage.wait(0.3)
        let a = first.navigationItem.rightBarButtonItems ?? []
        let b = second.navigationItem.rightBarButtonItems ?? []
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a.count, b.count)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(a.count, 3)
            XCTAssertEqual(a.compactMap(\.identifier), b.compactMap(\.identifier))
            XCTAssertEqual(Set(b.compactMap(\.identifier)), [UKShellHeaderItems.profileIdentifier, UKShellHeaderItems.quickLinksIdentifier])
        }
        navigation.popViewController(animated: false)
        HostedPage.wait(0.3)
        let profile = HostedPage.descendants(of: window).compactMap { $0 as? UKProfileButtonView }.first
        XCTAssertNotNil(profile?.window, "Profile is on the window after the pop")
        XCTAssertTrue(profile?.isUserInteractionEnabled ?? false)
        XCTAssertEqual(first.navigationItem.rightBarButtonItems?.count, a.count)
    }

    /// The Duo's vertical bar: the rail's Profile and Quick Links carry the stable identifiers on both pages and are still there after
    /// a push and a pop.
    func testVerticalBarPagesCarryMatchingIdentifiersAcrossPushAndPop() throws {
        guard #available(iOS 26.0, *), UKGlassEra.hasGlass else { throw XCTSkip("the rail's items are an iOS 26 glass-bar feature") }
        let context = context(inBar: true)
        context.navigator?.profileName = "Alex Demo"
        let first = HostedScrollPage(context: context, title: "Climate")
        let second = HostedScrollPage(context: context, title: "Lights")
        let (navigation, window) = host(first)
        defer { window.isHidden = true }
        navigation.pushViewController(second, animated: false)
        HostedPage.wait(0.3)
        let expected = [UKShellHeaderItems.profileIdentifier, UKShellHeaderItems.quickLinksIdentifier]
        func identifiers(_ page: UIViewController) -> [String] {
            let items = page.navigationItem.rightBarButtonItems ?? page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
            return items.compactMap(\.identifier)
        }
        XCTAssertEqual(identifiers(first), expected)
        XCTAssertEqual(identifiers(second), expected)
        navigation.popViewController(animated: false)
        HostedPage.wait(0.3)
        XCTAssertEqual(identifiers(first), expected, "Profile and Quick Links are still on the rail after the pop")
        let profile = (first.navigationItem.rightBarButtonItems ?? []).first
        XCTAssertEqual(profile?.accessibilityIdentifier, "nav.profile")
    }

    /// A live text-size change rebuilds the page's header items, so the rail's system badge takes the new size, capped at xLarge, and the
    /// rail's Large Content title carries the count.
    func testALiveTextSizeChangeRefontsTheRailBadge() throws {
        guard #available(iOS 26.0, *), UKGlassEra.hasGlass else { return }
        let context = context(inBar: true)
        context.shell?.attentionCount = 12
        context.navigator?.profileName = "Alex Demo"
        let page = HostedScrollPage(context: context, title: "Climate")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        let rail = { () -> UIBarButtonItem? in
            let grouped = page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
            return (grouped + (page.navigationItem.rightBarButtonItems ?? [])).first { $0.accessibilityIdentifier == "nav.profile" }
        }
        let expected = { (category: UIContentSizeCategory) in UKShellHeaderItems.badgeFont(category: category).pointSize }
        page.traitOverrides.preferredContentSizeCategory = .large
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let large = try XCTUnwrap(rail()?.badge?.font?.pointSize)
        XCTAssertEqual(large, expected(.large))
        XCTAssertEqual(rail()?.title, "\(UKShellHeaderItems.profileMenuTitle), 9+", "the Large Content Viewer names the count")
        if case let .some(menu as UIAction) = rail()?.menuRepresentation {
            XCTAssertEqual(menu.title, UKShellHeaderItems.profileMenuTitle, "the overflow menu keeps the owner-named \"Your Summary\"")
        } else {
            XCTFail("the rail item has its own menu representation")
        }
        page.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let ax5 = try XCTUnwrap(rail()?.badge?.font?.pointSize)
        XCTAssertEqual(ax5, expected(.extraLarge), "AX5 holds at the xLarge size")
        XCTAssertGreaterThan(ax5, large)
        XCTAssertEqual(rail()?.accessibilityValue, ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: 12))
    }

    func testDefaultHeaderActionsOpenTheNavigatorsSheetsAndFlyout() {
        let context = context(menu: true)
        let page = UKPageViewController(context: context, title: "Home")
        page.isSectionRoot = true
        let (_, window) = host(page)
        defer { window.isHidden = true }
        page.openQuickLinks()
        XCTAssertEqual(context.navigator?.quickLinksSection, .home)
        page.openAccount()
        XCTAssertEqual(context.navigator?.accountSection, .home)
        let menu = page.navigationItem.leftBarButtonItem
        XCTAssertEqual(menu?.accessibilityIdentifier, "nav.open", "a section root has the menu button where the flyout shows")
        XCTAssertEqual(menu?.accessibilityLabel, "Open Navigation")
        menu?.primaryAction?.performWithSender(nil, target: nil)
        XCTAssertTrue(context.navigator?.isFlyoutOpen == true, "the menu button opens the flyout")
        page.focusMenuButton()
        XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .automatic)
        context.shell?.chrome = ShellChrome(showsMenuButton: false, titleInHeader: true)
        HostedPage.wait(0.2)
        XCTAssertNil(page.navigationItem.leftBarButtonItem, "the menu button leaves with the flyout")
        XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .never, "the title moves into the header")
    }

    func testASheetPageHasNoShellButtonsAndAnInlineTitle() {
        var sheetContext = context()
        sheetContext.surface = .sheet
        let page = HostedScrollPage(context: sheetContext, title: "Details")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        XCTAssertTrue(page.isSheet)
        XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .never)
        XCTAssertNil(page.navigationItem.rightBarButtonItems)
        XCTAssertEqual(page.view.backgroundColor?.resolvedColor(with: page.traitCollection).cgColor, UIColor.systemGroupedBackground.resolvedColor(with: page.traitCollection).cgColor, "a sheet has the system's grouped ground")
        page.setSheetBackdrop(UIView(), ground: .black)
        XCTAssertEqual(page.view.backgroundColor?.cgColor, UIColor.black.cgColor)
    }

    func testSheetOnlyInitUsesThePlaceholderContext() {
        let page = UKPageViewController(sheetTitle: "Sheet")
        XCTAssertTrue(page.isSheet)
        XCTAssertEqual(page.title, "Sheet")
    }

    func testColumnGroupShowsBackOrCloseAndFollowsTheBarState() {
        let page = HostedScrollPage(context: context(menu: true), title: "Settings")
        page.isSectionRoot = true
        let (_, window) = host(page)
        defer { window.isHidden = true }
        var performed: [String] = []
        let extra = UIBarButtonItem(title: "Refresh", primaryAction: UIAction { _ in })
        page.setColumnBar(UKColumnBar(items: [extra], kind: .close, perform: { performed.append("close") }))
        var leading = page.navigationItem.leadingItemGroups.flatMap(\.barButtonItems)
        let close = leading.first { $0.accessibilityIdentifier == "split.close" }
        XCTAssertEqual(close?.accessibilityLabel, "Close")
        XCTAssertTrue(leading.contains(extra), "the open page's own items ride in the column group")
        close?.primaryAction?.performWithSender(nil, target: nil)
        XCTAssertEqual(performed, ["close"])
        page.setColumnBar(UKColumnBar(items: [extra], kind: .back, isEnabled: false, perform: { performed.append("back") }))
        HostedPage.wait(0.4)
        leading = page.navigationItem.leadingItemGroups.flatMap(\.barButtonItems)
        let back = leading.first { $0.accessibilityIdentifier == "columns.back" }
        XCTAssertEqual(back?.accessibilityLabel, "Back")
        XCTAssertEqual(back?.isEnabled, false, "a save in flight turns Back off")
        page.setColumnBar(UKColumnBar(items: [extra], kind: .none))
        HostedPage.wait(0.4)
        XCTAssertEqual(leading.first { $0.accessibilityIdentifier == "columns.back" }?.isHidden, true, "nothing open hides the item")
        page.setColumnBar(nil)
        XCTAssertTrue(page.navigationItem.leadingItemGroups.isEmpty, "a narrow window takes the group away")
        XCTAssertFalse(page.navigationItem.rightBarButtonItems?.isEmpty ?? true, "the shell's items sit on the bar again")
    }

    func testScrollToTopReturnsToTheTopOfTheContent() {
        let page = HostedScrollPage(context: context(), title: "Long")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        page.scroll.setContentOffset(CGPoint(x: 0, y: 900), animated: false)
        page.scrollToTop(animated: false)
        XCTAssertEqual(page.scroll.contentOffset.y, -page.scroll.adjustedContentInset.top, accuracy: 1)
        // Already at the top: nothing moves.
        page.scrollToTop(animated: false)
        XCTAssertEqual(page.scroll.contentOffset.y, -page.scroll.adjustedContentInset.top, accuracy: 1)
    }

    func testAScrollThatRestsAtItsTopFollowsTheBarsHeightChange() {
        let page = HostedScrollPage(context: context(), title: "Long")
        let (navigation, window) = host(page)
        defer { window.isHidden = true }
        page.followTopInset()
        let before = page.scroll.adjustedContentInset.top
        navigation.additionalSafeAreaInsets.top = 40
        navigation.view.layoutIfNeeded()
        HostedPage.wait(0.3)
        page.followTopInset()
        XCTAssertGreaterThan(page.scroll.adjustedContentInset.top, before)
        XCTAssertEqual(page.scroll.contentOffset.y, -page.scroll.adjustedContentInset.top, accuracy: 1.5, "a page nobody scrolled stays at its top")
    }

    func testBottomAccessoryRaisesTheBottomSafeAreaOnceAndLeavesWithIt() {
        let page = HostedScrollPage(context: context(), title: "Strip")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        let label = UILabel()
        label.text = "Last call"
        page.bottomAccessory = label
        page.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        XCTAssertGreaterThan(page.additionalSafeAreaInsets.bottom, 0, "the pinned strip's height is added to the safe area")
        XCTAssertNotNil(label.superview)
        page.bottomAccessory = nil
        XCTAssertEqual(page.additionalSafeAreaInsets.bottom, 0)
    }

    func testPageInAColumnShowsItsTitleAsContentAndScrollsItAway() {
        let page = HostedScrollPage(context: context(), title: "Vacation")
        let columns = UKColumnsViewController(rootController: HostedScrollPage(context: context(), title: "Root"), shell: nil) {
            UKPanePlaceholderViewController(symbol: "gearshape", text: "Select a setting", identifier: "pane.empty")
        }
        let window = HostedPage.show(columns, size: CGSize(width: 1024, height: 768))
        defer { window.isHidden = true }
        columns.setWide(true)
        columns.open(page, tag: nil, animated: false)
        HostedPage.wait(0.3)
        let heading = HostedPage.descendants(of: page.view).compactMap { $0 as? UKColumnTitleHeader }.first
        XCTAssertEqual(heading?.text, "Vacation", "a column page's title is a large heading in its content")
        XCTAssertTrue(heading?.accessibilityTraits.contains(.header) == true)
        XCTAssertGreaterThan(page.additionalSafeAreaInsets.top, 0, "the heading's room is reserved in the safe area")
        page.title = "Vacation Mode"
        XCTAssertEqual(heading?.text, "Vacation Mode")
        page.scroll.setContentOffset(CGPoint(x: 0, y: 200), animated: false)
        page.view.layoutIfNeeded()
        XCTAssertLessThan(heading?.alpha ?? 1, 0.01, "scrolled away, the heading fades out before it meets the header")
        columns.setWide(false)
        HostedPage.wait(0.3)
    }

    func testVerticalBarKeepsAFixedBarTitleAndRestoresIt() {
        let fixed = UKFixedBarTitle()
        let item = UINavigationItem(title: "Climate")
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        fixed.update(item: item, fallbackTitle: "Climate", fixed: true, traits: traits)
        if #available(iOS 26.0, *) {
            XCTAssertNotNil(item.attributedTitle, "the bar title is set in the medium weight")
            fixed.update(item: item, fallbackTitle: "Climate", fixed: true, traits: traits)
        }
        item.title = "Climate 2"
        HostedPage.wait(0.2)
        fixed.update(item: item, fallbackTitle: "Climate", fixed: false, traits: traits)
        XCTAssertEqual(item.title, "Climate 2", "the plain title comes back")
        XCTAssertEqual(UKFixedBarTitle.font(compatibleWith: traits).pointSize, BarTitleTreatment.pointSize, accuracy: 4)
        // Nothing to restore.
        fixed.restore()
    }

    func testPageInVerticalBarWritesTheFixedTitle() {
        let context = context(inBar: true)
        let page = HostedScrollPage(context: context, title: "Security")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        if #available(iOS 26.0, *) { XCTAssertNotNil(page.navigationItem.attributedTitle) }
        context.shell?.inVerticalBar = false
        HostedPage.wait(0.2)
        XCTAssertEqual(page.navigationItem.title ?? page.title, "Security")
    }

    func testScrollFitStopsAShortPageBouncingAndLocksSidewaysDrags() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        scroll.contentSize = CGSize(width: 800, height: 100)
        UKScrollFit.apply(to: scroll)
        XCTAssertFalse(scroll.alwaysBounceVertical)
        XCTAssertFalse(scroll.showsHorizontalScrollIndicator)
        scroll.contentOffset.x = 120
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.5, "a layout transient never leaves the page scrolled sideways")
        UKScrollFit.allowsPullToRefresh(scroll)
        XCTAssertTrue(scroll.alwaysBounceVertical, "pull to refresh always bounces")
    }

    func testMainScrollViewIsTheLargestVisibleOne() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let small = UIScrollView(frame: CGRect(x: 0, y: 0, width: 250, height: 250))
        small.contentSize = CGSize(width: 250, height: 900)
        let big = UIScrollView(frame: CGRect(x: 0, y: 260, width: 393, height: 500))
        big.contentSize = CGSize(width: 393, height: 2000)
        let hidden = UIScrollView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        hidden.contentSize = CGSize(width: 393, height: 4000)
        hidden.isHidden = true
        [small, big, hidden].forEach(root.addSubview)
        XCTAssertNil(UKScrollToTop.mainScrollView(in: root), "off screen there is nothing to scroll")
        let controller = UIViewController()
        controller.view = root
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        XCTAssertTrue(UKScrollToTop.mainScrollView(in: root) === big)
    }

    func testSystemAppearanceReadsTheScreenAndShellSheetPresents() {
        let page = HostedScrollPage(context: context(), title: "Host")
        let (_, window) = host(page)
        defer { window.isHidden = true }
        let style = UKSystemAppearance.style(for: page.view)
        XCTAssertTrue([.light, .dark].contains(style))
        XCTAssertTrue([.light, .dark].contains(UKSystemAppearance.style()))
        let modal = UKShellSheet.present(UIViewController(), from: page, width: .form, height: .full)
        HostedPage.wait(0.8)
        XCTAssertNotNil(page.presentedViewController, "the page opens as an app modal")
        XCTAssertEqual(modal.overrideUserInterfaceStyle, style, "the sheet follows the system appearance")
        page.dismiss(animated: false)
    }

    func testPageHostWrapsAPlainControllerAndKeepsItsTitle() {
        let plain = UIViewController()
        plain.title = "Plain"
        plain.view.backgroundColor = nil
        let wrapped = UKPageHost.wrapped(plain, context: context())
        XCTAssertTrue(wrapped is UKPageHost)
        XCTAssertTrue(UKPageHost.wrapped(wrapped, context: context()) === wrapped, "a page is not wrapped twice")
        XCTAssertTrue(UKPageHost.sheetWrapped(wrapped) === wrapped)
        let (_, window) = host(wrapped)
        defer { window.isHidden = true }
        XCTAssertEqual(wrapped.title, "Plain")
        XCTAssertTrue(plain.parent === wrapped)
        XCTAssertTrue((wrapped as? UKPageHost)?.sheetHeaderIsStandard == true)
    }

    func testSheetHostMirrorsTheHostedScreensBarItems() {
        let plain = UIViewController()
        plain.title = "Edit"
        let host = UKPageHost.sheetWrapped(plain) as! UKPageHost
        let navigation = UINavigationController(rootViewController: host)
        let window = HostedPage.show(navigation)
        defer { window.isHidden = true }
        let save = UIBarButtonItem(title: "Save", primaryAction: UIAction { _ in })
        plain.navigationItem.rightBarButtonItems = [save]
        plain.navigationItem.leftBarButtonItems = [UIBarButtonItem(title: "Cancel", primaryAction: UIAction { _ in })]
        plain.navigationItem.hidesBackButton = true
        plain.navigationItem.titleView = UILabel()
        plain.title = "Edit more"
        HostedPage.wait(0.2)
        XCTAssertEqual(host.navigationItem.rightBarButtonItems?.first?.title, "Save")
        XCTAssertEqual(host.navigationItem.leftBarButtonItems?.first?.title, "Cancel")
        XCTAssertTrue(host.navigationItem.hidesBackButton)
        XCTAssertEqual(host.navigationItem.title, "Edit more")
        XCTAssertNotNil(host.navigationItem.titleView)
        XCTAssertNil(host.sheetFitScrollView)
    }

    func testPageHostLinksTheHostedScreensBiggestScrollView() {
        let plain = UIViewController()
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 393, height: 3000)
        plain.view = scroll
        let page = UKPageHost(child: plain, context: context())
        let (_, window) = host(page)
        defer { window.isHidden = true }
        HostedPage.wait(0.3)
        XCTAssertTrue(page.contentScrollView === scroll, "the large title and scroll-to-top follow the screen's scroll view")
    }

    func testPageScrollViewLaysItsContentOutAtTheStandardPadding() {
        final class Content: UIView, UKGridMeasuring {
            var gridMinimumWidth: CGFloat { 0 }
            func gridHeight(forWidth width: CGFloat) -> CGFloat { 200 }
        }
        let content = Content()
        let scroll = UKPageScrollView(content: content, maxWidth: 300)
        scroll.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        scroll.layoutIfNeeded()
        XCTAssertEqual(content.frame.width, 300)
        XCTAssertEqual(content.frame.minX, (393 - 300) / 2 , accuracy: 1, "a wide window centres the column")
        XCTAssertEqual(scroll.contentSize.height, UKPageMetrics.top + 200 + UKPageMetrics.bottom)
        scroll.contentChanged(animated: false)
        let column = UKColumnScrollView(content: content)
        column.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        column.layoutIfNeeded()
        XCTAssertEqual(content.frame.minY, 0)
    }

    func testEmptyPanePlaceholderIsOneAccessibilityElement() {
        let pane = UKPanePlaceholderViewController(symbol: "gearshape", text: "Select a setting to see more options", identifier: "settings.empty")
        let window = HostedPage.show(pane)
        defer { window.isHidden = true }
        let element = HostedPage.descendants(of: pane.view).first { $0.accessibilityIdentifier == "settings.empty" }
        XCTAssertEqual(element?.accessibilityLabel, "Select a setting to see more options")
        XCTAssertEqual(element?.isAccessibilityElement, true)
    }

    func testHeaderEdgeFadeMasksTheContentAndHardensForReducedTransparency() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 800))
        let fade = UKHeaderEdgeFade(masking: view)
        let scroll = UIScrollView(frame: view.bounds)
        scroll.contentSize = CGSize(width: 393, height: 3000)
        fade.follow(scroll)
        fade.cap = 96
        fade.layoutChanged()
        fade.reduceTransparency = true
        fade.increaseContrast = true
        scroll.contentOffset.y = 300
        fade.layoutChanged()
        fade.follow(nil)
        UKHeaderEdgeFade.applySoftEdge(to: scroll)
        if UKHeaderEdgeFade.usesSoftEdge {
            XCTAssertNil(view.layer.mask, "the system's soft edge draws the header edge, no mask")
        } else {
            XCTAssertTrue(view.layer.mask is CAGradientLayer, "content fades under the header with a gradient mask")
        }
    }
}
