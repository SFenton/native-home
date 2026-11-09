import XCTest

/// Tiles round 2 (owner, 2026-10-16): Quick Links tiles are one size again and coloured, the Rooms grid keeps two lines for
/// a name with a one-line name on the bottom line, and the Direction G gallery's Tile Finish section draws the shipped
/// tinted glass beside the solid fallback (owner chose tinted glass, 2026-10-17). iPhone, folded iPhone Duo and iPad (`.agents/design/direction-g.md`).
@MainActor
final class TilesRound2JourneyTests: JourneyTestCase {
    // MARK: Helpers

    /// Launches (or, with reuse on, resets) a gallery. Every setting the tests change is a `FENTON_GALLERY_*` variable, so a reset
    /// applies it; AX5 (`arguments`), the pinned appearance and the system settings are part of the launch signature and launch
    /// their own app (`app-reuse.md`).
    private func gallery(_ page: String, environment: [String: String], arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        app.launchEnvironment.merge(environment) { _, new in new }
        if let appearance { app.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        app.launchArguments += arguments
        return startApp(app)
    }

    private func launchQuickLinks(arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        let app = gallery("rooms", environment: [
            "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_QUICK_LINKS": "1", "FENTON_GALLERY_CLEAN": "1",
        ], arguments: arguments, appearance: appearance)
        XCTAssertTrue(element("quickLinks.rooms", in: app).appears(timeout: 30), "Quick Links did not open")
        settleScreen() // Mid-animation frames move the ink.
        return app
    }

    private func openRooms(arguments: [String] = []) -> XCUIApplication {
        let app = launchQuickLinks(arguments: arguments)
        element("quickLinks.rooms", in: app).tap()
        XCTAssertTrue(element("rooms.living-room", in: app).appears(timeout: 10), "The Rooms grid did not open")
        settleScreen()
        return app
    }

    /// Keeps the screenshot in the result bundle and, when `TEST_RUNNER_FENTON_TILES2_SHOTS` names a folder, writes it there too
    /// (owner-facing captures; never committed).
    private func shot(_ app: XCUIApplication, _ name: String) {
        keepScreenshot(app, name)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_TILES2_SHOTS"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }

    private func capture() throws -> RenderedContrast.Capture {
        try XCTUnwrap(RenderedContrast.Capture.screen(), "No screen capture")
    }

    // MARK: Quick Links

    /// Every Quick Links tile has the same height (owner: "Quick Links now have different tile sizes") and the same width, at the
    /// default size and at AX5 (where the tiles grow together), and each is its own solid colour with white ink. The one exception is
    /// Security System, which carries the Arm Home / Disarm disc beside its chevron and so spans the row when two tracks do not hold
    /// its title, state, disc and chevron (rollout L, audit item 17): never narrower than the others.
    func testQuickLinkTilesAreOneSizeAndColoured() throws {
        let app = launchQuickLinks()
        let ids = ["rooms", "security-system", "food", "vacuums", "media", "custom-lights", "sprinklers"]
        let tiles = ids.map { element("quickLinks.\($0)", in: app) }
        // One tree snapshot answers existence, the whole tile's frame and the body's size for every link.
        let root = try app.snapshot()
        var nodes: [String: any XCUIElementSnapshot] = [:]
        func walk(_ node: any XCUIElementSnapshot) {
            if node.identifier.hasPrefix("quickLinks."), nodes[node.identifier] == nil { nodes[node.identifier] = node }
            node.children.forEach(walk)
        }
        walk(root)
        for id in ids { XCTAssertNotNil(nodes["quickLinks.\(id)"], id) }
        func whole(_ id: String) -> CGRect? { (nodes["quickLinks.\(id).tile"] ?? nodes["quickLinks.\(id)"])?.frame }
        let first = try XCTUnwrap(whole("rooms"))
        for (id, tile) in zip(ids, tiles) {
            guard let node = nodes["quickLinks.\(id)"], let whole = whole(id) else { continue }
            // The whole tile: Security System's body element stops where its disc starts.
            if id == "security-system" {
                XCTAssertGreaterThanOrEqual(whole.width, first.width - 1, "\(id) is never narrower than the others")
            } else {
                XCTAssertEqual(whole.width, first.width, accuracy: 1, "\(id) width")
            }
            XCTAssertEqual(whole.height, first.height, accuracy: 1, "\(id) height")
            XCTAssertGreaterThanOrEqual(node.frame.width, 43, node.label)
            XCTAssertGreaterThanOrEqual(node.frame.height, 43, node.label)
        }
        shot(app, "quick-links-\(layout)")
        // Tinted glass fills (opaque in a sheet).
        // The fixture's alarm is armed_home; Sprinklers shows only while its visibility entity is on.
        let expected: [String: UInt32] = ["rooms": 0x1F3A5F, "security-system": 0x1565C0, "food": 0x4A6B4E, "vacuums": 0x7A3FB0,
                                          "media": 0xA03A61, "custom-lights": 0x7A4A00, "sprinklers": 0x076C91]
        var seen = Set<UInt32>()
        let window = app.windows.firstMatch.frame
        for (id, tile) in zip(ids, tiles) where tile.exists {
            // The Duo's sheet scrolls (Security System takes a row, owner 2026-11-01): bring this tile fully on screen first.
            for _ in 0..<6 where tile.frame.maxY > window.maxY - 24 { app.swipeUp(); settleScreen() }
            for _ in 0..<6 where tile.frame.minY < 60 { app.swipeDown(); settleScreen() }
            guard tile.isHittable else { continue }
            let shot = try capture()
            let frame = tile.frame
            // Low on the tile, clear of the glyph, the text and the chevron, where only the sheen's bottom shade has touched the fill.
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.maxX - 14, y: frame.maxY - 10), in: shot))
            let fill = try XCTUnwrap(expected[id])
            XCTAssertTrue(TileGeometry.matchesGlass(sample, fill, heightFraction: 1 - 10 / frame.height),
                          "\(id) is \(sample), expected \(String(fill, radix: 16)) under tinted glass")
            seen.insert(fill)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 5, "Each visible link is its own colour")
    }

    func testQuickLinkTilesStayOneSizeAtAX5() {
        let app = launchQuickLinks(arguments: FentonHomeApp.ax5)
        let ids = ["rooms", "security-system", "food", "vacuums", "media", "custom-lights"]
        let frames = ids.map { wholeTile("quickLinks.\($0)", in: app) }
        let window = app.windows.firstMatch.frame
        for (id, frame) in zip(ids, frames) {
            if id == "security-system" {
                XCTAssertGreaterThanOrEqual(frame.width, frames[0].width - 1, "\(id) width at AX5")
            } else {
                XCTAssertEqual(frame.width, frames[0].width, accuracy: 1, "\(id) width at AX5")
            }
            XCTAssertEqual(frame.height, frames[0].height, accuracy: 1, "\(id) height at AX5")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 1, "\(id) is clipped at AX5")
        }
        shot(app, "quick-links-ax5-\(layout)")
    }

    /// Quick Links and its tiles pass the audit (contrast of white ink on each fill, names, targets).
    func testQuickLinksAuditsCleanDark() throws {
        let app = launchQuickLinks()
        try FentonHomeApp.audit(app) { self.launchQuickLinks(arguments: FentonHomeApp.ax5) }
    }

    /// A light sheet audits clean too, where the fills are unchanged.
    func testQuickLinksAuditsCleanLight() throws {
        let light = launchQuickLinks(appearance: "light")
        shot(light, "quick-links-light-\(layout)")
        try FentonHomeApp.audit(light) { self.launchQuickLinks(arguments: FentonHomeApp.ax5, appearance: "light") }
    }

    // MARK: Rooms

    /// The Rooms grid: one height for every tile, tall enough for two lines of the title, the glyph top-leading and the name on
    /// the bottom line whether it is one line or two.
    func testRoomsTilesReserveTwoLinesAndAnchorTheNameToTheBottom() throws {
        let app = openRooms()
        shot(app, "rooms-two-lines-\(layout)")
        let shot = try capture()
        let rooms = ["living-room", "guest-room", "gym", expectations[.roomBedroomId], "office", "hallway", "kitchen", "downstairs-hallway"]
        // Tiles wholly clear of the bottom edge (the last row can sit under the sheet's fold).
        let bottom = app.windows.firstMatch.frame.maxY - 90
        let tiles = rooms.map { element("rooms.\($0)", in: app) }.filter { $0.exists && $0.isHittable && $0.frame.maxY < bottom }
        XCTAssertGreaterThanOrEqual(tiles.count, 4)
        let height = tiles[0].frame.height
        // Glyph (title3, ~24 pt), the gap, two title lines (~20 pt each) and 12 pt padding top and bottom.
        XCTAssertGreaterThanOrEqual(height, 92, "A room tile is tall enough for two lines")
        for tile in tiles {
            XCTAssertEqual(tile.frame.height, height, accuracy: 1, "\(tile.identifier) height")
            let ink = try XCTUnwrap(TileGeometry.content(in: tile.frame, capture: shot), "\(tile.identifier): no content")
            XCTAssertLessThan(tile.frame.maxY - ink.maxY, 18, "\(tile.identifier): the name is on the bottom line")
            XCTAssertLessThan(ink.minY - tile.frame.minY, 18, "\(tile.identifier): the glyph is top-leading")
            XCTAssertGreaterThan(ink.height, 40, "\(tile.identifier): glyph and name are apart, not stacked at the top")
        }
    }

    func testRoomsTilesGrowTogetherAtAX5() throws {
        let app = openRooms(arguments: FentonHomeApp.ax5)
        let rooms = ["living-room", "guest-room", "gym", expectations[.roomBedroomId]]
        let tiles = rooms.map { element("rooms.\($0)", in: app) }.filter { $0.exists }
        let window = app.windows.firstMatch.frame
        for tile in tiles {
            XCTAssertEqual(tile.frame.height, tiles[0].frame.height, accuracy: 1, "\(tile.identifier) height at AX5")
            XCTAssertLessThanOrEqual(tile.frame.maxX, window.maxX + 1, "\(tile.identifier) is clipped at AX5")
            assertTarget(tile)
        }
        shot(app, "rooms-two-lines-ax5-\(layout)")
    }

    func testRoomsGridAuditsClean() throws {
        let app = openRooms()
        try FentonHomeApp.audit(app) { self.openRooms(arguments: FentonHomeApp.ax5) }
    }

    // MARK: Tile finish gallery

    private func launchFinish(_ finish: String?, arguments: [String] = [], appearance: String? = nil, sheet: Bool = false) -> XCUIApplication {
        var environment = ["FENTON_GALLERY_DIRECTION_G_ORDER": "finish"]
        if let finish { environment["FENTON_GALLERY_DIRECTION_G_FINISH"] = finish }
        if sheet {
            environment["FENTON_GALLERY_DIRECTION_G_SHEET"] = "open"
            environment["FENTON_GALLERY_DIRECTION_G_SHEET_SECTION"] = "Finish"
        }
        let app = gallery("direction-g", environment: environment, arguments: arguments, appearance: appearance)
        XCTAssertTrue(element("g.finish.\(finish ?? "tintedGlass").Table Lamp", in: app).appears(timeout: 30), "Tile Finish did not appear")
        settleScreen()
        return app
    }

    /// Each finish draws the same eight tiles; it is audited on the page and at AX5, and a screenshot is kept for the owner.
    private func assertFinishAuditsCleanOnThePage(_ finish: String) throws {
        let app = launchFinish(finish)
        for name in ["Office Lamp", "Table Lamp", "Living Room Purifier", "Towel Rack", "Garage Door", "Kitchen"] {
            let tile = element("g.finish.\(finish).\(name)", in: app)
            XCTAssertTrue(tile.exists, "\(finish) \(name)")
            assertTarget(tile)
        }
        shot(app, "tile-finish-\(finish)-\(layout)")
        try FentonHomeApp.audit(app) { self.launchFinish(finish, arguments: FentonHomeApp.ax5) }
    }

    func testFinishAuditsCleanOnThePageTintedGlass() throws { try assertFinishAuditsCleanOnThePage("tintedGlass") }
    func testFinishAuditsCleanOnThePageSolid() throws { try assertFinishAuditsCleanOnThePage("solid") }

    /// A finish audited in a light sheet, with a screenshot kept for the owner.
    private func assertFinishAuditsCleanInALightSheet(_ finish: String) throws {
        let app = launchFinish(finish, appearance: "light", sheet: true)
        XCTAssertTrue(app.buttons["sheet.close"].appears(timeout: 10), "\(finish) sheet")
        shot(app, "tile-finish-sheet-light-\(finish)-\(layout)")
        try FentonHomeApp.audit(app) { self.launchFinish(finish, arguments: FentonHomeApp.ax5, appearance: "light", sheet: true) }
    }

    func testFinishAuditsCleanInALightSheetTintedGlass() throws { try assertFinishAuditsCleanInALightSheet("tintedGlass") }
    func testFinishAuditsCleanInALightSheetSolid() throws { try assertFinishAuditsCleanInALightSheet("solid") }

    /// Reduce Transparency and Increase Contrast turn tinted glass into the solid finish: the page draws the same pixels for
    /// tinted glass as for the solid fallback.
    func testReduceTransparencyAndIncreaseContrastFallBackToSolid() throws {
        func tileFrame(_ finish: String, _ settings: [FentonHomeApp.SystemSetting]) throws -> [UInt8] {
            // An empty list is the default launch (the class's resident app); a setting is its own launch signature.
            let app = gallery("direction-g", environment: ["FENTON_GALLERY_DIRECTION_G_ORDER": "finish", "FENTON_GALLERY_DIRECTION_G_FINISH": finish]
                .merging(settings.isEmpty ? [:] : FentonHomeApp.SystemSetting.environment(settings)) { $1 })
            let tile = element("g.finish.\(finish).Living Room Purifier", in: app)
            XCTAssertTrue(tile.appears(timeout: 30))
            settleScreen()
            let shot = try capture()
            let frame = tile.frame
            // The fill, clear of the text: a column at the tile's trailing edge.
            return (0..<8).flatMap { step -> [UInt8] in
                let point = CGPoint(x: frame.maxX - 10, y: frame.minY + 8 + CGFloat(step) * (frame.height - 16) / 8)
                return TileGeometry.rgb(at: point, in: shot).map { [UInt8($0.r), UInt8($0.g), UInt8($0.b)] } ?? []
            }
        }
        let solid = try tileFrame("solid", [])
        let glass = try tileFrame("tintedGlass", [])
        // Tinted glass is not the solid fill: the sheen and the translucent fill put tens of levels between them.
        XCTAssertGreaterThan(zip(glass, solid).map { abs(Int($0) - Int($1)) }.max() ?? 0, 6, "Tinted glass draws differently from solid")
        for settings in [[FentonHomeApp.SystemSetting.reduceTransparency], [.increaseContrast]] {
            let fallback = try tileFrame("tintedGlass", settings)
            XCTAssertEqual(fallback.count, solid.count)
            // The same fill to within a few levels per channel (the capture's own dithering): a translucent ground would be
            // tens of levels away on at least one of the eight samples.
            let farthest = zip(fallback, solid).map { abs(Int($0) - Int($1)) }.max() ?? 0
            XCTAssertLessThanOrEqual(farthest, 4, "Tinted glass under \(settings) is the solid finish")
        }
    }
}
