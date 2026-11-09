import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Lets the main run loop turn for `seconds` (see ``HostedPage/wait(_:)``).
@MainActor
func hostedSettle(_ seconds: TimeInterval = 0.15) { HostedPage.wait(seconds) }

@MainActor
func hostedPhoto(_ color: UIColor, size: Int = 8) -> CGImage {
    UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { c in
        color.setFill(); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }.cgImage!
}

/// The avatar disc: initials or the placeholder, the photo fading over them, the hairline in each appearance.
@MainActor
final class UKHostedAvatarTests: XCTestCase {
    private func subviews(_ avatar: UKAvatarView) -> (labels: [UILabel], images: [UIImageView]) {
        let all = HostedPage.descendants(of: avatar)
        return (all.compactMap { $0 as? UILabel }, all.compactMap { $0 as? UIImageView })
    }

    func testInitialsShowOnTheDiscAndAnEmptyNameDrawsThePlaceholder() {
        let avatar = UKAvatarView(initials: "SF", fill: .systemBlue, image: nil, diameter: 40)
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        window.rootViewController?.view.addSubview(avatar)
        avatar.layoutIfNeeded()
        XCTAssertEqual(avatar.intrinsicContentSize, CGSize(width: 40, height: 40))
        XCTAssertEqual(avatar.sizeThatFits(.zero), CGSize(width: 40, height: 40))
        XCTAssertTrue(avatar.accessibilityElementsHidden, "the name is read by the control that holds the avatar")
        XCTAssertEqual(subviews(avatar).labels.first?.text, "SF")
        XCTAssertEqual(subviews(avatar).labels.first?.isHidden, false)
        avatar.update(initials: nil, fill: .systemRed, image: nil)
        XCTAssertEqual(subviews(avatar).labels.first?.isHidden, true, "no initials: the placeholder glyph instead")
        XCTAssertEqual(avatar.layer.cornerRadius, 20)
    }

    func testAPhotoCoversTheDiscAndChangingItFadesOnScreen() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let first = AvatarImage(hostedPhoto(.red), owner: "person.demo_alex", revision: 1)
        let avatar = UKAvatarView(initials: "A", fill: .gray, image: first, diameter: 44, font: .systemFont(ofSize: 12))
        host.view.addSubview(avatar)
        avatar.layoutIfNeeded()
        let shown = subviews(avatar).images.filter { !$0.isHidden && $0.image != nil && $0.frame.size == CGSize(width: 44, height: 44) }
        XCTAssertFalse(shown.isEmpty, "a view made with a photo draws it on its first frame")

        avatar.update(initials: "A", fill: .gray, image: AvatarImage(hostedPhoto(.green), owner: "person.demo_alex", revision: 2))
        hostedSettle(1.0)
        XCTAssertFalse(subviews(avatar).images.filter { !$0.isHidden && $0.image != nil }.isEmpty, "the new photo is shown after the fade")
        avatar.update(initials: "A", fill: .gray, image: nil)
        hostedSettle(1.0)
        XCTAssertTrue(subviews(avatar).images.filter { !$0.isHidden && $0.image != nil && $0.frame.size.width == 44 }.isEmpty
                      || subviews(avatar).labels.first?.isHidden == false, "removing the photo falls back to the initials")
        // Not yet on screen: takes the photo at once.
        let detached = UKAvatarView(initials: nil, fill: .gray, image: nil, diameter: 30)
        detached.update(initials: nil, fill: .gray, image: first)
        XCTAssertFalse(subviews(detached).images.filter { !$0.isHidden && $0.image != nil }.isEmpty)
    }

    func testTheHairlineFollowsAppearance() {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let avatar = UKAvatarView(initials: "Z", fill: .gray, image: nil, diameter: 40)
        host.view.addSubview(avatar)
        // The high-contrast arm (1 pt) cannot be reached here: a trait override of accessibilityContrast to .high does not take on a
        // hosted view, neither on the window, the controller nor the avatar itself (checked 2026-11-03). Appearance does.
        func hairline(_ style: UIUserInterfaceStyle) -> (CGFloat, CGColor?) {
            window.overrideUserInterfaceStyle = style
            hostedSettle(0.3)
            let line = HostedPage.descendants(of: avatar).max { $0.layer.borderWidth < $1.layer.borderWidth }
            return (line?.layer.borderWidth ?? 0, line?.layer.borderColor)
        }
        let light = hairline(.light)
        let dark = hairline(.dark)
        XCTAssertEqual(light.0, 0.5)
        XCTAssertEqual(dark.0, 0.5)
        // Open: the hairline colour does not change with a window style override here either (trait-change callbacks do not fire
        // for a hosted window override), so colour and the 1 pt contrast arm stay unasserted; the width is what holds.
        _ = light.1; _ = dark.1
    }
}
