import XCTest

/// The media remote sheet in the debug gallery (fixture state, recording service caller; nothing reaches the
/// house): semantics, service calls, layout per pose, accessibility audits and screenshots on iPhone, iPhone Duo
/// and iPad (`.agents/patterns/media-remote.md`).
@MainActor
final class MediaRemoteJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// An element each section shows once the sheet is up: power on Remote (and in every section in two
    /// columns), otherwise the section's first control.
    private func readyID(_ remote: String, tab: String) -> String {
        switch (remote, tab) {
        case (_, "controls"): "remote.power"
        case (expectations[.remoteStudioId], "apps"): "remote.app.\(expectations[.remoteStudioAppTitle])"
        case (_, "apps"): "remote.app.\(expectations[.remoteLivingRoomAppTitle])"
        case (expectations[.remoteStudioId], "devices"): "remote.device.TV"
        case (_, "devices"): "remote.device.Projector"
        case (_, "hueSync"): "remote.hue.Light Sync"
        default: "remote.tabs"
        }
    }

    private func launch(_ remote: String, tab: String = "controls", arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "media-remote"
        configured.launchEnvironment["FENTON_GALLERY_REMOTE"] = remote
        configured.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        configured.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        configured.launchArguments += arguments
        // Through `startApp`: with reuse on the class keeps one resident app, reset per test (`app-reuse.md`). The gallery builds its
        // fixtures and recording caller per gallery, so nothing survives a reset. AX5 launches (arguments) are fresh by signature.
        let app = startApp(configured)
        let ready = element(readyID(remote, tab: tab), in: app)
        XCTAssertTrue(ready.appears(timeout: 30), "Remote sheet did not open")
        XCTAssertTrue(ready.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        expectLastCall(expected, in: app, file: file, line: line)
    }

    /// Flips a list row's switch: XCUITest taps a row's middle, which lands on its label and leaves the switch alone.
    private func flip(_ toggle: XCUIElement, in app: XCUIApplication) {
        reveal(toggle, in: app)
        let knob = toggle.switches.firstMatch
        if knob.exists { knob.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
    }

    /// Scrolls toward `element` in short drags until it is hittable: full swipes overshoot long columns
    /// (AX5, the unfolded Duo), and the element may sit above or below the visible part.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) {
        let window = app.windows.firstMatch.frame
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<24 {
            // One snapshot answers "in the tree" and "where"; `isHittable` is read once the frame says it is on screen.
            let frame = (try? element.snapshot())?.frame
            let present = frame.map { !$0.isEmpty } ?? false
            if present, element.isHittable { break }
            // Stop once a drag no longer moves the element: it is as far in as the scroll allows.
            if let lastMinY, let frame, abs(lastMinY - frame.minY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 2 { break }
            lastMinY = frame?.minY
            let above = present ? frame!.midY < window.midY : down
            // Drag in the element's own column (in two columns each side scrolls on its own), in screen points
            // from the window origin: normalized app coordinates stay portrait in a landscape window
            // (FestivalNativeApps xcuitest pitfalls).
            // On iPhone Duo, gestures from `app.coordinate` never reach the inner display; anchor them on the window
            // and keep clear of the system vertical bar at its trailing edge (FestivalNativeApps `screenOrigin`).
            var x = present && frame!.midX > 0 ? frame!.midX : window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            // A drag that starts on the software keyboard scrolls nothing: start clear above it.
            let keyboard = app.keyboards.firstMatch
            let usableMaxY = keyboard.exists ? keyboard.frame.minY : window.maxY
            let startY = min(window.minY + window.height * (above ? 0.35 : 0.65), usableMaxY - 100)
            // With the keyboard up, the page is short and its middle is buttons: drag in the leading margin, above the
            // keyboard's suggestion bar (about 44 pt above its reported top).
            if keyboard.exists { x = window.minX + 14 }
            let from = origin.withOffset(CGVector(dx: x, dy: keyboard.exists ? min(startY, usableMaxY - 44 - 20) : startY))
            let to = from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        if !element.isHittable { keep(app, "reveal-failed") }
        let scrolls = app.scrollViews.allElementsBoundByIndex.map { "\($0.frame)" }.joined(separator: "; ")
        XCTAssertTrue(element.isHittable, "\(element) never came into view: frame \(element.frame), window \(window), scroll views \(scrolls)")
    }

    /// Every node of the app's tree by identifier, from one snapshot (instead of a lookup per element).
    private func tree(_ app: XCUIApplication) throws -> [String: any XCUIElementSnapshot] {
        var nodes: [String: any XCUIElementSnapshot] = [:]
        func collect(_ node: any XCUIElementSnapshot) {
            if !node.identifier.isEmpty, nodes[node.identifier] == nil { nodes[node.identifier] = node }
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        return nodes
    }

    private func isSelected(_ element: XCUIElement) -> Bool { element.isSelected }

    private func waitFor(_ element: XCUIElement, _ format: String, _ argument: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argument), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Controls

    /// Power and the d-pad: labels, values, 44 pt targets and the pad's geometry.
    func testRemotePadLayoutAndTargets() throws {
        let app = launch(expectations[.remoteLivingRoomId])
        // One snapshot of the tree answers every frame, label, value and enabled state below.
        let nodes = try tree(app)
        guard let power = nodes["remote.power"], let padNode = nodes["remote.dpad"],
              let back = nodes["remote.button.Back"], let home = nodes["remote.button.Home"],
              let keyboard = nodes["remote.button.Keyboard"] else { return XCTFail("Remote controls missing from the tree") }
        XCTAssertEqual(power.label, "Power")
        XCTAssertEqual(power.value as? String, "On")
        func target(_ node: any XCUIElementSnapshot) {
            XCTAssertGreaterThanOrEqual(node.frame.width, 43, node.label)
            XCTAssertGreaterThanOrEqual(node.frame.height, 43, node.label)
        }
        target(power)

        var pad: [String: any XCUIElementSnapshot] = [:]
        func collect(_ node: any XCUIElementSnapshot) {
            if node.elementType == .button, !node.label.isEmpty, pad[node.label] == nil { pad[node.label] = node }
            node.children.forEach(collect)
        }
        collect(padNode)
        // Power sits in the pad's top row, in the cell right of Up, so no row of its own (owner, 2026-10-13).
        guard let up = pad["Up"], let down = pad["Down"] else { return XCTFail("Up/Down missing from the pad: \(pad.keys)") }
        XCTAssertEqual(power.frame.midY, up.frame.midY, accuracy: 1, "Power shares Up's row")
        XCTAssertGreaterThan(power.frame.minX, up.frame.maxX, "Power is right of Up")
        XCTAssertEqual(power.frame.width, up.frame.width, accuracy: 1, "Power is a d-pad-sized button")
        // Direction G: Back and Home take the pad's leading corners, the keyboard its trailing bottom corner.
        XCTAssertEqual(back.frame.midY, up.frame.midY, accuracy: 1, "Back shares Up's row")
        XCTAssertLessThan(back.frame.maxX, up.frame.minX, "Back is left of Up")
        XCTAssertEqual(home.frame.midY, down.frame.midY, accuracy: 1, "Home shares Down's row")
        XCTAssertEqual(keyboard.frame.midY, down.frame.midY, accuracy: 1, "The keyboard shares Down's row")
        XCTAssertEqual(padNode.label, "\(expectations[.remoteLivingRoomTitle]) remote controls")
        for label in ["Back", "Up", "Left", "Select", "Right", "Home", "Down"] {
            guard let button = pad[label] else { XCTFail(label); continue }
            XCTAssertTrue(button.isEnabled, label)
            target(button)
        }
    }

    /// Up and Select send their directional commands.
    func testRemoteDpadSendsUpAndSelect() {
        let app = launch(expectations[.remoteLivingRoomId])
        let pad = element("remote.dpad", in: app)
        pad.buttons["Up"].tap()
        expectCall("remote.send_command command=DPAD_UP entity_id=\(expectations[.remoteLivingRoomRemote])", in: app)
        pad.buttons["Select"].tap()
        expectCall("remote.send_command command=DPAD_CENTER entity_id=\(expectations[.remoteLivingRoomRemote])", in: app)
    }

    /// Power off: the fixture echoes the SHIELD off, power flips and the directions disable; power stays enabled.
    func testRemotePowerTurnsOff() {
        let app = launch(expectations[.remoteLivingRoomId])
        let power = app.buttons["remote.power"]
        XCTAssertEqual(power.value as? String, "On")
        let pad = element("remote.dpad", in: app)
        power.tap()
        expectCall("remote.send_command command=POWER entity_id=\(expectations[.remoteLivingRoomRemote])", in: app)
        XCTAssertTrue(waitFor(power, "value == %@", "Off"), "Power value is \(power.value ?? "nil")")
        XCTAssertTrue(power.isEnabled, "Power is how the device turns back on")
        XCTAssertFalse(pad.buttons["Up"].isEnabled)
        XCTAssertFalse(app.buttons["remote.button.Play"].isEnabled)
    }

    /// The Studio power button is a switch with an On/Off value.
    func testMusicRoomPowerIsASwitch() {
        let app = launch(expectations[.remoteStudioId])
        let power = app.switches["remote.power"]
        XCTAssertTrue(power.exists, "\(expectations[.roomStudioTitle]) power is a switch")
        XCTAssertEqual(power.value as? String, "On")
        power.tap()
        expectCall(expectations[.remoteStudioPowerOffScript], in: app)
        XCTAssertTrue(waitFor(power, "value == %@", "Off"), "Optimistic off shows at once")
    }

    // Navigation, playback and volume rows send their configured calls: one test per row.

    func testRemoteMenu() {
        let app = launch(expectations[.remoteBedroomId])
        XCTAssertTrue(element("remote.dpad", in: app).buttons["Select"].exists)
        app.buttons["remote.button.Menu"].tap()
        expectCall("remote.send_command command=menu entity_id=\(expectations[.remoteBedroomRemote])", in: app)
        XCTAssertFalse(app.buttons["remote.button.Keyboard"].exists, "Apple TV has no keyboard")
    }

    func testRemoteVolumeUp() {
        let app = launch(expectations[.remoteBedroomId])
        let volumeUp = app.buttons["remote.button.Volume Up"]
        assertTarget(volumeUp)
        volumeUp.tap()
        expectCall("media_player.volume_up entity_id=\(expectations[.remoteBedroomVolumePlayer])", in: app)
    }

    func testRemoteMute() {
        let app = launch(expectations[.remoteBedroomId])
        app.buttons["remote.button.Mute"].tap()
        expectCall("\(expectations[.remoteMuteScript]) \(expectations[.remoteMuteSpeakerKey])=[\(expectations[.remoteBedroomVolumePlayer])]", in: app)
    }

    func testRemotePlay() {
        let app = launch(expectations[.remoteBedroomId])
        let play = app.buttons["remote.button.Play"]
        reveal(play, in: app)
        play.tap()
        expectCall("remote.send_command command=play entity_id=\(expectations[.remoteBedroomRemote])", in: app)
    }

    func testRemoteVolumeSlider() {
        let app = launch(expectations[.remoteBedroomId])
        let slider = app.sliders["remote.volume"]
        reveal(slider, in: app)
        XCTAssertEqual(slider.label, "Volume volume")
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertTrue(waitFor(app.staticTexts["gallery.lastCall"].firstMatch, "label CONTAINS %@", "media_player.volume_set"), lastCall(in: app))
        XCTAssertTrue(lastCall(in: app).contains("entity_id=\(expectations[.remoteBedroomVolumePlayer])"), lastCall(in: app))
    }

    /// The keyboard opens an inline field; Send types the text with quotes escaped and closes it.
    func testKeyboardSendsEscapedText() {
        let app = launch(expectations[.remoteLivingRoomId])
        let keyboard = app.buttons["remote.button.Keyboard"]
        XCTAssertEqual(keyboard.value as? String, "Collapsed")
        keyboard.tap()
        let field = app.textFields["remote.keyboard.field"]
        XCTAssertTrue(field.appears(timeout: 5))
        XCTAssertEqual(keyboard.value as? String, "Expanded")
        XCTAssertFalse(app.buttons["remote.keyboard.send"].isEnabled, "Blank text can't be sent")
        field.tap()
        field.typeText("it's")
        let send = app.buttons["remote.keyboard.send"]
        reveal(send, in: app)
        send.tap()
        expectCall(#"androidtv.adb_command command=input text 'it'\''s' entity_id=\#(expectations[.remoteLivingRoomControl])"#, in: app)
        XCTAssertTrue(field.disappears(timeout: 5))
    }

    // MARK: - Tabs

    /// Only sections with content appear, in the bottom glass bar, and they switch the content: in one column the
    /// pad belongs to Remote; in two columns it stays in the leading column for every section.
    func testTabsShowOnlyWhatTheRemoteHas() {
        let app = launch(expectations[.remoteMediaRoomId])
        let tabs = app.segmentedControls["remote.tabs"]
        XCTAssertTrue(tabs.exists)
        XCTAssertEqual(tabs.buttons.count, 3)
        XCTAssertGreaterThan(tabs.frame.midY, app.windows.firstMatch.frame.midY, "The section bar sits at the bottom")
        tabs.buttons["Devices"].tap()
        XCTAssertTrue(element("remote.device.Projector", in: app).appears(timeout: 5))
        XCTAssertTrue(tabs.buttons["Devices"].isSelected)
        let power = element("remote.power", in: app)
        if element("remote.layout.twoColumn", in: app).exists {
            XCTAssertTrue(power.exists, "The pad stays beside every section in two columns")
        } else {
            XCTAssertFalse(power.exists, "The pad belongs to the Remote section in one column")
            tabs.buttons["Remote"].tap()
            XCTAssertTrue(power.appears(timeout: 5), "Remote brings the pad back")
        }
    }

    /// App tiles launch apps; the running app carries the selected trait.
    func testRemoteAppsMusicRoomFortnite() {
        let app = launch(expectations[.remoteStudioId], tab: "apps")
        let fortnite = app.buttons["remote.app.\(expectations[.remoteStudioAppTitle])"]
        XCTAssertTrue(fortnite.appears(timeout: 5))
        XCTAssertEqual(fortnite.label, expectations[.remoteStudioAppTitle])
        XCTAssertFalse(isSelected(fortnite))
        assertTarget(fortnite)
        fortnite.tap()
        expectCall(expectations[.remoteStudioAppScript], in: app)
        XCTAssertTrue(fortnite.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    func testRemoteAppsLivingRoomPlex() {
        let living = launch(expectations[.remoteLivingRoomId], tab: "apps")
        let plex = living.buttons["remote.app.\(expectations[.remoteLivingRoomAppTitle])"]
        XCTAssertTrue(plex.appears(timeout: 5))
        plex.tap()
        expectCall("\(expectations[.remoteLaunchAppScript]) app_id=\(expectations[.remoteLivingRoomAppId]) entity=\(expectations[.remoteLivingRoomPlayer]) remote_entity=\(expectations[.remoteLivingRoomRemote])", in: living)
    }

    /// Device rows are switches that toggle their devices; the PC presses the matching input button.
    func testDevicesToggle() {
        let app = launch(expectations[.remoteMediaRoomId], tab: "devices")
        let projector = app.switches["remote.device.Projector"]
        XCTAssertTrue(projector.appears(timeout: 5))
        XCTAssertTrue(projector.label.hasPrefix("Projector"), projector.label)
        XCTAssertEqual(projector.value as? String, "1")
        assertTarget(projector)
        flip(projector, in: app)
        expectCall("media_player.toggle entity_id=\(expectations[.remoteProjector])", in: app)
        XCTAssertTrue(waitFor(projector, "value == %@", "0"), "Projector value is \(projector.value ?? "nil")")
        flip(app.switches["remote.device.\(expectations[.remoteComputerTitle])"], in: app)
        expectCall("input_button.press entity_id=\(expectations[.remoteComputerPress])", in: app)
    }

    /// The Studio's sources are a checkmark choice and its speaker only reports its state.
    func testMusicRoomSourcesAreAChoice() {
        let app = launch(expectations[.remoteStudioId], tab: "devices")
        let server = app.buttons["remote.device.Server"]
        reveal(server, in: app)
        XCTAssertFalse(server.isSelected)
        server.tap()
        XCTAssertTrue(server.wait(for: \.isSelected, toEqual: true, timeout: 5), "The chosen source is selected")
        XCTAssertFalse(app.buttons["remote.device.\(expectations[.remoteStudioSpeakerTitle])"].exists, "A state-only device is not a button")
        XCTAssertTrue(element("remote.device.\(expectations[.remoteStudioSpeakerTitle])", in: app).exists)
    }

    /// Hue Sync: toggles are switches, modes and choices are selected, unplugged inputs are disabled.
    func testHueSyncModeGame() {
        let app = launch(expectations[.remoteStudioId], tab: "hueSync")
        let lightSync = app.switches["remote.hue.Light Sync"]
        XCTAssertTrue(lightSync.appears(timeout: 5))
        XCTAssertEqual(lightSync.value as? String, "0")
        let modes = app.segmentedControls["remote.hue.mode"]
        reveal(modes, in: app)
        XCTAssertTrue(modes.buttons["Video"].isSelected)
        let game = modes.buttons["Game"]
        XCTAssertFalse(game.isSelected)
        game.tap()
        expectCall("select.select_option entity_id=\(expectations[.remoteSyncMode]) option=game", in: app)
        XCTAssertTrue(game.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertTrue(waitFor(lightSync, "value == %@", "1"), "Choosing a mode starts syncing")
    }

    func testHueSyncIntensityHigh() {
        let app = launch(expectations[.remoteStudioId], tab: "hueSync")
        let intensity = app.segmentedControls["remote.hue.intensity"]
        reveal(intensity, in: app)
        intensity.buttons["High"].tap()
        expectCall("select.select_option entity_id=\(expectations[.remoteSyncIntensity]) option=high", in: app)
    }

    func testHueSyncHdmiInputs() {
        let app = launch(expectations[.remoteStudioId], tab: "hueSync")
        let unplugged = element("remote.hue.hdmi.HDMI 4", in: app)
        reveal(unplugged, in: app)
        XCTAssertFalse(unplugged.isEnabled)
        XCTAssertTrue(element("remote.hue.hdmi.HDMI 1", in: app).isSelected)
    }

    // MARK: - Layout

    /// Two columns only on iPad landscape and unfolded Duo landscape; iPhone and every portrait are one column. This is the
    /// upright pose (iPad: portrait, one column); `…InIPadLandscape` is the iPad landscape split.
    func testLayoutFollowsThePose() {
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = .portrait
            let app = launch(expectations[.remoteMediaRoomId])
            XCTAssertTrue(element("remote.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            return
        }
        let app = launch(expectations[.remoteMediaRoomId])
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720
            ? "remote.layout.twoColumn" : "remote.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    func testLayoutFollowsThePoseInIPadLandscape() throws {
        try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(expectations[.remoteMediaRoomId])
        XCTAssertTrue(element("remote.layout.twoColumn", in: app).appears(timeout: 5), "iPad landscape splits")
        XCTAssertLessThan(element("remote.power", in: app).frame.maxX, app.buttons["remote.button.Play"].frame.minX,
                          "The pad leads, the section trails")
    }

    // MARK: - Accessibility audits

    private func audit(_ remote: String, tab: String) throws {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = launch(remote, tab: tab)
            try FentonHomeApp.audit(app) { self.launch(remote, tab: tab, arguments: FentonHomeApp.ax5) }
        }
    }

    func testControlsTabPassesAudit() throws { try audit(expectations[.remoteLivingRoomId], tab: "controls") }
    func testAppsTabPassesAudit() throws { try audit(expectations[.remoteLivingRoomId], tab: "apps") }
    func testDevicesTabPassesAudit() throws { try audit(expectations[.remoteMediaRoomId], tab: "devices") }
    func testHueSyncTabPassesAudit() throws { try audit(expectations[.remoteStudioId], tab: "hueSync") }

    /// At AX5 the d-pad (with power) grows and every control stays reachable by scrolling.
    func testLargestTextKeepsControlsReachable() {
        let regular = launch(expectations[.remoteLivingRoomId])
        let regularHeight = element("remote.power", in: regular).frame.height
        let app = launch(expectations[.remoteLivingRoomId], arguments: FentonHomeApp.ax5)
        XCTAssertGreaterThan(element("remote.power", in: app).frame.height, regularHeight * 1.2, "Power grows with the d-pad at AX5")
        for id in ["remote.button.Volume Up", "remote.button.Keyboard", "remote.button.Play"] {
            reveal(app.buttons[id], in: app)
        }
    }

    /// The sheet is live from the first frame, Power included (owner, 2026-10-24, `proposals/loading-states`): there is no
    /// gate, and app tiles fade their artwork in.
    func testSheetIsLiveWithoutWaitingForArtwork() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "media-remote"
        configured.launchEnvironment["FENTON_GALLERY_REMOTE"] = expectations[.remoteLivingRoomId]
        configured.launchEnvironment["FENTON_GALLERY_TAB"] = "apps"
        let app = startApp(configured)
        let plex = element("remote.app.\(expectations[.remoteLivingRoomAppTitle])", in: app)
        XCTAssertTrue(plex.appears(timeout: 30), "Remote sheet did not open")
        XCTAssertFalse(element("contentGate.spinner", in: app).exists, "The remote waits behind a spinner")
        XCTAssertTrue(element("remote.app.\(expectations[.remoteLivingRoomAppTitle])", in: app).isHittable, "App tiles are live")
    }

    // MARK: - Screenshots

    /// One screenshot of a tab in the pose, named `remote-<tab>-<orientation>`. Upright is the device's own pose (iPad: portrait);
    /// `…InIPadLandscape` is the iPad landscape one.
    private func capture(_ remote: String, tab: String, pose: Pose) throws {
        let suffix: String
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
            suffix = FentonHomeApp.family == .iPad ? "portrait" : "current"
        case .iPadLandscape:
            try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only")
            XCUIDevice.shared.orientation = .landscapeLeft
            suffix = "landscape"
        }
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "media-remote"
        configured.launchEnvironment["FENTON_GALLERY_REMOTE"] = remote
        configured.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        let app = startApp(configured)
        XCTAssertTrue(element(readyID(remote, tab: tab), in: app).appears(timeout: 30))
        settleScreen() // Artwork loads from the server's public /local folder.
        keep(app, "remote-\(tab)-\(suffix)")
    }

    private enum Pose { case upright, iPadLandscape }

    // Controls, Apps, Devices (Media room) and Hue Sync (Studio), named `remote-<tab>-<orientation>`.
    func testCaptureRemoteControls() throws { try capture(expectations[.remoteLivingRoomId], tab: "controls", pose: .upright) }
    func testCaptureRemoteControlsInIPadLandscape() throws { try capture(expectations[.remoteLivingRoomId], tab: "controls", pose: .iPadLandscape) }
    func testCaptureRemoteApps() throws { try capture(expectations[.remoteLivingRoomId], tab: "apps", pose: .upright) }
    func testCaptureRemoteAppsInIPadLandscape() throws { try capture(expectations[.remoteLivingRoomId], tab: "apps", pose: .iPadLandscape) }
    func testCaptureRemoteDevices() throws { try capture(expectations[.remoteMediaRoomId], tab: "devices", pose: .upright) }
    func testCaptureRemoteDevicesInIPadLandscape() throws { try capture(expectations[.remoteMediaRoomId], tab: "devices", pose: .iPadLandscape) }
    func testCaptureRemoteHueSync() throws { try capture(expectations[.remoteStudioId], tab: "hueSync", pose: .upright) }
    func testCaptureRemoteHueSyncInIPadLandscape() throws { try capture(expectations[.remoteStudioId], tab: "hueSync", pose: .iPadLandscape) }

    private func keep(_ app: XCUIApplication, _ name: String) {
        // Upright: the raw capture stays portrait in landscape (see RenderedContrast).
        let shot = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = shot.scale
        let upright = UIGraphicsImageRenderer(size: shot.size, format: format).image { _ in shot.draw(at: .zero) }
        let attachment = XCTAttachment(image: upright)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // XCUIScreen captures only the outer panel, which is dark on an unfolded iPhone Duo. With
        // FENTON_CAPTURE_DIR set, the host captures the lit panel: `<name>.ready` asks, `<name>.done` answers.
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
