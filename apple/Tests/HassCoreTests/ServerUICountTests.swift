import Foundation
import Testing
@testable import HassCore

// MARK: - The count operand

/// `sh.count@1`: the parser, the evaluator and what a count costs. The shared corpus (`ContractCorpus/evaluation/count-operand-*`) holds the
/// answers both sides give; these tests hold what only the app can say: the one read per entry, the viewer comparisons that cost no scan, and the
/// parts of the typed form (`sourceIds`, `readsViewer`, the static kind).
@Suite(.timeLimit(.minutes(1)))
struct ServerUICountTests {
    /// A reader over fixed states that counts how many reads it was asked for.
    private final class Reader: ServerUIReading, @unchecked Sendable {
        var states: [String: ServerUIReadResult] = [:]
        var viewer: ServerUIViewer?
        var person: ServerUIReadResult = .unavailable
        var isFlow = false
        private(set) var reads = 0
        func read(sourceId: String, path: [String]) -> ServerUIReadResult { reads += 1; return states[sourceId] ?? .unavailable }
        func viewerPersonState() -> ServerUIReadResult { person }
    }

    private func state(_ id: String, _ words: String...) -> String {
        #"{"test":{"type":"state","sourceId":"\#(id)","path":["state"],"in":[\#(words.map { "\"\($0)\"" }.joined(separator: ","))]}}"#
    }

