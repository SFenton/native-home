import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The cache keeps the last good document per server and throws away anything it cannot trust.
struct HouseConfigCacheTests {
    let server = HassServer(baseURL: URL(string: "https://demo.example.com")!)
    let url = FileManager.default.temporaryDirectory.appending(path: "house-cache-\(UUID()).json")

    private var cache: HouseConfigCache { HouseConfigCache(fileURL: url) }

    /// Rewrites the saved file after `edit` changes its fields.
    private func rewrite(_ edit: (inout HouseConfigCache.File) -> Void) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var file = try decoder.decode(HouseConfigCache.File.self, from: Data(contentsOf: url))
        edit(&file)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(file).write(to: url)
    }

    @Test func savesAndLoadsTheDocument() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        try cache.save(DemoHouse.config, hash: "abc", server: server, at: date)
        let loaded = try #require(cache.load(for: server))
        #expect(loaded == HouseConfigCache.Loaded(config: DemoHouse.config, hash: "abc", savedAt: date))
    }

    @Test func aMissingFileLoadsNothing() {
        #expect(cache.load(for: server) == nil)
    }

    @Test func aFileForAnotherServerIsDiscarded() throws {
        try cache.save(DemoHouse.config, hash: nil, server: server)
        #expect(cache.load(for: HassServer(baseURL: URL(string: "https://other.example.com")!)) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aDifferentFormatVersionIsDiscarded() throws {
        try cache.save(DemoHouse.config, hash: nil, server: server)
        try rewrite { $0.version = HouseConfigCache.currentVersion + 1 }
        #expect(cache.load(for: server) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aNewerSchemaIsDiscarded() throws {
        try cache.save(DemoHouse.config, hash: nil, server: server)
        try rewrite { $0.schema = HouseConfig.supportedSchema + 1 }
        #expect(cache.load(for: server) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aSchemaOneFileIsDiscardedSoTheServerLayoutIsFetched() throws {
        try cache.save(DemoHouse.config, hash: "old", server: server)
        try rewrite {
            $0.schema = 1
            $0.document = Data(String(decoding: $0.document, as: UTF8.self).replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1").utf8)
        }
        #expect(cache.load(for: server) == nil, "schema 1 is no longer read, and refusing it must not crash")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aDocumentThatNoLongerDecodesIsDiscarded() throws {
        try cache.save(DemoHouse.config, hash: nil, server: server)
        try rewrite { $0.document = Data(#"{"schema": 1}"#.utf8) }
        #expect(cache.load(for: server) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func garbageIsDiscarded() throws {
        try Data("not json".utf8).write(to: url)
        #expect(cache.load(for: server) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func clearRemovesTheFile() throws {
        try cache.save(DemoHouse.config, hash: nil, server: server)
        cache.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        cache.clear()
    }

    @Test func savingCreatesTheFolder() throws {
        let nested = FileManager.default.temporaryDirectory.appending(path: "house-\(UUID())/inner/house.json")
        try HouseConfigCache(fileURL: nested).save(DemoHouse.config, hash: nil, server: server)
        #expect(HouseConfigCache(fileURL: nested).load(for: server)?.config == DemoHouse.config)
    }

    @Test func theDefaultLocationIsTheAppGroupContainerOrApplicationSupport() {
        #expect(HouseConfigCache.defaultURL.lastPathComponent == "HouseConfig.json")
        _ = HouseConfigCache()
    }
}
