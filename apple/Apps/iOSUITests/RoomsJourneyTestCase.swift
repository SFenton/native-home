import XCTest

/// The base of the Rooms journeys: the `rooms` gallery launch (fixture state, recording service caller, offline; nothing reaches the house) through
/// `startApp`, so every area class is on app reuse (`.agents/testing/apple/app-reuse.md`), the recorded-call check, the window's own scroll-to-reveal
/// drag and the per-screen accessibility audit. The old single `RoomsJourneyTests` class was split by area (`contracts/test-map.json`) so a change
/// to one source file runs only its journeys; nothing here is specific to one area. iPhone, iPhone Duo and iPad (`.agents/pages/rooms/`).
@MainActor
class RoomsJourneyTestCase: JourneyTestCase {

    // MARK: - Helpers

    func launch(room: String? = nil, quickLinks: Bool = false, clean: Bool = false, scenario: String? = nil,
                sheetProbe: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "rooms"
        if let scenario { configured.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario }
        configured.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        if let room { configured.launchEnvironment["FENTON_GALLERY_ROOM"] = room }
        if quickLinks { configured.launchEnvironment["FENTON_GALLERY_QUICK_LINKS"] = "1" }
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        // Lets `assertTarget(_:inSheet:)` read the sheet's scale. Off for audits: the probe is an element they would see.
        if sheetProbe { configured.launchEnvironment["FENTON_SHEETFIT_PROBE"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        let ready = room.map { element("room.scroll.\($0)", in: app) } ?? (quickLinks ? element("quickLinks.rooms", in: app) : app.buttons["gallery.quickLinks"])
        XCTAssertTrue(ready.appears(timeout: 30), "Gallery did not open")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls the window in short drags until `element` is hittable (see `MediaRemoteJourneyTests.reveal`). One snapshot of the element per
    /// look (in the tree, where, which way to drag); the window is read once; `isHittable` is asked only once the frame is on screen. Stops
    /// after 3 drags that do not move the element (a row at the foot of a short page can never come clear).
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        var x = window.midX
        if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<24 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty, element.isHittable { return }
            let above = frame.map { !$0.isEmpty && $0.midY < window.midY && $0.maxY > 0 } ?? false
            if let frame, let lastMinY, abs(frame.minY - lastMinY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 3 { break }
            lastMinY = frame?.minY
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    // MARK: - Poses

    /// The pose a Rooms journey runs in. `.upright` runs on every family (iPad sets portrait first); `.iPadLandscape` (the `InIPadLandscape`
    /// method) runs on iPad only and skips elsewhere before any launch. The landscape step is the layout-relevant one (`layout_journeys`).
    enum Pose: String {
        case upright, iPadLandscape

        /// The name a capture or screenshot carries: `current` on a device that has no second pose.
        @MainActor var captureSuffix: String { FentonHomeApp.family == .iPad ? (self == .iPadLandscape ? "landscape" : "portrait") : "current" }
    }

    /// Puts the device in `pose` before the launch (iPad only; `tearDown` returns it to portrait), or skips a pose the family does not have.
    func enter(_ pose: Pose) throws {
        guard FentonHomeApp.family == .iPad else {
            try XCTSkipIf(pose == .iPadLandscape, "Only iPad has a second pose; the iPhone is portrait-only and the Duo's journeys run in their one pose")
            return
        }
        XCUIDevice.shared.orientation = pose == .iPadLandscape ? .landscapeLeft : .portrait
    }

    // MARK: - Accessibility audit

    /// One audit of a Rooms screen in `pose`.
    func audit(room: String? = nil, quickLinks: Bool = false, pose: Pose) throws {
        try enter(pose)
        let app = launch(room: room, quickLinks: quickLinks, clean: true)
        try FentonHomeApp.audit(app) { self.launch(room: room, quickLinks: quickLinks, clean: true, arguments: FentonHomeApp.ax5) }
    }
}
