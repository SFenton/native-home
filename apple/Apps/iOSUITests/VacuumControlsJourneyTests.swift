import XCTest

/// The Controls section with the map above it: the status tiles, cleaning settings and the Water and Fan rows that follow the Mode, the Use Area
/// and area-mode tiles, the run tiles, the area editor, the error, resumable and unavailable scenarios, the audits of the docked, error, cleaning,
/// area and Vacuum-mode states and Controls at the largest text size.
@MainActor
final class VacuumControlsJourneyTests: VacuumJourneyTestCase {
    /// Every setting is the same pop-up row (Mode, Fan, Water, Passes): the value opens a menu and picking sends select_option
    /// (direction G, Controls: Choosing one option; owner, 2026-10-28).
    func testPowerSettings() {
        let app = launch(Self.musicRoom)
        let mode = element("vacuum.setting.Mode", in: app)
        reveal(mode, in: app)
        assertTarget(mode)
        let modeReading = "\(mode.label) \(mode.value as? String ?? "")"
        XCTAssertTrue(modeReading.contains("Mode") && modeReading.contains("Vacuum"), modeReading)
        mode.tap()
        let vacuum = app.buttons["Vacuum"].firstMatch
        XCTAssertTrue(vacuum.appears(timeout: 5), "The Mode menu did not open")
        vacuum.tap()
        expectCall("select.select_option entity_id=\(expectations[.vacuumSecondaryModeSelect]) option=vacuum", in: app)

        let fanPicker = element("vacuum.setting.Fan", in: app)
        reveal(fanPicker, in: app)
        assertTarget(fanPicker)
        // A menu picker reads its name and value together ("Fan, Medium").
        let reading = "\(fanPicker.label) \(fanPicker.value as? String ?? "")"
        XCTAssertTrue(reading.contains("Fan") && reading.contains("Medium"), reading)
        fanPicker.tap()
        let turbo = app.buttons["Turbo"].firstMatch
        XCTAssertTrue(turbo.appears(timeout: 5), "The Fan menu did not open")
        // Only the value is the menu's source, so the row stays on screen while the menu is open (owner report:
        // the whole row used to vanish).
        XCTAssertTrue(element("vacuum.setting.Fan", in: app).exists)
        keepScreenshot(app, "vacuums-setting-menu")
        turbo.tap()
        expectCall("select.select_option entity_id=\(expectations[.vacuumSecondaryFanSelect]) option=turbo", in: app)

        let passes = element("vacuum.setting.Passes", in: app)
        reveal(passes, in: app)
        assertTarget(passes)
        XCTAssertTrue("\(passes.label) \(passes.value as? String ?? "")".contains("1x"), passes.label)
    }

    // MARK: Water and Fan follow the Mode

    /// Mode "Vacuum and Mop" shows both the Water and Fan rows.
    func testControlsWaterFanBothForVacuumAndMop() {
        let app = launch(Self.musicRoom)
        reveal(element("vacuum.setting.Mode", in: app), in: app)
        XCTAssertTrue(element("vacuum.setting.Water", in: app).exists && element("vacuum.setting.Fan", in: app).exists, "Vacuum and Mop shows both")
    }

    /// Choosing Vacuum takes the Water row away (the row animates with `standard`); Fan stays and Passes slides up under it.
    func testControlsWaterFanVacuumHidesWater() {
        let app = launch(Self.musicRoom)
        chooseMode("Vacuum", in: app)
        waitGone("vacuum.setting.Water", in: app)
        XCTAssertTrue(element("vacuum.setting.Fan", in: app).exists, "Fan stays for Vacuum")
        XCTAssertTrue(element("vacuum.setting.Passes", in: app).exists, "Passes slides up under Fan")
        // Settled: the rows below are still where a tap lands.
        let passes = element("vacuum.setting.Passes", in: app)
        reveal(passes, in: app)
        assertTarget(passes)
    }

    /// Choosing Mop takes the Fan row away; Water stays.
    func testControlsWaterFanMopHidesFan() {
        let app = launch(Self.musicRoom)
        chooseMode("Mop", in: app)
        waitGone("vacuum.setting.Fan", in: app)
        XCTAssertTrue(element("vacuum.setting.Water", in: app).exists, "Water stays for Mop")
    }

