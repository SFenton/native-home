import UIKit
import XCTest

/// Invariants a scroller that must never move sideways shares (apple-fidelity F2): no horizontal inset, no horizontal range, and no
/// sideways offset after the system scrolls a control into view. The sign-in screen applies it first; other scrollers can reuse it.
@MainActor
enum HostedScrollInvariants {
    /// Asserts `scroll` has a zero horizontal range, then asks it to reveal each rect and asserts the offset stays at the start.
    /// - Parameters:
    ///   - scroll: The scroll view, laid out in a window.
    ///   - reveal: Rects in the scroll view's content coordinates (a field's frame) to scroll into view.
    static func assertZeroHorizontalRange(_ scroll: UIScrollView, reveal: [CGRect] = [], _ context: String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
        let inset = scroll.adjustedContentInset
        XCTAssertEqual(inset.left, 0, "\(context) no adjusted inset on the left", file: file, line: line)
        XCTAssertEqual(inset.right, 0, "\(context) no adjusted inset on the right", file: file, line: line)
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 0.5, "\(context) content is no wider than the scroll view",
                                 file: file, line: line)
        let start = scroll.contentOffset.x
        XCTAssertEqual(start, 0, accuracy: 0.5, "\(context) at rest the offset is zero", file: file, line: line)
        for rect in reveal {
            scroll.scrollRectToVisible(rect, animated: false)
            XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 0.5, "\(context) revealing \(rect) does not move sideways", file: file, line: line)
        }
    }
}
