import XCTest

/// The fan timer's lengths in minutes (`BathroomFanController.timerMinutes`).
private enum BathroomLengths {
    static let all = [5, 10, 15, 20, 30, 60]
}

/// The bathroom fan sheet in the debug gallery: power, lock and timer controls, the running countdown, tile colours, the light-appearance audit, the dark audits and the largest-text reachability of the timer lengths.
@MainActor
final class RoomDevicesFanJourneyTests: RoomDevicesJourneyTestCase {

    /// Power and lock are toggles; the timer starts from the segmented row and one button, which works while the fan is off
    /// (the script turns it on).
    func testFanTogglesAndTimer() {
        let app = launch("fan-guest", ready: "fan.power")
        let power = element("fan.power", in: app)
        XCTAssertEqual(power.value as? String, "Off")
        assertTarget(power)
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        XCTAssertTrue(set.isEnabled, "Starting a timer turns the fan on, so the button needs no running fan")
        XCTAssertEqual(set.label, "Turn Off in 30 Minutes")
        XCTAssertFalse(app.staticTexts["Auto-disable lock"].exists)
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "The auto-unlock choice is gone")
        power.tap()
        expectCall("script.\(expectations[.fanFirstScript]) command=power target_power=on", in: app)
        XCTAssertEqual(power.value as? String, "On")
        element("fan.lock", in: app).tap()
        expectCall("script.\(expectations[.fanFirstScript]) command=lock locked=true", in: app)
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "Locked and on no longer shows an auto-unlock choice")
        reveal(set, in: app)
        let ten = element("fan.timerOption.10", in: app)
        ten.tap()
        XCTAssertTrue(ten.isSelected)
        XCTAssertEqual(set.label, "Turn Off in 10 Minutes")
        set.tap()
        expectCall("script.\(expectations[.fanFirstScript]) auto_unlock=true command=timer_start minutes=10", in: app)
        XCTAssertTrue(element("fan.remaining", in: app).appears(timeout: 5), "Counts down")
    }

    /// Starting a timer on an off fan turns it on (the echo, like the script, switches it on).
    func testTimerOnAnOffFanTurnsItOn() {
        let app = launch("fan-guest", ready: "fan.power")
        let power = element("fan.power", in: app)
        XCTAssertEqual(power.value as? String, "Off")
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        element("fan.timerOption.60", in: app).tap()
        XCTAssertEqual(set.label, "Turn Off in 1 Hour")
        set.tap()
        expectCall("script.\(expectations[.fanFirstScript]) auto_unlock=true command=timer_start minutes=60", in: app)
        XCTAssertTrue(element("fan.remaining", in: app).appears(timeout: 5))
        XCTAssertEqual(power.value as? String, "On")
    }

    /// Six lengths, each a 44 pt target; the chosen one is selected; the footnote says what the button does.
    func testTimerLengthRowAndFootnote() {
        let app = launch("fan-guest", ready: "fan.power")
        let set = element("fan.setTimer", in: app)
        reveal(set, in: app)
        let expected = [5: "5 minutes", 10: "10 minutes", 15: "15 minutes", 20: "20 minutes", 30: "30 minutes", 60: "1 hour"]
        var previousX: CGFloat = -1
        for minutes in expected.keys.sorted() {
            let option = element("fan.timerOption.\(minutes)", in: app)
            let facts = try? option.snapshot() // existence, label and frame from one read
            XCTAssertNotNil(facts, "\(minutes)")
            XCTAssertEqual(facts?.label, expected[minutes])
            XCTAssertGreaterThanOrEqual(facts?.frame.height ?? 0, 41.5, "\(minutes) height")
            XCTAssertGreaterThanOrEqual(facts?.frame.width ?? 0, 41.5, "\(minutes) width")
            XCTAssertGreaterThan(facts?.frame.minX ?? -2, previousX, "In order, left to right")
            previousX = facts?.frame.minX ?? previousX
        }
        XCTAssertTrue(element("fan.timerOption.30", in: app).isSelected, "30 minutes is the default")
        XCTAssertTrue(app.staticTexts["The fan runs, then turns itself off. Starting a timer turns it on if it's off."].exists)
    }

    /// A running timer counts down in orange and Clear Timer cancels it. Master is on, locked and timed.
    func testFanClearsARunningTimer() {
        let app = launch("fan-master", ready: "fan.power")
        let remaining = element("fan.remaining", in: app)
        let facts = try? remaining.snapshot()
        XCTAssertNotNil(facts, "The countdown is not in the tree")
        XCTAssertTrue((facts?.value as? String ?? "").contains("minute"), "Spoken as a duration: \(facts?.value ?? "")")
        XCTAssertGreaterThanOrEqual(facts?.frame.height ?? 0, 40, "A 40 pt countdown")
        XCTAssertEqual(element("fan.lock", in: app).value as? String, "Locked", "An action tile reads its state line")
        XCTAssertFalse(element("fan.autoUnlock", in: app).exists, "No auto-unlock choice while locked and timed")
        XCTAssertFalse(element("fan.timerOption.5", in: app).exists, "The length row is hidden while a timer runs")
        let clear = element("fan.clearTimer", in: app)
        reveal(clear, in: app)
        XCTAssertEqual((try? clear.snapshot())?.label, "Clear Timer")
        assertSheetTarget(clear)
        clear.tap()
        expectCall("script.\(expectations[.fanSecondScript]) command=timer_cancel", in: app)
        XCTAssertTrue(element("fan.setTimer", in: app).appears(timeout: 5))
    }

    /// Power is the air teal and Lock the security blue, so the two read apart at a glance (both on in Master).
    func testPowerAndLockTilesAreDistinctColours() throws {
        let app = launch("fan-master", ready: "fan.power", clean: true)
        let power = element("fan.power", in: app)
        let lock = element("fan.lock", in: app)
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let teal = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: power.frame.minX + 8, y: power.frame.maxY - 8), in: capture))
        let blue = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: lock.frame.minX + 8, y: lock.frame.maxY - 8), in: capture))
        XCTAssertTrue(TileGeometry.matches(teal, 0x006E62, tolerance: 14), "Power fills with the air teal: \(teal)")
        XCTAssertTrue(TileGeometry.matches(blue, 0x1565C0, tolerance: 14), "Lock fills with the security blue: \(blue)")
        keepScreenshot(app, "fan-sheet-running-\(FentonHomeApp.family)")
    }

    /// The sheet reads in the light appearance too (a dark selected segment, a deeper timer orange).
    private func assertFanSheetPassesAuditInLight(_ device: String) throws {
        let app = launch(device, ready: "fan.power", clean: true, appearance: "light")
        try FentonHomeApp.audit(app) {
            self.launch(device, ready: "fan.power", clean: true, appearance: "light", arguments: FentonHomeApp.ax5)
        }
        keepScreenshot(app, "fan-sheet-light-\(device)-\(FentonHomeApp.family)")
    }

    func testFanSheetGuestPassesAuditInLight() throws { try assertFanSheetPassesAuditInLight("fan-guest") }
    func testFanSheetMasterPassesAuditInLight() throws { try assertFanSheetPassesAuditInLight("fan-master") }

    func testFanPassesAudit() throws { try audit("fan-master", ready: "fan.power", pose: .upright) }
    func testFanPassesAuditInIPadLandscape() throws { try audit("fan-master", ready: "fan.power", pose: .iPadLandscape) }
    func testIdleFanPassesAudit() throws { try audit("fan-guest", ready: "fan.power", pose: .upright) }
    func testIdleFanPassesAuditInIPadLandscape() throws { try audit("fan-guest", ready: "fan.power", pose: .iPadLandscape) }

    /// At AX5 the guest fan sheet keeps its timer lengths reachable by scrolling.
    func testFanAX5GuestTimerOptions() {
        let fan = launch("fan-guest", ready: "fan.power", sheetProbe: true, arguments: FentonHomeApp.ax5)
        reveal(element("fan.setTimer", in: fan), in: fan)
        // The six lengths wrap to a grid and stay 44 pt targets that fit the width.
        let window = fan.windows.firstMatch.frame
        for minutes in BathroomLengths.all {
            let option = element("fan.timerOption.\(minutes)", in: fan)
            XCTAssertLessThanOrEqual((try? option.snapshot())?.frame.maxX ?? .infinity, window.maxX + 1, "\(minutes)m fits the width")
            assertTarget(option, inSheet: fan)
        }
    }

    /// At AX5 the master fan sheet keeps its countdown and Clear Timer reachable.
    func testFanAX5MasterRemainingAndClear() {
        let timed = launch("fan-master", ready: "fan.power", arguments: FentonHomeApp.ax5)
        let remaining = element("fan.remaining", in: timed)
        reveal(remaining, in: timed)
        XCTAssertLessThanOrEqual((try? remaining.snapshot())?.frame.maxX ?? .infinity, timed.windows.firstMatch.frame.maxX + 1, "The countdown fits at AX5")
        reveal(element("fan.clearTimer", in: timed), in: timed)
    }
}