    /// From Vacuum (no Water row), choosing Vacuum and Mop brings Water back.
    func testControlsWaterFanVacuumAndMopReturnsWater() {
        let app = launch(Self.mainFloor, scenario: "modeVacuum")
        XCTAssertFalse(element("vacuum.setting.Water", in: app).exists, "Vacuum mode starts without Water")
        chooseMode("Vacuum and Mop", in: app)
        XCTAssertTrue(element("vacuum.setting.Water", in: app).appears(timeout: 5), "Water returns for Vacuum and Mop")
        XCTAssertTrue(element("vacuum.setting.Fan", in: app).exists)
    }

    /// From Mop (no Fan row), choosing Vacuum and Mop brings Fan back (Water stays).
    func testControlsWaterFanMopToVacuumAndMopReturnsFan() {
        let app = launch(Self.mainFloor, scenario: "modeMop")
        XCTAssertFalse(element("vacuum.setting.Fan", in: app).exists, "Mop mode starts without Fan")
        XCTAssertTrue(element("vacuum.setting.Water", in: app).exists, "Mop mode keeps Water")
        chooseMode("Vacuum and Mop", in: app)
        XCTAssertTrue(element("vacuum.setting.Fan", in: app).appears(timeout: 5), "Fan returns when leaving Mop")
        XCTAssertTrue(element("vacuum.setting.Water", in: app).exists)
    }

    /// From Vacuum (no Water row), choosing Mop brings Water back and takes Fan away.
    func testControlsWaterFanVacuumToMopReturnsWater() {
        let app = launch(Self.mainFloor, scenario: "modeVacuum")
        XCTAssertFalse(element("vacuum.setting.Water", in: app).exists, "Vacuum mode starts without Water")
        chooseMode("Mop", in: app)
        XCTAssertTrue(element("vacuum.setting.Water", in: app).appears(timeout: 5), "Water returns on Vacuum to Mop")
        waitGone("vacuum.setting.Fan", in: app)
    }

    private func chooseMode(_ title: String, in app: XCUIApplication) {
        let mode = element("vacuum.setting.Mode", in: app)
        reveal(mode, in: app)
        mode.tap()
        let item = app.buttons[title].firstMatch
        XCTAssertTrue(item.appears(timeout: 5), "No \(title) in the Mode menu")
        item.tap()
    }

