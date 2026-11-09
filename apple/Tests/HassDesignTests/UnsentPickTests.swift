import Foundation
@testable import HassDesign
import Testing

/// ``UnsentPick``: a pick waiting for its quiet period is reported once, never twice and never lost.
struct UnsentPickTests {
    @Test func aHeldPickIsTakenOnce() {
        var pick = UnsentPick()
        #expect(pick.take() == nil)
        let date = Date(timeIntervalSince1970: 1000)
        pick.hold(date)
        #expect(pick.value == date)
        #expect(pick.take() == date)
        #expect(pick.take() == nil)
    }

    @Test func aNewerPickReplacesAndADiscardDropsIt() {
        var pick = UnsentPick()
        pick.hold(Date(timeIntervalSince1970: 1))
        pick.hold(Date(timeIntervalSince1970: 2))
        #expect(pick.value == Date(timeIntervalSince1970: 2))
        pick.discard()
        #expect(pick.take() == nil)
    }
}
