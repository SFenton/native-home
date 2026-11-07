import Foundation
@testable import HassTelemetry
import Testing

/// ``ResourceCensus``: gauges count while their token lives, sum by name and round-trip through the probe's text.
@MainActor
struct ResourceCensusTests {
    @Test func aGaugeCountsOnlyWhileItsTokenLives() {
        let census = ResourceCensus()
        var token: ResourceCensus.Registration? = census.register { ["Thing.observers": 3] }
        #expect(census.counts() == ["Thing.observers": 3])
        token = nil
        #expect(census.counts().isEmpty, "Releasing the owner's token takes its gauge away")
        _ = token
    }

    @Test func objectsSharingANameAreSummed() {
        let census = ResourceCensus()
        let first = census.register { ["Camera.players": 1] }
        let second = census.register { ["Camera.players": 1, "Camera.attempts": 1] }
        #expect(census.counts() == ["Camera.players": 2, "Camera.attempts": 1])
        withExtendedLifetime((first, second)) {}
    }

    @Test func aGaugeReadsItsOwnerLive() {
        final class Owner { var count = 0 }
        let owner = Owner()
        let census = ResourceCensus()
        let token = census.register { [weak owner] in ["Owner.things": owner?.count ?? 0] }
        owner.count = 2
        #expect(census.counts()["Owner.things"] == 2)
        owner.count = 0
        #expect(census.counts()["Owner.things"] == 0)
        withExtendedLifetime(token) {}
    }

    @Test func summaryIsSortedAndParsesBack() {
        let counts = ["B.two": 2, "A.one": 1, "Process.threads": 31]
        let text = ResourceCensus.summary(of: counts)
        #expect(text == "A.one=1 B.two=2 Process.threads=31")
        #expect(ResourceCensus.counts(fromSummary: text) == counts)
        #expect(ResourceCensus.counts(fromSummary: "").isEmpty)
        #expect(ResourceCensus.counts(fromSummary: "junk A.one=x B.two=2") == ["B.two": 2], "Unreadable pairs are skipped")
    }

    @Test func theProcessHasThreads() throws {
        #if canImport(Darwin)
        #expect(try #require(ResourceCensus.threadCount()) >= 1)
        #endif
    }
}
