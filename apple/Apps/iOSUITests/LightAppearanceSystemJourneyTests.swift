import XCTest

/// The sheets follow the system appearance while the pages stay dark (`HassDesign/SystemAppearance`): a pinned light and dark
/// override, the simulator's own setting at launch, and a change while the app runs. These tests are about launch and the
/// process (they set the simulator's appearance and relaunch), so they launch fresh (`fresh: true`) and never reuse the resident app.
@MainActor
final class LightAppearanceSystemJourneyTests: LightAppearanceJourneyTestCase {
    private func openGallerySheet(_ app: XCUIApplication) {
        let primary = app.buttons["g.primary"]
        for _ in 0..<6 where !primary.isHittable { app.swipeUp() }
        primary.tap()
        XCTAssertTrue(app.buttons["sheet.close"].appears(timeout: 5))
        settleScreen()
    }

    /// The sheet is light while the pages behind it are dark, and they are still dark once it closes.
    func testSheetIsLightWhileThePageStaysDark() {
        let app = gallery("direction-g", fresh: true)
        XCTAssertTrue(app.buttons["g.chip.Lights"].appears(timeout: FentonHomeApp.launchWait()))
        assertPageIsDark(app, "before the sheet")
        openGallerySheet(app)
        assertSheet(app, isLight: true, "gallery")
        keepScreenshot(app, "light-sheet-open-\(layout)")
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(app.buttons["g.primary"].appears(timeout: 5))
        XCTAssertTrue(app.buttons["sheet.close"].disappears(timeout: 5))
        settleScreen()
        assertPageIsDark(app, "after the sheet closed")
    }

    /// A system-appearance launch with no override: the probe says what the app measured.
    private func launchFollowingTheSystem() -> (app: XCUIApplication, probe: XCUIElement) {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment.removeValue(forKey: "FENTON_APPEARANCE")
        app.launchEnvironment["FENTON_GALLERY"] = "direction-g"
        app.launchEnvironment["FENTON_APPEARANCE_DEBUG"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["g.chip.Lights"].appears(timeout: 10))
        let probe = element("appearance.probe", in: app)
        XCTAssertTrue(probe.appears(timeout: 5), "No appearance probe")
        return (app, probe)
    }

    /// Sets the simulator's appearance and launches following it. The display takes the setting a moment later and a launch
    /// right after can still read the old one, so this relaunches until the probe's measurement agrees (the simulator
    /// is slow, not the app); it fails with what it saw if the simulator never takes the setting.
    private func launchAsSystem(_ appearance: XCUIDevice.Appearance) -> (app: XCUIApplication, probe: XCUIElement) {
        let wanted = appearance == .light ? 1 : 2
        XCUIDevice.shared.appearance = appearance
        settleScreen()
        var launched = launchFollowingTheSystem()
        // Against the clock, not a count of relaunches: three relaunches (about 15 s) were not enough for a simulator on a
        // loaded host to take the setting (iPhone, 2026-10-17: the device read dark, the screen stayed light).
        let deadline = Date().addingTimeInterval(120)
        while !launched.probe.label.hasPrefix("screen=\(wanted) "), Date() < deadline {
            launched.app.terminate()
            settleScreen()
            launched = launchFollowingTheSystem()
        }
        XCTAssertTrue(launched.probe.label.hasPrefix("screen=\(wanted) "),
                      "The simulator never took \(appearance == .light ? "light" : "dark") (device reads "
                      + "\(XCUIDevice.shared.appearance.rawValue)): \(launched.probe.label)")
        return launched
    }

    /// Sets the simulator to `appearance`, launches following it and checks the page stays dark while the sheet follows the system.
    /// Restores the device's own appearance afterwards.
    private func assertSystemDrivesSheets(_ appearance: XCUIDevice.Appearance) {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original == .unspecified ? .dark : original }
        let isLight = appearance == .light
        let name = isLight ? "light" : "dark"
        let (app, probe) = launchAsSystem(appearance)
        assertPageIsDark(app, "system \(name)")
        openGallerySheet(app)
        assertSheet(app, isLight: isLight, "system \(name) (\(probe.label))")
        if isLight { keepScreenshot(app, "light-system-appearance-\(layout)") }
        app.terminate()
    }

    /// With no override at all, a dark system draws dark sheets over dark pages.
    func testSystemAppearanceDarkDrivesTheSheets() { assertSystemDrivesSheets(.dark) }

    /// With no override at all, a light system draws light sheets over dark pages.
    func testSystemAppearanceLightDrivesTheSheets() { assertSystemDrivesSheets(.light) }

    /// The user changes the appearance while the app runs (Control Center): the next sheet follows, the pages stay dark.
    func testSystemAppearanceChangeReachesARunningApp() {
        let original = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = original == .unspecified ? .dark : original }
        let (app, _) = launchAsSystem(.dark)
        XCUIDevice.shared.appearance = .light
        settleScreen()
        assertPageIsDark(app, "after the system turned light")
        openGallerySheet(app)
        assertSheet(app, isLight: true, "after the change")
    }

    /// A pinned dark appearance keeps the sheet dark, whatever the simulator shows.
    func testPinnedDarkKeepsTheSheetDark() {
        let app = gallery("direction-g", appearance: "dark", fresh: true)
        XCTAssertTrue(app.buttons["g.chip.Lights"].appears(timeout: 10))
        openGallerySheet(app)
        assertSheet(app, isLight: false, "pinned dark")
    }
}
