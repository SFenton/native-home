import XCTest

/// The base of the Vacuum journeys: the gallery launch (`FENTON_GALLERY=vacuums`, fixture state, mock maps, a recording service caller; nothing
/// reaches a real robot), the recorded-call check, the sheet's own scroll-to-reveal drag, the section bar and the per-screen accessibility audit.
/// The old single `VacuumJourneyTests` class was split by area (`contracts/test-map.json`) so a change to one tab runs only its journeys; nothing
/// here is specific to one area. Launching through `startApp` opts every area class into app reuse (`.agents/testing/apple/app-reuse.md`).
/// iPhone, iPhone Duo and iPad (`.agents/patterns/vacuum-sheet.md`).
@MainActor
class VacuumJourneyTestCase: JourneyTestCase {
    static let mainFloor = JourneyExpectations.gallery[.vacuumMainFloorMapId]
    static let musicRoom = JourneyExpectations.gallery[.vacuumMusicRoomMapId]

    // MARK: - Helpers

    /// Opens the gallery page, or a vacuum's sheet on `tab`.
    func launch(_ vacuum: String? = nil, tab: String = "controls", scenario: String = "docked",
                        clean: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "vacuums"
        if let vacuum { configured.launchEnvironment["FENTON_GALLERY_VACUUM"] = vacuum }
        configured.launchEnvironment["FENTON_GALLERY_TAB"] = tab
        configured.launchEnvironment["FENTON_GALLERY_SCENARIO"] = scenario
        if clean { configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1" }
        configured.launchArguments += arguments
        let app = startApp(configured)
        let anchor = vacuum == nil ? element("vacuums.tile.\(Self.mainFloor)", in: app) : element("vacuum.tabs", in: app)
        XCTAssertTrue(anchor.appears(timeout: 30), "Vacuums did not open")
        // The section bar floats at the bottom of the sheet during the presentation; the Close button proves it settled.
        // Not through `navigationBars`: the folded Duo's rail takes the bar's Close into its own toolbar.
        let settled = vacuum == nil ? anchor : app.buttons["Close"].firstMatch
        XCTAssertTrue(settled.wait(for: \.isHittable, toEqual: true, timeout: 10), "Still presenting")
        settleScreen() // Mid-animation frames fail contrast and clipping.
        return app
    }

    func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    /// Drags toward `element` in short steps until it is hittable and clear of the Last call bar and the section bar.
    ///
    /// One element snapshot per drag answers "in the tree", "where" and "which way"; `isHittable` (a live read) is asked only once the
    /// frame is clear; the floating bars are measured once, since they do not move; and the scroll stops when drags no longer move the
    /// element (the foot of the sheet), instead of dragging until a deadline (see MediaRemoteJourneyTests.reveal).
    func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        let window = app.windows.firstMatch.frame
        // The gallery's Last call bar floats over the bottom of the sheet (absent in the clean gallery); a control under it is not
        // reachable. The section bar floats over the sheet's bottom, above the Last call line (the UIKit sheet's pinned bar holds both):
        // a control is clear of it when it ends above the bar, and a drag that starts under it would land on the bar, not the scroll view.
        let barFrame = (try? app.staticTexts["gallery.lastCall"].firstMatch.snapshot())?.frame
        let sectionsFrame = (try? app.descendants(matching: .any)["vacuum.tabs"].firstMatch.snapshot())?.frame
        let sectionTop = sectionsFrame.flatMap { $0.minY > window.midY ? $0.minY : nil }
        // The bar's background starts 4 pt above its text; a control ending there is fully visible.
        let top = min(barFrame.map { $0.minY + 1 } ?? .infinity, sectionTop ?? .infinity)
        func isClear(_ frame: CGRect) -> Bool {
            top == .infinity || frame.maxY <= top || (barFrame.map { frame.minY >= $0.maxY } ?? false)
        }
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        var frame: CGRect?
        var lastMinY: CGFloat?
        var stuck = 0
        let end = Date().addingTimeInterval(90)
        while Date() < end {
            let snapshot = try? element.snapshot()
            frame = snapshot.map(\.frame).flatMap { $0.isEmpty ? nil : $0 }
            if let frame, isClear(frame), element.isHittable {
                element.settled()
                if let settled = (try? element.snapshot())?.frame, isClear(settled), element.isHittable { break }
            }
            if let frame, let lastMinY, abs(lastMinY - frame.minY) < 1 { stuck += 1 } else { stuck = 0 }
            if stuck >= 3 { break }
            lastMinY = frame?.minY
            let above = frame.map { $0.midY < window.midY } ?? !down
            var x = frame.map { $0.midX > 0 ? $0.midX : window.midX } ?? window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            // Start on the control itself when it is on screen (e.g. under the Last call bar), kept clear of the edges.
            var y = window.minY + window.height * (above ? 0.35 : 0.65)
            if let frame, window.intersects(frame) {
                y = min(max(frame.midY, window.minY + 150), min(window.maxY - 150, (sectionTop ?? .infinity) - 30))
            } else if frame != nil, let id = snapshot?.identifier, !id.isEmpty {
                // Off screen: drag near the leading edge of the narrowest scroll view over it (the sheet's column, not
                // the page behind), clear of the map in the middle and of the back-swipe edge.
                let holders = app.scrollViews.containing(.any, identifier: id).allElementsBoundByIndex
                let column = holders.map(\.frame).filter { $0.height > 200 }.min { $0.width < $1.width }
                if let column { x = max(column.minX, window.minX) + 24 }
            }
            let from = origin.withOffset(CGVector(dx: x, dy: y))
            // A control far below the fold (AX5 stacks everything in one tall column) takes bigger drags.
            let far = frame.map { !window.intersects($0) } ?? false
            let step: CGFloat = far ? min(window.height * 0.5, 420) : 220
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? step : -step)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        // Bring a control low on the screen up toward the middle, clear of anything floating at the bottom.
        if let frame = (try? element.snapshot())?.frame, !frame.isEmpty, frame.maxY > window.maxY - window.height * 0.3 {
            var x = frame.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: window.midY - frame.midY)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        // The control must end hittable and clear of the floating bars: a control still under the Last call bar or the section bar
        // is hittable by frame but a tap would land on the bar.
        let finalFrame = (try? element.snapshot())?.frame
        if !element.isHittable || finalFrame.map({ !isClear($0) }) ?? true {
            add(XCTAttachment(string: "frame \(String(describing: finalFrame))\n" + app.debugDescription))
            XCTFail("\(element) never came into view clear of the floating bars (frame \(String(describing: finalFrame)), bars start at y \(top))")
        }
    }

