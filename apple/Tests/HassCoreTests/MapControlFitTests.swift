import Foundation
import Testing
@testable import HassCore

// MARK: - The fit rule, shared with the Studio

/// The fit rule for corner button groups. The Studio holds the same rule (`surface-controls-fit.ts`) and these are its tests with the same
/// inputs: the two must give the same counts, so a case here that moves is a case there that moves.
@Suite struct MapControlFitTests {
    private func g(_ corner: MapControlCorner, _ axis: MapControlAxis, _ count: Int) -> MapControlFit.Group { .init(corner: corner, axis: axis, count: count) }

    /// `[corner, shown, hidden]` as the Studio's `run` helper writes it: hidden is 0 when there is no More.
    private func run(_ width: Double, _ height: Double, _ groups: MapControlFit.Group...) -> [[String]] {
        MapControlFit.fit(width: width, height: height, groups: groups).map { [$0.corner.rawValue, String($0.shown), String($0.more ? $0.hidden : 0)] }
    }

    @Test func showsEverythingThatFits() {
        #expect(run(343, 300, g(.topLeading, .column, 1)) == [["top-leading", "1", "0"]])
        #expect(run(343, 300, g(.topTrailing, .row, 5)) == [["top-trailing", "5", "0"]])
        #expect(run(343, 300, g(.topLeading, .row, 3), g(.topTrailing, .row, 3)) == [["top-leading", "3", "0"], ["top-trailing", "3", "0"]])
    }

    @Test func keepsKMinusOneButtonsAndMoreWhenAGroupDoesNotFit() {
        #expect(run(343, 300, g(.topTrailing, .row, 8)) == [["top-trailing", "6", "2"]])
        #expect(run(120, 300, g(.topTrailing, .row, 3)) == [["top-trailing", "1", "2"]])
    }

    @Test func countsAGroupOfOneAsAColumnAndNeverFewerThanTheMoreButton() {
        #expect(run(40, 300, g(.topLeading, .row, 1)) == [["top-leading", "1", "0"]])
        #expect(run(40, 300, g(.topLeading, .row, 2)) == [["top-leading", "0", "2"]])
    }

    @Test func takesTheCrossingNeighboursOneButtonFirst() {
        #expect(run(200, 300, g(.topTrailing, .row, 3), g(.topLeading, .column, 2)) == [["top-trailing", "1", "2"], ["top-leading", "2", "0"]])
    }

    @Test func splitsAnEdgeInHalvesAndGivesAShortOnesRemainderToTheOther() {
        // The smallest card is 124 pt tall: two columns on one edge each get 48 pt, one button's room, so each shows More alone.
        #expect(run(343, 124, g(.topLeading, .column, 2), g(.bottomLeading, .column, 2)) == [["top-leading", "0", "2"], ["bottom-leading", "0", "2"]])
        // total 96: the short group needs 44 (under half), the long one gets 96 - 44 = 52, one button's room.
        #expect(run(343, 124, g(.topLeading, .column, 1), g(.bottomLeading, .column, 3)) == [["top-leading", "1", "0"], ["bottom-leading", "0", "3"]])
        // total 303 on 331: the short row keeps its 132, the long one gets 303 - 132 = 171, three buttons' room.
        #expect(run(331, 300, g(.topLeading, .row, 3), g(.topTrailing, .row, 6)) == [["top-leading", "3", "0"], ["top-trailing", "2", "4"]])
    }

    @Test func isTheSameForAGroupWhateverTheOrderOfTheList() {
        let a = run(331, 300, g(.topLeading, .row, 3), g(.topTrailing, .row, 6)).sorted { $0[0] < $1[0] }
        let b = run(331, 300, g(.topTrailing, .row, 6), g(.topLeading, .row, 3)).sorted { $0[0] < $1[0] }
        #expect(a == b)
    }

    // MARK: Per family

    /// The widths the Studio warns for: the smallest iPhone through the largest, the Duo folded and open, the iPad. The card is the window
    /// less a 16 pt margin on each side.
    private static let families: [(id: String, width: Double)] = [
        ("iphone-small", 375), ("iphone", 402), ("iphone-largest", 440), ("duo-folded", 466), ("duo-open", 669), ("ipad", 834),
    ]

    /// The buttons that move into More on each family, only where something does (`overflowByFamily`).
    private func overflow(_ groups: [MapControlFit.Group], height: Double = 300) -> [String: Int] {
        var counts: [String: Int] = [:]
        for family in Self.families {
            let hidden = MapControlFit.fit(width: family.width - 32, height: height, groups: groups).filter(\.more).reduce(0) { $0 + $1.hidden }
            if hidden > 0 { counts[family.id] = hidden }
        }
        return counts
    }

    @Test func countsTheButtonsThatMoveIntoMoreOnEachFamily() {
        #expect(overflow([g(.topTrailing, .row, 8)]) == ["iphone-small": 2])
        #expect(overflow([g(.topTrailing, .row, 8), g(.bottomTrailing, .row, 8)]) == ["iphone-small": 4])
        // A column's room is the card's height: 200 pt leaves 184, four buttons' room, so three show and five move, on every width.
        #expect(overflow([g(.topLeading, .column, 8)], height: 200)
            == ["iphone-small": 5, "iphone": 5, "iphone-largest": 5, "duo-folded": 5, "duo-open": 5, "ipad": 5])
    }

    @Test func sayNothingForTheDefaultLocateOrAGroupThatFits() {
        #expect(overflow(ServerUIMapControls.fitGroups(ServerUIMapControls.effective(locate: true, controls: nil)), height: 100).isEmpty)
        #expect(overflow([g(.topLeading, .row, 2)]).isEmpty)
        #expect(overflow([g(.topTrailing, .row, 7)]).isEmpty)
    }

    @Test func theSmallestCardKeepsOneButtonPerGroupAndNothingOverlaps() {
        // 124 pt is the smallest card (a 100 pt map and 12 pt on each side): four groups, each at least More.
        let groups = [g(.topLeading, .column, 4), g(.topTrailing, .column, 4), g(.bottomLeading, .column, 4), g(.bottomTrailing, .column, 4)]
        let results = MapControlFit.fit(width: 343, height: 124, groups: groups)
        #expect(results.allSatisfy { $0.more && $0.shown == 0 && $0.hidden == 4 })
    }

    @Test func theDefaultIsOneGroupOfOneAtTopLeading() {
        let groups = ServerUIMapControls.effective(locate: true, controls: nil)
        #expect(groups.map(\.corner) == [.topLeading])
        #expect(groups[0].buttons.map(\.id) == ["locate"])
        #expect(groups[0].buttons[0].identifier == "vacuum.locate")
        #expect(ServerUIMapControls.effective(locate: false, controls: nil).isEmpty)
        #expect(ServerUIMapControls.effective(locate: true, controls: []).isEmpty, "authored and empty draws nothing")
        #expect(MapControlFit.controlSize == 44 && MapControlFit.inset == 8 && MapControlFit.gap == 12)
    }
}
