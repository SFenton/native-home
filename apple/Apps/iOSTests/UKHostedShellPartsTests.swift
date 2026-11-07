import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

@MainActor
final class UKHostedShellPartsTests: XCTestCase {
    private func settle(_ seconds: TimeInterval = 0.3) { HostedPage.wait(seconds) }

    // MARK: Header items

    func testHeaderItemsListProfileThenQuickLinksAndTheArcOnlyWhileReconnectingIsPresent() {
        var calls: [String] = []
        let items = UKShellHeaderItems(openQuickLinks: { calls.append("quick") }, openAccount: { calls.append("account") })
        let plain = items.items(for: .init(profileName: "Alex Demo"))
        XCTAssertTrue(plain.contains { $0.accessibilityIdentifier == "quickLinks.open" }, "Quick Links is always there")
        XCTAssertNotNil(plain.first?.customView, "Profile is the bar's first item")
        XCTAssertFalse(plain.contains { $0.title == ReconnectingArc.label }, "no arc unless reconnecting")
        let reconnecting = items.items(for: .init(profileName: "Alex Demo", reconnectingPresent: true, reconnectingLit: true))
        XCTAssertTrue(reconnecting.contains { $0.title == ReconnectingArc.label }, "the arc joins while the connection retries")
        XCTAssertEqual((reconnecting.first { $0.title == ReconnectingArc.label }?.menuRepresentation as? UIAction)?.attributes, .disabled)
        items.quickLinks.primaryAction?.performWithSender(nil, target: nil)
        if items.quickLinks.primaryAction == nil { (items.quickLinks.customView as? UKMaterialCircleButton)?.sendActions(for: .touchUpInside) }
        XCTAssertEqual(calls, ["quick"])
        let profile = reconnecting.first?.menuRepresentation as? UIAction
        XCTAssertEqual(profile?.title, UKShellHeaderItems.profileMenuTitle, "the bar's menu names the sheet it opens")
        profile?.performWithSender(nil, target: nil)
        XCTAssertEqual(calls, ["quick", "account"])
    }

