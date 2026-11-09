import XCTest

/// The base of the room device journeys: the gallery launch, the segmented-choice and recording-call helpers, the scroll-to-reveal
/// loop and the per-device accessibility audit every device class shares. The old single `RoomDevicesJourneyTests` class was split by
/// device (`contracts/test-map.json`) so a change to one sheet runs only its journeys; nothing here is specific to one device.
/// The gallery fixtures drive every sheet (fixture state, recording service caller; nothing reaches the house)
/// (`.agents/patterns/room-device-sheets.md`). Launching through `startApp` opts every device class into app reuse.
@MainActor
class RoomDevicesJourneyTestCase: JourneyTestCase {

    // MARK: - Helpers

    /// Opens a gallery fixture's sheet and waits for `ready` to be hittable.
    func launch(_ device: String, ready: String, tab: String = "controls", clean: Bool = false,
                        appearance: String? = nil, sheetProbe: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        if let appearance { configured.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        configured.launchEnvironment["FENTON_GALLERY"] = "room-devices"
        configured.launchEnvironment["FENTON_GALLERY_DEVICE"] = device
        configured.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        // Lets `assertTarget(_:inSheet:)` read the sheet's scale. Off for audits: the probe is an element they would see.
        if sheetProbe { configured.launchEnvironment["FENTON_SHEETFIT_PROBE"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        let element = element(ready, in: app)
        XCTAssertTrue(element.appears(timeout: 30), "\(device) sheet did not open")
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    /// One option of a segmented choice (`SegmentedChoice`), found by its control and title.
    func segment(_ control: String, _ title: String, in app: XCUIApplication) -> XCUIElement {
        app.segmentedControls[control].buttons[title].firstMatch
    }

    func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Scrolls the column holding `element` in short drags until it is hittable (anchored on the window so
    /// gestures reach the inner display of an unfolded iPhone Duo).
    ///
    /// `onLeadingEdge`: drags 10 pt in from the window's leading edge, outside every dial (a drag that starts on a dial handle moves the handle,
    /// not the page), for a target that is, or sits below, a dial.
    ///
    /// Each look is one element snapshot (the frame and whether it is in the tree); `isHittable` is asked only once the frame is on
    /// screen. The loop gives up after 3 drags that leave the element where it was (a target at the foot of the column can never
    /// move further), and says what covers it.
    func reveal(_ element: XCUIElement, in app: XCUIApplication, onLeadingEdge: Bool = false) {
        let window = app.windows.firstMatch.frame
        // A page's leading edge holds no dial, so a long target (the AX5 column is some 5,700 pt tall) takes bigger drags.
        let step: CGFloat = onLeadingEdge ? 440 : 220
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<30 {
            let frame = (try? element.snapshot())?.frame
            let inTree = frame.map { !$0.isEmpty } ?? false
            if inTree, element.isHittable { return }
            let above = inTree && frame!.midY < window.midY && frame!.maxY < window.minY + 120
            if let frame, inTree, let lastMinY, abs(frame.minY - lastMinY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 3 { break }
            lastMinY = inTree ? frame!.minY : nil
            var x = onLeadingEdge ? window.minX + 10 : (inTree && frame!.midX > 0 ? frame!.midX : window.midX)
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? step : -step)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        if !isReachable(element) {
            // What else is on the element's centre, topmost last, so a covered control names what covers it.
            let frame = (try? element.snapshot())?.frame ?? .zero
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            let covering = app.descendants(matching: .any).allElementsBoundByIndex.filter { $0.exists && $0.frame.contains(centre) && !$0.frame.isEmpty }
                .suffix(8).map { "\($0.elementType.rawValue) '\($0.identifier)' \($0.frame)" }
            XCTFail("\(element) never came into view; on its centre: \(covering)")
        }
    }

    /// A 44 pt control inside a content-fitted sheet. iOS draws the inset (non-large) sheet's content at 0.955x (384 of 402 pt
    /// wide on iPhone), so a 44 pt target measures 42 pt there; the large sheet draws it at full size.
    func assertSheetTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let facts = try? element.snapshot()
        XCTAssertGreaterThanOrEqual(facts?.frame.height ?? 0, 41.5, facts?.label ?? "", file: file, line: line)
        XCTAssertGreaterThanOrEqual(facts?.frame.width ?? 0, 41.5, facts?.label ?? "", file: file, line: line)
    }

    // MARK: - Poses

    /// The pose a split test runs in. Phones and the Duo have one pose, so `upright` leaves them as they are; on an iPad it sets
    /// portrait. `iPadLandscape` is the iPad-only second pose (skipped elsewhere): the layout-relevant one.
    enum Pose { case upright, iPadLandscape }

    /// Sets the orientation `pose` names before the launch, or skips (before any launch) when this family does not have the pose.
    func enter(_ pose: Pose) throws {
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        case .iPadLandscape:
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    // MARK: - Accessibility audit

    /// Audits one device sheet in one pose (see `enter(_:)`): the plain launch, then the AX5 relaunch the audit compares against.
    func audit(_ device: String, ready: String, tab: String = "controls", pose: Pose = .upright) throws {
        try enter(pose)
        let app = launch(device, ready: ready, tab: tab)
        try FentonHomeApp.audit(app) { self.launch(device, ready: ready, tab: tab, arguments: FentonHomeApp.ax5) }
    }
}