    private func operand(_ entries: [String]) throws -> ServerUIOperand {
        var parser = ServerUIExpressionParser()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"count","of":[\#(entries.joined(separator: ","))]}"#.utf8))
        let value = parser.operand(json, at: "/x")
        #expect(parser.issues.isEmpty, "\(parser.issues)")
        #expect(parser.needs.contains("count"))
        return try #require(value)
    }

    private func sources(_ operand: ServerUIOperand) -> [String: ServerUIReadResult] {
        Dictionary(uniqueKeysWithValues: operand.sourceIds.map { ($0, .value(.string("on"))) })
    }

    // MARK: Cost

    /// Thirty-two entries are thirty-two reads: one for each entry, however many times the count is used or what its entries answer.
    @Test func aCountOfThirtyTwoReadsEachEntryOnce() throws {
        let ids = (0..<32).map { "s\($0)" }
        let count = try operand(ids.map { state($0, "on") })
        let reader = Reader()
        reader.states = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, .value(.string($0 % 2 == 0 ? "on" : "off"))) })
        #expect(count.evaluate(reader) == .value(.number(16)))
        #expect(reader.reads == 32)
    }

    /// A viewer filter is a comparison of strings: the entities of an entry the viewer is not in are not read at all.
    @Test func anEntryTheViewerIsNotInIsNeverRead() throws {
        let count = try operand([
            #"{"test":{"type":"state","sourceId":"a","path":["state"],"in":["on"]},"viewer":{"personEntityIds":["person.demo_sam"]}}"#,
            #"{"test":{"type":"state","sourceId":"b","path":["state"],"in":["on"]},"viewer":{"personEntityIds":["person.demo_alex"]}}"#,
            state("c", "on"),
        ])
        let reader = Reader()
        reader.viewer = ServerUIViewer(userId: "u", isAdmin: false, personEntityId: "person.demo_sam")
        reader.states = ["a": .value(.string("on")), "b": .value(.string("on")), "c": .value(.string("on"))]
        #expect(count.evaluate(reader) == .value(.number(2)))
        #expect(reader.reads == 2, "the entry for the other person is skipped, not read")
    }

    // MARK: The answer

    @Test func theSameEntityInTwoEntriesCountsTwice() throws {
        let count = try operand([state("a", "on"), state("a", "on")])
        let reader = Reader()
        reader.states = ["a": .value(.string("on"))]
        #expect(count.evaluate(reader) == .value(.number(2)))
    }

    @Test func oneUnanswerableEntryDoesNotStopTheOthers() throws {
        let count = try operand([state("a", "on"), state("b", "on"), state("c", "on")])
        let reader = Reader()
        reader.states = ["a": .value(.string("on")), "b": .loading]
        #expect(count.evaluate(reader) == .value(.number(1)))
    }

    @Test func everyEntryUnanswerableIsLoadingWhenAnyReadWaitedElseUnavailable() throws {
        let count = try operand([state("a", "on"), state("b", "on")])
        let reader = Reader()
        #expect(count.evaluate(reader) == .unavailable)
        reader.states = ["b": .loading]
        #expect(count.evaluate(reader) == .loading)
    }

    @Test func aFilteredEntryWaitsForTheViewerAndAnUnfilteredCountDoesNot() throws {
        let filtered = try operand([#"{"test":{"type":"state","sourceId":"a","path":["state"],"in":["on"]},"viewer":{"personEntityIds":["person.demo_sam"]}}"#])
        let plain = try operand([state("a", "on")])
        let reader = Reader()
        reader.states = ["a": .value(.string("on"))]
        #expect(filtered.evaluate(reader) == .loading)
        #expect(plain.evaluate(reader) == .value(.number(1)))
        reader.viewer = ServerUIViewer(userId: "u", isAdmin: nil, personEntityId: nil)
        #expect(filtered.evaluate(reader) == .value(.number(0)), "a viewer with no person entity is in no entry: the answer is known, and it is 0")
    }

    @Test func aViewerWhoseReadIsWaitedOnMakesAnUnanswerableCountLoading() throws {
        let count = try operand([#"{"test":{"type":"viewer-person","in":["home"]}}"#])
        let reader = Reader()
        reader.viewer = ServerUIViewer(userId: "u")
        reader.person = .loading
        #expect(count.evaluate(reader) == .loading)
        reader.person = .unavailable
        #expect(count.evaluate(reader) == .unavailable)
    }

    @Test func aFlowGetsNull() throws {
        let count = try operand([state("a", "on")])
        let reader = Reader()
        reader.isFlow = true
        reader.states = ["a": .value(.string("on"))]
        #expect(count.evaluate(reader) == .value(.null))
        #expect(reader.reads == 0)
    }

    // MARK: The typed form

    @Test func theTypedFormReportsWhatItReads() throws {
        let plain = try operand([state("a", "on"), state("b", "on")])
        #expect(plain.sourceIds == ["a", "b"])
        #expect(!plain.readsViewer && !plain.readsClock && !plain.usesControl)
        let filtered = try operand([#"{"test":{"type":"state","sourceId":"a","path":["state"],"in":["on"]},"viewer":{"personEntityIds":["person.demo_sam"]}}"#])
        #expect(filtered.readsViewer)
        #expect(ServerUIExpressionParser.kind(plain) == .number)
    }

    @Test func theCountsOfASumAreOneKindAndItsSourcesAreTheUnion() throws {
        var parser = ServerUIExpressionParser()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"type":"math","op":"add","args":[
          {"type":"count","of":[{"test":{"type":"state","sourceId":"a","path":["state"],"in":["on"]}}]},
          {"type":"count","of":[{"test":{"type":"state","sourceId":"b","path":["state"],"in":["on"]}}]}]}
        """#.utf8))
        let parsed = parser.operand(json, at: "/x")
        let sum = try #require(parsed)
        #expect(parser.issues.isEmpty)
        #expect(sum.sourceIds == ["a", "b"])
        let reader = Reader()
        reader.states = ["a": .value(.string("on")), "b": .value(.string("on"))]
        #expect(sum.evaluate(reader) == .value(.number(2)))
    }

    // MARK: The shape

    @Test func aCountIsRefusedInAFlowAndNamesItsCapability() throws {
        var parser = ServerUIExpressionParser(flow: true)
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"count","of":[\#(state("a", "on"))]}"#.utf8))
        _ = parser.operand(json, at: "/x")
        #expect(parser.issues.first?.code == .invalidCombination)
        #expect(parser.issues.first?.pointer == "/x")
        #expect(parser.needs.contains("count"))
    }

    @Test func aCountKeepsEachTestsOwnConditionBudgetAndRestoresTheOuterOne() throws {
        // 32 `state` tests are 33 of the 64 nodes; a count beside a second one of 32 passes the 64 and is refused at the second.
        let many = (0..<32).map { state("s\($0)", "on") }.joined(separator: ",")
        var parser = ServerUIExpressionParser()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"type":"math","op":"add","args":[{"type":"count","of":[\#(many)]},{"type":"count","of":[\#(many)]}]}
        """#.utf8))
        _ = parser.operand(json, at: "/x")
        #expect(parser.issues.first?.code == .limitExceeded)
    }
}
