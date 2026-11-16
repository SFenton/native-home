import XCTest

/// The page-growth evidence for Dynamic Type: the test itself and the pairing of two pages' texts. No app launches.
final class AuditGrowthTests: XCTestCase {
    func testPageGrewNeedsEveryTextNotSmallerAndTheTotalTaller() {
        XCTAssertTrue(AuditGrowth.pageGrew([(20, 40), (18, 36)]))
        XCTAssertFalse(AuditGrowth.pageGrew([]), "an empty sample proves nothing")
        XCTAssertFalse(AuditGrowth.pageGrew([(20, 24), (18, 20)]), "under 1.35x together")
        XCTAssertFalse(AuditGrowth.pageGrew([(20, 60), (20, 10)]), "one text shrank")
        XCTAssertTrue(AuditGrowth.pageGrew([(52, 51.6), (20, 80)]), "half a point of shrink is measurement noise")
    }

    func testPairsTakeTextsBothPagesShowInReadingOrder() {
        let small = ["Title": CGRect(x: 0, y: 10, width: 100, height: 20), "Body": CGRect(x: 0, y: 40, width: 100, height: 16),
                      "Gone": CGRect(x: 0, y: 80, width: 100, height: 16)]
        let large = ["Body": CGRect(x: 0, y: 120, width: 100, height: 40), "Title": CGRect(x: 0, y: 10, width: 100, height: 50),
                     "New": CGRect(x: 0, y: 200, width: 100, height: 30)]
        let pairs = AuditGrowth.pairs(smaller: small, larger: large)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 20); XCTAssertEqual(pairs[0].1, 50)
        XCTAssertEqual(pairs[1].0, 16); XCTAssertEqual(pairs[1].1, 40)
        XCTAssertEqual(AuditGrowth.pairs(smaller: small, larger: large, limit: 1).count, 1)
    }
}
