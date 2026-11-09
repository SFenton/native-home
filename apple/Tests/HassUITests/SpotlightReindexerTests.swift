import Foundation
import HassCore
import HassDemoHouse
@testable import HassUI
import Testing

/// Records what the reindexer asks of system search.
@MainActor
private final class RecordingIndexer: SpotlightIndexing {
    var indexed: [[SpotlightEntry]] = []
    func indexPages(_ entries: [SpotlightEntry]) { indexed.append(entries) }
    func removeAll() {}
}

/// A debounce wait the test ends by hand.
@MainActor
private final class HeldSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { continuations.count }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { continuations.append($0) }
    }

    /// Ends every wait.
    func release() {
        let held = continuations
        continuations = []
        for continuation in held { continuation.resume() }
    }
}

/// The rooms in system search follow the house document, not only the sign-in.
@MainActor
@Suite(.serialized, .hosted)
struct SpotlightReindexerTests {
    /// Lets the reindexer's main-actor hop run.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func roomsDocument(_ count: Int) -> HouseConfig {
        var house = DemoHouse.config
        house.rooms.pages = Array(house.rooms.pages.prefix(count))
        return house
    }

    @Test func startingIndexesTheCurrentEntriesOnce() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer)
        reindexer.start()
        await settle()
        #expect(indexer.indexed == [SpotlightCatalog.entries(in: source)])
    }

    /// Fails if: a changed document is not indexed again after the debounce, is indexed before it, or the watch is not
    /// armed again afterwards.
    @Test func aDocumentThatChangesTheRoomsIndexesAgainAfterTheDebounce() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let clock = HeldSleeper()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer, sleeper: { await clock.sleep($0) })
        reindexer.start()
        source.set(roomsDocument(3))
        await settle()
        #expect(indexer.indexed.count == 1, "Not before the debounce has passed")
        #expect(clock.waiting == 1)
        clock.release()
        await settle()
        #expect(indexer.indexed.count == 2)
        #expect(indexer.indexed.last?.count == 5 + 3)
        // Armed again: a second change is followed too.
        source.set(roomsDocument(2))
        await settle()
        clock.release()
        await settle()
        #expect(indexer.indexed.count == 3)
        #expect(indexer.indexed.last?.count == 5 + 2)
    }

    /// Fails if: each change in a burst indexes (more than one index call), or the last change is not the one indexed.
    @Test func aBurstOfChangesIndexesOnceWithTheLastEntries() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let clock = HeldSleeper()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer, sleeper: { await clock.sleep($0) })
        reindexer.start()
        source.set(roomsDocument(4))
        await settle()
        source.set(roomsDocument(3))
        await settle()
        source.set(roomsDocument(2))
        await settle()
        clock.release()
        await settle()
        #expect(indexer.indexed.count == 2)
        #expect(indexer.indexed.last?.count == 5 + 2)
    }

    /// Fails if: a change that is undone before the debounce ends still indexes (the content is what was indexed).
    @Test func aChangeUndoneBeforeTheDebounceIndexesNothing() async {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        let indexer = RecordingIndexer()
        let clock = HeldSleeper()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer, sleeper: { await clock.sleep($0) })
        reindexer.start()
        source.set(roomsDocument(3))
        await settle()
        source.set(DemoHouse.config)
        await settle()
        clock.release()
        await settle()
        #expect(indexer.indexed.count == 1)
    }

    /// Fails if: stopping leaves a debounced index to fire after sign-out.
    @Test func stoppingCancelsAnIndexWaitingOutTheDebounce() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let clock = HeldSleeper()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer, sleeper: { await clock.sleep($0) })
        reindexer.start()
        source.set(roomsDocument(3))
        await settle()
        reindexer.stop()
        clock.release()
        await settle()
        #expect(indexer.indexed.count == 1)
    }

    @Test func aDocumentChangeThatLeavesTheEntriesAloneIndexesNothing() async {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        let indexer = RecordingIndexer()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer)
        reindexer.start()
        var house = DemoHouse.config
        house.home.weatherEntityId = "weather.demo_elsewhere"
        source.set(house)
        await settle()
        #expect(indexer.indexed.count == 1)
    }

    @Test func nothingIsIndexedAfterStopping() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer)
        reindexer.start()
        reindexer.stop()
        source.set(roomsDocument(3))
        await settle()
        #expect(indexer.indexed.count == 1)
    }

    @Test func startingAgainIndexesAgainEvenWithTheSameEntries() async {
        let source = HouseConfigSource()
        let indexer = RecordingIndexer()
        let reindexer = SpotlightReindexer(source: source, indexer: indexer)
        reindexer.start()
        reindexer.stop()
        // A new session: sign-out emptied the system index, so the same entries must go in again.
        reindexer.start()
        await settle()
        #expect(indexer.indexed.count == 2)
    }

    @Test func signingOutStopsTheReindexerBeforeTheDocumentIsCleared() throws {
        let indexer = RecordingIndexer()
        let session = AppSession(
            tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "reindex-\(UUID()).json")),
            spotlight: indexer
        )
        try session.didSignIn(server: HassServer(baseURL: URL(string: "http://127.0.0.1:1")!),
                              tokens: AuthTokens(accessToken: "a", expiresAt: .distantFuture, refreshToken: "r"))
        let before = indexer.indexed.count
        session.signOut()
        #expect(indexer.indexed.count == before)
    }
}

/// Records the order batches ran in.
private actor BatchOrder {
    var events: [String] = []
    func add(_ event: String) { events.append(event) }
}

/// Spotlight batches run in the order they were queued.
@MainActor
@Suite(.hosted)
struct SpotlightBatchQueueTests {
    @Test func aSlowEarlierBatchStillFinishesBeforeALaterOne() async {
        let queue = SpotlightBatchQueue()
        let order = BatchOrder()
        queue.enqueue {
            try? await Task.sleep(for: .milliseconds(80))
            await order.add("first")
        }
        queue.enqueue { await order.add("second") }
        queue.enqueue { await order.add("third") }
        await queue.drain()
        #expect(await order.events == ["first", "second", "third"])
    }

    @Test func aRemovalQueuedAfterAnIndexRunsLastSoSignedOutRoomsDoNotReturn() async {
        let queue = SpotlightBatchQueue()
        let order = BatchOrder()
        queue.enqueue {
            try? await Task.sleep(for: .milliseconds(50))
            await order.add("index")
        }
        queue.enqueue { await order.add("removeAll") }
        await queue.drain()
        #expect(await order.events.last == "removeAll")
    }

    @Test func anEmptyQueueDrainsAtOnce() async {
        await SpotlightBatchQueue().drain()
    }
}
