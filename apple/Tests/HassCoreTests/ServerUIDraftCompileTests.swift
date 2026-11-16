import Foundation
@testable import HassDesign
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Draft compile entry

/// The compile entry point `tools/parity_loop/draft.py` drives: it runs one publication file through the app's own acceptance
/// (the preview's `published` event, ``ServerUIPublicationEvent/judge(_:)``, then ``ServerUIPublicationStore/apply(_:)``) and reports
/// the outcome as one JSON object, never an authored value.
///
/// `PARITY_DRAFT_PUBLICATION` names the file and `PARITY_DRAFT_RESULT` the file the result is written to. Without both, that test is
/// reported as skipped; the other tests check the reporting on the shared corpus in every run.
@Suite(.timeLimit(.minutes(5)))
@MainActor
struct ServerUIDraftCompileTests {
    /// The outcome of accepting one file: `{"ok":true,"unchecked":[...]}` or the first refusal (stage, code, pointer, capability).
    ///
    /// This is the path the preview takes: ``ServerUIAcceptance/publishedEvent(envelope:)`` (the same function `UKServerUIPreview`
    /// calls), a ``ServerUIPublicationStore`` with a no-op prepare, then ``ServerUIAcceptance/refusal(in:)``, which the UIKit preflight
    /// calls too. What needs a device is listed in ``ServerUIAcceptance/uncheckedOnDevice``.
    static func report(for bytes: Data) async -> [String: Any] {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        let event: ServerUIPublicationEvent
        do { event = try HouseConfigSource.$scoped.withValue(source) { try ServerUIAcceptance.publishedEvent(envelope: bytes) } }
        catch { return ["ok": false, "stage": "envelope", "code": "malformed", "pointer": ""] }
        return await report(for: event)
    }

    /// The outcome for one judged event; see ``report(for:)-(Data)``.
    ///
    /// - Parameter cacheDirectory: Where the store keeps its record; share one between two calls to model a last-good record already on disk.
    static func report(for event: ServerUIPublicationEvent, cacheDirectory: URL? = nil) async -> [String: Any] {
        switch event {
        case .invalid(.composition(let error)):
            var value: [String: Any] = ["ok": false, "stage": "decode", "code": error.code.rawValue, "pointer": error.pointer]
            if let capability = error.capability { value["capability"] = capability }
            return value
        case .invalid(let error):
            return ["ok": false, "stage": "judge", "code": "\(error)", "pointer": ""]
        case .incompatible, .unpublished:
            return ["ok": false, "stage": "judge", "code": "not_published", "pointer": ""]
        case .published(let published):
            if let refusal = ServerUIAcceptance.refusal(in: published.publication.document) {
                return ["ok": false, "stage": "preflight", "code": refusal.code, "pointer": refusal.pointer]
            }
            let directory = cacheDirectory ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("draft-accept-\(UUID().uuidString)", isDirectory: true)
            defer { if cacheDirectory == nil { try? FileManager.default.removeItem(at: directory) } }
            guard let partition = try? ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "https://preview.invalid")!)) else {
                return ["ok": false, "stage": "store", "code": "partition", "pointer": ""]
            }
            let store = ServerUIPublicationStore<Int>(partition: partition, cacheDirectory: directory,
                                                       prepare: { _, _ in 0 }, discard: { _, _ in })
            await store.bind(userID: "preview")
            await store.apply(.published(published))
            guard case .ready = store.status, store.current != nil else {
                return ["ok": false, "stage": "store", "code": "\(store.status)", "pointer": store.rejection ?? ""]
            }
            return ["ok": true, "revision": published.publication.revision, "capabilities": published.publication.capabilities.count,
                    "unchecked": ServerUIAcceptance.uncheckedOnDevice]
        }
    }

    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    /// Compiles the file `PARITY_DRAFT_PUBLICATION` names and writes the report to `PARITY_DRAFT_RESULT`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PARITY_DRAFT_PUBLICATION"] != nil
                   && ProcessInfo.processInfo.environment["PARITY_DRAFT_RESULT"] != nil))
    func compilesTheNamedPublication() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["PARITY_DRAFT_PUBLICATION"]), out = try #require(environment["PARITY_DRAFT_RESULT"])
        let report = await Self.report(for: try Data(contentsOf: URL(fileURLWithPath: path)))
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: out), options: .atomic)
    }

    @Test func reportsAnAcceptedFileAsOk() async throws {
        let report = await Self.report(for: try Data(contentsOf: Self.corpus.appendingPathComponent("accept/action-rules-row.json")))
        #expect(report["ok"] as? Bool == true)
    }

    @Test func reportsARejectedFileWithItsFirstIssue() async throws {
        let index = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.corpus.appendingPathComponent("index.json"))) as? [String: Any])
        let cases = try #require(index["cases"] as? [[String: Any]])
        let item = try #require(cases.first { $0["outcome"] as? String == "reject" && $0["houseScripts"] == nil && $0["pending"] == nil })
        let issue = try #require(item["issue"] as? [String: Any])
        let file = try #require(item["file"] as? String)
        let report = await Self.report(for: try Data(contentsOf: Self.corpus.appendingPathComponent(file)))
        #expect(report["ok"] as? Bool == false)
        #expect(report["code"] as? String == issue["code"] as? String)
        #expect(report["pointer"] as? String == issue["pointer"] as? String)
    }

    /// Sets every authored status-chip appearance fill in `value` to a solid colour, returning how many it changed.
    private static func paintChips(_ value: inout Any, red: Int, green: Int, blue: Int) -> Int {
        var changed = 0
        if var object = value as? [String: Any] {
            if object["type"] as? String == "status-chip", var props = object["props"] as? [String: Any],
               var states = props["states"] as? [[String: Any]] {
                for index in states.indices {
                    guard var appearance = states[index]["appearance"] as? [String: Any] else { continue }
                    appearance["fill"] = ["type": "solid-rgb", "red": red, "green": green, "blue": blue]
                    appearance.removeValue(forKey: "glyph")
                    states[index]["appearance"] = appearance
                    changed += 1
                }
                props["states"] = states
                object["props"] = props
            }
            for key in object.keys {
                var child = object[key] as Any
                changed += paintChips(&child, red: red, green: green, blue: blue)
                object[key] = child
            }
            value = object
        } else if var array = value as? [Any] {
            for index in array.indices { changed += paintChips(&array[index], red: red, green: green, blue: blue) }
            value = array
        }
        return changed
    }

    /// A synthetic publication that decodes but that the app refuses at acceptance: a chip fill too light for white text.
    @Test func reportsAChipFillTheAppRefusesThoughItDecodes() async throws {
        let base = try Data(contentsOf: Self.corpus.appendingPathComponent("accept/appearance-fill.json"))
        for (light, expected) in [((67, 160, 71), false), ((47, 111, 49), true)] {
            var value = try JSONSerialization.jsonObject(with: base)
            #expect(Self.paintChips(&value, red: light.0, green: light.1, blue: light.2) > 0)
            let report = await Self.report(for: try JSONSerialization.data(withJSONObject: value))
            #expect(report["ok"] as? Bool == expected)
            if !expected {
                #expect(report["stage"] as? String == "preflight")
                #expect(report["code"] as? String == "unsupported_capability")
                #expect((report["pointer"] as? String)?.hasSuffix("/appearance/fill") == true)
            }
        }
    }
}

