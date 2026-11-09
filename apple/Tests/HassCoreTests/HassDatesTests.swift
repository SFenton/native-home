import Foundation
@testable import HassCore
import Testing

/// The shared date and number readers every feature parses Home Assistant values with.
struct HassDatesTests {
    @Test func parsesTimestampsWithAndWithoutFractionalSeconds() throws {
        let plain = try #require(HassDates.iso8601("2026-10-11T14:30:00Z"))
        let fractional = try #require(HassDates.iso8601("2026-10-11T14:30:00.250Z"))
        #expect(fractional.timeIntervalSince(plain) == 0.25)
        #expect(HassDates.iso8601("2026-10-11T14:30:00+02:00") == plain.addingTimeInterval(-7200))
        #expect(HassDates.iso8601(nil) == nil)
        #expect(HassDates.iso8601("") == nil)
        #expect(HassDates.iso8601("soon") == nil)
    }

    @Test func parsesZonelessLocalTimesWithASpaceOrT() throws {
        let spaced = try #require(HassDates.localDateTime("2026-10-11 14:30:00"))
        #expect(HassDates.localDateTime("2026-10-11T14:30:00") == spaced)
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: spaced)
        #expect(parts.hour == 14 && parts.minute == 30)
        #expect(HassDates.localDateTime("14:30") == nil)
    }

    @Test func finiteNumberAcceptsNumbersAndTrimmedNumericText() {
        #expect(JSONValue.number(3).finiteNumber == 3)
        #expect(JSONValue.string(" 72.5 ").finiteNumber == 72.5)
        #expect(JSONValue.string("inf").finiteNumber == nil)
        #expect(JSONValue.string("nan").finiteNumber == nil)
        #expect(JSONValue.number(.infinity).finiteNumber == nil)
        #expect(JSONValue.string("  ").finiteNumber == nil)
        #expect(JSONValue.bool(true).finiteNumber == nil)
        #expect(JSONValue.null.finiteNumber == nil)
    }
}
