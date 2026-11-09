import XCTest

/// The Media, Custom Lights and Sprinklers pages in the debug gallery (fixture state, recording service caller;
/// nothing reaches the house): what each control sends, sheets and pushes, accessibility audits with the AX5
/// relaunch, and screenshots on iPhone, iPhone Duo and iPad. Specs: `.agents/pages/{media,custom-lights,sprinklers}`.
@MainActor
final class HomePagesJourneyTests: JourneyTestCase {
    /// The next `launch` adds the AX5 text size (the audit's relaunch).
    private var nextLaunchIsAX5 = false


    // MARK: - Helpers

    private func launch(_ page: String, _ environment: [String: String] = [:], arguments: [String] = [],
                        waitFor id: String) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = page
        app.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        if nextLaunchIsAX5 {
            app.launchArguments += FentonHomeApp.ax5
            nextLaunchIsAX5 = false
        }
        // Through `startApp`: with reuse on the class keeps one resident app, reset per test (`app-reuse.md`). The gallery builds its
        // fixtures and recording caller per gallery, so nothing survives a reset. AX5 launches (the audit's relaunch) are fresh by signature.
        return finishLaunch(startApp(app), id)
    }

    private func finishLaunch(_ app: XCUIApplication, _ id: String) -> XCUIApplication {
        let ready = element(id, in: app)
        XCTAssertTrue(ready.appears(timeout: 30), "\(id) did not appear")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(id) not reachable")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls the page in short drags until `element` is in view: hittable and clear of the navigation bar (a card scrolled under the
    /// bar reports hittable, but a tap there lands on the bar; seen on the folded iPhone Duo). Full swipes overshoot at AX5 and on the
    /// Duo. One snapshot per drag answers "in the tree" and "where"; `isHittable` is read only once the frame is on screen, and the
    /// scroll stops when a drag no longer moves the element (the foot of the page).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<20 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty, element.isHittable {
                let bar = app.navigationBars.firstMatch
                if !bar.exists || frame.midY > bar.frame.maxY { break }
            }
            if let frame, let lastMinY, abs(lastMinY - frame.minY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 2 { break }
            lastMinY = frame?.minY
            let above = frame.map { !$0.isEmpty && $0.midY < window.midY } ?? false
            var x = window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: 10), "\(id) missing")
        reveal(target, in: app)
        target.tap()
    }

    /// Taps a navigation tile's body, clear of its discs: the tile's middle can be the transport or the volume slider.
    private func tapBody(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: 10), "\(id) missing")
        reveal(target, in: app)
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
    }

    /// Flips a `Form` toggle: XCUITest taps a row's middle, which lands on its label and leaves the switch alone.
    private func flip(_ id: String, in app: XCUIApplication) {
        let row = app.switches[id].firstMatch
        XCTAssertTrue(row.appears(timeout: 10), "\(id) missing")
        reveal(row, in: app)
        let knob = row.switches.firstMatch
        if knob.exists { knob.tap() } else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }

    private func assertTarget(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let frame = (try? element(id, in: app).snapshot())?.frame ?? .zero
        XCTAssertGreaterThanOrEqual(frame.width, 43, id, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 43, id, file: file, line: line)
    }

    /// The pose an audit-and-capture test runs in. `upright` is every family's own pose (on iPad it sets portrait
    /// first, so a test never starts in the previous test's landscape); `iPadLandscape` is iPad only.
    private enum Pose {
        case upright, iPadLandscape
        var suffix: String { self == .iPadLandscape ? "landscape" : "portrait" }
    }

    /// Audits (with the AX5 relaunch) and keeps a screenshot in `pose`.
    private func auditAndCapture(_ name: String, pose: Pose = .upright, relaunch: @escaping () -> XCUIApplication) throws {
        if pose == .iPadLandscape { try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only") }
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = pose == .iPadLandscape ? .landscapeLeft : .portrait
            if pose == .iPadLandscape { addTeardownBlock { XCUIDevice.shared.orientation = .portrait } }
            settleScreen()
        }
        let app = relaunch()
        try FentonHomeApp.audit(app) {
            self.nextLaunchIsAX5 = true
            return relaunch()
        }
        keepScreenshot(relaunch(), "\(name)-\(pose.suffix)")
    }

    // MARK: - Media

    private func launchMediaPage() -> XCUIApplication {
        launch("media-page", waitFor: expectations[.mediaLivingRoomCard])
    }

    func testMediaTileXboxSendsScriptAndShowsOn() {
        let app = launchMediaPage()
        let xbox = element(expectations[.mediaConsoleCard], in: app)
        XCTAssertFalse(xbox.isSelected, "A source that is not chosen has no check and says nothing")
        tap(expectations[.mediaConsoleCard], in: app)
        expectCall(expectations[.mediaConsoleScript], in: app)
        let shownOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On the TV'"), object: xbox)
        XCTAssertEqual(XCTWaiter().wait(for: [shownOn], timeout: 5), .completed, "The source shows chosen at once")
        XCTAssertTrue(xbox.isSelected, "A chosen source reads selected")
    }

    func testMediaTileSwitchSendsScript() {
        let app = launchMediaPage()
        let switchTile = element(expectations[.mediaHandheldCard], in: app)
        tap(expectations[.mediaHandheldCard], in: app)
        expectCall(expectations[.mediaHandheldScript], in: app)
        // Tracked: the tile waits on the boolean, then settles on the final face once the gallery reports it.
        let switchedOn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: switchTile)
        XCTAssertEqual(XCTWaiter().wait(for: [switchedOn], timeout: 10), .completed, "The Switch settles on On when its boolean reports")
    }

    func testMediaTileTargets() {
        let app = launchMediaPage()
        for id in [expectations[.mediaLivingRoomCard], expectations[.mediaServerCard], expectations[.mediaStreamerCard]] {
            assertTarget(id, in: app)
        }
    }

    func testMediaTileBodyOpensRemote() {
        let app = launchMediaPage()
        tapBody(expectations[.mediaLivingRoomCard], in: app) // The body opens the remote; its discs act.
        XCTAssertTrue(element("remote.power", in: app).appears(timeout: 10), "The Living Room remote opened")
    }

    /// A playing remote's tile: previous / play-pause / next below the text, a volume slider under them (lane 4 of the action
    /// tiles, `.agents/patterns/action-tiles.md`); an off remote keeps Power beside the chevron.
    func testPlayingRemoteTileShowsTransportAndVolumeAndAnOffOneShowsPower() {
        let app = launch("media-page", waitFor: expectations[.mediaLivingRoomCard])
        let tile = expectations[.mediaLivingRoomCard]
        for action in ["previous", "play_pause", "next"] { assertTarget("\(tile).action.\(action)", in: app) }
        XCTAssertFalse(element("\(tile).action.power", in: app).exists, "a playing remote has no Power disc")
        let volume = try? element("\(tile).volume", in: app).snapshot()
        XCTAssertNotNil(volume, "the volume slider shows under the transport")
        XCTAssertEqual(volume?.label, "Volume \(expectations[.remoteLivingRoomTitle])")
        XCTAssertEqual(volume?.value as? String, "32 percent")
        assertTarget("\(tile).volume", in: app)
        tap("\(tile).action.next", in: app)
        let lastCall = app.staticTexts["gallery.lastCall"].firstMatch
        let sentNext = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "media_player.media_next_track"), object: lastCall)
        XCTAssertEqual(XCTWaiter().wait(for: [sentNext], timeout: 10), .completed, "Last call was '\(lastCall.label)'")
    }

    /// The Media room remote tile: Power turns it on as playing (the gallery's echo), so its tile swaps Power for the transport and
    /// volume, and Next swaps them back. (The Media STREAMER source tile beside it is not a remote; its toggle is a later lane.)
    func testRemoteTileSwapsPowerForTransportAndBack() {
        // Wait on the first tile: the Media room's sits below the fold on the folded Duo, so `tap` scrolls to it.
        let app = launch("media-page", waitFor: expectations[.mediaLivingRoomCard])
        let tile = "media.card.\(expectations[.roomMediaId]).\(expectations[.roomMediaId])"
        tap("\(tile).action.power", in: app) // On, to the transport once the gallery echoes it as playing.
        XCTAssertTrue(element("\(tile).action.next", in: app).appears(timeout: 10), "the transport arrives")
        XCTAssertTrue(element("\(tile).volume", in: app).appears(timeout: 5), "and the volume slider")
        tap("\(tile).action.next", in: app) // Gallery: Next stops it.
        XCTAssertTrue(element("\(tile).action.power", in: app).appears(timeout: 10), "Power returns")
    }

    func testMusicRoomRemoteSharesTheSourceWithThePage() {
        let app = launch("media-page", ["FENTON_GALLERY_REMOTE": expectations[.remoteStudioId], "FENTON_GALLERY_TAB": "devices"],
                         waitFor: "remote.device.TV")
        XCTAssertTrue(app.navigationBars["\(expectations[.roomStudioTitle]) Remote"].exists)
        XCTAssertTrue(app.segmentedControls["remote.tabs"].buttons["Devices"].isSelected, "The remote opens on Devices")
    }

    private func auditMedia(_ pose: Pose) throws {
        try auditAndCapture("media", pose: pose) { self.launch("media-page", ["FENTON_GALLERY_CLEAN": "1"], waitFor: self.expectations[.mediaLivingRoomCard]) }
    }

    func testMediaAuditsAndScreenshots() throws { try auditMedia(.upright) }
    // `InIPadLandscape` sits before `AuditsAndScreenshots` so the name still ends `Screenshots` (the Capture plan rule).
    func testMediaInIPadLandscapeAuditsAndScreenshots() throws { try auditMedia(.iPadLandscape) }

    // MARK: - Custom Lights

    func testCustomLightsModePicksSeahawks() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        tap("customLights.mode", in: app)
        // A pop-up menu of the modes (no sheet): the choice is a menu item named for the mode.
        app.buttons[expectations[.customLightsModeChoice]].firstMatch.tap()
        expectCall("input_select.select_option entity_id=\(expectations[.customLightsModeEntity]) option=\(expectations[.customLightsModeChoice])", in: app)
        XCTAssertTrue(element("customLights.resetAll", in: app).disappears(timeout: 3), "Lights show only in Custom mode")
    }

    func testCustomLightsManualOffHidesMode() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        flip("customLights.manual", in: app)
        expectCall("input_boolean.turn_off entity_id=\(expectations[.customLightsManualControl])", in: app)
        XCTAssertTrue(element("customLights.mode", in: app).disappears(timeout: 3), "Mode hides without manual control")
    }

    /// Opens Bollard 1's sheet directly (the gallery's `FENTON_GALLERY_LIGHT`); the last-call line stays, the steps read it.
    private func launchLightSheet() -> XCUIApplication {
        let app = launch("custom-lights", ["FENTON_GALLERY_LIGHT": expectations[.customLightsFirstLight]], waitFor: "customLight.brightness")
        return app
    }

    func testCustomLightOtherLightColour() {
        let app = launchLightSheet()
        tap("customLight.other.\(expectations[.customLightsSecondLight])", in: app)
        expectCall("light.turn_on entity_id=\(expectations[.customLightsFirstLight]) rgb_color=[0,0,255]", in: app)
    }

    func testCustomLightReset() {
        let app = launchLightSheet()
        tap("customLight.reset", in: app)
        expectCall("light.turn_on brightness=255 color_temp_kelvin=2000 entity_id=\(expectations[.customLightsFirstLight]) transition=1", in: app)
    }

    func testCustomLightBrightnessOff() {
        let app = launchLightSheet()
        tap("customLight.brightness", in: app)
        expectCall("light.turn_off entity_id=\(expectations[.customLightsFirstLight])", in: app)
    }

    func testCustomLightResetAll() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        tap("customLights.resetAll", in: app)
        // Reset All asks first (Alerts, #153).
        tap("customLights.resetAll.confirm", in: app)
        expectCall("light.turn_on brightness=255 color_temp_kelvin=2000 entity_id=\(expectations[.customLightsGroup]) transition=1", in: app)
    }

    /// A Custom Lights tile is a navigation tile (rollout L, audit item 11): its `power` disc sits left of the chevron and switches the
    /// light without opening the sheet.
    func testCustomLightTileDiscSwitchesThePower() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        let tile = element("customLights.light.\(expectations[.customLightsFirstLight])", in: app)
        // A toggle-styled disc is a switch to the accessibility tree (`TileActionStrip.traits`), not a button.
        let disc = app.switches["customLights.light.\(expectations[.customLightsFirstLight]).action.power"]
        reveal(tile, in: app)
        XCTAssertTrue(disc.appears(timeout: 10), "No power disc")
        XCTAssertEqual(disc.label, "Turn Off \(tile.label)")
        XCTAssertGreaterThanOrEqual(disc.frame.width, 44)
        XCTAssertLessThan(disc.frame.maxX, wholeTile("customLights.light.\(expectations[.customLightsFirstLight])", in: app).maxX - 20, "The chevron sits to the disc's right")
        disc.tap()
        expectCall("light.turn_off entity_id=\(expectations[.customLightsFirstLight])", in: app)
        XCTAssertFalse(element("customLight.brightness", in: app).exists, "The disc opened the sheet")
    }

    /// The body of a Custom Lights tile still opens its sheet beside the disc.
    func testCustomLightTileBodyOpensTheSheet() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        let tile = element("customLights.light.\(expectations[.customLightsFirstLight])", in: app)
        reveal(tile, in: app)
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(element("customLight.brightness", in: app).appears(timeout: 10), "The body did not open the sheet")
    }

    /// A sideways drag on a tile sets brightness.
    func testCustomLightTileHorizontalDragSetsBrightness() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        let tile = element("customLights.light.\(expectations[.customLightsFirstLight])", in: app)
        reveal(tile, in: app)
        // Not near the trailing edge: the power disc and the chevron sit there, and the disc takes the touch.
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let parts = ["light.turn_on", "brightness_pct=", "entity_id=\(expectations[.customLightsFirstLight])"]
        let predicate = NSPredicate(format: parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND "), argumentArray: parts)
        let sent = XCTNSPredicateExpectation(predicate: predicate, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [sent], timeout: 10), .completed, "Last call was '\(label.label)'")
    }

    /// A vertical drag starting on a tile scrolls the page (it used to be swallowed).
    func testCustomLightTileVerticalDragScrolls() {
        let app = launch("custom-lights", waitFor: "customLights.manual")
        // Only where the page is taller than the window (an iPad in landscape shows it all).
        guard element("customLights.resetAll", in: app).frame.maxY > app.windows.firstMatch.frame.maxY else { return }
        let manual = element("customLights.manual", in: app)
        let before = manual.frame.minY
        let onTile = element("customLights.light.light.demo_front_door_door_1", in: app)
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        onTile.press(forDuration: 0.05, thenDragTo: onTile.withOffset(CGVector(dx: 0, dy: -200)), withVelocity: .slow,
                     thenHoldForDuration: 0.2)
        XCTAssertLessThan(manual.frame.minY, before - 40, "A vertical drag starting on a tile scrolls the page")
    }

    // One test per page, as for Sprinklers: a host-load crash costs one page.
    private func auditCustomLights(_ pose: Pose) throws {
        try auditAndCapture("custom-lights", pose: pose) { self.launch("custom-lights", ["FENTON_GALLERY_CLEAN": "1"], waitFor: "customLights.manual") }
    }

    private func auditCustomLightSheet(_ pose: Pose) throws {
        try auditAndCapture("custom-light-sheet", pose: pose) {
            self.launch("custom-lights", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_LIGHT": self.expectations[.customLightsFirstLight]],
                        waitFor: "customLight.brightness")
        }
    }

    func testCustomLightsAuditsAndScreenshots() throws { try auditCustomLights(.upright) }
    func testCustomLightsInIPadLandscapeAuditsAndScreenshots() throws { try auditCustomLights(.iPadLandscape) }
    func testCustomLightSheetAuditsAndScreenshots() throws { try auditCustomLightSheet(.upright) }
    func testCustomLightSheetInIPadLandscapeAuditsAndScreenshots() throws { try auditCustomLightSheet(.iPadLandscape) }

    // MARK: - Sprinklers

    /// Opens the front yard controller's overview directly (`FENTON_GALLERY_SPRINKLER`).
    private func launchFrontYardController() -> XCUIApplication {
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "frontYard"], waitFor: "sprinkler.zone.0")
        XCTAssertTrue(element("sprinkler.overview", in: app).appears(timeout: 10))
        return app
    }

    func testSprinklerControllerRainDelay() {
        let app = launchFrontYardController()
        flip("sprinkler.rainDelay", in: app)
        expectCall("switch.turn_on entity_id=\(expectations[.sprinklerFirstRainDelay])", in: app)
    }

    /// Start and Stop stay one flow: Stop is enabled only while the zone runs, and no fixture starts a zone watering.
    func testSprinklerControllerStartThenStopWatering() {
        let app = launchFrontYardController()
        tap("sprinkler.zone.0", in: app)
        tap("sprinkler.startWatering", in: app)
        expectCall("bhyve.start_watering entity_id=\(expectations[.sprinklerFirstZoneValve]) minutes=15", in: app)
        XCTAssertTrue(element("sprinkler.stop", in: app).wait(for: \.isEnabled, toEqual: true, timeout: 10), "Back on the overview, watering")
        tap("sprinkler.stop", in: app)
        expectCall("bhyve.stop_watering entity_id=\(expectations[.sprinklerFirstZoneValve])", in: app)
    }

    /// The controller card is a navigation tile with a Stop Watering disc (rollout lane M, item 30): it dims while idle, stops the
    /// watering valve while a zone runs, and a tap on the disc never also opens the sheet.
    func testControllerCardTileCarriesStopWatering() {
        let app = launch("sprinklers", waitFor: "sprinklers.controller.backyard")
        let stop = element("sprinklers.controller.backyard.action.stop", in: app)
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        reveal(stop, in: app)
        assertTarget("sprinklers.controller.backyard.action.stop", in: app)
        XCTAssertTrue(stop.isEnabled, "The backyard is watering: Stop Watering is ready")
        XCTAssertFalse(element("sprinklers.controller.frontYard.action.stop", in: app).isEnabled, "Idle: the disc dims in place")
        tap("sprinklers.controller.backyard.action.stop", in: app)
        expectCall("bhyve.stop_watering entity_id=\(expectations[.sprinklerSecondZoneValve])", in: app)
        XCTAssertFalse(element("sprinkler.overview", in: app).exists, "The disc does not open the sheet")
    }

    /// While one zone waters, another zone's row still opens and says why it can't start.
    func testBusyControllerExplainsWhyAZoneCannotStart() {
        // Wait on a row: the list's own center is not hittable on the unfolded iPhone Duo in landscape.
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "backyard"], waitFor: "sprinkler.zone.0")
        tap("sprinkler.zone.0", in: app)
        XCTAssertTrue(element("sprinkler.waterBlocked", in: app).appears(timeout: 10), "The reason shows")
        XCTAssertFalse(element("sprinkler.startWatering", in: app).isEnabled, "Start waits for the running zone")
    }

    func testScheduleEditorSavesTheProgram() {
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "schedule-0"],
                         waitFor: "sprinkler.schedule.apply")
        let sunday = element("sprinkler.schedule.day.0", in: app)
        XCTAssertFalse(sunday.isSelected)
        sunday.tap()
        XCTAssertTrue(sunday.isSelected)
        assertTarget("sprinkler.schedule.day.0", in: app)
        tap("sprinkler.schedule.apply", in: app)
        // `frequency` prints as a dictionary, whose key order is not fixed: check its parts.
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let parts = ["bhyve.update_program budget=100 entity_id=\(expectations[.sprinklerFirstProgram])", "[0, 1, 3, 5]",
                     "start_times=[06:30]"]
        let predicate = NSPredicate(format: parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND "), argumentArray: parts)
        let saved = XCTNSPredicateExpectation(predicate: predicate, object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 10), .completed, "Last call was '\(label.label)'")
        XCTAssertTrue(element("sprinkler.overview", in: app).appears(timeout: 10), "Apply returns to the overview")
    }

    /// Start times are identified by their own id (audit 2026-10-13): removing the first keeps the added one intact.
    func testScheduleEditorRemovesAStartTime() {
        let app = launch("sprinklers", ["FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "schedule-0"],
                         waitFor: "sprinkler.schedule.apply")
        // On the folded Duo the Add button starts under the floating Apply bar and its lower edge: a tap there does nothing.
        // Scroll it clear of the bar first.
        let add = element("sprinkler.schedule.addTime", in: app)
        let apply = element("sprinkler.schedule.apply", in: app)
        XCTAssertTrue(add.appears(timeout: 10))
        let window = app.windows.firstMatch.frame
        for _ in 0..<10 where add.frame.maxY > apply.frame.minY - 8 {
            let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: min(window.midX, window.maxX - 96), dy: window.height * 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        tap("sprinkler.schedule.addTime", in: app)
        // The new row lands below the Add button, off screen on the folded Duo, where the lazy form does not expose it yet.
        reveal(element("sprinkler.schedule.time.1", in: app), in: app)
        XCTAssertTrue(element("sprinkler.schedule.time.1", in: app).appears(timeout: 10), "A second start time appears")
        let removeFirst = app.buttons["Remove Start Time 1"].firstMatch
        XCTAssertTrue(removeFirst.appears(timeout: 10))
        removeFirst.tap()
        XCTAssertTrue(element("sprinkler.schedule.time.1", in: app).disappears(timeout: 10), "One start time is left")
        tap("sprinkler.schedule.apply", in: app)
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "start_times=[07:00]"), object: label)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 10), .completed, "Last call was '\(label.label)'")
    }

    // One test per page: each audit relaunches the app several times, and under host load a crash should
    // cost one page, not four.
    private func auditSprinklers(_ pose: Pose) throws {
        try auditAndCapture("sprinklers", pose: pose) { self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1"], waitFor: "sprinklers.controller.frontYard") }
    }

    private func auditSprinklerController(_ pose: Pose) throws {
        try auditAndCapture("sprinkler-controller", pose: pose) {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "backyard"], waitFor: "sprinkler.zone.0")
        }
    }

    private func auditSprinklerWater(_ pose: Pose) throws {
        try auditAndCapture("sprinkler-water", pose: pose) {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "water-0"],
                        waitFor: "sprinkler.startWatering")
        }
    }

    private func auditSprinklerSchedule(_ pose: Pose) throws {
        try auditAndCapture("sprinkler-schedule", pose: pose) {
            self.launch("sprinklers", ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_SPRINKLER": "frontYard", "FENTON_GALLERY_DETAIL": "schedule-0"],
                        waitFor: "sprinkler.schedule.apply")
        }
    }

    func testSprinklersAuditsAndScreenshots() throws { try auditSprinklers(.upright) }
    func testSprinklersInIPadLandscapeAuditsAndScreenshots() throws { try auditSprinklers(.iPadLandscape) }
    func testSprinklerControllerAuditsAndScreenshots() throws { try auditSprinklerController(.upright) }
    func testSprinklerControllerInIPadLandscapeAuditsAndScreenshots() throws { try auditSprinklerController(.iPadLandscape) }
    func testSprinklerWaterAuditsAndScreenshots() throws { try auditSprinklerWater(.upright) }
    func testSprinklerWaterInIPadLandscapeAuditsAndScreenshots() throws { try auditSprinklerWater(.iPadLandscape) }
    func testSprinklerScheduleAuditsAndScreenshots() throws { try auditSprinklerSchedule(.upright) }
    func testSprinklerScheduleInIPadLandscapeAuditsAndScreenshots() throws { try auditSprinklerSchedule(.iPadLandscape) }
}
