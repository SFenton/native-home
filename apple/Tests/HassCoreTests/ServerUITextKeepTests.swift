import Foundation
import Testing
@testable import HassCore

// MARK: - Keeping unavailable text

/// A text slot's `whenUnavailable` policy (`sh.text-keep@1`): how it decodes, what it needs declared, and what a slot instance draws.
///
/// The shared corpus (`ServerUIContractCorpusTests`, `ServerUIExpressionCorpusTests`) holds the Studio's answers; these tests pin each rule
/// with the data written out, so a failure names the rule that broke.
@Suite(.timeLimit(.minutes(1)))
struct ServerUITextKeepTests {
    // MARK: Fixtures

    private struct Reader: ServerUIReading {
        var states: [String: ServerUIReadResult] = [:]
        var viewer: ServerUIViewer? { nil }
        func read(sourceId: String, path: [String]) -> ServerUIReadResult { states[sourceId] ?? .unavailable }
        func viewerPersonState() -> ServerUIReadResult { .unavailable }
    }

    private static let temp = ServerUIOperand.read(sourceId: "temp", path: ["state"], as: .string)

    private static func answer(_ text: String) -> Reader { Reader(states: ["temp": .value(.string(text))]) }
    private static let gone = Reader()
    private static let loading = Reader(states: ["temp": .loading])

    private static func slot(_ policy: ServerUIUnavailablePolicy, fallback: String? = "No reading") -> ServerUICompositionDocument.StringValue {
        .expression(temp, fallback: fallback, whenUnavailable: policy)
    }

    /// One draw of `value` in `reader` by a slot instance with `memory`.
    private static func draw(_ value: ServerUICompositionDocument.StringValue, _ reader: Reader,
                             _ memory: inout ServerUITextMemory) -> ServerUIReadResult {
        ServerUIStringResolver.resolve(value, read: { _ in .unavailable }, in: reader, memory: &memory)
    }

    // MARK: Evaluation

    @Test func keepBeforeAnyAnswerDrawsTheFallback() {
        var memory = ServerUITextMemory()
        let outcome = Self.draw(Self.slot(.keep), Self.gone, &memory)
        #expect(outcome == .value(.string("No reading")))
        #expect(memory.answered == nil)
    }

    @Test func keepBeforeAnyAnswerWithNoFallbackIsUnavailable() {
        var memory = ServerUITextMemory()
        #expect(Self.draw(Self.slot(.keep, fallback: nil), Self.gone, &memory) == .unavailable)
    }

