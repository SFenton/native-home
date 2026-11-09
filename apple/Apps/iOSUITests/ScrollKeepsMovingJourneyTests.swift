import XCTest

/// Regression (2026-10-28): the swipe row's SwiftUI `DragGesture` left the Chores page without a working scroll after its
/// first gesture on iOS 26 (a drag never scrolled again, a swipe moved it once). Repeated drags and swipes on the long
/// Chores page keep moving it, at the default size and at AX5. Pattern: `.agents/patterns/swipe-row.md`.
@MainActor
final class ScrollKeepsMovingJourneyTests: JourneyTestCase {
    private enum Gesture { case dragLeadingEdge, dragMiddle, swipe }

    private func assertKeepsMoving(_ gesture: Gesture, arguments: [String] = [], gestures: Int = 12,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "chores"
        configured.launchEnvironment["FENTON_GALLERY_CLEAN"] = "1"
        configured.launchEnvironment["FENTON_GALLERY_CHORES"] = "12"
        configured.launchArguments += arguments
        // Gallery settings only, so the default-size tests are resets of one app (`app-reuse.md`); AX5 is a launch argument, so fresh.
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["fab.add"].waitForExistence(timeout: FentonHomeApp.launchWait()), "Add button missing", file: file, line: line)
        let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'todo.item.'"))
        let first = rows.element(boundBy: 0)
        // A collection view makes only the cells on screen: at AX5 the page's header fills the first screen, so scroll until a row exists.
        if !first.waitForExistence(timeout: 5) {
            for _ in 0..<6 where !first.exists { scroll.swipeUp(); _ = restingMinY(first) }
        }
        XCTAssertTrue(first.exists, "No rows", file: file, line: line)
        var stuck = 0
        var before = first.frame.minY
        for i in 0..<gestures {
            let up = i % 2 == 0
            let x: CGFloat = gesture == .dragMiddle ? 0.5 : 0.05
            switch gesture {
            case .swipe:
                if up { scroll.swipeUp() } else { scroll.swipeDown() }
            case .dragLeadingEdge, .dragMiddle:
                let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.75 : 0.25))
                let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.25 : 0.75))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            // Wait for the momentum to end (the row stops moving), then compare: one frame read per gesture, and it is the next one's start.
            let after = restingMinY(first)
            if after == before { stuck += 1 }
            before = after
        }
        // A page at its end can legitimately ignore one gesture; a wedged page ignores all of them.
        XCTAssertLessThanOrEqual(stuck, 2, "\(stuck) of \(gestures) gestures did not move the page", file: file, line: line)
    }

    /// The row's `minY` once it has stopped moving: reads it until two reads 50 ms apart agree (up to about 3 s). It replaces a fixed
    /// 0.6 s pause after each gesture; a page that is stuck answers at once, a coasting one is waited out.
    private func restingMinY(_ element: XCUIElement) -> CGFloat {
        var last = (try? element.snapshot().frame.minY) ?? .nan
        for _ in 0..<40 {
            usleep(50_000)
            let now = (try? element.snapshot().frame.minY) ?? .nan
            if now == last || (now.isNaN && last.isNaN) { return now }
            last = now
        }
        return last
    }

    func testDragsKeepScrollingTheLongPage() { assertKeepsMoving(.dragLeadingEdge) }
    func testDragsInTheMiddleKeepScrollingTheLongPage() { assertKeepsMoving(.dragMiddle) }
    func testSwipesKeepScrollingTheLongPage() { assertKeepsMoving(.swipe) }
    func testDragsKeepScrollingTheLongPageAtAX5() { assertKeepsMoving(.dragLeadingEdge, arguments: FentonHomeApp.ax5) }
    func testSwipesKeepScrollingTheLongPageAtAX5() { assertKeepsMoving(.swipe, arguments: FentonHomeApp.ax5) }
}