    func testRailProfileIsAPlainItemWithTheCountAsItsValueInTheVerticalBar() {
        let items = UKShellHeaderItems(openQuickLinks: {}, openAccount: {})
        let state = UKShellHeaderItems.State(profileName: "Alex Demo", attentionCount: 12, isOffline: true, reconnectingPresent: true,
                                              reconnectingLit: true, isFirstConnect: true, inVerticalBar: true)
        let result = items.items(for: state)
        if #available(iOS 26.0, *) {
            let profile = result.first
            XCTAssertEqual(profile?.accessibilityIdentifier, "nav.profile")
            XCTAssertEqual(profile?.accessibilityLabel, "Profile")
            XCTAssertEqual(profile?.accessibilityValue, ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: 12, isOffline: true))
            XCTAssertNotNil(profile?.badge, "the count is the bar item's own badge")
            XCTAssertEqual(result[1].accessibilityIdentifier, "quickLinks.open", "no spacer between the two in one glass group")
            XCTAssertNotNil(profile?.image)
            // A photo replaces the monogram.
            items.bindAvatar { nil }
            _ = items.items(for: .init(profileName: nil, inVerticalBar: true))
        }
    }

    func testProfileBadgeFontFollowsTheTextSizeAndCapsAtXLarge() {
        let trait = { (category: UIContentSizeCategory) in UITraitCollection(preferredContentSizeCategory: category) }
        let large = UKShellFont.preferred(.caption1, weight: .bold, traits: trait(.large))
        let extraLarge = UKShellFont.preferred(.caption1, weight: .bold, traits: trait(.extraLarge))
        XCTAssertEqual(UKShellHeaderItems.badgeFont(category: .large).pointSize, large.pointSize)
        XCTAssertGreaterThan(extraLarge.pointSize, large.pointSize)
        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge] {
            XCTAssertEqual(UKShellHeaderItems.badgeFont(category: category).pointSize, extraLarge.pointSize, "\(category.rawValue) holds at xLarge")
        }
        if #available(iOS 26.0, *) {
            let items = UKShellHeaderItems(openQuickLinks: {}, openAccount: {})
            let state = UKShellHeaderItems.State(profileName: "Alex Demo", attentionCount: 12, inVerticalBar: true,
                                                 contentSize: .accessibilityExtraExtraExtraLarge)
            let rail = items.items(for: state).first
            XCTAssertEqual(rail?.badge?.font?.pointSize, extraLarge.pointSize)
            XCTAssertEqual(rail?.accessibilityValue, ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: 12),
                           "the spoken count does not depend on the badge's size")
            XCTAssertEqual(items.lastState?.contentSize, .accessibilityExtraExtraExtraLarge)
        }
    }

    /// The header's count is the Profile view's own drawn badge on the disc's top-trailing corner (4 pt past, 2 pt above), red with white
    /// text, hidden from VoiceOver, and the bar item carries no system badge of its own.
    func testHeaderBadgeSitsOnTheDiscCornerAndIsRedAndHiddenFromAccessibility() throws {
        guard #available(iOS 26.0, *), UKGlassEra.hasGlass else { return }
        let items = UKShellHeaderItems(openQuickLinks: {}, openAccount: {})
        for (count, expectedSize) in [(12, CGSize(width: 24, height: 18)), (3, CGSize(width: 18, height: 18))] {
            let result = items.items(for: .init(profileName: "Alex Demo", attentionCount: count))
            let profile = try XCTUnwrap(result.first)
            XCTAssertNil(profile.badge, "the header item has no system badge")
            let view = try XCTUnwrap(profile.customView as? UKProfileButtonView)
            view.layoutIfNeeded()
            let disc = view.discFrame
            let badge = view.shownBadgeFrame
            XCTAssertEqual(badge.maxX, disc.maxX + 4, accuracy: 1)
            XCTAssertEqual(badge.minY, disc.minY - 2, accuracy: 1)
            XCTAssertEqual(badge.width, expectedSize.width, accuracy: 1, "count \(count)")
            XCTAssertEqual(badge.height, expectedSize.height, accuracy: 1)
            XCTAssertFalse(view.badgeIsAccessible)
            XCTAssertEqual(profile.customView?.accessibilityElements?.count, 1, "only the button is an element")
            let button = try XCTUnwrap(HostedPage.descendants(of: view).first { $0.accessibilityIdentifier == "nav.profile" })
            XCTAssertEqual(button.accessibilityValue, ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: count))
            XCTAssertTrue((button as? UIControl)?.largeContentTitle?.contains(count > 9 ? "9+" : "3") == true, "the Large Content Viewer names the count")
            // The drawn badge renders red with a white count, never tinted white.
            let image = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UIImageView }.first { $0.frame == badge }?.image)
            XCTAssertEqual(image.renderingMode, .alwaysOriginal)
            let pixel = Self.pixel(of: image, at: CGPoint(x: 3, y: image.size.height / 2))
            XCTAssertGreaterThan(pixel.red, 0.7)
            XCTAssertLessThan(pixel.green, 0.4)
        }
    }

    private static func pixel(of image: UIImage, at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let cgImage = image.cgImage,
              let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
        let scale = image.scale
        context.draw(cgImage, in: CGRect(x: -point.x * scale, y: -(image.size.height - point.y) * scale + 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255)
    }

    func testHeaderItemsInTheHorizontalBarSeparateTheCirclesAndBadgeTheProfile() {
        let items = UKShellHeaderItems(openQuickLinks: {}, openAccount: {})
        _ = items.items(for: .init(profileName: nil))
        let result = items.items(for: .init(profileName: "Alex Demo", attentionCount: 3, reconnectingPresent: true))
        if #available(iOS 26.0, *) {
            XCTAssertEqual(result.count, 5, "profile, space, quick links, space, arc")
            XCTAssertNil(result.first?.badge, "the header count is the view's own drawn badge")
        } else {
            XCTAssertEqual(result.count, 3)
        }
    }

    func testProfileButtonShowsInitialsPhotoSlotBadgeAndOfflineMark() {
        let button = UKProfileButtonView()
        var taps = 0
        button.onTap = { taps += 1 }
        button.configure(name: "Alex Demo", attentionCount: 4, isOffline: true, grouped: false, animated: false)
        let window = HostedPage.show({ let c = UIViewController(); c.view.addSubview(button); return c }())
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: button).contains("AD"), "the initials show on the disc")
        let control = HostedPage.descendants(of: button).first { $0.accessibilityIdentifier == "nav.profile" } as? UIControl
        XCTAssertEqual(control?.accessibilityLabel, "Profile")
        XCTAssertEqual(control?.accessibilityValue, ProfileButton.accessibilityValue(name: "Alex Demo", attentionCount: 4, isOffline: true))
        control?.sendActions(for: .touchUpInside)
        XCTAssertEqual(taps, 1)
        button.configure(name: "Alex Demo", attentionCount: 120, isOffline: false, grouped: false, animated: true)
        settle(0.4)
        XCTAssertEqual(button.attentionCount, 120)
        XCTAssertFalse(button.isOffline)
        button.configure(name: nil, attentionCount: 0, isOffline: false, grouped: true, animated: false)
        XCTAssertTrue(button.grouped)
        button.side = 36
        settle(0.1)
        let width = button.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil }
        XCTAssertEqual(width?.constant, 36, "a 36 pt side where the bar draws its own glass")
        button.bindAvatar { nil }
    }

    func testReconnectingArcFadesWithItsLitStateAndNamesTheFirstConnect() {
        let arc = UKReconnectingArcView()
        let window = HostedPage.show({ let c = UIViewController(); c.view.addSubview(arc); return c }())
        defer { window.isHidden = true }
        arc.configure(lit: true, isFirstConnect: true, besideQuickLinks: true, animated: false)
        let spinner = HostedPage.descendants(of: arc).first { $0.accessibilityIdentifier == "reconnecting.arc" }
        XCTAssertEqual(spinner?.accessibilityLabel, ReconnectingArc.connectingLabel)
        XCTAssertEqual(spinner?.alpha, 1)
        arc.configure(lit: false, isFirstConnect: false, besideQuickLinks: false, animated: true)
        settle(0.5)
        XCTAssertEqual(spinner?.accessibilityLabel, ReconnectingArc.label)
        XCTAssertEqual(spinner?.alpha ?? 1, 0, accuracy: 0.01)
        arc.layoutIfNeeded()
        let circle = UKMaterialCircleButton(image: UIImage(systemName: "square.grid.2x2"))
        var tapped = false
        circle.onTap = { tapped = true }
        circle.sendActions(for: .touchUpInside)
        XCTAssertTrue(tapped)
        XCTAssertTrue(circle.accessibilityTraits.contains(.button))
    }

    // MARK: Offline chip and reconnecting host

    func testOfflineChipReadsAsOneElementAndWrapsWithinTheGivenWidth() {
        let chip = UKOfflineChipView()
        XCTAssertEqual(chip.accessibilityLabel, "Offline. Showing last known values.")
        XCTAssertTrue(chip.isAccessibilityElement)
        chip.setMaxWidth(120)
        let narrow = chip.systemLayoutSizeFitting(CGSize(width: 120, height: UIView.layoutFittingExpandedSize.height))
        chip.setMaxWidth(600)
        let wide = chip.systemLayoutSizeFitting(CGSize(width: 600, height: UIView.layoutFittingExpandedSize.height))
        XCTAssertGreaterThan(narrow.height, wide.height, "a narrow window wraps the text onto more lines")
        chip.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
        chip.layoutIfNeeded()
        XCTAssertEqual(chip.layer.cornerRadius, 20, accuracy: 0.5, "the capsule radius follows the height")
    }

    func testOfflineOverlayAnnouncesAndAnimatesTheChipIn() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let controller = UIViewController()
        controller.view = host
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let overlay = UKOfflineOverlay(host: host)
        overlay.hostLaidOut()
        overlay.update(isOffline: false, headerEnd: 96, reduceMotion: false)
        XCTAssertNil(host.subviews.first { $0.accessibilityIdentifier == "offline.chip" }, "the chip is not in the layout while hidden")
        overlay.update(isOffline: true, headerEnd: 96, reduceMotion: true)
        settle(0.4)
        let chip = host.subviews.first { $0.accessibilityIdentifier == "offline.chip" }
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip?.alpha ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(chip?.frame.minY ?? 0, 96 + HassTokens.Spacing.xs, accuracy: 1, "it hangs under the header")
        overlay.hostLaidOut()
        overlay.update(isOffline: false, headerEnd: 96, reduceMotion: false)
        settle(0.6)
        XCTAssertNil(host.subviews.first { $0.accessibilityIdentifier == "offline.chip" })
        XCTAssertEqual(UKOfflineOverlay.announcement(isOffline: true), OfflineOverlay.announcement(isOffline: true))
    }

    func testReconnectingHostLightsTheArcOnlyAfterTheConnectionKeepsRetrying() {
        let store = EntityStore()
        // The store has state from an earlier session; a snapshot cache of the test's own keeps that independent of whatever the
        // app's default cache holds on this simulator.
        _ = store.replaceAll([], freshness: .snapshot(savedAt: Date()))
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "uk-hosted-reconnect-\(UUID().uuidString).json"))
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: store, snapshotCache: cache)
        let host = UKReconnectingHost(connection: connection)
        // This store already counts as having state (`hasReceivedFirstState`), so the connection is not on its first connect: a
        // disconnected status gets the retry delay, and until it passes the arc is neither placed nor lit.
        XCTAssertTrue(connection.store.hasReceivedFirstState)
        for _ in 0..<10 { settle(0.02) }
        XCTAssertFalse(host.indicator.isFirstConnect, "not the first connect")
        XCTAssertFalse(host.indicator.isLit, "a blip never shows the arc")
        XCTAssertFalse(host.indicator.isPresent)
    }

    // MARK: Notification banner

    func testPermissionBannerOffersTurnOnAndNotNowAndHidesWhenAnswered() async throws {
        let counter = AskCounter()
        var platform = PushPlatform.inert
        platform.authorization = { .notDetermined }
        platform.requestAuthorization = { counter.count += 1; return false }
        let defaults = UserDefaults(suiteName: "uk-hosted-banner-\(UUID().uuidString)")!
        let push = PushCoordinator(platform: platform, store: InMemoryMobileAppRegistrationStore(), isEnabled: false, defaults: defaults)
        push.setupHasShownNotifications = true
        await push.refreshSettings()
        let banner = UKNotificationPermissionBannerView(push: push)
        let host = UIViewController()
        banner.frame = CGRect(x: 16, y: 100, width: 361, height: 200)
        host.view.addSubview(banner)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        // Not connected yet: the coordinator reads the system's answer once the session connected or the person answered.
        await push.enableNotifications()
        XCTAssertEqual(push.authorization, .notDetermined, "the system's answer was read after the ask")
        XCTAssertTrue(push.showsPermissionBanner)
        for _ in 0..<50 where banner.isHidden { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(counter.count, 1, "Turn On asks the system once")
        XCTAssertEqual(HostedPage.descendants(of: banner).compactMap { $0 as? UIButton }.map { $0.accessibilityIdentifier },
                       ["push.banner.turnOn", "push.banner.notNow"])
        XCTAssertEqual(HostedPage.descendants(of: banner).first { $0.accessibilityIdentifier == "push.banner.text" }?.accessibilityLabel,
                       "\(NotificationPermissionCopy.title). \(NotificationPermissionCopy.message)")
        XCTAssertFalse(banner.isHidden, "never answered: the banner shows")
        let notNow = HostedPage.descendants(of: banner).first { $0.accessibilityIdentifier == "push.banner.notNow" } as? UIButton
        notNow?.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(push.bannerDismissed)
        XCTAssertTrue(banner.isHidden, "Not Now hides it")
        let turnOn = HostedPage.descendants(of: banner).first { $0.accessibilityIdentifier == "push.banner.turnOn" } as? UIButton
        turnOn?.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(counter.count, 2)
        banner.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        banner.layoutIfNeeded()
        UKNotificationPermissionBannerView(push: nil).layoutIfNeeded()
    }

    // MARK: Layout signals

    func testDeviceSignalsReportNoHingeOrRailOnAPhone() {
        // The folded Duo simulator has the system's vertical bar (and the Duo a hinge record); stand in for a phone there, so the
        // phone's answers are checked on every family and read from the device itself on the iPhone and the iPad.
        if let scene = HostedPage.scene, UKDeviceSignals.hasVerticalBar(scene.traitCollection) || UKSheetPlacement.hasHinge(in: nil) {
            UKDeviceSignals.verticalBarOverride = { _ in false }
            UKDeviceSignals.regionsOverride = { _, _ in [] }
            HingePresence.shared.resetForTests()
        }
        let shell = UKShellEnvironment()
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let signals = UKDeviceSignals(view: controller.view, environment: shell)
        signals.refresh()
        XCTAssertNil(shell.windowHinge)
        XCTAssertFalse(shell.inVerticalBar)
        XCTAssertNil(UKDeviceSignals.hinge(in: controller.view))
        XCTAssertEqual(UKDeviceSignals.railWidth(in: window), 0)
        XCTAssertEqual(UKDeviceSignals.freeWidth(in: window), window.bounds.width)
        XCTAssertFalse(UKDeviceSignals.hasVerticalBar(controller.traitCollection))
        XCTAssertEqual(UKDeviceSignals.fold(in: UIView()), WindowFold.none)
    }

    func testHingedPanesKeepTheTrailingPaneOffTheHinge() {
        let leading = UIView(), trailing = UIView()
        let shell = UKShellEnvironment()
        let panes = UKHingedPanes(leading: leading, trailing: trailing, showsTrailing: false, gutter: 8, shell: shell)
        let controller = UIViewController()
        panes.frame = CGRect(x: 0, y: 0, width: 1000, height: 600)
        controller.view.addSubview(panes)
        let window = HostedPage.show(controller, size: CGSize(width: 1000, height: 600))
        defer { window.isHidden = true }
        panes.layoutIfNeeded()
        XCTAssertEqual(leading.frame, panes.bounds, "the leading pane takes everything while the trailing one is hidden")
        XCTAssertTrue(trailing.isHidden)
        panes.showsTrailing = true
        shell.windowHinge = CGRect(x: 600, y: 0, width: 24, height: 600)
        settle(0.2)
        panes.layoutIfNeeded()
        XCTAssertFalse(trailing.isHidden)
        XCTAssertLessThanOrEqual(leading.frame.maxX, 600 + 0.5, "the leading pane ends at the hinge")
        XCTAssertGreaterThanOrEqual(trailing.frame.minX, 624 - 0.5, "the trailing pane starts after it")
        shell.windowHinge = nil
        settle(0.2)
        panes.layoutIfNeeded()
        XCTAssertEqual(leading.frame.width + 8, trailing.frame.minX, accuracy: 1, "flat, the panes split evenly with the gutter between")
    }

    func testReflowSnapshotsOnlyUnderReduceMotionAndLaysOutOnCommit() {
        final class Probe: UIView {
            var laidOut = 0
            override func layoutSubviews() { super.layoutSubviews(); laidOut += 1 }
        }
        let host = Probe(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let controller = UIViewController()
        controller.view.addSubview(host)
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let before = UKReflow.begin(host)
        XCTAssertEqual(before != nil, UKMotion.reduceMotion, "only Reduce Motion cross-fades a snapshot")
        let count = host.laidOut
        UKReflow.commit(host, before: before)
        host.setNeedsLayout()
        settle(0.6)
        XCTAssertGreaterThan(host.laidOut, count, "the reflow lays the tree out inside the animation")
        // A snapshot comes off after the fade.
        let snapshot = UIView(frame: host.bounds)
        host.addSubview(snapshot)
        UKReflow.commit(host, before: snapshot)
        settle(0.8)
        XCTAssertNil(snapshot.superview)
    }

    func testArrivalMotionHoldsAnElementBackUntilTheArrivalIsRevealed() {
        let shell = UKShellEnvironment()
        let arrival = HomeArrival()
        shell.arrival = arrival
        let bag = UKObservationBag()
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let chip = UIView(frame: CGRect(x: 0, y: 50, width: 100, height: 40))
        let controller = UIViewController()
        controller.view.addSubview(card)
        controller.view.addSubview(chip)
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        arrival.begin()
        UKArrivalMotion.apply(to: card, shell: shell, kind: .rise, index: 2, bag: bag)
        UKArrivalMotion.apply(to: chip, shell: shell, kind: .slideIn, bag: bag)
        XCTAssertEqual(card.alpha, 0, "held back while the arrival is under way")
        XCTAssertEqual(card.transform.ty, MotionTokens.Arrival.riseDistance)
        XCTAssertEqual(chip.transform.tx, MotionTokens.Arrival.slideDistance)
        arrival.reveal()
        settle(1.2)
        XCTAssertEqual(card.alpha, 1)
        XCTAssertEqual(card.transform, .identity)
        XCTAssertEqual(chip.alpha, 1)
        arrival.finish()
        // Reduce Motion cross-fades without the offset.
        let still = UIView()
        controller.view.addSubview(still)
        shell.reduceMotion = true
        arrival.begin()
        UKArrivalMotion.apply(to: still, shell: shell, bag: bag)
        XCTAssertEqual(still.alpha, 0)
        XCTAssertEqual(still.transform, .identity, "no movement under Reduce Motion")
        arrival.reveal()
        settle(0.5)
        XCTAssertEqual(still.alpha, 1)
        // Outside the shell nothing arrives.
        let outside = UIView()
        UKArrivalMotion.apply(to: outside, shell: nil, bag: bag)
        XCTAssertEqual(outside.alpha, 1)
    }

    func testArrivalChromeHoldsTheBarsBackAndLetsThemIn() throws {
        let rig = try HostedShellRig.make()
        defer { rig.tearDown() }
        rig.settle()
        let shell = UKShellEnvironmentProbe.environment(of: rig.shell)
        let arrival = HomeArrival()
        shell?.arrival = arrival
        arrival.begin()
        rig.settle(0.2)
        XCTAssertEqual(rig.shell.tabBar.alpha, 0, "the tab bar waits for the arrival")
        XCTAssertEqual(rig.shell.sectionControllers.first?.navigationBar.alpha, 0)
        arrival.reveal()
        rig.settle(1.2)
        XCTAssertEqual(rig.shell.tabBar.alpha, 1)
        XCTAssertEqual(rig.shell.sectionControllers.first?.navigationBar.alpha, 1)
        arrival.finish()
    }

    // MARK: Probes

    func testProbeElementIsAnInvisibleTwoPointAccessibilityElement() {
        let probe = UKProbeElementView(identifier: "x.probe", label: "ready")
        XCTAssertEqual(probe.accessibilityIdentifier, "x.probe")
        XCTAssertEqual(probe.accessibilityLabel, "ready")
        XCTAssertTrue(probe.isAccessibilityElement)
        XCTAssertFalse(probe.isUserInteractionEnabled)
        probe.show("running")
        XCTAssertEqual(probe.accessibilityLabel, "running")
        XCTAssertEqual(probe.frame.size, CGSize(width: 2, height: 2))
    }

    func testDiagnosticProbesPublishTheirStateOnTheirElement() async throws {
        let perf = UKNavigationPerfProbe()
        XCTAssertEqual(perf.element.accessibilityLabel, "ready")
        let cost = UKLaunchCostProbe()
        XCTAssertEqual(cost.element.accessibilityLabel, LaunchCostProbe.latest)
        let scroll = UKScrollCostProbe()
        XCTAssertEqual(scroll.element.accessibilityLabel, "ready")
        let census = UKResourceCensusProbe()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse((census.element.accessibilityLabel ?? "").isEmpty, "the census shows live counts")
        _ = UKNavigationPerfProbe.isEnabled
        _ = UKScrollCostProbe.isEnabled
        _ = UKLaunchCostProbe.isEnabled
        _ = UKResourceCensusProbe.isEnabled
        _ = UKAppearanceProbe.isEnabled
    }

    func testAppearanceProbeReportsWhatTheScreenSceneAndWindowSay() async throws {
        let probe = UKAppearanceProbe()
        let controller = UIViewController()
        controller.view.addSubview(probe.element)
        guard let window = HostedScene.show(controller) else { throw XCTSkip("the host app has no window scene") }
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        let label = probe.element.accessibilityLabel ?? ""
        XCTAssertTrue(label.hasPrefix("screen=") && label.contains("scene=") && label.contains("window="), "got \(label)")
        XCTAssertFalse(label.contains("?"))
    }
}

final class AskCounter: @unchecked Sendable { var count = 0 }
