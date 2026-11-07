@testable import HassDesign
import Testing

/// The owner's placement rules (`.agents/design/action-navigation-tiles.md`): the full matrix, glyph carrying, and the
/// disc-hidden accessibility rule.
struct TileActionPlacementTests {
    private static let behaviors: [TileBehavior] = [.perform("a"), .navigate, .inert]

    private func slot(_ count: Int, _ behavior: TileBehavior, ax: Bool = false, fits: Bool = true) -> TileActionSlot {
        TileActionPlacement.slot(count: count, behavior: behavior, accessibilitySize: ax, fitsTrailing: fits)
    }

    @Test(arguments: behaviors)
    func noActionsMeansNoSlot(behavior: TileBehavior) {
        // Navigate with no actions is the chevron only.
        for ax in [false, true] {
            for fits in [false, true] {
                #expect(slot(0, behavior, ax: ax, fits: fits) == .none)
            }
        }
    }

    @Test(arguments: behaviors, [1, 2])
    func oneOrTwoActionsTrailOnAnyTile(behavior: TileBehavior, count: Int) {
        #expect(slot(count, behavior) == .trailing)
    }

    @Test(arguments: behaviors, [3, 4, 9])
    func threeOrMoreGoBelow(behavior: TileBehavior, count: Int) {
        #expect(slot(count, behavior) == .below)
    }

    @Test(arguments: behaviors, [1, 2, 3, 4])
    func accessibilitySizesAndNarrowTilesGoBelow(behavior: TileBehavior, count: Int) {
        #expect(slot(count, behavior, ax: true) == .below)
        #expect(slot(count, behavior, fits: false) == .below)
        #expect(slot(count, behavior, ax: true, fits: false) == .below)
    }

    @Test func theMatrixIsExhaustive() {
        var trailing = 0, below = 0, none = 0
        for count in 0...4 {
            for behavior in Self.behaviors {
                for ax in [false, true] {
                    for fits in [false, true] {
                        switch slot(count, behavior, ax: ax, fits: fits) {
                        case .none: none += 1
                        case .trailing: trailing += 1
                        case .below: below += 1
                        }
                    }
                }
            }
        }
        #expect(none == 12)
        #expect(trailing == 6)
        #expect(below == 42)
    }

    @Test func onlyAnActionTileWithTrailingDiscsCarriesTheGlyph() {
        for behavior in Self.behaviors {
            for slot in [TileActionSlot.none, .trailing, .below] {
                let expected: Bool = if case .perform = behavior { slot == .trailing } else { false }
                #expect(TileActionPlacement.carriesGlyph(behavior: behavior, slot: slot) == expected)
            }
        }
        #expect(!TileActionPlacement.carriesGlyph(behavior: .navigate, slot: .trailing), "A navigation tile keeps its glyph")
        #expect(!TileActionPlacement.carriesGlyph(behavior: .inert, slot: .none), "A read-only tile keeps its glyph")
    }

    @Test func aSingleDiscIsHiddenOnlyWhenItRepeatsTheBody() {
        let lock = TileActionItem(id: "lock", verb: "Unlock", symbol: "lock.fill", isOn: true)
        let power = TileActionItem(id: "power", verb: "Turn On", symbol: "power")
        #expect(TileActionPlacement.discIsAccessibilityHidden(behavior: .perform("lock"), items: [lock]))
        #expect(!TileActionPlacement.discIsAccessibilityHidden(behavior: .perform("power"), items: [lock]), "Another action")
        #expect(!TileActionPlacement.discIsAccessibilityHidden(behavior: .perform("lock"), items: [lock, power]), "Two actions")
        #expect(!TileActionPlacement.discIsAccessibilityHidden(behavior: .navigate, items: [lock]))
        #expect(!TileActionPlacement.discIsAccessibilityHidden(behavior: .inert, items: [lock]))
        #expect(!TileActionPlacement.discIsAccessibilityHidden(behavior: .perform("lock"), items: []))
    }

    @Test func aMomentaryItemNeverShowsProgress() {
        for feedback in [TileActionItem.Feedback.momentary, .optimistic, .tracked] {
            let item = TileActionItem(id: "x", verb: "Go", symbol: "play", phase: .inFlight, feedback: feedback)
            #expect(item.showsProgress == (feedback != .momentary))
        }
        #expect(!TileActionItem(id: "x", verb: "Go", symbol: "play", phase: .ready, feedback: .tracked).showsProgress)
    }
}
