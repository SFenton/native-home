import XCTest

/// Screenshots of the same sheets in light and dark, for design review next to each other (never committed): each
/// is kept in the result bundle as `g4-<sheet>-<appearance>-<layout>`. No audit and no assertion beyond the sheet
/// opening; the audits are `LightSheetsJourneyTests`.
@MainActor
final class LightSheetCaptureTests: JourneyTestCase {
    private func capture(_ name: String, page: String, environment: [String: String] = [:], arguments: [String] = [],
                         fresh: Bool = false, ready: @escaping (XCUIApplication) -> XCUIElement) {
        for appearance in ["light", "dark"] {
            let configured = FentonHomeApp.makeApp()
            configured.launchEnvironment["FENTON_GALLERY"] = page
            // A gallery setting, so light and dark are resets of one resident app, not two launches.
            configured.launchEnvironment["FENTON_GALLERY_APPEARANCE"] = appearance
            configured.launchEnvironment.merge(environment) { _, new in new }
            configured.launchArguments += arguments
            let app: XCUIApplication
            if fresh {
                AppReuse.willLaunchOutside()
                configured.launch()
                app = configured
            } else {
                app = startApp(configured)
            }
            let anchor = ready(app)
            XCTAssertTrue(anchor.appears(timeout: 30), "\(name) did not open")
            XCTAssertTrue(anchor.wait(for: \.isHittable, toEqual: true, timeout: 10), "\(name) is still presenting")
            settleScreen()
            keepScreenshot(app, "g4-\(name)-\(appearance)-\(layout)")
            if fresh { app.terminate() }
        }
    }

    private func captureGallerySheet(_ section: String) {
        capture("gallery-\(section.lowercased())", page: "direction-g",
                environment: ["FENTON_GALLERY_DIRECTION_G_SHEET": "open", "FENTON_GALLERY_DIRECTION_G_SHEET_SECTION": section]) { self.element("g.sheet.tabs", in: $0) }
    }

    func testCaptureGallerySheetControls() { captureGallerySheet("Controls") }

    func testCaptureGallerySheetFamilies() { captureGallerySheet("Families") }

    func testCaptureGallerySheetSettings() { captureGallerySheet("Settings") }

    private func captureSecuritySheet(_ appearance: String) {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "security"
        configured.launchEnvironment["FENTON_GALLERY_APPEARANCE"] = appearance
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["security.chip.security"].appears(timeout: 30))
        app.buttons["security.chip.security"].tap()
        XCTAssertTrue(app.navigationBars["Security System"].appears(timeout: 10))
        XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
        settleScreen()
        keepScreenshot(app, "g4-security-\(appearance)-\(layout)")
    }

    func testCaptureSecuritySheetLight() { captureSecuritySheet("light") }

    func testCaptureSecuritySheetDark() { captureSecuritySheet("dark") }

    func testClimateSheet() {
        capture("climate-rooms", page: "climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": "rooms", "FENTON_GALLERY_CLEAN": "1"]) {
            $0.buttons["Close"]
        }
        capture("climate-room", page: "climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": "room:bedroom_1", "FENTON_GALLERY_CLEAN": "1"]) {
            $0.buttons["Close"]
        }
    }

    func testRemoteSheet() {
        capture("remote", page: "media-remote", environment: [
            "FENTON_GALLERY_REMOTE": expectations[.remoteLivingRoomId], "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_OFFLINE": "1",
        ]) { self.element("remote.power", in: $0) }
    }

    func testCapturePurifierSheet() {
        capture("purifier", page: "room-devices", environment: [
            "FENTON_GALLERY_DEVICE": "purifier-auto", "FENTON_GALLERY_TAB": "controls", "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("purifier.mode", in: $0) }
    }

    func testCaptureBedSheet() {
        capture("bed", page: "bedroom", environment: [
            "FENTON_GALLERY_SCENARIO": "default", "FENTON_GALLERY_SHEET": expectations[.bedFirstSheetId], "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("bed.hint", in: $0) }
    }

    /// `fresh: true`: after other captures the reused app drew the dark sheet's grab handle black (the pixel comparison with a fresh
    /// launch differed, 2026-11-03); a fresh process draws it as before. Cause not found.
    func testQuickLinksSheet() {
        capture("quick-links", page: "rooms", environment: [
            "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_QUICK_LINKS": "1", "FENTON_GALLERY_CLEAN": "1",
        ], fresh: true) { self.element("quickLinks.rooms", in: $0) }
    }

    private func captureVacuumSheet(_ tab: String) {
        capture("vacuum-\(tab)", page: "vacuums", environment: [
            "FENTON_GALLERY_VACUUM": JourneyExpectations.gallery[.vacuumMainFloorMapId], "FENTON_GALLERY_TAB": tab,
            "FENTON_GALLERY_SCENARIO": "docked", "FENTON_GALLERY_CLEAN": "1",
        ]) { self.element("vacuum.tabs", in: $0) }
    }

    func testCaptureVacuumSheetControls() { captureVacuumSheet("controls") }

    func testCaptureVacuumSheetZones() { captureVacuumSheet("zones") }
}