// MARK: - Shared rules

extension ServerUIDraftCompileTests {
    private static func corpusJSON(_ name: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: corpus.appendingPathComponent(name))) as? [String: Any])
    }

    /// What the judge refuses or does not publish is reported at its own stage, never as accepted.
    @Test func reportsAJudgeStageRefusal() async {
        let refused = await Self.report(for: ServerUIPublicationEvent.invalid(.malformedEvent))
        #expect(refused["ok"] as? Bool == false)
        #expect(refused["stage"] as? String == "judge")
        let unpublished = await Self.report(for: ServerUIPublicationEvent.unpublished)
        #expect(unpublished["stage"] as? String == "judge" && unpublished["code"] as? String == "not_published")
    }

    /// A newer record already on disk (the preview's last-good from an earlier run) makes the store refuse an older revision of the same epoch.
    @Test func reportsAStaleRevisionAgainstTheRecordOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("draft-stale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func event(revision: Int) throws -> ServerUIPublicationEvent {
            var envelope = try Self.corpusJSON("accept/action-rules-row.json")
            envelope["revision"] = revision
            let source = HouseConfigSource()
            source.set(DemoHouse.config)
            return try HouseConfigSource.$scoped.withValue(source) {
                try ServerUIAcceptance.publishedEvent(envelope: JSONSerialization.data(withJSONObject: envelope))
            }
        }
        let first = await Self.report(for: try event(revision: 5), cacheDirectory: directory)
        #expect(first["ok"] as? Bool == true)
        let older = await Self.report(for: try event(revision: 2), cacheDirectory: directory)
        #expect(older["ok"] as? Bool == false)
        #expect(older["stage"] as? String == "store")
        #expect((older["code"] as? String)?.contains("staleGeneration") == true)
        let newer = await Self.report(for: try event(revision: 6), cacheDirectory: directory)
        #expect(newer["ok"] as? Bool == true)
    }

    @Test func reportsWhatOnlyADeviceChecksOnSuccess() async throws {
        let bytes = try Data(contentsOf: Self.corpus.appendingPathComponent("accept/action-rules-row.json"))
        let report = await Self.report(for: bytes)
        #expect(report["unchecked"] as? [String] == ServerUIAcceptance.uncheckedOnDevice)
    }

    /// Mixed horizontal chrome policies on one side, on a synthetic edit of an accepted file, give the preflight's pointer.
    @Test func refusesMixedChromePoliciesWithThePreflightPointer() throws {
        func refusal(_ edit: (inout [String: Any]) -> Void) throws -> ServerUIAcceptance.Refusal? {
            var envelope = try Self.corpusJSON("accept/action-rules-row.json")
            var document = try #require(envelope["document"] as? [String: Any])
            edit(&document)
            envelope["document"] = document
            let bytes = try JSONSerialization.data(withJSONObject: envelope)
            let source = HouseConfigSource()
            source.set(DemoHouse.config)
            let publication = try HouseConfigSource.$scoped.withValue(source) { try ServerUICompositionPublication.decode(bytes) }
            return ServerUIAcceptance.refusal(in: publication.document)
        }
        #expect(try refusal { _ in } == nil)
        let mixed = try refusal { document in
            var navigation = document["navigation"] as? [String: Any] ?? [:]
            var chrome = navigation["chrome"] as? [String: Any] ?? [:]
            var groups = chrome["groups"] as? [[String: Any]] ?? []
            for index in groups.indices {
                groups[index]["placement"] = "leading"
                groups[index]["horizontal"] = index == 0 ? "separate-circles@1" : "shared@1"
            }
            chrome["groups"] = groups
            navigation["chrome"] = chrome
            document["navigation"] = navigation
        }
        #expect(mixed?.pointer == "/document/navigation/chrome/groups")
    }

    /// `ServerUIColorText` is the port of `ChipTint`; the chip rule is only the app's if the numbers agree.
    @Test func colorTextAgreesWithChipTint() {
        #expect(ServerUIColorText.fillScale == ChipTint.fillScale)
        #expect(ServerUIColorText.highlight == ChipTint.highlight)
        #expect(ServerUIColorText.textContrast == ChipTint.textContrast)
        #expect(ServerUIColorText.glyphContrast == ChipTint.glyphContrast)
        for value in [0x000000, 0xFFFFFF, 0x43A047, 0x2F6F31, 0x196482, 0xD70015, 0x8A5200, 0x3B523E, 0x7ED787, 0x123456] {
            let tint = ChipTint(fill: UInt32(value), glyph: 0xFFFFFF)
            #expect(ServerUIColorText.liftedFill(value) == Int(tint.liftedFill))
            #expect(ServerUIColorText.luminance(value) == ChipTint.luminance(UInt32(value)))
            for other in [0xFFFFFF, 0x000000, 0x7ED787] {
                #expect(ServerUIColorText.contrast(value, other) == ChipTint.contrast(UInt32(value), UInt32(other)))
            }
            let web = ChipTint.fromWeb(UInt32(value))
            let port = ServerUIColorText.tint(value)
            #expect(port.fill == Int(web.fill) && port.glyph == Int(web.glyph))
        }
    }

    // MARK: Staged container layout

    /// Serves the one synthetic PNG the corpus fixture's asset names.
    private struct FixtureAssets: ServerUIAssetFetching {
        func download(_ asset: ServerUICompositionDocument.Asset) async throws -> Data {
            try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGOQsIhIWLCBYUOBxYMDDQAiXgXRUMwx1wAAAABJRU5ErkJggg=="))
        }
    }

    private static let previewServer = HassServer(baseURL: URL(string: "https://preview.invalid")!)

    /// Lays out a preview container as `stage.py` does, runs what the preview does before it accepts (the house-config cache writes
    /// under the partition, then the asset stager stages), and returns the stager's outcome.
    private static func stage(partitionMode: Int?) async throws -> Result<Int, ServerUIAssetError> {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("draft-stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let partition = try ServerUIPublicationPartition(server: previewServer)
        let root = partition.storageDirectory(in: container.appendingPathComponent("publications", isDirectory: true))
        if let partitionMode {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: partitionMode])
        }
        let cache = HouseConfigCache(fileURL: root.appendingPathComponent("live/HouseConfig.json"))
        try cache.save(DemoHouse.config, hash: nil, server: previewServer)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        let publication = try ServerUICompositionPublication.decode(Data(contentsOf: fixture))
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: root, transport: FixtureAssets())
        do {
            let staged = try await stager.stage(publication, documentDigest: publication.documentSha256)
            return .success(staged.assets.count)
        } catch let error as ServerUIAssetError { return .failure(error) }
    }

    /// The device's `asset: storage`: with no partition directory the house-config cache creates it with the default mode, and the
    /// stager refuses a directory others can read.
    @Test func anUnpreparedPartitionDirectoryRefusesStagingAsStorage() async throws {
        let result = try await Self.stage(partitionMode: nil)
        #expect(result == .failure(.storage))
    }

    /// The fix: `stage.py` leaves the partition directory private, so the same sequence stages the asset.
    @Test func aPrivatePartitionDirectoryStagesTheAsset() async throws {
        let result = try await Self.stage(partitionMode: 0o700)
        #expect(result == .success(1))
    }

    /// `stage.py` names the partition directory by this digest; it must be the app's.
    @Test func thePreviewPartitionDigestMatchesWhatStagePyWrites() throws {
        let partition = try ServerUIPublicationPartition(server: Self.previewServer)
        #expect(partition.digest == "061360d23f8d83ab0d03db3dc31451c58c90760ff2436e2c9ebfd956e76ce509")
    }
}