    /// Drags the section's content up to the top of the sheet, as a reader would, so it is on screen. The section bar
    /// floats at the bottom (direction G), so the content's top edge is the mark.
    func scrollToTabContent(in app: XCUIApplication) {
        let content = element("vacuum.tabContent", in: app)
        guard (try? content.snapshot()) != nil, element("vacuum.layout.singleColumn", in: app).exists else { return }
        let window = app.windows.firstMatch.frame
        let top = window.minY + window.height * 0.18
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
        // Start low in the sheet, clear of the map and above the section bar (never at the bottom edge: that is the
        // Home gesture and backgrounds the app), near the leading edge, clear of the Duo's hinge.
        let from = origin.withOffset(CGVector(dx: window.minX + 40, dy: window.minY + window.height * 0.7))
        // One snapshot per drag gives the content's top edge (it was two frame reads).
        for _ in 0..<6 {
            guard let minY = (try? content.snapshot())?.frame.minY, minY > top + 40 else { break }
            let distance = min(minY - top, window.height * 0.45)
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -distance)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        // Let the scroll settle: a frame captured mid-deceleration samples text at stale positions.
        content.settled(maxWait: 5)
    }

    /// Picks a section from the bottom section bar, or from its menu at accessibility sizes. The bar floats over the
    /// sheet, so it is always on screen.
    func tab(_ title: String, in app: XCUIApplication) {
        let picker = element("vacuum.tabs", in: app)
        XCTAssertTrue(picker.appears(timeout: 10), "No section bar")
        let segment = picker.buttons[title].firstMatch
        if segment.exists {
            segment.tap()
        } else {
            // The menu's rows read as buttons or as menu items depending on the layout; under load the first tap
            // can land while the picker is still settling, so open the menu again if nothing appeared.
            let button = app.buttons[title].firstMatch, menuItem = app.menuItems[title].firstMatch
            var shown = false
            for _ in 0..<2 where !shown {
                picker.tap()
                shown = button.appears(timeout: 5) || menuItem.appears(timeout: 2)
            }
            if !shown { add(XCTAttachment(string: app.debugDescription)) }
            XCTAssertTrue(shown, "No \(title) menu item")
            (button.exists ? button : menuItem).tap()
        }
    }

    // MARK: - Audits

    /// The pose an audit runs in. Phones and the Duo have one pose, so ``upright`` leaves them as they are; on an iPad it sets portrait.
    /// ``iPadLandscape`` is the iPad-only second pose (skipped elsewhere): the layout-relevant one.
    enum Pose { case upright, iPadLandscape }

    /// Audits one screen in one `pose` (the iPad's two poses used to be a loop here; each is its own test now).
    func audit(_ vacuum: String?, tab: String = "controls", scenario: String = "docked", pose: Pose = .upright) throws {
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        case .iPadLandscape:
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        // Clean gallery: the debug Last call bar is not product UI, and text half under it can't be judged.
        let app = launch(vacuum, tab: tab, scenario: scenario, clean: true)
        if tab != "controls" { scrollToTabContent(in: app) }
        try FentonHomeApp.audit(app) { self.launch(vacuum, tab: tab, scenario: scenario, clean: true, arguments: FentonHomeApp.ax5) }
    }
}
