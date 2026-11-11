@testable import HassDesign
import Testing

/// Tickets and the reapply window behind a list's updates: what an apply does, whom it announces, and when a ticket lapses.
struct ListUpdateLedgerTests {
    private func plan(
        _ ledger: inout ListUpdateLedger<String>, removed: Set<String> = [], inserted: Set<String> = [], first: Bool = false,
        window: Bool = true, cause: ListUpdateCause = .live, reduceMotion: Bool = false, generation: Int? = nil, now: Double = 100
    ) -> ListUpdateLedger<String>.Plan {
        ledger.plan(removed: removed, inserted: inserted, isFirstApply: first, hasWindow: window, cause: cause,
                    reduceMotion: reduceMotion, generation: generation, now: now)
    }

    @Test func aTicketedRemovalIsPersonCausedAndAnnounced() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["honey"], title: "Honey", now: 100)
        let result = plan(&ledger, removed: ["honey"])
        #expect(result.transition == .animate)
        #expect(result.cause == .person)
        #expect(result.removedByPerson)
        #expect(result.removedTitles == ["Honey"])
        #expect(!ledger.hasTickets, "the ticket is spent")
    }

    @Test func anUnticketedLiveRemovalAnimatesButIsNotAnnounced() {
        var ledger = ListUpdateLedger<String>()
        let result = plan(&ledger, removed: ["honey"])
        #expect(result.transition == .animate)
        #expect(result.cause == .live)
        #expect(!result.removedByPerson)
        #expect(result.removedTitles.isEmpty)
    }

    @Test func aTicketedInsertionIsNotAnAnnouncedRemoval() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectInsertion(of: ["honey"], now: 100)
        let result = plan(&ledger, inserted: ["honey"])
        #expect(result.transition == .animate)
        #expect(result.cause == .person)
        #expect(!result.removedByPerson)
        #expect(result.removedTitles.isEmpty)
    }

    @Test func aTicketExpiresAfterTenSeconds() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["honey"], title: "Honey", now: 100)
        let result = plan(&ledger, removed: ["honey"], now: 111)
        #expect(!result.removedByPerson)
        #expect(result.removedTitles.isEmpty)
        #expect(result.cause == .live)
        #expect(!ledger.hasTickets)
    }

    @Test func aCancelledTicketAnnouncesNothing() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["honey"], title: "Honey", now: 100)
        ledger.cancelExpectation(of: ["honey"])
        #expect(plan(&ledger, removed: ["honey"]).removedTitles.isEmpty)
    }

    @Test func aTicketWaitsForItsOwnRow() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["honey"], title: "Honey", now: 100)
        #expect(plan(&ledger, removed: ["jam"]).removedTitles.isEmpty)
        #expect(ledger.hasTickets)
    }

    @Test func aReconnectWindowSuppressesMotionEvenForATicket() {
        var ledger = ListUpdateLedger<String>()
        _ = plan(&ledger, generation: 1, now: 90)
        ledger.expectRemoval(of: ["honey"], title: "Honey", now: 99)
        let during = plan(&ledger, removed: ["honey"], generation: 2, now: 100)
        #expect(during.transition == .none)
        ledger.expectRemoval(of: ["jam"], title: "Jam", now: 100)
        let after = plan(&ledger, removed: ["jam"], generation: 2, now: 102.5)
        #expect(after.transition == .animate)
    }

    @Test func aListThatDoesNotReadTheStoreNeverReapplies() {
        var ledger = ListUpdateLedger<String>()
        _ = plan(&ledger, generation: nil, now: 90)
        #expect(plan(&ledger, removed: ["a"], generation: nil, now: 90.5).transition == .animate)
    }

    @Test func theFirstApplyAndAnOffscreenListNeverMove() {
        var ledger = ListUpdateLedger<String>()
        #expect(plan(&ledger, removed: ["a"], first: true).transition == .none)
        #expect(plan(&ledger, removed: ["a"], window: false).transition == .none)
    }

    @Test func aResetStaysAResetEvenWithATicket() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["a"], title: "A", now: 100)
        let result = plan(&ledger, removed: ["a"], cause: .reset)
        #expect(result.transition == .none)
        #expect(result.cause == .reset)
        #expect(!result.removedByPerson)
    }

    @Test func reduceMotionFades() {
        var ledger = ListUpdateLedger<String>()
        #expect(plan(&ledger, removed: ["a"], reduceMotion: true).transition == .fade)
    }

    @Test func aReloadedHeaderCrossFadesLikeAStructuralChange() {
        var ledger = ListUpdateLedger<String>()
        let result = ledger.plan(removed: [], inserted: [], reloaded: true, isFirstApply: false, hasWindow: true, cause: .live,
                                 reduceMotion: false, generation: nil, now: 100)
        #expect(result.transition == .animate)
    }

    @Test func aRedrawOnlyApplyHasNoMotion() {
        var ledger = ListUpdateLedger<String>()
        #expect(plan(&ledger).transition == .none)
    }

    @Test func titlesComeInRegistrationOrder() {
        var ledger = ListUpdateLedger<String>()
        ledger.expectRemoval(of: ["a"], title: "Apple", now: 100)
        ledger.expectRemoval(of: ["b"], title: "Bread", now: 100)
        #expect(plan(&ledger, removed: ["a", "b"]).removedTitles == ["Apple", "Bread"])
    }
}
