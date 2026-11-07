import XCTest

/// The base every journey subclasses: setup, orientation and the gallery helpers each journey used to redeclare
/// (`.agents/archive/audit/tests.md` findings 1 and 2).
///
/// A run asks for landscape with `TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape` (the older `FENTON_ORIENTATION`
/// also works). Only the families in ``rotatingFamilies`` turn; every test ends back in portrait.
@MainActor
class JourneyTestCase: XCTestCase {
    /// Whether this run is the landscape pass.
    static var wantsLandscape: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["FENTON_UITEST_ORIENTATION"] == "landscape" || environment["FENTON_ORIENTATION"] == "landscape"
    }

    /// The families a landscape run rotates. iPhone is portrait-locked; override to add the unfolded Duo.
    class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad] }

    /// `iphone`, `ipad-landscape` and so on, for screenshot names.
    var layout: String {
        let landscape = Self.wantsLandscape && Self.rotatingFamilies.contains(FentonHomeApp.family) ? "-landscape" : ""
        return "\(FentonHomeApp.family)\(landscape)"
    }

    /// Whether this class measures animation (motion and performance tests): its launches keep the app's animations on.
    /// Every other journey launches with them off (`FENTON_UITEST_NO_ANIMATIONS`), so it never waits out a transition.
    class var measuresAnimation: Bool { false }

    /// The expectations of a gallery journey: the DemoHouse values the gallery draws. Signed-in journeys that assert house content
    /// call `try JourneyExpectations.current(for: .signedIn)` instead, which skips on the owner's house without the private file.
    var expectations: JourneyExpectations { .gallery }

    override func setUp() {
        continueAfterFailure = false
        // The capture tests (every screen in each pose) and the motion and performance tests legitimately run 450 to 480 s on
        // an iPad, over the runner's default 300 s allowance; the runner's 900 s maximum still bounds them.
        if name.contains(" testCapture") || Self.measuresAnimation { executionTimeAllowance = 600 }
        FentonHomeApp.animationsOff = !Self.measuresAnimation
            && ProcessInfo.processInfo.environment["FENTON_UITEST_ANIMATIONS"] != "1"
        if Self.rotatingFamilies.contains(FentonHomeApp.family), Self.wantsLandscape {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    /// Ends the class's resident app when reuse is on (``AppReuse``).
    override class func tearDown() {
        MainActor.assumeIsolated { AppReuse.finish(owner: String(describing: self)) }
        super.tearDown()
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if Self.rotatingFamilies.contains(FentonHomeApp.family) { XCUIDevice.shared.orientation = .portrait }
        }
    }

    // MARK: - Shell navigation

    /// Opens a root section through whichever navigation the window shows (`ShellNavigationStyle`): the tab bar
    /// (iPhone), the folded iPhone Duo's vertical bar (a toolbar to XCUITest), or the flyout in regular width
    /// (iPad, unfolded Duo). Compact windows also show the menu button, so a visible bar item wins.
    /// - Parameters:
    ///   - section: The `AppSection` raw value (`security`), whose flyout row is `nav.<section>`.
    ///   - title: The section's visible name (`Security`), which labels its bar item.
    func openSection(_ section: String, title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let items = [app.barItem(title)]
        let menu = app.buttons["nav.open"]
        let start = Date()
        let deadline = start.addingTimeInterval(10)
        repeat {
            if let item = items.first(where: { $0.exists && $0.isHittable }) {
                item.tap()
                return
            }
            // A bar that exists but stays off screen (a regular-width window) gets two seconds to show.
            if menu.exists, menu.isHittable, !items.contains(where: \.exists) || Date().timeIntervalSince(start) > 2 { break }
            usleep(100_000)
        } while Date() < deadline
        XCTAssertTrue(menu.exists, "\(title) has no tab and the window has no menu", file: file, line: line)
        menu.tap()
        XCTAssertTrue(element("nav.flyout", in: app).appears(timeout: 5), "Menu did not open", file: file, line: line)
        app.buttons["nav.\(section)"].tap()
        XCTAssertTrue(element("nav.flyout", in: app).disappears(timeout: 5), "Menu stayed open", file: file, line: line)
    }

    /// Matches a bar item by its title even when the tab carries a badge: the label reads `Chores, 8 overdue`.
    static func barItemPredicate(_ title: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title),")
    }

    // MARK: - Scrolling

    /// Scrolls until `element` is on screen and clear, the one reveal loop every journey shares.
    ///
    /// Each round checks, and when it passes lets the page settle (the frame stops moving) and checks again, because a page that is
    /// still coasting carries a row through the clear band between two reads. Otherwise it moves toward the element: a measured
    /// leading-edge drag once the element is in the tree (its position says which way), a hard flick while it is far or not in the
    /// tree yet (a lazy page builds rows only near the viewport; the search runs down first, then up). The element's own
    /// frame decides the direction. On failure it attaches the accessibility tree and fails once.
    ///
    /// - Parameters:
    ///   - element: What to reveal.
    ///   - app: The app, for the window and the default scroller.
    ///   - scroller: The scroll view to drag. Default: the frontmost collection view, else scroll view.
    ///   - deadline: Seconds before giving up (30).
    ///   - isClear: Whether the element is where the test needs it. Default: hittable and inside the window.
    ///   - gesture: Replaces the built-in drag with a page's own (a sheet column, the Duo's hinge); it gets the element and whether the
    ///     page has to move to bring it from above (content down). The loop, the settle and the failure report stay shared.
    /// - Returns: Whether the element ended clear.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication, scroller: (() -> XCUIElement)? = nil, deadline: TimeInterval = 30,
                  isClear: ((XCUIElement) -> Bool)? = nil,
                  gesture: ((XCUIElement, Bool) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let window = app.windows.firstMatch
        func clear() -> Bool {
            // One snapshot answers "in the tree" and "has a frame"; `isHittable` is a live read (a snapshot cannot say).
            guard let snapshot = try? element.snapshot(), !snapshot.frame.isEmpty, element.isHittable else { return false }
            return isClear.map { $0(element) } ?? window.frame.contains(snapshot.frame.insetBy(dx: 0, dy: 1))
        }
        func area() -> XCUIElement {
            if let scroller { return scroller() }
            let collection = app.collectionViews.firstMatch
            return collection.exists ? collection : app.scrollViews.firstMatch
        }
        let end = Date().addingTimeInterval(deadline)
        var round = 0
        var lastMid = CGFloat.nan
        // A hard flick coasts past a target on a long page (the Settings page at AX5): once one has overshot, flicks are done
        // and the measured drags, which stop where they are told, finish the approach.
        var lastFlick: Bool?
        var flickOvershot = false
        var searchUp = false, turned = false, unmoved = 0, sinceTurn = 0
        while Date() < end {
            if clear() {
                element.settled()
                if clear() { return true }
            }
            round += 1
            if let gesture {
                if let frame = (try? element.snapshot())?.frame, !frame.isEmpty {
                    gesture(element, frame.midY < window.frame.midY)
                } else {
                    // Not in the tree: search down, then up, six drags each way. A page already at its end (the folded Duo's short
                    // sheet, left at the bottom by the previous reveal) does not move under the drag, so the first search turns as soon
                    // as two drags leave the first cell where it was, instead of spending the deadline there; after that the turns are
                    // six drags apart (the first cell may belong to another page that never moves). Without cells to watch, six rounds.
                    let before = app.cells.firstMatch.frame
                    if before.isEmpty { searchUp = (round / 6) % 2 == 1 }
                    gesture(element, searchUp)
                    sinceTurn += 1
                    let after = app.cells.firstMatch.frame
                    if !before.isEmpty, !after.isEmpty, abs(before.minY - after.minY) < 1 { unmoved += 1 } else { unmoved = 0 }
                    if !before.isEmpty, (!turned && unmoved >= 2) || sinceTurn >= 6 {
                        searchUp.toggle()
                        turned = true
                        sinceTurn = 0
                        unmoved = 0
                    }
                }
                continue
            }
            let scrolling = area()
            guard scrolling.exists else { usleep(100_000); continue }
            let frame = scrolling.frame
            guard let elementFrame = (try? element.snapshot())?.frame, !elementFrame.isEmpty else {
                // Not in the tree: search down for six rounds, then up, with whichever gesture the page answers: the leading-edge
                // drag scrolls the folded Duo (it ignores `swipeUp`), the system swipe scrolls iPhone and iPad, the hard flick
                // carries a long AX5 page. Each is tried only while the element is still missing.
                let down = (round / 6) % 2 == 0
                scrolling.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: down ? 0.8 : 0.2))
                    .press(forDuration: 0.05, thenDragTo: scrolling.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: down ? 0.2 : 0.8)))
                if !element.exists { if down { scrolling.swipeUp(velocity: .fast) } else { scrolling.swipeDown(velocity: .fast) } }
                if !element.exists { flickList(scrolling, up: down) }
                element.settled()
                continue
            }
            let delta = elementFrame.midY - (frame.minY + frame.height * 0.45)
            if let lastFlick, abs(delta) > frame.height * 1.2, lastFlick != (delta > 0) { flickOvershot = true }
            if abs(delta) > frame.height * 1.2, !flickOvershot {
                lastFlick = delta > 0
                flickList(scrolling, up: delta > 0)
                element.settled(maxWait: 2)
            } else if abs(elementFrame.midY - lastMid) < 1 {
                // The last measured drag did not move it: use the system swipe, which some pages answer instead.
                if delta > 0 { scrolling.swipeUp() } else { scrolling.swipeDown() }
                lastMid = .nan
            } else {
                lastMid = elementFrame.midY
                let half = min(max(abs(delta), 60), 420) / max(frame.height, 1) / 2
                let sign: CGFloat = delta > 0 ? 1 : -1
                scrolling.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5 + sign * half))
                    .press(forDuration: 0.05, thenDragTo: scrolling.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5 - sign * half)))
            }
        }
        if !clear() {
            let state = element.exists ? "exists hittable=\(element.isHittable) frame=\(element.frame)" : "not in the tree"
            add(XCTAttachment(string: "\(state)\n" + app.debugDescription))
            XCTFail("\(element) never came into view (\(state))", file: file, line: line)
            return false
        }
        return true
    }

    /// One hard flick of `list` along its trailing edge, where no button or tile takes the touch.
    func flickList(_ list: XCUIElement, up: Bool = true) {
        let from = CGVector(dx: 0.975, dy: up ? 0.7 : 0.2), to = CGVector(dx: 0.975, dy: up ? 0.2 : 0.7)
        list.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.01, thenDragTo: list.coordinate(withNormalizedOffset: to),
                   withVelocity: XCUIGestureVelocity(7_000), thenHoldForDuration: 0)
    }

    // MARK: - Gallery helpers

    /// The first element of any type with accessibility identifier `id`.
    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The whole frame of the tile whose body element has identifier `id`.
    ///
    /// A UIKit tile that carries controls exposes its body element cropped to what the discs leave (so the discs stay hittable) and is
    /// itself a container identified `<id>.tile`, whose frame is the tile's bounds. A tile with no controls is one element carrying `id`,
    /// whose frame is the answer.
    func wholeTile(_ id: String, in app: XCUIApplication) -> CGRect {
        let container = element(id + ".tile", in: app)
        return (container.exists ? container : element(id, in: app)).frame
    }

    /// The gallery's last recorded service call, without the `Last call: ` prefix.
    func lastCall(in app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label.replacing("Last call: ", with: "")
    }

    /// How ``expectLastCall(_:matching:in:timeout:file:line:)`` compares.
    enum CallMatch: String { case equals = "==", beginsWith = "BEGINSWITH", contains = "CONTAINS" }

    /// Waits until the gallery's last call matches `expected` (`Last call: ` is added for `.equals` and `.beginsWith`).
    func expectLastCall(_ expected: String, matching match: CallMatch = .equals, in app: XCUIApplication, timeout: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let value = match == .contains ? expected : "Last call: \(expected)"
        let predicate = NSPredicate(format: "label \(match.rawValue) %@", value)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: label)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Last call was '\(label.label)', expected \(match) '\(expected)'", file: file, line: line)
    }

    /// Asserts a 44 pt minimum hit target (43 allows for the simulator's rounding).
    func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 43, element.label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43, element.label, file: file, line: line)
    }

    /// The scale the system draws the presented sheet at, read from the transforms on the sheet-fit probe's ancestors (the sheet's
    /// container view carries the scale on a phone and an iPad); 1 where the sheet is not transformed (the folded Duo's is only inset).
    /// Needs the probe, so launch with `FENTON_SHEETFIT_PROBE=1`; fails the test when it is missing rather than guess from a width.
    func sheetScale(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGFloat {
        let probe = app.descendants(matching: .any)["sheet.fit.probe"].firstMatch
        guard probe.waitForExistence(timeout: 10), let value = probe.value as? String else {
            let near = app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'probe' OR identifier CONTAINS 'sheet'")).allElementsBoundByIndex.map { "\($0.identifier)/\($0.elementType.rawValue)" }
            XCTFail("No sheet-fit probe (exists \(probe.exists)): launch with FENTON_SHEETFIT_PROBE=1 to measure inside a sheet. Near: \(near)", file: file, line: line)
            return 1
        }
        var scale: CGFloat = 1
        let view = try? NSRegularExpression(pattern: #" t=([0-9.]+)/([0-9.]+)"#)
        let layer = try? NSRegularExpression(pattern: #" lt=([0-9.]+)/([0-9.]+)"#)
        for part in value.components(separatedBy: " | ") {
            // A view's transform and its layer's are the same scale: count whichever the part reports, once.
            for expression in [view, layer] {
                let range = NSRange(part.startIndex..., in: part)
                if let match = expression?.firstMatch(in: part, range: range), let x = Range(match.range(at: 1), in: part), let factor = Double(part[x]) {
                    scale *= CGFloat(factor)
                    break
                }
            }
        }
        return scale
    }

    /// Asserts a 44 pt minimum hit target for an element inside a presented sheet. A phone's and an iPad's sheet is drawn scaled
    /// (an iPhone's at 0.96), and accessibility frames are in that scaled space, so the check compares layout size: the frame divided
    /// by the sheet's real scale (``sheetScale(in:file:line:)``), not guessed from the sheet's width.
    func assertTarget(_ element: XCUIElement, inSheet app: XCUIApplication, scale knownScale: CGFloat? = nil,
                      file: StaticString = #filePath, line: UInt = #line) {
        // `scale` is for a page pushed over the sheet's root, which can take the probe out of the tree: read it before the push.
        let scale = knownScale ?? sheetScale(in: app, file: file, line: line)
        let note = "\(element.label): on screen \(element.frame.width) x \(element.frame.height), sheet scale \(scale)"
        XCTAssertGreaterThanOrEqual(element.frame.width / scale, 43, note, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height / scale, 43, note, file: file, line: line)
    }
}

@MainActor
extension XCTestCase {
    /// Whether `element` is in the tree and hittable: one snapshot for "in the tree" (no `exists` round trip before `isHittable`). On
    /// `XCTestCase`, not `JourneyTestCase`, so the Food base (a plain `XCTestCase`) shares it with the journey bases.
    func isReachable(_ element: XCUIElement) -> Bool {
        guard let frame = (try? element.snapshot())?.frame, !frame.isEmpty else { return false }
        return element.isHittable
    }
}

extension XCUIApplication {
    /// The bar item for a section, in the tab bar, else in the folded Duo's vertical bar (a toolbar to XCUITest). Matches a
    /// badged label (`Chores, 8 overdue`) as well as the bare title.
    func barItem(_ title: String) -> XCUIElement {
        let predicate = JourneyTestCase.barItemPredicate(title)
        let tab = tabBars.buttons.matching(predicate).firstMatch
        return tab.exists ? tab : toolbars.buttons.matching(predicate).firstMatch
    }
}

extension XCUIElement {
    /// Whether the element appears within `timeout`, polling `.exists` every 0.1 s. `waitForExistence` re-queries on its own
    /// slower cadence (about a second a call across ~870 sites); this returns the moment the element is in the tree.
    func appears(timeout: TimeInterval = 10) -> Bool {
        if exists { return true }
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            usleep(100_000)
            if exists { return true }
        }
        return exists
    }

    /// Whether the element is gone within `timeout`, polling every 0.1 s.
    func disappears(timeout: TimeInterval = 10) -> Bool {
        if !exists { return true }
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            usleep(100_000)
            if !exists { return true }
        }
        return !exists
    }

    /// Waits until the frame has been the same for two reads 0.1 s apart (a coasting scroll or a presenting sheet has stopped),
    /// or `maxWait` passes. An absent element returns at once.
    func settled(maxWait: TimeInterval = 1.5) {
        guard exists else { return }
        let end = Date().addingTimeInterval(maxWait)
        var previous = frame
        while Date() < end {
            usleep(100_000)
            let now = frame
            if now == previous { return }
            previous = now
        }
    }
}

/// Waits until the screen stops changing: two screenshots 0.1 s apart are byte-identical (a sheet has finished presenting, a
/// scroll has stopped, a fade has ended), or `timeout` passes. It replaces the fixed `sleep(1)` / `sleep(2)` "let it settle"
/// pauses: a still screen returns in about 0.3 s, a moving one waits for as long as it moves, and neither guesses.
@MainActor
func settleScreen(timeout: TimeInterval = 3) {
    let end = Date().addingTimeInterval(timeout)
    var previous = XCUIScreen.main.screenshot().pngRepresentation
    while Date() < end {
        usleep(100_000)
        let now = XCUIScreen.main.screenshot().pngRepresentation
        if now == previous { return }
        previous = now
    }
}
