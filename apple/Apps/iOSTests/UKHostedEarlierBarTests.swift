@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The app ships to iOS 17 and later, so the bar before iOS 26 (no glass: the mask fade, the material ring behind Profile, the drawn
/// badge, the custom Quick Links circle) is real code. `UKGlassEra.override` runs it on the newer simulator.
@MainActor
final class UKHostedEarlierBarTests: DemoHouseTestCase {
    override func setUp() { UKGlassEra.override = false }
    override func tearDown() { UKGlassEra.override = nil; UKMotion.reduceMotionOverride = nil }

    private func settle(_ seconds: TimeInterval = 0.3) { HostedPage.wait(seconds) }

    private func photo() -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }.cgImage!
    }

    private func alpha(_ colors: [Any]?, at index: Int) -> CGFloat {
        guard let color = colors?[index] else { return -1 }
        return UIColor(cgColor: color as! CGColor).cgColor.alpha
    }

    func testTheContentFadesUnderTheHeaderWithAMaskThatFollowsTheScroll() throws {
        XCTAssertFalse(UKHeaderEdgeFade.usesSoftEdge)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 800))
        let fade = UKHeaderEdgeFade(masking: view)
        let gradient = try XCTUnwrap(view.layer.mask as? CAGradientLayer, "the earlier bar draws the header edge with a mask")
        let scroll = UIScrollView(frame: view.bounds)
        scroll.contentSize = CGSize(width: 393, height: 3000)
        fade.follow(scroll)
        fade.cap = 96
        fade.layoutChanged()
        XCTAssertEqual(alpha(gradient.colors, at: 2), 1, accuracy: 0.01, "at rest the page looks untouched")
        let softSpan = (gradient.locations?[3].doubleValue ?? 0) - (gradient.locations?[2].doubleValue ?? 0)
        XCTAssertGreaterThan(softSpan, 0, "a ramp, not a cut")
        scroll.contentOffset.y = 300
        XCTAssertLessThan(alpha(gradient.colors, at: 2), 1, "scrolled a ramp's length, the edge turns transparent")
        fade.reduceTransparency = true
        fade.increaseContrast = true
        let hardSpan = (gradient.locations?[3].doubleValue ?? 0) - (gradient.locations?[2].doubleValue ?? 0)
        XCTAssertLessThan(hardSpan, softSpan, "Reduce Transparency and Increase Contrast turn the ramp into a hard cut")
        fade.follow(nil)
        XCTAssertEqual(fade.cap, 96)
        view.bounds.size.height = 0
        fade.layoutChanged()
    }

    func testAPageGivesItsScrollViewNoSoftEdgeWhereTheMaskDrawsTheEdge() {
        let context = UKGalleryChrome.context()
        let page = HostedScrollPage(context: context, title: "Climate")
        let navigation = UINavigationController(rootViewController: page)
        let window = HostedPage.show(navigation)
        defer { window.isHidden = true }
        if #available(iOS 26.0, *) { XCTAssertTrue(page.scroll.topEdgeEffect.isHidden, "no system soft edge where the mask draws it") }
        XCTAssertTrue(page.contentView.layer.mask is CAGradientLayer)
    }

    func testTheBarDrawsItsOwnCirclesAndTheProfileBadge() throws {
        var calls: [String] = []
        let items = UKShellHeaderItems(openQuickLinks: { calls.append("quick") }, openAccount: { calls.append("account") })
        let result = items.items(for: .init(profileName: "Alex Demo", attentionCount: 3, reconnectingPresent: true, reconnectingLit: true))
        XCTAssertEqual(result.count, 3, "profile, quick links, arc: the bar draws no glass groups")
        let circle = try XCTUnwrap(items.quickLinks.customView as? UKMaterialCircleButton, "Quick Links is a drawn material circle")
        circle.sendActions(for: .touchUpInside)
        XCTAssertEqual(calls, ["quick"])
        XCTAssertEqual((items.quickLinks.menuRepresentation as? UIAction)?.title, QuickLinks.title)
        let profile = try XCTUnwrap(result.first?.customView as? UKProfileButtonView)
        let window = HostedPage.show({ let c = UIViewController(); c.view.addSubview(profile); return c }())
        defer { window.isHidden = true }
        let badge = HostedPage.descendants(of: profile).compactMap { $0 as? UILabel }.first { $0.text == "3" }
        XCTAssertEqual(badge?.isHidden, false, "the drawn count shows where the bar item has no badge of its own")
        let reconnecting = result.first { $0.title == ReconnectingArc.label }
        XCTAssertNotNil(reconnecting)
        (reconnecting?.customView ?? profile).layoutIfNeeded()
    }

    func testProfileSitsInAMaterialRingAndShowsAPhotoOnceItArrives() throws {
        let button = UKProfileButtonView()
        button.configure(name: "Alex Demo", attentionCount: 0, isOffline: false, grouped: false, animated: false)
        let window = HostedPage.show({ let c = UIViewController(); c.view.addSubview(button); return c }())
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.descendants(of: button).contains { $0 is UIVisualEffectView }, "a 44 pt material circle behind the 32 pt disc")
        let box = AvatarBox(id: "person.demo_alex", image: nil)
        button.bindAvatar { box }
        settle(0.1)
        XCTAssertTrue(HostedPage.labels(in: button).contains("AD"))
        box.apply(photo())
        settle(0.6)
        let width = CGFloat(photo().width)
        let image = HostedPage.descendants(of: button).compactMap { $0 as? UIImageView }.first { $0.image?.size.width == width && $0.image?.size.height == CGFloat(photo().height) }
        XCTAssertNotNil(image, "the photo is drawn on the disc")
        XCTAssertEqual(image?.alpha, 1)
        box.apply(nil)
        settle(0.6)
        XCTAssertEqual(image?.alpha ?? 1, 0, accuracy: 0.01, "without a photo the initials come back")
    }

    func testReconnectingArcSitsBesideQuickLinksWithoutTheGlassShift() {
        let arc = UKReconnectingArcView()
        arc.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        arc.configure(lit: true, isFirstConnect: false, besideQuickLinks: true, animated: false)
        arc.layoutIfNeeded()
        let spinner = HostedPage.descendants(of: arc).first { $0.accessibilityIdentifier == "reconnecting.arc" }
        XCTAssertEqual(spinner?.frame.midX ?? 0, 22, accuracy: 0.5, "no glass: the spinner stays centred")
    }

    func testTheRailShowsThePhotoDrawnIntoACircle() {
        UKGlassEra.override = nil
        guard #available(iOS 26.0, *) else { return }
        let items = UKShellHeaderItems(openQuickLinks: {}, openAccount: {})
        let box = AvatarBox(id: "person.demo_alex", image: photo())
        items.bindAvatar { box }
        let result = items.items(for: .init(profileName: "Alex Demo", inVerticalBar: true))
        XCTAssertEqual(result.first?.image?.size, CGSize(width: 30, height: 30), "the photo is cropped to the rail's 30 pt circle")
        box.apply(nil)
        settle(0.2)
        let monogram = items.items(for: .init(profileName: "Alex Demo", inVerticalBar: true))
        XCTAssertNotNil(monogram.first?.image, "without a photo the monogram is drawn")
    }
}
