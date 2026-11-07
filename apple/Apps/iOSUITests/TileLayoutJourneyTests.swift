import XCTest

/// Tile layout and chevron geometry on the Direction G gallery's Tile Layouts section
/// (`FENTON_GALLERY=direction-g`, `-directionGOrder layouts`, `-directionGLayout <layout>`): the four arrangements
/// compared for the owner (2026-10-16: "it feels too high up / lots of dead space"), the shipped row's centring, the
/// chevron's vertical centre, equal row heights and 44 pt targets at the default size and AX5 on iPhone, folded Duo
/// and iPad. Positions are read from screenshots (`TileGeometry`) because a tile's glyph and chevron are hidden from
/// VoiceOver.
@MainActor
final class TileLayoutJourneyTests: JourneyTestCase {
    private static let layouts = ["row", "anchoredBottom", "centeredStack", "stackedTop"]

    /// The gallery takes its arrangement from `FENTON_GALLERY_DIRECTION_G_ORDER` / `_LAYOUT` (the same as the `-directionGOrder` and
    /// `-directionGLayout` arguments), so it is a gallery setting a reset can change and the class keeps one resident app
    /// (`app-reuse.md`). The geometry reads wait for the layout's own tile and for the screen to stop moving, as after a fresh launch.
    /// AX5 (`arguments`) launches fresh by signature.
    private func launch(_ layout: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "direction-g"
        app.launchEnvironment["FENTON_GALLERY_DIRECTION_G_ORDER"] = "layouts"
        app.launchEnvironment["FENTON_GALLERY_DIRECTION_G_LAYOUT"] = layout
        app.launchArguments += arguments
        let running = startApp(app)
        XCTAssertTrue(element("g.layout.\(layout).Kitchen", in: running).appears(timeout: 20), "\(layout) did not appear")
        settleScreen() // Mid-animation frames move the ink.
        return running
    }

    private func tile(_ layout: String, _ name: String, in app: XCUIApplication) -> XCUIElement {
        element("g.layout.\(layout).\(name)", in: app)
    }

    /// The frames of the named tiles of one arrangement, from a single tree snapshot (a frame read on an element is a request each).
    private func frames(_ layout: String, _ names: [String], in app: XCUIApplication) -> [String: CGRect] {
        guard let root = try? app.snapshot() else { return [:] }
        let wanted = Dictionary(uniqueKeysWithValues: names.map { ("g.layout.\(layout).\($0)", $0) })
        var found: [String: CGRect] = [:]
        func walk(_ node: any XCUIElementSnapshot) {
            if let name = wanted[node.identifier], found[name] == nil { found[name] = node.frame }
            node.children.forEach(walk)
        }
        walk(root)
        return found
    }

    private func tileFrame(_ layout: String, _ name: String, in app: XCUIApplication) -> CGRect? {
        (try? tile(layout, name, in: app).snapshot())?.frame
    }

    /// A tile is at least 43 pt each way (`assertTarget`, from its frame).
    private func assertTarget(_ frame: CGRect, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(frame.width, 43, name, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 43, name, file: file, line: line)
    }

    private func capture(_ file: StaticString = #filePath, _ line: UInt = #line) throws -> RenderedContrast.Capture {
        try XCTUnwrap(RenderedContrast.Capture.screen(), "No screen capture", file: file, line: line)
    }

    /// One arrangement keeps 44 pt targets and equal heights within a row; the row's tile stays Apple Home's height. The
    /// shortest single-line tile height is returned for the comparison test.
    @discardableResult
    private func assertTargetsAndEqualRowHeights(_ layout: String) -> CGFloat? {
        let app = launch(layout)
        let names = ["Office Lamp", "Living Room Purifier", expectations[.tileClosetTitle], "Kitchen", "Security", "Towel Rack"]
        let frames = frames(layout, names, in: app)
        for name in names {
            guard let frame = frames[name] else { XCTFail("\(layout) \(name)"); continue }
            assertTarget(frame, name)
        }
        // Two columns on iPhone: tiles in the same row share a height (the grid's equal row heights).
        if let closet = frames[expectations[.tileClosetTitle]], let kitchen = frames["Kitchen"], abs(closet.minY - kitchen.minY) < 2 {
            XCTAssertEqual(closet.height, kitchen.height, accuracy: 1, "\(layout) row heights differ")
        }
        keepScreenshot(app, "tile-layout-\(layout)-\(self.layout)")
        return frames.filter { ["Office Lamp", "Kitchen", "Towel Rack"].contains($0.key) }.values.map(\.height).min()
    }

    /// The shortest tile in the grid: a wrapped title lifts its whole row, so the single-line rows show the layout.
    private func shortestTileHeight(_ layout: String, in app: XCUIApplication) -> CGFloat? {
        frames(layout, ["Office Lamp", "Kitchen", "Towel Rack"], in: app).values.map(\.height).min()
    }

    func testTileLayoutRowKeepsTargetsAndEqualRowHeights() {
        let height = assertTargetsAndEqualRowHeights("row")
        XCTAssertLessThanOrEqual(height ?? .infinity, 100, "A row tile stays Apple Home's height: \(String(describing: height))")
    }

    func testTileLayoutAnchoredBottomKeepsTargetsAndEqualRowHeights() {
        assertTargetsAndEqualRowHeights("anchoredBottom")
    }

    func testTileLayoutCenteredStackKeepsTargetsAndEqualRowHeights() {
        assertTargetsAndEqualRowHeights("centeredStack")
    }

