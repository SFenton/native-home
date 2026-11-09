import CoreGraphics
@testable import HassDesign
import Testing

struct PagedRowMetricsTests {
    @Test func pagesRoundUpAndAnEmptyRowHasOne() {
        #expect(PagedRowMetrics.pageCount(itemCount: 24, perPage: 5) == 5)
        #expect(PagedRowMetrics.pageCount(itemCount: 25, perPage: 5) == 5)
        #expect(PagedRowMetrics.pageCount(itemCount: 5, perPage: 1) == 5)
        #expect(PagedRowMetrics.pageCount(itemCount: 0, perPage: 5) == 1)
        // A zero page size is read as one, never divided by.
        #expect(PagedRowMetrics.pageCount(itemCount: 3, perPage: 0) == 3)
    }

    @Test func anOffsetShowsTheNearestPageStart() {
        // 24 hours of 80 pt, 5 a page: 400 pt viewport, 1920 pt of content, last offset 1520.
        func page(_ offset: CGFloat) -> Int {
            PagedRowMetrics.page(forOffset: offset, viewport: 400, contentWidth: 1920, pageCount: 5)
        }
        #expect(page(0) == 0)
        #expect(page(199) == 0)
        #expect(page(201) == 1)
        #expect(page(800) == 2)
        #expect(page(1230) == 3)
    }

    @Test func theEndOfTheContentIsTheLastPageEvenWhenItHoldsFewerCells() {
        // The scroll view stops at 1520 pt, short of a whole fifth page (1600 pt): still page 5.
        #expect(PagedRowMetrics.page(forOffset: 1520, viewport: 400, contentWidth: 1920, pageCount: 5) == 4)
        #expect(PagedRowMetrics.page(forOffset: 1519.5, viewport: 400, contentWidth: 1920, pageCount: 5) == 4)
        // Rubber-banding past the end still reads as the last page.
        #expect(PagedRowMetrics.page(forOffset: 1700, viewport: 400, contentWidth: 1920, pageCount: 5) == 4)
        // And before the start as the first.
        #expect(PagedRowMetrics.page(forOffset: -40, viewport: 400, contentWidth: 1920, pageCount: 5) == 0)
    }

    @Test func aRowThatFitsHasNothingToPage() {
        #expect(PagedRowMetrics.page(forOffset: 0, viewport: 400, contentWidth: 400, pageCount: 1) == 0)
        #expect(PagedRowMetrics.page(forOffset: 90, viewport: 0, contentWidth: 0, pageCount: 3) == 0)
    }

    @Test func aPageStartsOnItsFirstCellAndIsHeldInsideTheContent() {
        #expect(PagedRowMetrics.firstIndex(ofPage: 2, itemCount: 24, perPage: 5) == 10)
        #expect(PagedRowMetrics.firstIndex(ofPage: 4, itemCount: 24, perPage: 5) == 20)
        // Past the cells that exist, the last cell.
        #expect(PagedRowMetrics.firstIndex(ofPage: 9, itemCount: 24, perPage: 5) == 23)
        #expect(PagedRowMetrics.firstIndex(ofPage: -1, itemCount: 24, perPage: 5) == 0)
        #expect(PagedRowMetrics.firstIndex(ofPage: 3, itemCount: 0, perPage: 5) == 0)
    }

    @Test func aCellBelongsToThePageHoldingIt() {
        #expect(PagedRowMetrics.page(containing: nil, perPage: 5, pageCount: 5) == 0)
        #expect(PagedRowMetrics.page(containing: 9, perPage: 5, pageCount: 5) == 1)
        #expect(PagedRowMetrics.page(containing: 10, perPage: 5, pageCount: 5) == 2)
        #expect(PagedRowMetrics.page(containing: 99, perPage: 5, pageCount: 5) == 4)
    }

    @Test func aPageOffsetIsHeldInsideTheContent() {
        #expect(PagedRowMetrics.offset(ofPage: 0, viewport: 400, contentWidth: 1920) == 0)
        #expect(PagedRowMetrics.offset(ofPage: 2, viewport: 400, contentWidth: 1920) == 800)
        #expect(PagedRowMetrics.offset(ofPage: 4, viewport: 400, contentWidth: 1920) == 1520)
        #expect(PagedRowMetrics.offset(ofPage: 1, viewport: 400, contentWidth: 300) == 0)
    }

    @Test func aPagingGestureStopsAtTheEnds() {
        #expect(PagedRowMetrics.page(from: 0, step: 1, pageCount: 3) == 1)
        #expect(PagedRowMetrics.page(from: 2, step: 1, pageCount: 3) == nil)
        #expect(PagedRowMetrics.page(from: 0, step: -1, pageCount: 3) == nil)
        #expect(PagedRowMetrics.page(from: 1, step: -1, pageCount: 3) == 0)
    }

    @Test func thePageIsAnnouncedFromOne() {
        #expect(PagedRowMetrics.pageDescription(1, pageCount: 3) == "Page 2 of 3")
        #expect(PagedRowMetrics.pageDescription(9, pageCount: 3) == "Page 3 of 3")
        #expect(PagedRowMetrics.pageDescription(0, pageCount: 0) == "Page 1 of 1")
    }

    @Test func onlyTheCellsOnScreenAreExposedToVoiceOver() {
        // Five 80 pt cells on screen at x 100...500; the rest of the row sits right of it, and one cell is cut at each edge.
        let viewport = CGRect(x: 100, y: 200, width: 400, height: 80)
        let frames = (0..<8).map { CGRect(x: 100 + CGFloat($0) * 80, y: 200, width: 80, height: 80) }
        #expect(PagedRowMetrics.indexes(ofFrames: frames, overlapping: viewport) == [0, 1, 2, 3, 4])
        // After a page, the first cells are off to the left and the next ones are in.
        let shifted = frames.map { $0.offsetBy(dx: -400, dy: 0) }
        #expect(PagedRowMetrics.indexes(ofFrames: shifted, overlapping: viewport) == [5, 6, 7])
        // A null frame (no accessibility frame) is not exposed.
        #expect(PagedRowMetrics.indexes(ofFrames: [.null], overlapping: viewport).isEmpty)
    }
}
