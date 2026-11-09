import XCTest

/// Household Settings pages (Admin, Special Device Modes, Guest Controls, Car). Controls are exercised in the
/// debug gallery (`FENTON_GALLERY=household-settings`) on fixture state with a recording caller, so no journey
/// switches anything in the house; the signed-in journey only opens the live pages and audits them.
@MainActor
final class HouseholdSettingsJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// Opens the gallery on `page` (`admin`, `specialDeviceModes`, `guests`, "car"). Goes through app reuse (`startApp`): the gallery
    /// builds its store and recording caller per gallery, so a reset is a clean page; the AX5 launches carry arguments and so relaunch by
    /// their launch signature (`.agents/testing/apple/app-reuse.md`).
    private func launch(_ page: String, unavailable: Bool = false, arguments: [String] = [], clean: Bool = false) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "household-settings"
        configured.launchEnvironment["FENTON_GALLERY_HOUSEHOLD"] = page
        if unavailable { configured.launchEnvironment["FENTON_GALLERY_UNAVAILABLE"] = "1" }
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.descendants(matching: .any)["household.\(page)"].appears(timeout: FentonHomeApp.launchWait()), "\(page) page did not open")
        return app
    }

    /// A tile by entity id.
    private func tile(_ app: XCUIApplication, _ entityId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "household.tile.\(entityId)").firstMatch
    }

    /// Scrolls the page until `element` can be tapped. One snapshot of the element (and one of the gallery's last-call bar) per drag;
    /// `isHittable` is asked only once the frame is clear of the bar. Stops after 3 drags that do not move the element (a row at the foot
    /// of a short page can never come clear), as in `RoomsJourneyTestCase.reveal`.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scroller: XCUIElement? = nil) -> XCUIElement {
        let scroll = scroller ?? app.scrollViews.firstMatch
        // The gallery's last-call bar covers the bottom of the page, and a tile under it still reads as hittable.
        let bar = lastCall(app)
        var lastMinY: CGFloat?
        var stuck = 0
        var swiped = false
        for _ in 0..<12 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty {
                let barTop = (try? bar.snapshot())?.frame.minY
                if frame.maxY <= (barTop ?? .greatestFiniteMagnitude), element.isHittable { break }
                if let lastMinY, abs(frame.minY - lastMinY) < 1 { stuck += 1 } else { stuck = 0 }
                if stuck >= 3 { break }
                lastMinY = frame.minY
            }
            scroll.swipeUp(velocity: .slow)
            swiped = true
        }
        // A tap during scroll momentum only stops the scroll, so wait until the frame holds still.
        if swiped {
            var previous = (try? element.snapshot())?.frame
            let end = Date().addingTimeInterval(2)
            while Date() < end {
                let now = (try? element.snapshot())?.frame
                if now == previous { break }
                previous = now
            }
        }
        return element
    }

    /// Waits until the element's accessibility value is `text`.
    private func waitForValue(_ element: XCUIElement, _ text: String, timeout: TimeInterval = 6) -> Bool {
        let predicate = NSPredicate(format: "value == %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func lastCall(_ app: XCUIApplication) -> XCUIElement { app.staticTexts["gallery.lastCall"] }

    private func expectLastCall(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(lastCall(app).wait(for: \.label, toEqual: "Last call: \(text)", timeout: 6),
                      "Last call was \(lastCall(app).label)", file: file, line: line)
    }

    /// Back: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Back from the presence detail to the room grid. Prefers the detail's own bar: with the sheet over the
    /// page, the first `BackButton` can be the page's (behind the sheet) on the unfolded iPhone Duo.
    private func backFromPresenceDetail(_ app: XCUIApplication) {
        // The detail's bar is titled with the room and carries the sheet's Done; the grid's is the sheet title.
        let bar = app.navigationBars.containing(.button, identifier: "household.sheet.done")
            .matching(NSPredicate(format: "identifier != 'Presence-Based Overrides'")).firstMatch
        // The detail's bar also carries the sheet's Done, which closes the whole sheet: never pick that.
        let back = bar.buttons.matching(NSPredicate(format: "identifier != 'household.sheet.done'")).firstMatch
        if back.exists, back.isHittable { back.tap() } else { goBack(app) }
    }

    /// Opens one of the Admin sheets.
    private func openSheet(_ app: XCUIApplication, _ sheet: String) {
        let opener = reveal(app.buttons["admin.open.\(sheet)"], in: app)
        opener.tap()
        let done = app.buttons["household.sheet.done"]
        // A loaded host can drop the first tap; tap once more if the sheet hasn't started presenting.
        if !done.appears(timeout: 6), opener.isHittable { opener.tap() }
        XCTAssertTrue(done.appears(timeout: 6), "\(sheet) sheet did not open")
        settleScreen() // Let the sheet finish presenting.
    }

    // MARK: - Admin

    func testAdminTogglesSendExplicitOnOff() {
        let app = launch("admin")
        let autoLock = tile(app, expectations[.householdAutoLock])
        XCTAssertTrue(autoLock.appears(timeout: 5))
        XCTAssertEqual(autoLock.value as? String, "On")
        XCTAssertGreaterThanOrEqual(autoLock.frame.height, 44)
        autoLock.tapCenter()
        expectLastCall(app, "input_boolean.turn_off entity_id=\(expectations[.householdAutoLock])")
        XCTAssertTrue(waitForValue(autoLock, "Off"), "autoLock value is \(autoLock.value ?? "nil")")

        let faucets = reveal(tile(app, expectations[.householdOutdoorFaucets]), in: app)
        XCTAssertEqual(faucets.value as? String, "Off")
        faucets.tapCenter()
        expectLastCall(app, "input_boolean.turn_on entity_id=\(expectations[.householdOutdoorFaucets])")
    }

    func testPowerRecoveryTriggersTheAutomation() {
        let app = launch("admin")
        // An action tile (audit item 21): the body and its bolt disc both run the automation; the tile is one button.
        let recovery = reveal(app.buttons["admin.powerRecovery"], in: app)
        XCTAssertGreaterThanOrEqual(recovery.frame.height, 44)
        recovery.tap()
        expectLastCall(app, "automation.trigger entity_id=\(expectations[.householdPowerRecoveryAutomation])")
    }

    /// Fixtures start with Relay Control Mode and Guest Room guest mode on, so the warning shows until relay mode is off.
    func testRelayWarningFollowsRelayModeAndGuestRoom() {
        let app = launch("admin")
        let warning = app.descendants(matching: .any)["admin.relayWarning"]
        XCTAssertTrue(warning.appears(timeout: 5), "Relay warning missing")
        // Reveal the tile itself: revealing the warning below it can leave the tile under the bar on the
        // folded iPhone Duo, where a tap misses (flaky, 2026-10-12).
        let relay = reveal(tile(app, expectations[.householdRelayControl]), in: app)
        XCTAssertTrue(waitForValue(relay, "On"), "relay value is \(relay.value ?? "nil")")
        relay.tapCenter()
        expectLastCall(app, "input_boolean.turn_off entity_id=\(expectations[.householdRelayControl])")
        XCTAssertTrue(warning.disappears(timeout: 3), "Relay warning stayed after relay mode turned off")
    }

    func testPresenceOverrideSetsTheRoomMode() {
        let app = launch("admin")
        openSheet(app, "presenceOverrides")
        let livingRoom = app.buttons["presence.room.\(expectations[.householdFirstPresence])"]
        XCTAssertTrue(livingRoom.appears(timeout: 5))
        XCTAssertEqual(livingRoom.value as? String, "Enabled")
        // An unavailable room still opens (its detail disables the choices); see testUnavailableEntitiesDisableTheirControls.
        let upperDeck = app.buttons["presence.room.\(expectations[.householdUnavailablePresence])"]
        XCTAssertEqual(upperDeck.value as? String, "Unavailable")
        XCTAssertTrue(upperDeck.isEnabled, "An unavailable room should still open")
        livingRoom.tap()
        let paused = app.buttons["presence.option.paused"]
        XCTAssertTrue(paused.appears(timeout: 5))
        XCTAssertTrue(app.buttons["presence.option.enabled"].isSelected)
        paused.tap()
        XCTAssertTrue(paused.isSelected, "Paused not shown at once")
        settleScreen() // The recorder echoes after 400 ms; the live value must keep it selected.
        XCTAssertTrue(paused.isSelected)
        XCTAssertFalse(app.buttons["presence.option.enabled"].isSelected)
        backFromPresenceDetail(app)
        XCTAssertTrue(waitForValue(livingRoom, "Paused"), "livingRoom value is \(livingRoom.value ?? "nil")")
        app.buttons["household.sheet.done"].tap()
        expectLastCall(app, "presence_based_lighting.set_automation_state entity_id=\(expectations[.householdFirstPresence]) state=paused")
    }

    func testAutoResetSheetToggles() {
        let app = launch("admin")
        openSheet(app, "autoReset")
        let kitchen = tile(app, expectations[.householdKitchenAutoReenable])
        XCTAssertTrue(kitchen.appears(timeout: 5))
        XCTAssertEqual(kitchen.value as? String, "On")
        kitchen.tapCenter()
        XCTAssertTrue(waitForValue(kitchen, "Off"), "kitchen value is \(kitchen.value ?? "nil")")
        app.buttons["household.sheet.done"].tap()
        expectLastCall(app, "switch.turn_off entity_id=\(expectations[.householdKitchenAutoReenable])")
    }

    // MARK: - Other pages

    func testSpecialDeviceModesTogglesHighAqi() {
        let app = launch("specialDeviceModes")
        let aqi = tile(app, expectations[.householdHighAqi])
        XCTAssertTrue(aqi.appears(timeout: 5))
        XCTAssertEqual(aqi.value as? String, "Off")
        aqi.tapCenter()
        // Every purifier changes at once, so the flip asks first (`AlertCopy.highAqiMode`).
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5), "High AQI Mode asks before it flips")
        XCTAssertTrue(app.alerts.staticTexts["This changes every air purifier in the house."].exists)
        app.alerts.buttons["household.tile.\(expectations[.householdHighAqi]).confirm"].firstMatch.tap()
        expectLastCall(app, "input_boolean.turn_on entity_id=\(expectations[.householdHighAqi])")
        XCTAssertTrue(waitForValue(aqi, "On"), "aqi value is \(aqi.value ?? "nil")")
    }

    /// Cancel on the High AQI question sends nothing (the tile's confirmation, audit item 14), and the body asks again.
    func testSpecialDeviceModesHighAqiCancelSendsNothing() {
        let app = launch("specialDeviceModes")
        let aqi = tile(app, expectations[.householdHighAqi])
        XCTAssertTrue(aqi.appears(timeout: 5))
        aqi.tapCenter()
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5), "High AQI Mode asks before it flips")
        XCTAssertEqual(lastCall(app).label, "Last call: None")
        app.alerts.buttons["household.tile.\(expectations[.householdHighAqi]).cancel"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(lastCall(app).label, "Last call: None", "Cancel sent \(lastCall(app).label)")
        XCTAssertEqual(aqi.value as? String, "Off")
        aqi.tapCenter()
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5), "High AQI Mode asks again")
    }

    /// Guest Controls are action tiles like the Home page's (ids `guest.tile.<entity>`, "Guests staying" / "No guests").
    func testGuestControlsToggleEachRoom() {
        let app = launch("guests")
        func guest(_ entityId: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "guest.tile.\(entityId)").firstMatch }
        let guests = [expectations[.householdGuestFirst], expectations[.householdGuestSecond], expectations[.householdGuestThird]]
        for id in guests {
            XCTAssertTrue(guest(id).appears(timeout: 5), id)
        }
        XCTAssertEqual(guest(guests[0]).value as? String, "Guests staying")
        XCTAssertEqual(guest(guests[1]).value as? String, "No guests")
        guest(guests[1]).tapCenter()
        expectLastCall(app, "input_boolean.turn_on entity_id=\(guests[1])")
        XCTAssertTrue(waitForValue(guest(guests[1]), "Guests staying"), "second guest value is \(guest(guests[1]).value ?? "nil")")
    }

    /// The Car readings stay unpressable: Charge Status is no button (audit item 25).
    func testVehicleReadingsStayReadOnly() {
        let app = launch("car")
        let doors = tile(app, expectations[.householdVehicleDoors])
        XCTAssertTrue(doors.appears(timeout: 5))
        XCTAssertFalse(app.buttons["household.tile.\(expectations[.householdVehicleCharge])"].exists, "Charge Status must not be a button")
        XCTAssertEqual(tile(app, expectations[.householdVehicleCharge]).value as? String, "ChargingAC")
    }

    /// Doors is the one action tile (audit item 25: the lock disc): a switch (its disc is toggle-styled) that unlocks.
    func testVehicleDoorsActs() {
        let app = launch("car")
        let doorsID = "household.tile.\(expectations[.householdVehicleDoors])"
        let doors = tile(app, expectations[.householdVehicleDoors])
        XCTAssertTrue(doors.appears(timeout: 5))
        XCTAssertEqual(doors.value as? String, "Locked")
        // The lock disc is toggle-styled (isOn = unlocked), so the tile reads as a switch: Unlock/Lock flips it.
        XCTAssertTrue(app.switches[doorsID].exists, "Doors is a switch")
        XCTAssertGreaterThanOrEqual(doors.frame.height, 44)
        doors.tapCenter()
        expectLastCall(app, "lock.unlock entity_id=\(expectations[.householdVehicleDoors])")
        XCTAssertTrue(waitForValue(doors, "Unlocked"), "doors value is \(doors.value ?? "nil")")
    }

    /// An unavailable tile reads Unavailable and is disabled. Step 1 of the split journey (`testUnavailableEntities*`).
    func testUnavailableEntitiesAdminTile() {
        let app = launch("admin", unavailable: true)
        let autoLock = tile(app, expectations[.householdAutoLock])
        XCTAssertTrue(autoLock.appears(timeout: 5))
        XCTAssertEqual(autoLock.value as? String, "Unavailable")
        XCTAssertFalse(autoLock.isEnabled)
    }

    /// An unavailable room opens so it can say why; its choices are disabled and nothing is sent. Step 2.
    func testUnavailableEntitiesPresenceDetail() {
        let app = launch("admin", unavailable: true)
        openSheet(app, "presenceOverrides")
        let kitchen = app.buttons["presence.room.\(expectations[.householdKitchenPresence])"]
        XCTAssertTrue(kitchen.appears(timeout: 5))
        XCTAssertEqual(kitchen.value as? String, "Unavailable")
        kitchen.tap()
        let enabled = app.buttons["presence.option.enabled"]
        XCTAssertTrue(enabled.appears(timeout: 5))
        for mode in ["enabled", "off", "paused", "quieted"] {
            XCTAssertFalse(app.buttons["presence.option.\(mode)"].isEnabled, "\(mode) should be disabled")
        }
        app.buttons["household.sheet.done"].firstMatch.tap()
        XCTAssertTrue(enabled.disappears(timeout: 5), "Done on the detail should close the sheet")
        XCTAssertFalse(lastCall(app).label.contains("set_automation_state"), "An unavailable room sent \(lastCall(app).label)")
    }

    // MARK: - Audits and screenshots

    /// Opens the presence detail of the kitchen room (the audited state of the detail step).
    private func openPresenceDetail(_ app: XCUIApplication) {
        openSheet(app, "presenceOverrides")
        app.buttons["presence.room.\(expectations[.householdKitchenPresence])"].tap()
        XCTAssertTrue(app.buttons["presence.option.enabled"].appears(timeout: 5))
    }

    /// Full audit (with the AX5 relaunch) of one page. One test per page, sheet and the presence detail
    /// (`testHousehold*PassesAccessibilityAudit`).
    private func auditPage(_ page: String) throws {
        let app = launch(page, clean: true)
        try FentonHomeApp.audit(app) { self.launch(page, arguments: FentonHomeApp.ax5, clean: true) }
    }

    /// Full audit of one Admin sheet.
    private func auditAdminSheet(_ sheet: String) throws {
        let app = launch("admin", clean: true)
        openSheet(app, sheet)
        try FentonHomeApp.audit(app) {
            let large = self.launch("admin", arguments: FentonHomeApp.ax5, clean: true)
            self.openSheet(large, sheet)
            return large
        }
    }

    func testHouseholdAdminPassesAccessibilityAudit() throws { try auditPage("admin") }
    func testHouseholdSpecialDeviceModesPassesAccessibilityAudit() throws { try auditPage("specialDeviceModes") }
    func testHouseholdGuestsPassesAccessibilityAudit() throws { try auditPage("guests") }
    func testHouseholdVehiclePassesAccessibilityAudit() throws { try auditPage("car") }
    func testHouseholdPresenceOverridesSheetPassesAccessibilityAudit() throws { try auditAdminSheet("presenceOverrides") }
    func testHouseholdAutoResetSheetPassesAccessibilityAudit() throws { try auditAdminSheet("autoReset") }

    func testHouseholdPresenceDetailPassesAccessibilityAudit() throws {
        let app = launch("admin", clean: true)
        openPresenceDetail(app)
        // With the AX5 page, "may be clipped" is checked against the text at AX5 like the sheets above; without it the
        // folded Duo's two-line option titles could not be disproved (2026-10-14).
        try FentonHomeApp.audit(app) {
            let large = self.launch("admin", arguments: FentonHomeApp.ax5, clean: true)
            self.openPresenceDetail(large)
            return large
        }
    }

    /// How a capture test is posed. `.upright` is the device's own portrait pose (iPad is turned to portrait first);
    /// `.iPadLandscape` turns an iPad to landscape and skips elsewhere. Only iPad rotates here; setting the orientation on an
    /// unfolded Duo hangs the runner (devices.md).
    private enum Pose { case upright, iPadLandscape }

    /// Poses the device, launches `page` clean and hands the app to `body`, then restores portrait on iPad.
    private func capture(pose: Pose, page: String = "admin", _ body: (XCUIApplication) -> Void) throws {
        if pose == .iPadLandscape { guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad landscape only") } }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = pose == .iPadLandscape ? .landscapeLeft : .portrait }
        defer { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } }
        body(launch(page, clean: true))
    }

    private func suffix(_ pose: Pose) -> String {
        pose == .iPadLandscape ? "landscape" : FentonHomeApp.family == .iPad ? "portrait" : "current"
    }

    private func capturePage(_ page: String, pose: Pose) throws {
        try capture(pose: pose, page: page) { app in
            settleScreen()
            keepScreenshot(app, "\(page)-\(suffix(pose))")
        }
    }

    private func captureAdminLower(pose: Pose) throws {
        try capture(pose: pose) { app in
            reveal(app.descendants(matching: .any)["admin.relayWarning"], in: app)
            keepScreenshot(app, "admin-lower-\(suffix(pose))")
        }
    }

    private func capturePresenceOverrides(pose: Pose) throws {
        try capture(pose: pose) { app in
            openSheet(app, "presenceOverrides")
            keepScreenshot(app, "presence-overrides-\(suffix(pose))")
        }
    }

    private func capturePresenceDetail(pose: Pose) throws {
        try capture(pose: pose) { app in
            openSheet(app, "presenceOverrides")
            app.buttons["presence.room.switch.demo_hallway_presence_2"].tap()
            XCTAssertTrue(app.buttons["presence.option.enabled"].appears(timeout: 5))
            settleScreen()
            keepScreenshot(app, "presence-detail-\(suffix(pose))")
            backFromPresenceDetail(app) // Back to the grid.
            XCTAssertTrue(app.buttons["household.sheet.done"].firstMatch.appears(timeout: 5))
        }
    }

    private func captureAutoReset(pose: Pose) throws {
        try capture(pose: pose) { app in
            openSheet(app, "autoReset")
            keepScreenshot(app, "auto-reset-\(suffix(pose))")
        }
    }

    // Screenshots of each page, sheet and the presence detail, one test per screen (`testCaptureHousehold*`); each has an
    // `InIPadLandscape` twin that skips off iPad.
    func testCaptureHouseholdAdmin() throws { try capturePage("admin", pose: .upright) }
    func testCaptureHouseholdAdminInIPadLandscape() throws { try capturePage("admin", pose: .iPadLandscape) }
    func testCaptureHouseholdSpecialDeviceModes() throws { try capturePage("specialDeviceModes", pose: .upright) }
    func testCaptureHouseholdSpecialDeviceModesInIPadLandscape() throws { try capturePage("specialDeviceModes", pose: .iPadLandscape) }
    func testCaptureHouseholdGuests() throws { try capturePage("guests", pose: .upright) }
    func testCaptureHouseholdGuestsInIPadLandscape() throws { try capturePage("guests", pose: .iPadLandscape) }
    func testCaptureHouseholdVehicle() throws { try capturePage("car", pose: .upright) }
    func testCaptureHouseholdVehicleInIPadLandscape() throws { try capturePage("car", pose: .iPadLandscape) }
    func testCaptureHouseholdAdminLower() throws { try captureAdminLower(pose: .upright) }
    func testCaptureHouseholdAdminLowerInIPadLandscape() throws { try captureAdminLower(pose: .iPadLandscape) }
    func testCaptureHouseholdPresenceOverrides() throws { try capturePresenceOverrides(pose: .upright) }
    func testCaptureHouseholdPresenceOverridesInIPadLandscape() throws { try capturePresenceOverrides(pose: .iPadLandscape) }
    func testCaptureHouseholdPresenceDetail() throws { try capturePresenceDetail(pose: .upright) }
    func testCaptureHouseholdPresenceDetailInIPadLandscape() throws { try capturePresenceDetail(pose: .iPadLandscape) }
    func testCaptureHouseholdAutoReset() throws { try captureAutoReset(pose: .upright) }
    func testCaptureHouseholdAutoResetInIPadLandscape() throws { try captureAutoReset(pose: .iPadLandscape) }

    // MARK: - Live

    /// The Settings tab lists the household rows and each opens its live page (`testLiveSettingsRowOpens*`). Read-only: nothing
    /// is tapped inside the pages, so the house is never switched.
    private func openLiveRow(_ page: String) throws -> XCUIApplication {
        let app = try FentonHomeApp.launchSignedIn()
        showSettingsTab(app)
        let row = app.buttons["settings.topic.\(page)"]
        app.revealSettingsRow(row)
        XCTAssertTrue(row.appears(timeout: 5), "\(page) row missing")
        XCTAssertGreaterThanOrEqual(row.frame.height, 43)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["household.\(page)"].appears(timeout: 10), "\(page) did not open")
        return app
    }

    func testLiveSettingsRowOpensSpecialDeviceModes() throws { _ = try openLiveRow("specialDeviceModes") }
    func testLiveSettingsRowOpensGuests() throws { _ = try openLiveRow("guests") }
    func testLiveSettingsRowOpensVehicle() throws { _ = try openLiveRow("car") }

    /// Admin: the live state loads, then the page is audited (the audit relaunches at AX5 for the Dynamic Type check).
    func testLiveSettingsRowOpensAdminAndAudit() throws {
        // The Admin tile ids are the house's own: DemoHouse on the test instance, the private file on the owner's house (else a skip).
        let autoLock = try JourneyExpectations.current(for: .signedIn).value(.householdAutoLock)
        let app = try openLiveRow("admin")
        XCTAssertTrue(waitForLiveAdmin(app, autoLock: autoLock), "Live state did not load")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSettingsTab(large)
            self.reveal(large.buttons["settings.topic.admin"], in: large, scroller: large.settingsList).tap()
            XCTAssertTrue(self.waitForLiveAdmin(large, autoLock: autoLock), "Live state did not load at AX5")
            return large
        }
    }

    /// Goes to Settings: the profile avatar's Account sheet (direction G).
    private func showSettingsTab(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// Waits for the live Admin page's first tile to show a real state.
    private func waitForLiveAdmin(_ app: XCUIApplication, autoLock entityId: String) -> Bool {
        let autoLock = tile(app, entityId)
        return autoLock.appears(timeout: 15) && autoLock.value as? String != "Unavailable"
    }
}

private extension XCUIElement {
    /// Taps the middle of a toggle tile. Plain `tap()` on these switch-type elements often didn't reach the
    /// tile on the iPhone Duo (iOS 27.1) while button tiles were fine; the tile takes taps anywhere.
    func tapCenter() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