    @Test func keepAfterAnAnswerDrawsTheLastAnswerWhileUnavailable() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep)
        #expect(Self.draw(slot, Self.answer("21.5"), &memory) == .value(.string("21.5")))
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("21.5")))
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("21.5")), "it stays for as long as the value is unavailable")
        #expect(Self.draw(slot, Self.answer("22"), &memory) == .value(.string("22")), "a new answer replaces it")
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("22")))
    }

    @Test func keepWithNoFallbackStillKeeps() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep, fallback: nil)
        _ = Self.draw(slot, Self.answer("on"), &memory)
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("on")))
    }

    @Test func theFallbackPolicyIsToday() {
        for slot in [Self.slot(.fallback), .expression(Self.temp, fallback: "No reading")] {
            var memory = ServerUITextMemory()
            _ = Self.draw(slot, Self.answer("21.5"), &memory)
            #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("No reading")))
            #expect(memory.answered == nil, "a slot that does not keep remembers nothing")
        }
        var memory = ServerUITextMemory()
        #expect(Self.draw(Self.slot(.fallback, fallback: nil), Self.gone, &memory) == .unavailable)
    }

    @Test func anEmptyAnswerIsAnAnswer() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep)
        _ = Self.draw(slot, Self.answer("21.5"), &memory)
        _ = Self.draw(slot, Self.answer(""), &memory)
        #expect(memory.answered == "")
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("")))
    }

    @Test func drawingTheFallbackIsNotAnAnswer() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep)
        _ = Self.draw(slot, Self.gone, &memory)
        #expect(memory.answered == nil)
        // The first real answer is what is kept, never the fallback drawn before it.
        _ = Self.draw(slot, Self.answer("19"), &memory)
        #expect(Self.draw(slot, Self.gone, &memory) == .value(.string("19")))
    }

    @Test func drawingTheKeptTextIsNotAnAnswerEither() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep)
        _ = Self.draw(slot, Self.answer("19"), &memory)
        _ = Self.draw(slot, Self.gone, &memory)
        #expect(memory.answered == "19")
    }

    @Test(arguments: [ServerUIUnavailablePolicy.fallback, .keep])
    func loadingKeepsWhatWasShownUnderBothPolicies(policy: ServerUIUnavailablePolicy) {
        var memory = ServerUITextMemory()
        let slot = Self.slot(policy)
        _ = Self.draw(slot, Self.answer("21.5"), &memory)
        let before = memory
        #expect(Self.draw(slot, Self.loading, &memory) == .loading, "the site keeps what it showed")
        #expect(memory == before, "loading neither answers nor forgets")
    }

    @Test func aListOrObjectIsNotAnAnswer() {
        var memory = ServerUITextMemory()
        let slot = Self.slot(.keep)
        _ = Self.draw(slot, Self.answer("21.5"), &memory)
        let list = Reader(states: ["temp": .value(.array([.string("a")]))])
        #expect(Self.draw(slot, list, &memory) == .value(.string("21.5")))
    }

    @Test func aNumberIsAnAnswerAsText() {
        var memory = ServerUITextMemory()
        let number = Reader(states: ["temp": .value(.number(21.5))])
        let slot = ServerUICompositionDocument.StringValue.expression(.read(sourceId: "temp", path: ["state"], as: .number),
                                                                      fallback: "No reading", whenUnavailable: .keep)
        #expect(Self.draw(slot, number, &memory) == .value(.string("21.5")))
        #expect(memory.answered == "21.5")
    }

    @Test func eachSlotInstanceKeepsItsOwnAnswer() {
        let slot = Self.slot(.keep)
        var first = ServerUITextMemory(), second = ServerUITextMemory()
        _ = Self.draw(slot, Self.answer("a"), &first)
        _ = Self.draw(slot, Self.answer("b"), &second)
        #expect(Self.draw(slot, Self.gone, &first) == .value(.string("a")))
        #expect(Self.draw(slot, Self.gone, &second) == .value(.string("b")))
    }

    @Test func aReadKeepsLikeAnExpression() {
        let source = ServerUICompositionDocument.Read(sourceId: "temp", path: ["state"], kind: .string)
        let slot = ServerUICompositionDocument.StringValue.read(source, fallback: nil, whenUnavailable: .keep)
        var memory = ServerUITextMemory()
        let read: (ServerUICompositionDocument.Read) -> ServerUIReadResult = { _ in .value(.string("on")) }
        #expect(ServerUIStringResolver.resolve(slot, read: read, in: Self.gone, memory: &memory) == .value(.string("on")))
        let outcome = ServerUIStringResolver.resolve(slot, read: { _ in .unavailable }, in: Self.gone, memory: &memory)
        #expect(outcome == .value(.string("on")))
    }

    @Test func aMemoryForgetsWhenTheSlotIsPointedAtAnotherSource() {
        var memory = ServerUITextMemory()
        let other = ServerUICompositionDocument.StringValue.expression(.read(sourceId: "other", path: ["state"], as: .string),
                                                                      fallback: "No reading", whenUnavailable: .keep)
        #expect(Self.draw(Self.slot(.keep), Self.answer("21.5"), &memory) == .value(.string("21.5")))
        #expect(Self.draw(Self.slot(.keep), Self.gone, &memory) == .value(.string("21.5")), "the same source keeps")
        #expect(Self.draw(other, Self.gone, &memory) == .value(.string("No reading")), "a new source draws its fallback, not the old text")
    }

    @Test func aMemoryForgetsWhenARepeatCellShowsAnotherRecord() {
        var memory = ServerUITextMemory()
        let value = Self.slot(.keep)
        memory.attend(to: value, owner: .string("a"))
        #expect(Self.draw(value, Self.answer("21.5"), &memory) == .value(.string("21.5")))
        memory.attend(to: value, owner: .string("a"))
        #expect(memory.answered == "21.5", "the same record keeps")
        memory.attend(to: value, owner: .string("b"))
        #expect(memory.answered == nil, "another record starts over")
        #expect(Self.draw(value, Self.gone, &memory) == .value(.string("No reading")))
    }

    @Test func aLiteralHasNothingToKeep() {
        var memory = ServerUITextMemory()
        #expect(Self.draw(.literal("A"), Self.gone, &memory) == .value(.string("A")))
        #expect(memory.answered == nil)
    }

    @Test func theMemoryFreeResolverDrawsTheFallbackForAKeepSlot() {
        let slot = Self.slot(.keep)
        #expect(ServerUIStringResolver.resolve(slot, read: { _ in .unavailable }, in: Self.gone) == .value(.string("No reading")))
    }

    @Test func policyWordsDecode() {
        #expect(ServerUIUnavailablePolicy("keep") == .keep)
        #expect(ServerUIUnavailablePolicy("fallback") == .fallback)
        #expect(ServerUIUnavailablePolicy(nil) == .fallback)
        #expect(ServerUIUnavailablePolicy("retain") == .fallback, "the shape refuses it before it gets here")
    }

    // MARK: Decoding and validation

    private static func corpus(_ file: String) throws -> String {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func decode(_ text: String) -> Result<ServerUICompositionPublication, any Error> {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return HouseConfigSource.$scoped.withValue(source) { Result { try ServerUICompositionPublication.decode(Data(text.utf8)) } }
    }

    private static func slot(in publication: ServerUICompositionPublication) -> ServerUICompositionDocument.StringValue? {
        guard case .text(let text)? = publication.document.pages[2].surface.components.first else { return nil }
        return text.value
    }

    private static func refusal(_ result: Result<ServerUICompositionPublication, any Error>) -> ServerUICompositionError? {
        if case .failure(let error) = result { return error as? ServerUICompositionError }
        return nil
    }

    @Test func aReadDecodesItsPolicy() throws {
        let text = try Self.corpus("accept/text-keep-read-keep.json")
        let publication = try Self.decode(text).get()
        #expect(publication.capabilities.contains("sh.text-keep@1"))
        guard case .read(_, let fallback, let policy)? = Self.slot(in: publication) else { Issue.record("not a read"); return }
        #expect(policy == .keep && fallback == "No reading")
    }

    @Test func anExprDecodesItsPolicy() throws {
        let publication = try Self.decode(Self.corpus("accept/text-keep-expr-keep.json")).get()
        guard case .expression(_, _, let policy)? = Self.slot(in: publication) else { Issue.record("not an expression"); return }
        #expect(policy == .keep)
    }

    @Test func keepOnAReadNeedsNoFallbackAndNoRules() throws {
        let publication = try Self.decode(Self.corpus("accept/text-keep-read-without-fallback.json")).get()
        guard case .read(_, let fallback, let policy)? = Self.slot(in: publication) else { Issue.record("not a read"); return }
        #expect(fallback == nil && policy == .keep)
        #expect(!publication.capabilities.contains("sh.rules@1"))
    }

    @Test func theFallbackPolicyIsDeclaredToo() throws {
        let publication = try Self.decode(Self.corpus("accept/text-keep-read-fallback.json")).get()
        #expect(publication.capabilities.contains("sh.text-keep@1"), "writing either policy declares the capability")
        guard case .read(_, _, let policy)? = Self.slot(in: publication) else { Issue.record("not a read"); return }
        #expect(policy == .fallback)
    }

    @Test(arguments: ["read", "expr"])
    func anUnknownPolicyIsRefusedAtItsPointer(kind: String) throws {
        let error = try #require(Self.refusal(Self.decode(Self.corpus("reject/text-keep-\(kind)-invalid-policy.json"))))
        #expect(error.code == .unknownVariant)
        #expect(error.pointer == "/document/pages/2/components/0/props/value/whenUnavailable")
    }

    @Test(arguments: ["read", "expr"])
    func thePolicyWithoutTheCapabilityIsAMismatch(kind: String) throws {
        let error = try #require(Self.refusal(Self.decode(Self.corpus("reject/text-keep-\(kind)-missing-capability.json"))))
        #expect(error.code == .capabilityManifestMismatch)
        #expect(error.pointer == "/capabilities")
    }

    @Test func aDeclaredCapabilityNothingUsesIsAMismatchToo() throws {
        // The other direction of the same equality: the capability listed, the field written nowhere.
        let text = try Self.corpus("accept/text-keep-read-keep.json").replacingOccurrences(of: #","whenUnavailable":"keep""#, with: "")
            .replacingOccurrences(of: #""whenUnavailable":"keep","#, with: "")
        try #require(!text.contains("whenUnavailable"))
        let error = try #require(Self.refusal(Self.decode(text)))
        #expect(error.code == .capabilityManifestMismatch && error.pointer == "/capabilities")
    }

    @Test func aLiteralRefusesThePolicy() throws {
        let error = try #require(Self.refusal(Self.decode(Self.corpus("reject/text-keep-on-literal.json"))))
        #expect(error.code == .unknownField)
        #expect(error.pointer == "/document/pages/2/components/0/props/value/whenUnavailable")
    }

    @Test func theCapabilityIsShippedNotPending() throws {
        #expect(ServerUIIngestedCapabilities.all.contains("sh.text-keep@1"))
        #expect(ServerUICompositionPublication.supportedCapabilities.contains("sh.text-keep@1"))
        let pending = try JSONDecoder().decode([String].self, from: Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent("capabilities.pending.json")))
        #expect(!pending.contains("sh.text-keep@1"))
    }
}
