import XCTest

/// Layout that adapts to the window (plan Phase 4, decisions 1 to 5; `.agents/design/apple/ipados.md`, `duo.md`):
/// grids reach four columns on iPad, and status chips are one sideways row on every width that wraps only at accessibility
/// sizes (owner, 2026-10-26). Every test names what it expects per device family; the unfolded Duo is driven only when
/// the simulator is unfolded (`.agents/testing/apple/devices.md`), and its hinge rules are also unit tested
/// (`HomeColumnsTests`, `ChipRailTests`, `DynamicGridHingeTests`).
@MainActor
final class AdaptiveLayoutJourneyTests: JourneyTestCase {
    /// Whether the window is regular width: iPad, and the unfolded Duo (669 pt portrait, 951 pt landscape); never the
    /// folded Duo's outer display (466 pt) or an iPhone. Read from the window, as the app reads its size class.
    private func isRegular(_ app: XCUIApplication) -> Bool { app.windows.firstMatch.frame.width >= 600 }

    /// Opens the named gallery through app reuse (one resident app per class; every test here is a plain gallery launch).
    private func gallery(_ page: String) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = page
        return startApp(configured)
    }

    // MARK: Grids (decision 1)

    /// The Chores quick links in the gallery (fixture state): four tiles across on iPad in either orientation, two on a
    /// phone. Tiles on one row share a `minY`.
    func testChoresQuickLinksGrowToFourColumnsOnIPad() {
        let app = gallery("chores")
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 10), "Chores gallery did not open")
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chores.link.'")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(tiles.count, 4, "Quick links missing")
        let rows = tiles.map { ($0, $0.frame) }
        let top = rows.map(\.1.minY).min() ?? 0
        let firstRow = rows.filter { abs($0.1.minY - top) < 2 }.map(\.0)
        if isRegular(app) {
            XCTAssertGreaterThanOrEqual(firstRow.count, 4, "iPad shows \(firstRow.count) quick links across, expected at least 4")
            let widths = Set(rows.filter { abs($0.1.minY - top) < 2 }.map { Int($0.1.width.rounded()) })
            XCTAssertLessThanOrEqual(widths.count, 2, "Tiles in a row differ in width: \(widths)")
        } else {
            XCTAssertGreaterThanOrEqual(firstRow.count, 2)
            XCTAssertLessThan(firstRow.count, 4, "A phone should not squeeze \(firstRow.count) tiles across")
        }
        for tile in firstRow { assertTarget(tile) }
        keepShot(app, "g4-chores-\(layout)")
    }

    /// A room page lays two sections side by side on iPad (a shared top edge, the second in the right half), one column on a phone.
    func testRoomSectionsSitSideBySideOnIPad() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "rooms"
        configured.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        configured.launchEnvironment["FENTON_GALLERY_ROOM"] = "living-room"
        let app = startApp(configured)
        XCTAssertTrue(element("room.scroll.living-room", in: app).appears(timeout: 30), "Room did not open")
        settleScreen()
        // Side by side is a property of the sections (`room.section.<title>`), not of a tile count: a content-aware tile (the Air
        // Purifier, owner 2026-11-01) takes its section's full width, and a full-width section's own grid also puts two tiles on a row.
        let climate = element("room.section.Climate", in: app), devices = element("room.section.Devices", in: app)
        XCTAssertTrue(climate.exists && devices.exists, "The Climate and Devices sections are on the page")
        if isRegular(app) {
            XCTAssertEqual(climate.frame.minY, devices.frame.minY, accuracy: 2, "The sections share a top edge")
            XCTAssertLessThan(climate.frame.maxX, devices.frame.minX, "The sections do not overlap")
            XCTAssertGreaterThan(devices.frame.minX, app.windows.firstMatch.frame.midX - 20, "The second section starts in the right half")
        } else {
            XCTAssertGreaterThanOrEqual(devices.frame.minY, climate.frame.maxY - 1, "A phone stacks the sections in one column")
        }
        keepShot(app, "g4-room-\(layout)")
    }

    // MARK: Chips (decision 2, replaced by the owner 2026-10-26)

    /// Home's six chips are one row that scrolls sideways on every family, full page width: they share a `minY`, keep
    /// 44 pt targets and, where the row overflows the window, a swipe moves the first chip. Where it fits (iPad
    /// landscape, the unfolded Duo) nothing scrolls and the rail still spans the window.
    func testHomeChipsAreOneScrollingRowOnEveryWidth() throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        let ids = ["lights", "security", "climate", "occupancy", "contacts", "airQuality"]
        let chips = ids.map { app.buttons["home.chip.\($0)"] }
        for chip in chips {
            XCTAssertTrue(chip.exists, chip.identifier)
            assertTarget(chip)
        }
        let rows = Set(chips.map { Int($0.frame.minY.rounded()) })
        XCTAssertEqual(rows.count, 1, "Chips took \(rows.count) rows; they scroll in one")
        let window = app.windows.firstMatch.frame
        let rail = element("chipRail.scroll", in: app)
        XCTAssertTrue(rail.appears(timeout: 5), "No scrolling chip rail")
        let first = chips[0], last = chips[chips.count - 1]
        if last.frame.maxX > window.maxX {
            let startX = first.frame.minX
            rail.swipeLeft(velocity: .fast)
            XCTAssertLessThan(first.frame.minX, startX, "The rail did not scroll sideways")
        } else {
            XCTAssertEqual(rail.frame.width, window.width, accuracy: 2, "A rail that fits still spans the window")
        }
        keepShot(app, "g4-home-chips-\(layout)")
    }

    /// At the largest text size the rail wraps (chips grow to about the screen's width), on iPad too: no chip runs off
    /// screen, and the chips are still buttons named "<title>, <summary>" with 44 pt targets.
    func testHomeChipsWrapAtAX5AndKeepTheirNames() throws {
        let app = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
        settleScreen()
        let lights = app.buttons["home.chip.lights"]
        XCTAssertTrue(lights.appears(timeout: 10))
        let window = app.windows.firstMatch.frame
        for id in ["lights", "security", "climate"] {
            let chip = app.buttons["home.chip.\(id)"]
            XCTAssertTrue(chip.exists, id)
            XCTAssertTrue(chip.label.contains(", "), "\(id) label is not '<title>, <summary>': \(chip.label)")
            assertTarget(chip)
            XCTAssertLessThanOrEqual(chip.frame.maxX, window.maxX + 1, "\(id) runs off screen")
        }
        XCTAssertFalse(element("chipRail.scroll", in: app).exists, "A wrapped rail does not scroll")
        keepShot(app, "g4-home-chips-ax5-\(layout)")
    }

    // MARK: Quick Links (decision 3, reversed 2026-10-16)

    // Quick Links is a header button beside Profile on every page of every window now, so the floating circle's journeys
    // are gone; `ShellJourneyTests` covers the button on every tab root and on a pushed page, on all three families.

    // MARK: Home on the hinge (decision 5)

    /// Unfolded Duo in landscape: the chip rail spans the whole page above the columns and crosses the hinge, weather leads,
    /// cameras trail, and the tab bar stays (owner, 2026-10-26). Elsewhere Home is one column. Not a skip when it does not
    /// apply: it passes by checking the one-column layout.
    func testHomeSplitsOnTheHingeOnlyWhenUnfoldedInLandscape() throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        let window = app.windows.firstMatch.frame
        let chip = app.buttons["home.chip.lights"]
        let camera = app.buttons["home.camera.front_door"]
        XCTAssertTrue(camera.appears(timeout: 10), "No camera tile")
        let unfoldedLandscape = FentonHomeApp.family == .iPhoneDuo && window.width > window.height && window.width >= 900
        if unfoldedLandscape {
            let rail = element("chipRail.scroll", in: app)
            XCTAssertTrue(rail.exists, "No chip rail")
            XCTAssertGreaterThan(rail.frame.maxX, Self.hingeBand.upperBound, "The rail stops at the hinge: \(rail.frame)")
            XCTAssertEqual(rail.frame.minX, window.minX, accuracy: 2, "The rail does not start at the page's edge")
            XCTAssertGreaterThan(app.buttons["home.chip.airQuality"].frame.maxX, Self.hingeBand.upperBound, "Chips stop at the hinge")
            XCTAssertGreaterThan(camera.frame.minX, window.midX, "Cameras are not in the trailing half")
            XCTAssertGreaterThan(camera.frame.minY, chip.frame.maxY, "Cameras sit beside the rail, not below it")
        } else {
            // One column: the cameras sit below the chips, not beside them.
            XCTAssertGreaterThan(camera.frame.minY, chip.frame.maxY, "Home is split without a hinge")
        }
        keepShot(app, "g4-home-\(layout)-\(unfoldedLandscape ? "split" : "single")")
    }

    // MARK: Root navigation (owner, 2026-10-26)

    /// A section's item in the tab bar, or the folded and unfolded Duo's vertical bar (a toolbar to XCUITest).
    /// Matched by label prefix: Chores speaks its overdue count ("Chores, 9+ overdue"), and the vertical bar draws icons only.
    private func barItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let match = NSPredicate(format: "label BEGINSWITH %@", title)
        let item = app.tabBars.buttons.matching(match).firstMatch
        return item.exists ? item : app.toolbars.buttons.matching(match).firstMatch
    }

    /// One section: phones and the Duo, folded or unfolded, show the tab bar and reach it from there; iPad hides the bar and
    /// reaches it through the flyout. The unfolded Duo keeping its bar is the owner's 2026-10-26 report.
    private func assertRootNavigationOpens(_ section: String, title: String) throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        let item = barItem(title, in: app)
        if FentonHomeApp.family == .iPad {
            XCTAssertFalse(item.exists && item.isHittable, "iPad shows a tab for \(title)")
        } else {
            XCTAssertTrue(item.appears(timeout: 5), "\(title) has no tab on \(layout)")
            XCTAssertTrue(item.isHittable, "\(title) tab is not hittable on \(layout)")
        }
        if FentonHomeApp.family == .iPad { openSection(section, title: title, in: app) } else { item.tap() }
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 5), "\(title) did not open on \(layout)")
        keepShot(app, "g4-nav-\(section)-\(layout)")
    }

    func testRootNavigationOpensHome() throws { try assertRootNavigationOpens("home", title: "Home") }
    func testRootNavigationOpensSecurity() throws { try assertRootNavigationOpens("security", title: "Security") }
    func testRootNavigationOpensClimate() throws { try assertRootNavigationOpens("climate", title: "Climate") }
    func testRootNavigationOpensChores() throws { try assertRootNavigationOpens("chores", title: "Chores") }
    func testRootNavigationOpensSettings() throws { try assertRootNavigationOpens("settings", title: "Settings") }

    // MARK: Hinge avoidance and readable width (duo-ipad-fold-layout, decided 2026-10-24)

    /// The unfolded Duo's hinge band in window points (simulator measurement: 455.3 to 495.7).
    private static let hingeBand: ClosedRange<CGFloat> = 455.3...495.7

    private func isUnfoldedDuoLandscape(_ app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        return FentonHomeApp.family == .iPhoneDuo && window.width > window.height && window.width >= 900
    }

    /// The Security page's alarm card takes the whole content width on every family (owner, 2026-10-30: its mode buttons then share
    /// the Doors tiles' columns; the 560 pt cap is for the Security sheet). On the unfolded Duo in landscape the fold crosses the card
    /// and no mode button sits under the hinge band.
    func testSecurityAlarmCardIsReadableWidthAndClearsTheHinge() {
        let app = gallery("security")
        let card = element("security.alarm.card", in: app)
        XCTAssertTrue(card.appears(timeout: 30), "Security did not open")
        let window = app.windows.firstMatch.frame
        // The content width is the page's: the window less the system's vertical bar on the folded Duo, which the page keeps clear of
        // (UKPageViewController side insets). The narrowest scroller holding the card is that page.
        let scrollers = (app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex).map(\.frame)
        let content = scrollers.filter { $0.width > 0 && $0.minX <= card.frame.minX + 1 && $0.maxX >= card.frame.maxX - 1 }.map(\.width).min() ?? window.width
        XCTAssertGreaterThanOrEqual(card.frame.width, min(content - 32, 560) - 1, "The alarm card is narrower than the content width (the page minus the 16 pt margins; page \(content), window \(window.width))")
        XCTAssertLessThanOrEqual(card.frame.width, window.width + 1, "The alarm card is wider than the window")
        if isUnfoldedDuoLandscape(app) {
            let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'security.mode.'")).allElementsBoundByIndex
            XCTAssertGreaterThanOrEqual(buttons.count, 4, "The four mode buttons are missing")
            for modeButton in buttons {
                XCTAssertTrue(modeButton.frame.maxX <= Self.hingeBand.lowerBound + 1 || modeButton.frame.minX >= Self.hingeBand.upperBound - 1,
                              "A mode button crosses the hinge: \(modeButton.identifier) \(modeButton.frame)")
            }
        }
        keepShot(app, "k-security-alarm-\(layout)")
    }

    /// Food & Recipes on the unfolded Duo in landscape: the recipe column ends at the hinge and the inventory column
    /// starts after it. Elsewhere (iPad landscape included) the columns share the width.
    func testFoodHubColumnsMeetAtTheHinge() {
        let app = gallery("food")
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertTrue(allRecipes.appears(timeout: 30), "Food did not open")
        let space = element("food.space.frigo", in: app)
        XCTAssertTrue(space.appears(timeout: 10))
        if isUnfoldedDuoLandscape(app) {
            XCTAssertLessThanOrEqual(allRecipes.frame.maxX, Self.hingeBand.lowerBound + 1, "The recipe column reaches the hinge")
            XCTAssertGreaterThanOrEqual(space.frame.minX, Self.hingeBand.upperBound - 1, "The inventory column starts under the hinge")
        } else if isRegular(app), app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height {
            XCTAssertLessThan(allRecipes.frame.maxX, space.frame.minX, "iPad landscape columns overlap")
        }
        keepShot(app, "k-food-hub-\(layout)")
    }

    /// Grids keep every tile off the hinge band on the unfolded Duo: Security's door tiles.
    func testSecurityDoorTilesStayOffTheHinge() throws {
        let app = gallery("security")
        XCTAssertTrue(element("security.scroll", in: app).appears(timeout: 30), "Security did not open")
        guard isUnfoldedDuoLandscape(app) else { return }
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'security.tile.'")).allElementsBoundByIndex
        XCTAssertFalse(tiles.isEmpty, "No door tiles")
        for tile in tiles where tile.exists && tile.frame.width > 0 {
            let frame = tile.frame
            XCTAssertFalse(frame.minX < Self.hingeBand.upperBound - 1 && frame.maxX > Self.hingeBand.lowerBound + 1,
                           "\(tile.identifier) crosses the hinge: \(frame)")
        }
    }

    // MARK: Helpers

    /// Saves a screenshot as an attachment for design review (never committed).
    private func keepShot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
