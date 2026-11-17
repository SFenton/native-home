import Foundation
@testable import HassCore
import Observation
import Testing

private final class Counter: @unchecked Sendable { var value = 0 }

/// What a `repeat` draws, how it counts a page, how it keeps cells by position, and how a records flow reaches it (`sh.repeat@1`).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ServerUIRepeatTests {
    // MARK: Paging

    private static let paging = ServerUIRepeat.Paging(compact: 4, regular: 7, scaleByTextSize: [1, 0.75, 0.5, 0.25], minimum: 2)

    @Test func aPageHoldsTheCountOfTheWindowScaledByTheTextSize() {
        #expect(Self.paging.pageSize(isRegular: false, textStep: 0) == 4)
        #expect(Self.paging.pageSize(isRegular: true, textStep: 0) == 7)
        #expect(Self.paging.pageSize(isRegular: false, textStep: 1) == 3)
        #expect(Self.paging.pageSize(isRegular: true, textStep: 1) == 5)
        #expect(Self.paging.pageSize(isRegular: false, textStep: 2) == 2)
    }

    @Test func aPageNeverShrinksBelowTheMinimumOrOneAndNeverGrowsPastItsBase() {
        #expect(Self.paging.pageSize(isRegular: false, textStep: 3) == 2)
        let plain = ServerUIRepeat.Paging(compact: 3, regular: 3, scaleByTextSize: [1, 1, 1, 0.1])
        #expect(plain.pageSize(isRegular: false, textStep: 3) == 1)
        let grows = ServerUIRepeat.Paging(compact: 3, regular: 3, scaleByTextSize: [2, 1, 1, 1])
        #expect(grows.pageSize(isRegular: false, textStep: 0) == 3)
        #expect(Self.paging.pageSize(isRegular: false, textStep: 9) == 4, "a step with no factor keeps the count")
    }

    @Test func theTextStepFollowsTheScaleThresholds() {
        #expect(ServerUIRepeat.textStep(scale: 1) == 0)
        #expect(ServerUIRepeat.textStep(scale: 1.1) == 1)
        #expect(ServerUIRepeat.textStep(scale: 1.24) == 1)
        #expect(ServerUIRepeat.textStep(scale: 1.25) == 2)
        #expect(ServerUIRepeat.textStep(scale: 1.4) == 3)
        #expect(ServerUIRepeat.textStep(scale: 3) == 3)
    }

    // MARK: What shows

    private func plan(_ phase: ServerUIRowCollection.Phase?, _ count: Int, limit: Int = 100, placeholders: Int? = nil) -> ServerUIRepeatPlan {
        .make(phase: phase, recordCount: count, limit: limit, placeholderCount: placeholders)
    }

    @Test func recordsDrawAsCellsUpToTheLimit() {
        #expect(plan(.ready, 5) == .init(body: .cells(5), isStale: false))
        #expect(plan(.ready, 50, limit: 10).body == .cells(10))
        #expect(plan(.loading, 3).body == .cells(3), "a refresh keeps the cells")
    }

    @Test func aKeptListThatFailedShowsTheStaleFootnote() {
        #expect(plan(.stale, 2).isStale)
        #expect(plan(.failed, 2).isStale)
        #expect(plan(.unavailable, 2).isStale)
        #expect(!plan(.ready, 2).isStale)
    }

    @Test func withNoRecordsTheWordsFollowTheState() {
        #expect(plan(.ready, 0).body == .word(.empty))
        #expect(plan(.failed, 0).body == .word(.error))
        #expect(plan(.unavailable, 0).body == .word(.unavailable))
        #expect(plan(.loading, 0).body == .word(.loading))
        #expect(plan(nil, 0).body == .word(.loading))
    }

    @Test func whileLoadingThePlaceholderDrawsAtMostTwentyFourTimes() {
        #expect(plan(.loading, 0, placeholders: 3).body == .placeholders(3))
        #expect(plan(.loading, 0, placeholders: 99).body == .placeholders(24))
        #expect(plan(.ready, 0, placeholders: 3).body == .word(.empty), "a placeholder is only for loading")
    }

    @Test func eachStateTakesItsOwnWord() {
        let words = ServerUIRepeat.Words(loading: "L", empty: "E", unavailable: "U", error: "X", stale: "S")
        let any = plan(.ready, 0)
        #expect([ServerUIRepeatPlan.Word.loading, .empty, .unavailable, .error].map { any.text($0, in: words) } == ["L", "E", "U", "X"])
    }

    // MARK: Keyed updates

    private func record(_ id: String, _ value: Double) -> JSONValue { .object(["id": .string(id), "value": .number(value)]) }

    @Test func oneChangedRecordIsOneChangedCell() {
        let old = [record("a", 1), record("b", 2), record("c", 3)]
        let new = [record("a", 1), record("b", 9), record("c", 3)]
        let diff = ServerUIRepeatDiff.between(old, new)
        #expect(diff.changed == [1])
        #expect(diff.added.isEmpty && diff.removed.isEmpty)
        #expect(!diff.isEmpty)
    }

    @Test func theSameRecordsAreNoChange() {
        let rows = [record("a", 1), record("b", 2)]
        #expect(ServerUIRepeatDiff.between(rows, rows).isEmpty)
    }

    @Test func newAndGoneCellsAreCountedByPosition() {
        let old = [record("a", 1), record("b", 2)]
        let longer = ServerUIRepeatDiff.between(old, old + [record("c", 3), record("d", 4)])
        #expect(longer.added == 2..<4 && longer.removed.isEmpty && longer.changed.isEmpty)
        let shorter = ServerUIRepeatDiff.between(old, [record("a", 1)])
        #expect(shorter.removed == 1..<2 && shorter.added.isEmpty)
    }

    @Test func theLimitCutsBothSidesBeforeComparing() {
        let old = (0..<6).map { record("r\($0)", Double($0)) }
        var new = old
        new[5] = record("r5", 99)
        #expect(ServerUIRepeatDiff.between(old, new, limit: 5).isEmpty, "the changed record is past the limit and not drawn")
        #expect(ServerUIRepeatDiff.between(old, new, limit: 6).changed == [5])
    }

    // MARK: The collection

    @Test func aCollectionKeepsLastGoodRecordsAndCountsOnlyWhenTheCountChanges() throws {
        let collection = ServerUIRowCollection()
        try collection.apply(records: [record("a", 1), record("b", 2)], phase: .ready)
        #expect(collection.records.count == 2 && collection.recordCount == 2 && collection.phase == .ready)

        let counts = Counter()
        withObservationTracking { _ = collection.recordCount } onChange: { counts.value += 1 }
        try collection.apply(records: [record("a", 1), record("b", 7)], phase: .ready)
        #expect(counts.value == 0, "a changed record does not wake what watches the count")
        #expect(collection.records[1] == record("b", 7))

        try collection.apply(records: nil, phase: .stale)
        #expect(collection.records.count == 2 && collection.phase == .stale, "nothing new keeps the last records")
    }

    @Test func aCollectionRefusesRecordsThatBreakItsLimits() throws {
        let collection = ServerUIRowCollection()
        #expect(throws: ServerUIRowCollection.Failure.self) { try collection.apply(records: [.string("not an object")], phase: .ready) }
        #expect(throws: ServerUIRowCollection.Failure.self) {
            try collection.apply(records: (0..<101).map { record("r\($0)", 0) }, phase: .ready)
        }
        #expect(throws: ServerUIRowCollection.Failure.self) { try collection.apply(records: [], phase: .loading) }
        #expect(throws: ServerUIRowCollection.Failure.self) { try collection.apply(records: nil, phase: .ready) }
    }

    // MARK: The flow's records

    private static let recordsFlow = """
    {"title": "Chores", "parameters": [],
     "request": {"type": "ha-subscription", "kind": "todo-items", "entityId": {"type": "literal", "value": "todo.demo_chores"}},
     "steps": [{"id": "items", "op": "get", "path": ["items"]},
               {"id": "cells", "op": "map", "fields": {"title": {"type": "item", "path": ["summary"]}, "position": {"type": "index"}}}],
     "output": {"kind": "records", "max": 24},
     "schema": {"kind": "array", "of": {"kind": "object", "fields": {"title": {"shape": {"kind": "string"}}, "position": {"shape": {"kind": "number", "integer": true}}}}}}
    """

    private static func push(_ titles: [String]) -> JSONValue {
        .object(["items": .array(titles.map { .object(["summary": .string($0)]) })])
    }

    @Test func aRecordsFlowPublishesRecordsWithTheirPositionAndKeepsThemWhenItFails() async throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(Self.recordsFlow.utf8))
        let decoded = ServerUIFlowDecoder.decode(value, at: "")
        try #require(decoded.issues.isEmpty, "decode issues \(decoded.issues)")
        let flow = try #require(decoded.flow)
        #expect(flow.givesRecords && !flow.givesRows)

        let feed = FakeFlowFeed()
        let collection = ServerUIRowCollection()
        let session = ServerUIFlowSession(flow: flow, collection: collection, host: .init(feed: feed))
        session.start()
        #expect(collection.phase == .loading && collection.records.isEmpty)

        feed.send(.success(Self.push(["Bins", "Dishes"])))
        #expect(await eventually { collection.recordCount == 2 })
        #expect(collection.records == [.object(["title": .string("Bins"), "position": .number(0)]),
                                       .object(["title": .string("Dishes"), "position": .number(1)])])
        #expect(collection.phase == .ready)

        feed.send(.success(Self.push(["Bins", "Laundry"])))
        #expect(await eventually { collection.records.last?["title"] == .string("Laundry") })
        #expect(collection.recordCount == 2)

        feed.send(.failure(CancellationError()))
        #expect(await eventually { collection.phase == .stale })
        #expect(collection.recordCount == 2, "a failure keeps the last good records")
    }

    // MARK: Gating

    private static func decode(_ envelope: [String: Any]) -> Result<ServerUICompositionPublication, any Error> {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return HouseConfigSource.$scoped.withValue(source) {
            Result { try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: envelope)) }
        }
    }

    private static func corpusEnvelope(_ path: String) throws -> [String: Any] {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent(path)
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func aDocumentThatUsesARepeatMustDeclareIt() throws {
        var envelope = try Self.corpusEnvelope("accept/repeat-horizontal.json")
        guard case .success = Self.decode(envelope) else { Issue.record("the corpus case must decode as written"); return }
        envelope["capabilities"] = (envelope["capabilities"] as? [String] ?? []).filter { $0 != "sh.repeat@1" }
        guard case .failure(let error) = Self.decode(envelope), let thrown = error as? ServerUICompositionError else {
            Issue.record("a repeat with no declaration must be refused")
            return
        }
        #expect(thrown.code == .capabilityManifestMismatch && thrown.pointer == "/capabilities")
    }

    @Test func aDocumentThatDoesNotUseARepeatMayNotDeclareIt() throws {
        var envelope = try Self.corpusEnvelope("accept/fixture-composition-first-slice.json")
        envelope["capabilities"] = (envelope["capabilities"] as? [String] ?? []) + ["sh.repeat@1"]
        guard case .failure(let error) = Self.decode(envelope), let thrown = error as? ServerUICompositionError else {
            Issue.record("a declaration nothing uses must be refused")
            return
        }
        #expect(thrown.code == .capabilityManifestMismatch)
    }

    @Test func aDocumentThatDeclaresNeitherIdDecodesAsItDidBefore() throws {
        let envelope = try Self.corpusEnvelope("accept/fixture-composition-first-slice.json")
        let declared = envelope["capabilities"] as? [String] ?? []
        #expect(!declared.contains("sh.repeat@1") && !declared.contains("sh.flow-extras@1"))
        guard case .success = Self.decode(envelope) else { Issue.record("the older document must decode"); return }
    }

    @Test func bothIdsAreIngested() {
        #expect(ServerUIIngestedCapabilities.all.contains("sh.repeat@1") && ServerUIIngestedCapabilities.all.contains("sh.flow-extras@1"))
    }
}
