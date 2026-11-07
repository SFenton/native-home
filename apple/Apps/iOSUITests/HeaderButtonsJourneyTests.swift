import XCTest

/// The shell's two trailing header buttons after the owner's 2026-10-18 decision (option A, FestivalNativeApps parity;
/// `.agents/design/direction-g.md`, Navigation): Profile with a known name is a 44 pt monogram disc that is the whole button
/// (no glass ring), Profile without a name is the person symbol on the bar's glass, and Quick Links stays a separate glass
/// circle 12 pt away. Runs on the `shell-header` gallery on iPhone, the iPhone Duo (folded and unfolded) and iPad, with no
/// sign-in.
///
/// XCUITest reports a glass bar item's frame several points inside its circle (and the disc's frame includes its badge), so
/// sizes and gaps are measured from the screenshot's pixels on a plain black page (``HeaderPixels``), the way the owner
/// reads them.
@MainActor
final class HeaderButtonsJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    private func launch(profile: String? = nil, badge: Int = 0, offline: Bool = false, reconnecting: Bool = false, photos: Bool = false, scheme: String = "dark", pushed: Bool = false, plain: Bool = true,
                        arguments: [String] = []) -> XCUIApplication {
        var environment = ["FENTON_GALLERY_BADGE": "\(badge)", "FENTON_GALLERY_SCHEME": scheme]
        if offline { environment["FENTON_GALLERY_OFFLINE"] = "1" }
        if reconnecting { environment["FENTON_GALLERY_RECONNECTING"] = "1" }
        if photos { environment["FENTON_GALLERY_PHOTOS"] = "1" }
        if let profile { environment["FENTON_GALLERY_PROFILE"] = profile }
        if pushed { environment["FENTON_GALLERY_PUSHED"] = "1" }
        if plain { environment["FENTON_GALLERY_PLAIN"] = "1" }
        // Every switch is a `FENTON_GALLERY_*` variable, so a test's state is a reset of the class's resident app (`app-reuse.md`);
        // AX5 (`arguments`) launches fresh by signature.
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "shell-header"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        _ = startApp(app)
        XCTAssertTrue(app.buttons["nav.profile"].appears(timeout: 20), "No Profile button")
        XCTAssertTrue(app.buttons["quickLinks.open"].exists, "No Quick Links button")
        settleScreen() // Let the bar settle.
        return app
    }

    /// The unfolded Duo's inner display: XCUITest's own screenshots capture the dark outer panel there, so pixels are read
    /// from host captures instead (`FENTON_CAPTURE_DIR`, `.agents/testing/apple/devices.md`).
    private func isUnfolded(_ app: XCUIApplication) -> Bool {
        FentonHomeApp.family == .iPhoneDuo && app.windows.firstMatch.frame.width >= 600
    }

    /// Saves a screenshot to `FENTON_SHOTS_DIR` (never the repository) and attaches it for the result bundle.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        if isUnfolded(app) {
            keepScreenshot(app, "\(layout)-unfolded-\(name)")
            return
        }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(layout)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
    }

    private func pixels(_ app: XCUIApplication) -> HeaderPixels {
        let measured = HeaderPixels(screenshot: app.screenshot(), windowWidth: app.windows.firstMatch.frame.width)
        print("HEADERPIXELS \(layout) disc=\(String(describing: measured.disc)) glass=\(measured.glass) window=\(app.windows.firstMatch.frame)")
        return measured
    }

    /// The bar draws both buttons side by side. The folded Duo moves bar items into its vertical rail (system behaviour),
    /// where no horizontal gap exists.
    private func isHorizontal(_ app: XCUIApplication) -> Bool {
        !isUnfolded(app) && abs(app.buttons["quickLinks.open"].frame.midY - app.buttons["nav.profile"].frame.midY) < 12
    }

    /// The expected gap between Quick Links and Profile: 12 pt on iOS 27, 16 pt on iOS 26.5, where the bar gives a hidden-glass
    /// custom view a cell 8 pt wider (direction-g.md, "iOS 26.5 differs").
    private var expectedGap: CGFloat { ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) ? 12 : 16 }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label.replacingOccurrences(of: "Last action: ", with: "")
    }

    /// Taps the window at (`x`, `y`) and waits for the gallery to record `action` (up to 2 s; a tap that misses reads what was
    /// there before, and the caller's assertion then fails).
    private func tap(_ x: CGFloat, _ y: CGFloat, in app: XCUIApplication, recording action: String) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        let end = Date().addingTimeInterval(2)
        while lastAction(app) != action, Date() < end { usleep(20_000) }
    }

    // MARK: - Grouping

    /// Owner, 2026-10-20: on the Duo's vertical rail Quick Links and Profile share one glass blob (their frames touch or
    /// overlap, one column); on iPhone and iPad they stay two circles 12 pt apart.
    func testDuoRailSharesOneGlassGroup() throws {
        let app = launch(profile: expectations[.personFirstFullName])
        let links = app.buttons["quickLinks.open"].frame
        let profile = app.buttons["nav.profile"].frame
        if isHorizontal(app) {
            XCTAssertGreaterThanOrEqual(abs(profile.minX - links.maxX), 4, "Two circles expected outside the rail")
            return
        }
        XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "Only the Duo has a vertical rail")
        XCTAssertLessThan(abs(links.midX - profile.midX), 6, "Not in one column")
        // XCUITest frames sit inside the glass, so read the screenshot: on the plain black page the point midway between
        // the two buttons is glass (not black) in one blob, and black between two separate circles.
        let screenshot = app.screenshot()
        guard let image = screenshot.image.cgImage, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return XCTFail("No screenshot pixels")
        }
        let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
        let x = Int(((links.midX + profile.midX) / 2) * scale)
        let y = Int(((links.maxY + profile.minY) / 2) * scale)
        let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        let brightness = Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])
        XCTAssertGreaterThan(brightness, 30, "Black between the buttons: two separate circles, not one glass group")
        shoot(app, "rail-group")
    }

    // MARK: - Named profile

    /// The monogram disc is 44 pt, is the whole button (no glass ring around it), sits 12 pt from Quick Links' 44 pt glass
    /// circle, and both keep their labels, identifiers and the spoken value.
    func testNamedProfileFillsItsContainerNextToQuickLinks() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 3)
        let profile = app.buttons["nav.profile"]
        let links = app.buttons["quickLinks.open"]
        // One snapshot each instead of a request per property.
        guard let profileFacts = try? profile.snapshot(), let linksFacts = try? links.snapshot() else { return XCTFail("No header button snapshot") }
        XCTAssertEqual(profileFacts.label, "Profile")
        XCTAssertEqual(profileFacts.value as? String, "\(expectations[.personFirstFullName]), 3 items need attention")
        XCTAssertEqual(linksFacts.label, "Quick Links")
        XCTAssertTrue(profile.isHittable)
        XCTAssertTrue(links.isHittable)
        XCTAssertFalse(linksFacts.frame.intersects(profileFacts.frame.insetBy(dx: 2, dy: 2)), "The buttons overlap")
        XCTAssertGreaterThanOrEqual(min(profileFacts.frame.width, profileFacts.frame.height), 36)
        shoot(app, "named-plain")
        guard isHorizontal(app) else {
            // Owner, 2026-10-20: in the Duo's rail both buttons share one glass group, so Profile is the person symbol
            // there (the monogram custom view cannot join the rail); the two stack and do not overlap.
            if !isUnfolded(app) {
                XCTAssertNotEqual(linksFacts.frame.minY, profileFacts.frame.minY, "The rail stacks the buttons")
                XCTAssertNil(pixels(app).disc, "A monogram disc drew outside the rail group")
            }
            return
        }
        XCTAssertLessThan(linksFacts.frame.maxX, profileFacts.frame.minX + 1, "Quick Links is not before Profile")
        let measured = pixels(app)
        guard let disc = measured.disc else { return XCTFail("No monogram disc in the screenshot") }
        XCTAssertEqual(disc.width, 44, accuracy: 1, "The monogram is not 44 pt")
        XCTAssertEqual(disc.height, 44, accuracy: 1)
        guard let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else { return XCTFail("No Quick Links glass") }
        XCTAssertEqual(glass.upperBound - glass.lowerBound, 44, accuracy: 1, "Quick Links' glass is not a 44 pt circle")
        let gap = disc.minX - glass.upperBound
        XCTAssertEqual(gap, expectedGap, accuracy: 1.5, "The gap between Quick Links and Profile is \(gap) pt")
        XCTAssertLessThanOrEqual(gap, expectedGap + 2)
        // No glass ring: nothing but the disc (and its badge) is drawn right of it.
        XCTAssertNil(measured.glass.first { $0.lowerBound > disc.maxX - 1 }, "Something is drawn past the disc")
    }

    /// Each button opens its own action from 19 pt off its centre, inside the 44 pt target and outside what XCUITest reports
    /// for a glass bar item.
    func testBothButtonsHaveA44PointTarget() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 3)
        guard isHorizontal(app) else {
            app.buttons["quickLinks.open"].tap()
            XCTAssertEqual(lastAction(app), "quick-links")
            app.buttons["nav.profile"].tap()
            XCTAssertEqual(lastAction(app), "profile")
            return
        }
        let measured = pixels(app)
        guard let disc = measured.disc, let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else {
            return XCTFail("Could not measure the buttons")
        }
        let y = disc.midY
        let linksX = (glass.lowerBound + glass.upperBound) / 2
        for (name, x, yy, expected) in [("Quick Links left", linksX - 19, y, "quick-links"), ("Profile left", disc.midX - 19, y, "profile"),
                                        ("Quick Links right", linksX + 19, y, "quick-links"), ("Profile right", disc.midX + 19, y, "profile"),
                                        ("Profile above", disc.midX, y - 19, "profile"), ("Profile below", disc.midX, y + 19, "profile"),
                                        ("Quick Links above", linksX, y - 19, "quick-links"), ("Quick Links below", linksX, y + 19, "quick-links")] {
            // Tap the other button first so a miss cannot pass on the previous value.
            let other = expected == "profile" ? "quick-links" : "profile"
            tap(expected == "profile" ? linksX : disc.midX, y, in: app, recording: other)
            XCTAssertNotEqual(lastAction(app), expected)
            // On iOS 26.5 Quick Links' system item answers taps only nearer its centre (a known departure; only Profile left/right are asserted there).
            if expectedGap != 12, !(name.hasPrefix("Profile") && (name.hasSuffix("left") || name.hasSuffix("right"))) { continue }
            tap(x, yy, in: app, recording: expected)
            XCTAssertEqual(lastAction(app), expected, "\(name): a tap 19 pt from the centre did not reach the button")
        }
    }

    /// At the largest text size the bar items keep their size (HIG Toolbars; the Large Content Viewer shows them bigger).
    func testBarKeepsItsSizesAtAX5() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 3, arguments: FentonHomeApp.ax5)
        let profile = app.buttons["nav.profile"]
        XCTAssertTrue(profile.isHittable)
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable)
        XCTAssertEqual(profile.value as? String, "\(expectations[.personFirstFullName]), 3 items need attention")
        shoot(app, "named-ax5")
        guard isHorizontal(app) else { return }
        let measured = pixels(app)
        guard let disc = measured.disc else { return XCTFail("No monogram disc at AX5") }
        XCTAssertEqual(disc.width, 44, accuracy: 1, "The disc grew with text size")
        guard let glass = measured.glass.last(where: { $0.upperBound <= disc.minX + 1 }) else { return XCTFail("No Quick Links glass") }
        XCTAssertEqual(disc.minX - glass.upperBound, expectedGap, accuracy: 1.5)
    }

    // MARK: - Photo

    /// The area around the Profile button, where a photo disc draws (XCUITest reports a bar item's frame inside its circle).
    private func profileArea(_ app: XCUIApplication) -> CGRect { app.buttons["nav.profile"].frame.insetBy(dx: -14, dy: -14) }

    /// Alex's Home Assistant photo replaces their initials on the 44 pt disc, and the button reads and taps exactly as before:
    /// label, value, a target of 44 pt (19 pt off centre still opens it). The Duo's rail item draws the same photo (UIKit port, owner 2026-11-01).
    func testPhotoReplacesTheMonogramWithoutChangingTheButton() {
        // No badge: its red would read as a photo pixel, and it widens the disc's bounds.
        let app = launch(profile: expectations[.personFirstFullName], photos: true)
        let profile = app.buttons["nav.profile"]
        XCTAssertEqual(profile.label, "Profile")
        XCTAssertEqual(profile.value as? String, expectations[.personFirstFullName])
        XCTAssertTrue(profile.isHittable)
        shoot(app, "photo")
        let photo = AvatarPixels.photoPixels(in: profileArea(app), of: app)
        guard isHorizontal(app) else {
            if !isUnfolded(app) {
                // UIKit port (owner, 2026-11-01: "rail Profile shows the avatar"): the rail item is a bar item with an image, so the
                // person's photo is drawn into it (a SwiftUI rail item could only tint a symbol). It is not the 44 pt monogram disc.
                XCTAssertGreaterThanOrEqual(photo, AvatarPixels.photoThreshold, "The Duo's rail Profile must show the photo (\(photo) warm pixels)")
                XCTAssertNil(pixels(app).disc, "A monogram disc drew outside the rail group")
            }
            return
        }
        XCTAssertGreaterThanOrEqual(photo, AvatarPixels.photoThreshold, "No photo on the Profile button (\(photo) warm pixels)")
        XCTAssertNil(pixels(app).disc, "The blue monogram still draws under the photo")
        // The disc is 44 pt: read it from the pixels (the bar item's frame sits inside its circle), within reach of the button
        // only (Quick Links' glass is 12 pt further out).
        let near = CGRect(x: profile.frame.midX - 26, y: profile.frame.midY - 26, width: 52, height: 52)
        XCTAssertGreaterThanOrEqual(min(profile.frame.width, profile.frame.height), 36)
        guard let disc = AvatarPixels.litBounds(in: near, of: app) else { return XCTFail("No disc in the screenshot") }
        XCTAssertEqual(disc.width, 44, accuracy: 2, "The photo disc is not 44 pt")
        app.buttons["quickLinks.open"].tap()
        XCTAssertEqual(lastAction(app), "quick-links")
        tap(disc.midX + 19, disc.midY, in: app, recording: "profile")
        XCTAssertEqual(lastAction(app), "profile", "A tap 19 pt from the centre did not reach the photo button")
    }

    /// Without a photo (never synced, or after sign-out) the button draws the initials, as before.
    func testNoPhotoKeepsTheInitials() {
        let app = launch(profile: expectations[.personFirstFullName])
        if isHorizontal(app) {
            XCTAssertLessThan(AvatarPixels.photoPixels(in: profileArea(app), of: app), AvatarPixels.photoThreshold)
            XCTAssertNotNil(pixels(app).disc, "No monogram disc")
        }
    }

    /// At AX5 the photo disc keeps its size and the button its label and value.
    func testPhotoButtonKeepsItsSizeAtAX5() {
        let app = launch(profile: expectations[.personFirstFullName], photos: true, arguments: FentonHomeApp.ax5)
        let profile = app.buttons["nav.profile"]
        XCTAssertTrue(profile.isHittable)
        XCTAssertEqual(profile.label, "Profile")
        XCTAssertEqual(profile.value as? String, expectations[.personFirstFullName])
        shoot(app, "photo-ax5")
        guard isHorizontal(app) else { return }
        XCTAssertGreaterThanOrEqual(AvatarPixels.photoPixels(in: profileArea(app), of: app), AvatarPixels.photoThreshold)
        XCTAssertNil(pixels(app).disc)
        XCTAssertLessThanOrEqual(max(profile.frame.width, profile.frame.height), 60, "The bar item grew with text size")
    }

    // MARK: - Unnamed profile

    /// With no name yet Profile is the person symbol on the standard 44 pt glass circle, 12 pt from Quick Links.
    func testUnnamedProfileIsAGlassSymbol() {
        let app = launch(profile: "none")
        let profile = app.buttons["nav.profile"]
        XCTAssertEqual(profile.label, "Profile")
        XCTAssertEqual(profile.value as? String ?? "", "")
        XCTAssertTrue(profile.isHittable)
        shoot(app, "unnamed-plain")
        if isHorizontal(app) {
            let measured = pixels(app)
            XCTAssertNil(measured.disc, "The monogram's blue disc shows with no name")
            let circles = measured.glass.suffix(2)
            if circles.count == 2, let links = circles.first, let symbol = circles.last {
                XCTAssertEqual(links.upperBound - links.lowerBound, 44, accuracy: 1)
                XCTAssertEqual(symbol.upperBound - symbol.lowerBound, 44, accuracy: 1, "The symbol's glass is not a 44 pt circle")
                XCTAssertEqual(symbol.lowerBound - links.upperBound, 12, accuracy: 1.5)
            } else {
                XCTFail("Expected two glass circles, saw \(measured.glass)")
            }
        }
        profile.tap()
        XCTAssertEqual(lastAction(app), "profile")
    }

    // MARK: - Other states

    /// The spoken value says the count: a badge of twelve reads as "12 items".
    func testHeaderBadgeNinePlus() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 12)
        XCTAssertEqual(app.buttons["nav.profile"].value as? String, "\(expectations[.personFirstFullName]), 12 items need attention")
        shoot(app, "named-badge9plus")
    }

    /// A badge of one reads as "1 item".
    func testHeaderBadgeOne() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 1)
        XCTAssertEqual(app.buttons["nav.profile"].value as? String, "\(expectations[.personFirstFullName]), 1 item needs attention")
    }

    /// A pushed page keeps both buttons trailing and the disc the same size.
    func testHeaderBadgePushedPage() {
        let app = launch(profile: expectations[.personFirstFullName], badge: 3, pushed: true)
        XCTAssertTrue(app.buttons["quickLinks.open"].exists)
        shoot(app, "pushed-plain")
        if isHorizontal(app), let disc = pixels(app).disc {
            XCTAssertEqual(disc.width, 44, accuracy: 1, "The disc changed on a pushed page")
        }
    }

    // MARK: - Captures

    /// One state on the house backdrop and on the plain page, in one scheme, for design review.
    private func captureState(_ state: String, scheme: String, profile: String, badge: Int, pushed: Bool) {
        let app = launch(profile: profile, badge: badge, scheme: scheme, pushed: pushed, plain: false)
        shoot(app, "\(state)-\(scheme)")
        let plain = launch(profile: profile, badge: badge, scheme: scheme, pushed: pushed, plain: true)
        shoot(plain, "\(state)-plain-\(scheme)")
    }

    func testCaptureHeaderStateDarkNamed() { captureState("named", scheme: "dark", profile: expectations[.personFirstFullName], badge: 0, pushed: false) }
    func testCaptureHeaderStateDarkNamedBadge3() { captureState("named-badge3", scheme: "dark", profile: expectations[.personFirstFullName], badge: 3, pushed: false) }
    func testCaptureHeaderStateDarkNamedBadge9Plus() { captureState("named-badge9plus", scheme: "dark", profile: expectations[.personFirstFullName], badge: 12, pushed: false) }
    func testCaptureHeaderStateDarkUnnamed() { captureState("unnamed", scheme: "dark", profile: "none", badge: 0, pushed: false) }
    func testCaptureHeaderStateDarkPushed() { captureState("pushed", scheme: "dark", profile: expectations[.personFirstFullName], badge: 3, pushed: true) }
    func testCaptureHeaderStateLightNamed() { captureState("named", scheme: "light", profile: expectations[.personFirstFullName], badge: 0, pushed: false) }
    func testCaptureHeaderStateLightNamedBadge3() { captureState("named-badge3", scheme: "light", profile: expectations[.personFirstFullName], badge: 3, pushed: false) }
    func testCaptureHeaderStateLightNamedBadge9Plus() { captureState("named-badge9plus", scheme: "light", profile: expectations[.personFirstFullName], badge: 12, pushed: false) }
    func testCaptureHeaderStateLightUnnamed() { captureState("unnamed", scheme: "light", profile: "none", badge: 0, pushed: false) }
    func testCaptureHeaderStateLightPushed() { captureState("pushed", scheme: "light", profile: expectations[.personFirstFullName], badge: 3, pushed: true) }

    // MARK: - Reconnecting

    /// Owner, 2026-10-23: while the connection is retrying a 20 pt white arc sits left of Quick Links, the same gap from Quick
    /// Links as Quick Links is from Profile; it is a status, so VoiceOver reads it and nothing taps. The circles do not move
    /// when it appears. On the Duo's vertical rail it stays in the page header, trailing, not in the rail.
    func testReconnectingArcSitsLeftOfQuickLinksAtTheSameGap() {
        let still = launch(profile: expectations[.personFirstFullName])
        let stillMeasured = isHorizontal(still) ? pixels(still) : nil
        let app = launch(profile: expectations[.personFirstFullName], reconnecting: true)
        let arc = app.descendants(matching: .any)["reconnecting.arc"]
        XCTAssertTrue(arc.appears(timeout: 5), "No reconnecting arc")
        XCTAssertEqual(arc.label, "Reconnecting to Home Assistant")
        XCTAssertFalse(app.staticTexts["Reconnecting…"].exists, "The arc has no text")
        shoot(app, "reconnecting-plain")
        guard isHorizontal(app) else {
            // The arc is a custom view: like the monogram it stays in the horizontal page header, on the trailing side, and
            // never joins the vertical rail (owner, 2026-10-23).
            let window = app.windows.firstMatch.frame
            XCTAssertLessThan(arc.frame.midY, 110, "The arc left the page header")
            XCTAssertGreaterThan(arc.frame.midX, window.midX, "The arc is not on the trailing side of the header")
            return
        }
        XCTAssertLessThan(arc.frame.maxX, app.buttons["quickLinks.open"].frame.minX + 1, "The arc is not left of Quick Links")
        let measured = pixels(app)
        guard let disc = measured.disc, measured.glass.count >= 3 else { return XCTFail("Expected the arc, Quick Links and Profile, saw \(measured.glass)") }
        let ring = measured.glass[measured.glass.count - 3], links = measured.glass[measured.glass.count - 2]
        XCTAssertEqual(ring.upperBound - ring.lowerBound, 20, accuracy: 2, "The arc is not 20 pt")
        let arcGap = links.lowerBound - ring.upperBound
        let profileGap = disc.minX - links.upperBound
        XCTAssertEqual(arcGap, profileGap, accuracy: 1.5, "The arc is \(arcGap) pt from Quick Links, Profile \(profileGap) pt")
        if let stillDisc = stillMeasured?.disc {
            XCTAssertEqual(disc.minX, stillDisc.minX, accuracy: 1, "Profile moved when the arc appeared")
        }
    }

    // MARK: - Offline

    /// No network path: Profile carries an "Offline" badge (bottom-right); online it has none. Screenshots go to
    /// `FENTON_SHOTS_DIR` as `<layout>-header-online.png` and `<layout>-header-offline.png`.
    func testOfflineBadgeShowsOnlyWithoutANetworkPath() {
        let online = launch(profile: expectations[.personFirstFullName])
        XCTAssertFalse(((online.buttons["nav.profile"].value as? String) ?? "").contains("Offline"), "no badge while online")
        shoot(online, "header-online")
        let offline = launch(profile: expectations[.personFirstFullName], offline: true)
        // The badge is part of the Profile button for VoiceOver: its value ends with "Offline".
        XCTAssertTrue(((offline.buttons["nav.profile"].value as? String) ?? "").contains("Offline"), "offline badge is announced")
        shoot(offline, "header-offline")
    }
}

