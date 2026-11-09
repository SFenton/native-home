import XCTest

/// The bed sheet's layout per pose (hero beside the tabs only on iPad landscape and unfolded Duo landscape). Its own class, named to sort last: it rotates the iPad.
@MainActor
final class BedroomWideLayoutJourneyTests: BedroomJourneyTestCase {
    // MARK: - Layout

    /// iPad portrait is one column. Phones and the Duo run only this one (the window decides the layout).
    func testLayoutFollowsThePose() throws {
        try enter(.upright)
        let app = launch(sheet: expectations[.bedFirstSheetId])
        if FentonHomeApp.family == .iPad {
            XCTAssertTrue(element("bed.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            return
        }
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720 ? "bed.layout.twoColumn" : "bed.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    /// iPad landscape splits (hero beside the tabs). Skips on other families.
    func testLayoutFollowsThePoseInIPadLandscape() throws {
        try enter(.iPadLandscape)
        let app = launch(sheet: expectations[.bedFirstSheetId])
        XCTAssertTrue(element("bed.layout.twoColumn", in: app).appears(timeout: 5), "iPad landscape splits")
    }
}
