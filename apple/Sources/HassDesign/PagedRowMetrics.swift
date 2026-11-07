import SwiftUI

/// The page arithmetic of a ``PagedRow``: which page an offset shows and where a page starts.
///
/// A page holds `perPage` equal-width cells and is as wide as the viewport, so a swipe snaps to whole pages and no cell
/// is ever cut in half. The last page may hold fewer cells than the others; the scroll view stops where the content ends,
/// so its offset is short of a whole page, and it still counts as the last page.
public enum PagedRowMetrics {
    /// Pages for `itemCount` cells, `perPage` at a time (one page when empty).
    public static func pageCount(itemCount: Int, perPage: Int) -> Int {
        let perPage = max(1, perPage)
        return itemCount <= 0 ? 1 : (itemCount + perPage - 1) / perPage
    }

    /// The page a scroll offset shows: the nearest page start, and the last page once the content's end is reached.
    /// - Parameters:
    ///   - offset: The scroll view's horizontal content offset.
    ///   - viewport: The viewport (page) width.
    ///   - contentWidth: The content's width.
    ///   - pageCount: Pages in the row.
    public static func page(forOffset offset: CGFloat, viewport: CGFloat, contentWidth: CGFloat, pageCount: Int) -> Int {
        guard viewport > 0, pageCount > 1 else { return 0 }
        let maxOffset = max(0, contentWidth - viewport)
        if maxOffset > 0, offset >= maxOffset - 1 { return pageCount - 1 }
        return max(0, min(pageCount - 1, Int((offset / viewport).rounded())))
    }

    /// The first cell on a page, clamped to the cells that exist.
    public static func firstIndex(ofPage page: Int, itemCount: Int, perPage: Int) -> Int {
        min(max(0, itemCount - 1), max(0, page) * max(1, perPage))
    }

    /// The page holding a cell (the first page when none is given).
    public static func page(containing index: Int?, perPage: Int, pageCount: Int) -> Int {
        max(0, min(pageCount - 1, (index ?? 0) / max(1, perPage)))
    }

    /// The page a VoiceOver paging gesture goes to: a swipe left (next) or right (previous) from `page`, or nil at the ends.
    public static func page(from page: Int, step: Int, pageCount: Int) -> Int? {
        let target = page + step
        return target >= 0 && target < pageCount && target != page ? target : nil
    }

    /// `Page 2 of 3`, what VoiceOver says when a paging row settles on a page.
    public static func pageDescription(_ page: Int, pageCount: Int) -> String {
        "Page \(max(0, min(pageCount - 1, page)) + 1) of \(max(1, pageCount))"
    }

    /// The indexes of the accessibility frames that overlap the viewport (both in screen coordinates). A paging row exposes
    /// only the page on screen to VoiceOver; the hidden flag on SwiftUI cells does not reach UIKit from a hosted view.
    public static func indexes(ofFrames frames: [CGRect], overlapping viewport: CGRect) -> [Int] {
        frames.indices.filter { index in
            let overlap = frames[index].intersection(viewport)
            return !overlap.isNull && overlap.width > 1 && overlap.height > 0
        }
    }

    /// The offset that puts a page at the leading edge, held inside the content.
    public static func offset(ofPage page: Int, viewport: CGFloat, contentWidth: CGFloat) -> CGFloat {
        min(max(0, CGFloat(page) * viewport), max(0, contentWidth - viewport))
    }
}