// MARK: - Pixel measurement

/// Where the header's blue monogram disc and glass circles are in a screenshot of the plain black gallery page, in points.
struct HeaderPixels {
    /// The bounding box of the monogram's blue disc (`ProfileButton.fill`), nil when none is drawn.
    var disc: CGRect?
    /// The horizontal extents of the glass circles (and the disc) right of the window's middle, leading to trailing.
    var glass: [ClosedRange<CGFloat>] = []

    init(screenshot: XCUIScreenshot, windowWidth: CGFloat) {
        guard let image = screenshot.image.cgImage else { return }
        let scale = CGFloat(image.width) / windowWidth
        let width = image.width
        let rows = min(image.height, Int(220 * scale))
        var buffer = [UInt8](repeating: 0, count: width * rows * 4)
        guard let context = CGContext(data: &buffer, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // The context's origin is bottom-left; drawing the image shifted up keeps its top rows.
        context.draw(image, in: CGRect(x: 0, y: rows - image.height, width: width, height: image.height))
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(buffer[i]), Int(buffer[i + 1]), Int(buffer[i + 2]))
        }
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1, count = 0
        for y in 0..<rows {
            for x in 0..<width {
                let p = pixel(x, y)
                if abs(p.r - 0) < 40, abs(p.g - 102) < 40, abs(p.b - 204) < 40 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y); count += 1
                }
            }
        }
        var bandStart = Int(50 * scale), bandEnd = Int(120 * scale)
        if count > 200 {
            disc = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX + 1 - minX) / scale, height: CGFloat(maxY + 1 - minY) / scale)
            bandStart = minY; bandEnd = maxY + 1
        }
        var start: Int?
        var last = 0
        var clusters: [ClosedRange<CGFloat>] = []
        for x in Int(CGFloat(width) * 0.5)..<width {
            var bright = 0
            for y in bandStart..<min(bandEnd, rows) {
                let p = pixel(x, y)
                if Double(p.r) * 0.3 + Double(p.g) * 0.59 + Double(p.b) * 0.11 > 14 { bright += 1 }
            }
            if bright > 3 {
                if start == nil { start = x }
                last = x
            } else if let s = start, CGFloat(x - last) > 2 * scale {
                if CGFloat(last + 1 - s) / scale > 6 { clusters.append(CGFloat(s) / scale...CGFloat(last + 1) / scale) }
                start = nil
            }
        }
        if let s = start, CGFloat(last + 1 - s) / scale > 6 { clusters.append(CGFloat(s) / scale...CGFloat(last + 1) / scale) }
        glass = clusters
    }
}