    func testTileLayoutStackedTopKeepsTargetsAndEqualRowHeights() {
        assertTargetsAndEqualRowHeights("stackedTop")
    }

    /// The rows get shorter the closer the arrangement is to Apple Home's tile: the row is shorter than the old stack.
    func testTileLayoutRowShorterThanStack() {
        let rowApp = launch("row")
        let row = shortestTileHeight("row", in: rowApp)
        let stackedApp = launch("stackedTop")
        let stacked = shortestTileHeight("stackedTop", in: stackedApp)
        XCTAssertLessThan(row ?? .infinity, stacked ?? 0, "The row is shorter than the old stack: row \(String(describing: row)), stackedTop \(String(describing: stacked))")
    }

    /// The chevron sits at the tile's vertical centre in one arrangement.
    private func assertChevronIsVerticallyCentred(_ layout: String) throws {
        let app = launch(layout)
        for name in ["Kitchen", "Security"] {
            let frame = try XCTUnwrap(tileFrame(layout, name, in: app), "\(layout) \(name)")
            // The Security tile is dark (the page module), the Kitchen tile a flat room fill; the chevron is
            // read against the corner colour either way.
            let capture = try capture()
            guard let chevron = TileGeometry.chevron(in: frame, capture: capture) else {
                XCTFail("\(layout) \(name): no chevron found"); continue
            }
            XCTAssertEqual(chevron.midY, frame.midY, accuracy: 3,
                           "\(layout) \(name): chevron midY \(chevron.midY) vs tile midY \(frame.midY)")
            XCTAssertGreaterThan(chevron.minX, frame.maxX - 32, "\(layout) \(name): chevron is trailing")
        }
    }

    func testChevronIsVerticallyCentredRow() throws { try assertChevronIsVerticallyCentred("row") }
    func testChevronIsVerticallyCentredAnchoredBottom() throws { try assertChevronIsVerticallyCentred("anchoredBottom") }
    func testChevronIsVerticallyCentredCenteredStack() throws { try assertChevronIsVerticallyCentred("centeredStack") }
    func testChevronIsVerticallyCentredStackedTop() throws { try assertChevronIsVerticallyCentred("stackedTop") }

    /// The shipped row puts the glyph and title at the tile's vertical centre; the anchored layout puts the title at the
    /// bottom edge and the glyph at the top; neither floats near the top with dead space under it.
    func testRowIsCentredAndAnchoredTextSitsAtTheBottom() throws {
        let row = launch("row")
        let rowFrame = try XCTUnwrap(tileFrame("row", "Kitchen", in: row), "row Kitchen")
        let rowContent = try XCTUnwrap(TileGeometry.content(in: rowFrame, capture: try capture()), "row: no content")
        XCTAssertEqual(rowContent.midY, rowFrame.midY, accuracy: 4, "row content is vertically centred (content \(rowContent), tile \(rowFrame))")

        let anchored = launch("anchoredBottom")
        let anchoredFrame = try XCTUnwrap(tileFrame("anchoredBottom", "Kitchen", in: anchored), "anchoredBottom Kitchen")
        let content = try XCTUnwrap(TileGeometry.content(in: anchoredFrame, capture: try capture()), "anchored: no content")
        XCTAssertLessThan(anchoredFrame.maxY - content.maxY, 22, "anchored text sits at the bottom padding")
        XCTAssertLessThan(content.minY - anchoredFrame.minY, 22, "anchored glyph sits at the top padding")

        let stacked = launch("stackedTop")
        let oldFrame = try XCTUnwrap(tileFrame("stackedTop", "Kitchen", in: stacked), "stackedTop Kitchen")
        let oldContent = try XCTUnwrap(TileGeometry.content(in: oldFrame, capture: try capture()), "stackedTop: no content")
        XCTAssertGreaterThan(oldFrame.maxY - oldContent.maxY, rowFrame.maxY - rowContent.maxY + 8,
                             "The old stack left more dead space under its text")
    }

    /// At AX5 a row falls back to the bottom-anchored stack: targets hold and nothing clips off the tile.
    private func assertReadableAtAX5(_ layout: String) {
        let app = launch(layout, arguments: FentonHomeApp.ax5)
        let window = app.windows.firstMatch.frame
        let names = [expectations[.tileClosetTitle], "Kitchen", "Security"]
        let frames = frames(layout, names, in: app)
        for name in names {
            guard let frame = frames[name] else { XCTFail("\(layout) \(name) at AX5"); continue }
            assertTarget(frame, name)
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "\(layout) \(name) is clipped at AX5")
        }
        keepScreenshot(app, "tile-layout-\(layout)-ax5-\(self.layout)")
    }

    func testTileLayoutAX5RowKeepsTilesReadable() { assertReadableAtAX5("row") }
    func testTileLayoutAX5AnchoredBottomKeepsTilesReadable() { assertReadableAtAX5("anchoredBottom") }
    func testTileLayoutAX5CenteredStackKeepsTilesReadable() { assertReadableAtAX5("centeredStack") }
    func testTileLayoutAX5StackedTopKeepsTilesReadable() { assertReadableAtAX5("stackedTop") }

    /// The shipped layout passes the accessibility audit.
    func testTileLayoutAX5RowPassesAudit() throws {
        let shipped = launch("row")
        try FentonHomeApp.audit(shipped) { self.launch("row", arguments: FentonHomeApp.ax5) }
    }
}