    private func waitGone(_ id: String, in app: XCUIApplication) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(id, in: app))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "\(id) is still there")
    }

    // MARK: Status and target tiles

    /// Status, Battery and Dock are three read-only tiles of one size.
    func testControlsStatusTilesAreEqual() {
        let app = launch(Self.mainFloor)
        let tiles = ["vacuum.status", "vacuum.status.battery", "vacuum.status.dock"].map { element($0, in: app) }
        for tile in tiles { XCTAssertTrue(tile.appears(timeout: 10), "No \(tile.identifier) tile") }
        XCTAssertEqual(tiles[0].label, "Status")
        XCTAssertEqual(tiles[0].value as? String, "Docked")
        XCTAssertEqual(tiles[1].label, "Battery")
        XCTAssertEqual(tiles[1].value as? String, "87%")
        XCTAssertEqual(tiles[2].label, "Dock")
        XCTAssertEqual(tiles[2].value as? String, "Idle")
        let widths = tiles.map { $0.frame.width }, heights = tiles.map { $0.frame.height }
        XCTAssertEqual(widths[0], widths[1], accuracy: 1, "Equal widths: \(widths)")
        XCTAssertEqual(widths[1], widths[2], accuracy: 1, "Equal widths: \(widths)")
        XCTAssertEqual(heights[0], heights[2], accuracy: 1, "Equal heights: \(heights)")
        XCTAssertLessThan(tiles[0].frame.maxX, tiles[1].frame.minX + 2, "Reading order is left to right")
        XCTAssertLessThan(tiles[1].frame.maxX, tiles[2].frame.minX + 2)
        XCTAssertFalse(tiles[0].buttons.firstMatch.exists, "Read-only: no control inside")
    }

    /// At accessibility sizes the status tiles stack in one column, in reading order.
    func testControlsStatusTilesStackAtLargestText() {
        let app = launch(Self.mainFloor, arguments: FentonHomeApp.ax5)
        let tiles = ["vacuum.status", "vacuum.status.battery", "vacuum.status.dock"].map { element($0, in: app) }
        XCTAssertTrue(tiles[0].appears(timeout: 10))
        XCTAssertEqual(tiles[0].frame.minX, tiles[1].frame.minX, accuracy: 1, "One column")
        XCTAssertEqual(tiles[0].frame.width, tiles[2].frame.width, accuracy: 1)
        XCTAssertLessThan(tiles[0].frame.minY, tiles[1].frame.minY, "Status, then Battery, then Dock")
        XCTAssertLessThan(tiles[1].frame.minY, tiles[2].frame.minY)
    }

    /// Rooms mode: Selected Rooms summary and a Use Area action tile; no segmented control.
    func testControlsOfferUseAreaTile() {
        let app = launch(Self.mainFloor)
        XCTAssertFalse(element("vacuum.target", in: app).exists, "The Rooms/Area segmented control is gone")
        let summary = element("vacuum.selectedRooms", in: app)
        reveal(summary, in: app)
        XCTAssertEqual(summary.label, "Selected Rooms")
        XCTAssertTrue((summary.value as? String ?? "").contains("1."), summary.value as? String ?? "")
        let area = app.buttons["vacuum.target.area"]
        reveal(area, in: app)
        assertTarget(area)
        XCTAssertEqual(area.label, "Use Area")
        XCTAssertFalse(app.buttons["vacuum.area.edit"].exists, "Edit Area is Area mode only")
        XCTAssertTrue(app.buttons["vacuum.action.clean"].exists, "One Clean button")
    }

    /// Area mode (an area drawn): Edit Area with its size, Clear Area and Use Rooms tiles, and Clean for the area.
    func testControlsAreaModeTiles() {
        let app = launch(Self.mainFloor, scenario: "areaDrawn")
        let edit = app.buttons["vacuum.area.edit"]
        reveal(edit, in: app)
        assertTarget(edit)
        XCTAssertEqual(edit.label, "Edit Area")
        XCTAssertTrue((edit.value as? String ?? "").isEmpty || (edit.value as? String ?? "").contains("m"), "Size as the subtitle: \(edit.value as? String ?? "")")
        let clear = app.buttons["vacuum.area.clearSelection"], rooms = app.buttons["vacuum.target.rooms"]
        reveal(rooms, in: app)
        assertTarget(clear)
        assertTarget(rooms)
        XCTAssertEqual(rooms.label, "Use Rooms")
        XCTAssertFalse(app.buttons["vacuum.target.area"].exists)
        let startArea = app.buttons["vacuum.action.cleanArea"]
        reveal(startArea, in: app)
        XCTAssertEqual(startArea.label, "Clean", "Clean in both modes")
    }

    /// Clear Area returns to Rooms mode.
    func testControlsAreaModeClearReturnsToRooms() {
        let app = launch(Self.mainFloor, scenario: "areaDrawn")
        let clear = app.buttons["vacuum.area.clearSelection"]
        reveal(clear, in: app)
        clear.tap()
        XCTAssertTrue(app.buttons["vacuum.target.area"].appears(timeout: 5), "Clear Area returns to Rooms mode")
    }

    /// A run in progress: Pause and Stop are tiles side by side with no state header and no text under them.
    func testControlsRunTilesSitSideBySide() {
        let app = launch(Self.mainFloor, scenario: "cleaning")
        let pause = app.buttons["vacuum.action.pause"], stop = app.buttons["vacuum.action.stop"]
        XCTAssertTrue(pause.appears(timeout: 10))
        assertTarget(pause)
        assertTarget(stop)
        if FentonHomeApp.family == .iPhone && !app.windows.firstMatch.frame.isEmpty {
            XCTAssertEqual(pause.frame.minY, stop.frame.minY, accuracy: 2, "Side by side")
            XCTAssertLessThan(pause.frame.maxX, stop.frame.minX + 2, "Pause then Stop")
            XCTAssertEqual(pause.frame.width, stop.frame.width, accuracy: 2)
        }
        XCTAssertFalse(app.staticTexts["Pause the current cleaning run."].exists, "No description under the tile")
        XCTAssertTrue(pause.label.contains("Pause"), pause.label)
        XCTAssertEqual(pause.value as? String, "Pause the current cleaning run.", "The reason is the accessibility value")
        XCTAssertFalse(element("vacuum.tabs", in: app).buttons["Rooms"].exists, "Three sections during a run")
        XCTAssertEqual(element("vacuum.status", in: app).value as? String, "Cleaning")
    }

    // MARK: Area editor

    /// The area editor draws a default area for VoiceOver users and Use This Area returns to Controls.
    func testAreaEditor() {
        let app = launch(Self.mainFloor)
        // Use Area is an action tile (owner, 2026-10-28), not a segment.
        let area = app.buttons["vacuum.target.area"]
        reveal(area, in: app, down: true)
        area.tap()
        // The fixture has rooms selected, so Use Area asks before clearing them.
        let confirm = app.buttons["Use Area"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 10), "No Use Area confirmation")
        confirm.tap()
        // Area (after confirming away from the selected rooms) opens the editor directly.
        let draw = app.buttons["vacuum.area.draw"]
        XCTAssertTrue(draw.appears(timeout: 10), "Area did not open the editor")
        // Draw, then drag across the map; the map reads the new size back.
        if !draw.isSelected { draw.tap() }
        let map = element("vacuum.area.map", in: app)
        XCTAssertEqual(map.value as? String, "No area selected")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35))
        start.press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        let drawn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "×"), object: map)
        XCTAssertEqual(XCTWaiter().wait(for: [drawn], timeout: 10), .completed, "Map value is \(map.value ?? "nil")")
        // Scroll from below the map: a drag on the map moves the area instead of the page.
        let use = app.buttons["vacuum.area.use"]
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        for _ in 0..<8 where !use.isHittable {
            let y = max(map.frame.maxY + 24, window.minY + window.height * 0.6)
            guard y < window.maxY - 120 else { break } // No room below the map: let XCTest scroll it into view.
            let from = origin.withOffset(CGVector(dx: window.midX, dy: y))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -200)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        use.tap()
        let startArea = app.buttons["vacuum.action.cleanArea"]
        reveal(startArea, in: app)
        XCTAssertTrue(startArea.isEnabled)
        XCTAssertEqual(startArea.label, "Clean")
        startArea.tap()
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let zone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Last call: \(expectations[.vacuumMainFloorZoneScript]) x_max_cm="), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [zone], timeout: 10), .completed, label.label)
    }

    /// An error shows Stop and Dock.
    func testVacuumScenarioError() {
        let app = launch(Self.mainFloor, scenario: "error")
        XCTAssertTrue(app.buttons["vacuum.action.stop"].appears(timeout: 10))
        XCTAssertTrue(app.buttons["vacuum.action.dock"].exists)
    }

    /// A resumable run shows Resume and Cancel; Cancel stops.
    func testVacuumScenarioResumable() {
        let app = launch(Self.mainFloor, scenario: "resumable")
        XCTAssertTrue(app.buttons["vacuum.action.resume"].appears(timeout: 10))
        let cancel = app.buttons["vacuum.action.cancelResume"]
        reveal(cancel, in: app)
        cancel.tap()
        expectCall("vacuum.stop entity_id=\(expectations[.vacuumMainFloorEntity])", in: app)
    }

    /// An unavailable robot shows the reported map.
    func testVacuumScenarioUnavailable() {
        let app = launch(Self.musicRoom, scenario: "unavailable")
        // An inline alert ("Warning: Last Reported Map: …"), one combined element.
        let notice = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "last reported")).firstMatch
        XCTAssertTrue(notice.appears(timeout: 10))
    }

    /// At AX5 every control stays reachable by scrolling.
    func testLargestTextKeepsControlsReachable() {
        let app = launch(Self.mainFloor, arguments: FentonHomeApp.ax5)
        reveal(app.buttons["vacuum.action.clean"], in: app)
    }

    func testControlsPassAudit() throws { try audit(Self.mainFloor) }
    func testControlsPassAuditInIPadLandscape() throws { try audit(Self.mainFloor, pose: .iPadLandscape) }

    func testErrorPassesAudit() throws { try audit(Self.mainFloor, scenario: "error") }
    func testErrorPassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, scenario: "error", pose: .iPadLandscape) }

    func testCleaningPassesAudit() throws { try audit(Self.mainFloor, scenario: "cleaning") }
    func testCleaningPassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, scenario: "cleaning", pose: .iPadLandscape) }

    func testAreaModePassesAudit() throws { try audit(Self.mainFloor, scenario: "areaDrawn") }
    func testAreaModePassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, scenario: "areaDrawn", pose: .iPadLandscape) }

    func testVacuumModeHidesWaterAndPassesAudit() throws { try audit(Self.mainFloor, scenario: "modeVacuum") }
    func testVacuumModeHidesWaterAndPassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, scenario: "modeVacuum", pose: .iPadLandscape) }
}
