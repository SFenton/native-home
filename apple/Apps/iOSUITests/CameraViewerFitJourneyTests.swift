import XCTest

/// The camera viewer's sheet is content-fitted (owner, 2026-10-23; `.agents/patterns/modal-sheet.md`, Camera viewer):
/// it opens only as tall as the video and its controls, and never resizes while open. Runs on the `camera-viewer`
/// gallery (fixture cameras, no stream) on iPhone, iPhone Duo and iPad.
@MainActor
final class CameraViewerFitJourneyTests: JourneyTestCase {
    /// Launches (or resets) the camera viewer gallery with the viewer open on `stream`. The stream is `FENTON_GALLERY_CAMERA_VIEWER_OPEN`
    /// (the `-cameraViewerOpen` argument's gallery-setting form), so each test is a reset of the class's resident app
    /// (`app-reuse.md`); AX5 stays a launch argument (its own process). `FENTON_SHEETFIT_RESET=1` makes a reset clear the remembered
    /// sheet heights, so the first-open tests still see a first presentation.
    private func open(_ stream: String, arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "camera-viewer"
        configured.launchEnvironment["FENTON_GALLERY_CAMERA_VIEWER_OPEN"] = stream
        configured.launchEnvironment.merge(environment) { _, new in new }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["camera.control.snapshot"].appears(timeout: 20), "The viewer did not open")
        settleScreen() // The presentation and the first measurement.
        let tree = XCTAttachment(string: "window \(app.windows.firstMatch.frame)\n\(app.debugDescription)")
        tree.name = "element-tree"
        tree.lifetime = .keepAlways
        add(tree)
        return app
    }

    /// The sheet is as tall as the video and controls, not the large detent: the large detent would put the video in the
    /// top sixth with a screenful of empty ground under the controls. Where the content is taller than the large detent
    /// (the folded Duo's is about 430 pt) the sheet is at large instead and the controls are a scroll away.
    func testViewerOpensAtContentHeight() {
        let app = open("front_door")
        let window = app.windows.firstMatch.frame
        let video = app.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame
        let snapshot = app.buttons["camera.control.snapshot"]
        keepScreenshot(app, "camera-viewer-fit-\(layout)")
        if window.contains(snapshot.frame) {
            // The controls end one page padding above the home-indicator area (`SheetBottomGapJourneyTests`): about 56 pt on an iPhone, 58 on the folded Duo.
            XCTAssertLessThan(window.maxY - snapshot.frame.maxY, 75, "Empty ground under the controls: \(window.maxY - snapshot.frame.maxY) pt")
            if FentonHomeApp.family == .iPhone {
                XCTAssertGreaterThan(video.minY, window.height * 0.3, "The viewer opened at full height: video at \(video.minY) of \(window.height)")
            }
        } else {
            for _ in 0..<4 where !snapshot.isHittable { app.swipeUp() }
            XCTAssertTrue(snapshot.isHittable, "The controls are neither shown nor reachable by scrolling")
        }
        let first = video
        sleep(2) // Asserts that nothing happens: the sheet must not resize while open.
        XCTAssertEqual(app.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame.minY, first.minY, accuracy: 1,
                       "The sheet resized while open")
    }

    /// A wide camera makes a shorter sheet than a 4:3 one: the camera's own aspect sets the height.
    func testWideCameraOpensShorter() {
        let tall = open("front_door")
        let tallTop = tall.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame.minY
        let wide = open("garage_camera")
        let wideTop = wide.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame.minY
        XCTAssertGreaterThan(wideTop, tallTop, "A 10:3 camera should open a shorter sheet than a 4:3 one")
    }

    /// At AX5 the controls stack and the sheet may reach large; everything is still reachable by scrolling.
    func testControlsReachableAtAccessibilitySizes() {
        let app = open("front_door", arguments: FentonHomeApp.ax5)
        keepScreenshot(app, "camera-viewer-fit-ax5-\(layout)")
        let snapshot = app.buttons["camera.control.snapshot"]
        for _ in 0..<4 where !snapshot.isHittable { app.swipeUp() }
        XCTAssertTrue(snapshot.isHittable, "The Snapshot control cannot be reached at AX5")
    }

    /// iPad landscape puts the video beside the controls; the sheet is still fitted to that row, not to the controls alone.
    func testLandscapeSplitFitsTheVideo() throws {
        try XCTSkipUnless(FentonHomeApp.family == .iPad, "Only iPad rotates here (an unfolded Duo hangs the runner, devices.md)")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = open("front_door")
        XCTAssertTrue(app.descendants(matching: .any)["camera.layout.split"].appears(timeout: 5), "Landscape iPad should split")
        let window = app.windows.firstMatch.frame
        let video = app.descendants(matching: .any)["camera.viewer.video"].firstMatch.frame
        let snapshot = app.buttons["camera.control.snapshot"].frame
        keepScreenshot(app, "camera-viewer-fit-split-\(layout)")
        XCTAssertLessThanOrEqual(video.maxX, snapshot.minX, "Controls trail the video")
        XCTAssertGreaterThan(video.height, 150, "The video is squeezed: \(video)")
        XCTAssertTrue(window.contains(video) && window.contains(snapshot), "Video or controls fall outside the window")
        // A fitted iPad sheet is centred, so measure what it leaves above it: the large page sheet put the video at 142 pt of 834.
        XCTAssertGreaterThan(video.minY, window.height * 0.25, "The sheet reaches the top: video at \(video.minY) of \(window.height)")
        // The sheet's scroller fills the sheet. It ends one page padding (16 pt) under the taller of the video and the
        // controls column: the first measurement once came from a layout at the full window width and left ~106 pt of
        // slack under them (an iPad sheet does not resize after it opens).
        let sheet = app.scrollViews.containing(.other, identifier: "camera.layout.split").firstMatch.frame
        let content = max(video.maxY, app.switches["camera.control.record"].frame.maxY)
        XCTAssertLessThan(sheet.maxY - content, 40, "Empty ground under the video and controls: \(sheet.maxY - content) pt")
    }

    // MARK: - First open

    /// Taps the sheet's Close button in its lower part. On the folded Duo a sheet that opens at y 113 (the Front Door viewer now that its
    /// detent leaves out the bottom safe area; it used to be pinned at 82) puts the button's centre under the status pill, which
    /// swallows an element tap there (measured 2026-10-28: centre y 153 does nothing, 165 closes), so the sheet never closed and the next
    /// camera's button was tapped through the open sheet.
    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["sheet.close"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        XCTAssertTrue(app.buttons["camera.control.snapshot"].disappears(timeout: 8), "The sheet did not close")
    }

    /// The viewer's page scroller, which fills the sheet: its frame is the sheet's.
    private func sheetFrame(_ app: XCUIApplication) -> CGRect {
        app.scrollViews.containing(.other, identifier: "camera.layout.stacked").firstMatch.frame
    }

    /// Where the sheet's width is not known before it opens (a regular-width page sheet) only a camera opened before has its height.
    private var regularWidth: Bool { FentonHomeApp.family == .iPad }

    /// Records the sheet's frame once the presentation has settled and again 1.5 s later: a sheet that measured after it
    /// opened and then moved would differ.
    ///
    /// - Parameter firstEver: This is the very first sheet shown in this context (after install, sign-out or a text-size
    ///   change). Owner decision, 2026-10-26: there is no warm-up, so that one sheet may correct once, by a few points, while it
    ///   learns what the system's sheets add around a page; every later sheet opens at its final height with zero moves.
    private func assertSettled(_ app: XCUIApplication, _ name: String, firstEver: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.buttons["camera.control.snapshot"].appears(timeout: 20), "\(name) did not open", file: file, line: line)
        usleep(800_000) // The presentation animation.
        let early = sheetFrame(app)
        let probe = app.descendants(matching: .any)["sheet.fit.probe"].firstMatch.value as? String ?? "no probe"
        sleep(1)
        usleep(500_000)
        let late = sheetFrame(app)
        keepScreenshot(app, "sheet-\(name)-\(layout)")
        let note = XCTAttachment(string: "\(name): early \(early) late \(late) probe \(probe) window \(app.windows.firstMatch.frame)")
        note.name = "sheet-frames-\(name)"
        note.lifetime = .keepAlways
        add(note)
        // A move while the presentation animates is over before any frame is read: the probe counts it.
        let allowed = firstEver ? 1 : 0
        let moves = probe.components(separatedBy: "moves=").dropFirst().first.flatMap { Int($0.prefix { $0.isNumber }) }
        XCTAssertTrue(regularWidth || (moves.map { $0 <= allowed } ?? false), "\(name): \(firstEver ? "the first sheet may move once, not more" : "a measurement moved the sheet after it opened"): \(probe)", file: file, line: line)
        XCTAssertGreaterThan(early.height, 100, "\(name): no sheet found at \(early)", file: file, line: line)
        XCTAssertEqual(late.minY, early.minY, accuracy: 1, "\(name): the sheet moved after it settled: \(early) then \(late)", file: file, line: line)
        XCTAssertEqual(late.height, early.height, accuracy: 1, "\(name): the sheet resized after it settled: \(early) then \(late)", file: file, line: line)
    }

    /// With every sheet-fit memory cleared (the very first sheet this device ever shows), the viewer opens at the height computed
    /// before it opens, which may be a few points off once (no warm-up teaches the sheets' chrome first: owner, 2026-10-26).
    /// Then Driveway (10:3, another height) opens at its final height with no move. Where the width is not known beforehand (iPad's page sheet) the sheet still opens at the
    /// camera's remembered height, so the second open there is the one that is exact.
    func testFirstOpenIsAtTheFinalHeight() {
        let app = open("front_door", environment: ["FENTON_SHEETFIT_RESET": "1", "FENTON_SHEETFIT_PROBE": "1"])
        assertSettled(app, "front-door-first-open", firstEver: true)
        let front = sheetFrame(app)
        closeSheet(app)
        let driveway = app.buttons["cameraViewer.open.garage_camera"]
        XCTAssertTrue(driveway.appears(timeout: 10), "The sheet did not close")
        driveway.tap()
        assertSettled(app, "driveway-first-open")
        let wide = sheetFrame(app)
        if wide.height < app.windows.firstMatch.frame.height - 100, front.height < app.windows.firstMatch.frame.height - 100 {
            XCTAssertLessThan(wide.height, front.height, "A 10:3 camera should open a shorter sheet than a 4:3 one")
        }
    }

    /// Every camera in turn, the very first sheet of the device being the first one opened: that one may correct once (it
    /// teaches the chrome), every later one opens at its final height with zero moves.
    func testEveryCameraOpensAtItsFinalHeight() {
        let app = open("garage_camera", environment: ["FENTON_SHEETFIT_RESET": "1", "FENTON_SHEETFIT_PROBE": "1"])
        assertSettled(app, "driveway-first-sheet", firstEver: true)
        for (stream, name) in [("upper_deck", "upper-deck"), ("lower_deck", "lower-deck"), ("front_door", "front-door"), ("garage_camera", "driveway-again")] {
            closeSheet(app)
            let button = app.buttons["cameraViewer.open.\(stream)"]
            XCTAssertTrue(button.appears(timeout: 10), "The sheet did not close")
            button.tap()
            assertSettled(app, "\(name)-in-turn")
        }
    }

    /// The same at AX5, where the controls stack in a column and the prediction must lay them out at that size.
    func testFirstOpenAtAccessibilitySizeIsAtTheFinalHeight() {
        let app = open("front_door", arguments: FentonHomeApp.ax5, environment: ["FENTON_SHEETFIT_RESET": "1", "FENTON_SHEETFIT_PROBE": "1"])
        assertSettled(app, "front-door-first-open-ax5", firstEver: true)
        closeSheet(app)
        let driveway = app.buttons["cameraViewer.open.garage_camera"]
        XCTAssertTrue(driveway.appears(timeout: 10), "The sheet did not close")
        driveway.tap()
        assertSettled(app, "driveway-first-open-ax5")
    }
}
