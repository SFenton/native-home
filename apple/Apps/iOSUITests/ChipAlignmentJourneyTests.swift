import XCTest

/// The status chip row starts at the page's leading margin, whether it overflows or not (owner, 2026-10-17: "Security
/// chips are not left-aligned. Even if all chips fit on screen, they still need to be left aligned."). The compact rail is
/// a hosted `UIScrollView`, whose hosting view centred a row narrower than the scroll view; on every width it is that one
/// row now (owner, 2026-10-26), and only an accessibility-size rail wraps, with `FlowLayout`, whose rows start at the
/// leading edge (`.agents/patterns/status-rail.md`).
///
/// Each page is checked on iPhone, the folded Duo and iPad in portrait and landscape (the unfolded Duo is not scriptable;
/// its rule is `ChipRailMetrics` and `ChipRailTests`): the first chip's leading edge is the page's content margin from the
/// page's own leading edge, and so is the first chip of every wrapped row.
final class ChipAlignmentJourneyTests: JourneyTestCase {
    /// The page's content margin (`HassTokens.Spacing.l`).
    private let margin: CGFloat = 16

    /// The pose a step checks: upright runs on every family (an iPad is set to portrait first), iPad landscape only on iPad.
    private enum Pose {
        case upright, iPadLandscape
        var orientation: UIDeviceOrientation { self == .upright ? .portrait : .landscapeLeft }
    }

    /// Skips off iPad for the landscape pose, before any launch.
    private func requirePose(_ pose: Pose) throws {
        if pose == .iPadLandscape { try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only") }
    }

    private func launch(gallery: String, environment: [String: String] = [:], ready: String) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = gallery
        app.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        // Every switch is a `FENTON_GALLERY_*` variable, so each test is a reset of the class's resident app (`app-reuse.md`).
        _ = startApp(app)
        XCTAssertTrue(element(ready, in: app).appears(timeout: 30), "\(gallery) did not open")
        return app
    }

    /// A chip as one tree read sees it.
    private struct Chip { let label: String; let frame: CGRect }

    /// The chips whose identifier starts with `prefix`, by top then leading edge, and the frame of `page`, from one tree snapshot
    /// (a request per chip and per property before).
    private func chips(_ prefix: String, page: String, in app: XCUIApplication) -> (chips: [Chip], page: CGRect?) {
        guard let root = try? app.snapshot() else { return ([], nil) }
        var found: [Chip] = []
        var pageFrame: CGRect?
        func walk(_ node: any XCUIElementSnapshot) {
            if node.identifier.hasPrefix(prefix), node.frame.width > 0 { found.append(Chip(label: node.label, frame: node.frame)) }
            if node.identifier == page, pageFrame == nil { pageFrame = node.frame }
            node.children.forEach(walk)
        }
        walk(root)
        return (found.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }, pageFrame)
    }

    /// Every row of chips begins `margin` points inside `page`'s leading edge.
    private func assertChipsStartAtTheMargin(_ prefix: String, page: String, in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let (all, found) = chips(prefix, page: page, in: app)
        guard let pageFrame = found else { return XCTFail("No \(page) in the tree", file: file, line: line) }
        XCTAssertFalse(all.isEmpty, "No \(prefix) chips on \(layout)", file: file, line: line)
        // A row is the chips sharing a top; the scrolling rail is one row, the wrapped rail several.
        var rows: [CGFloat: [Chip]] = [:]
        for chip in all { rows[chip.frame.minY.rounded(), default: []].append(chip) }
        for (_, row) in rows {
            guard let first = row.min(by: { $0.frame.minX < $1.frame.minX }) else { continue }
            XCTAssertEqual(first.frame.minX - pageFrame.minX, margin, accuracy: 1,
                           "The first \(prefix) chip in its row (\(first.label)) is not at the content margin on \(layout)", file: file, line: line)
        }
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        guard XCUIDevice.shared.orientation != orientation else { return }
        XCUIDevice.shared.orientation = orientation
        settleScreen() // the rail lays out again for the new width
    }

    private func check(_ pose: Pose, gallery: String, environment: [String: String] = [:], ready: String,
                       prefix: String, page: String) throws {
        try requirePose(pose)
        let app = launch(gallery: gallery, environment: environment, ready: ready)
        if FentonHomeApp.family == .iPad || pose == .upright { rotate(to: pose.orientation) }
        assertChipsStartAtTheMargin(prefix, page: page, in: app)
    }

    /// Security's two chips fit on every phone: they still start at the margin (this was the reported bug).
    func testSecurityChipsStartAtTheLeadingMargin() throws {
        try check(.upright, gallery: "security", ready: "security.chip.security", prefix: "security.chip.", page: "security.scroll")
    }

    func testSecurityChipsStartAtTheLeadingMarginInIPadLandscape() throws {
        try check(.iPadLandscape, gallery: "security", ready: "security.chip.security", prefix: "security.chip.", page: "security.scroll")
    }

    /// Home's six chips overflow a phone and scroll as one row on an iPad too.
    func testHomeChipsStartAtTheLeadingMargin() throws {
        try check(.upright, gallery: "performance", environment: ["FENTON_GALLERY_PERF": "chips"], ready: "home.chip.lights",
                  prefix: "home.chip.", page: "perf.chips")
    }

    func testHomeChipsStartAtTheLeadingMarginInIPadLandscape() throws {
        try check(.iPadLandscape, gallery: "performance", environment: ["FENTON_GALLERY_PERF": "chips"], ready: "home.chip.lights",
                  prefix: "home.chip.", page: "perf.chips")
    }

    /// A room page's rail.
    func testRoomChipsStartAtTheLeadingMargin() throws {
        try check(.upright, gallery: "rooms", environment: ["FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_ROOM": "living-room"],
                  ready: "room.scroll.living-room", prefix: "room.chip.", page: "room.scroll.living-room")
    }

    func testRoomChipsStartAtTheLeadingMarginInIPadLandscape() throws {
        try check(.iPadLandscape, gallery: "rooms", environment: ["FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_ROOM": "living-room"],
                  ready: "room.scroll.living-room", prefix: "room.chip.", page: "room.scroll.living-room")
    }
}
