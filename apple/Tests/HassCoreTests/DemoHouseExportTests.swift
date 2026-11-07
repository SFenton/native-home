import Foundation
@testable import HassCore
import Testing

/// The DEBUG exporter behind `build/ha/demo-house.json` (the test Home Assistant instance's source).
@MainActor
struct DemoHouseExportTests {
    private func root() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: DemoHouse.exportJSON()) as? [String: Any])
    }

    @Test func exportCarriesTheDocumentAndOneStatePerId() throws {
        let root = try root()
        #expect(root["version"] as? Int == DemoHouse.exportVersion)
        let document = try #require(root["document"] as? [String: Any])
        #expect(document["schema"] as? Int == HouseConfig.supportedSchema)
        let entities = try #require(root["entities"] as? [[String: Any]])
        #expect(entities.compactMap { $0["entity_id"] as? String } == DemoHouse.entityIds)
        for entity in entities {
            #expect(entity["state"] is String)
            #expect(entity["attributes"] is [String: Any])
        }
    }

    @Test func documentRoundTripsThroughTheServerPath() throws {
        let document = try #require(root()["document"])
        let data = try JSONSerialization.data(withJSONObject: document)
        #expect(try HouseConfig.decode(data) == DemoHouse.config)
    }

    @Test func exportIsStableAndOnlyDemoIds() throws {
        #expect(try DemoHouse.exportJSON() == DemoHouse.exportJSON())
        let entities = try #require(root()["entities"] as? [[String: Any]])
        for entity in entities {
            let id = try #require(entity["entity_id"] as? String)
            #expect(id.range(of: #"^[a-z_]+\.demo_[a-z0-9_]+$"#, options: .regularExpression) != nil, "\(id)")
        }
    }

    @Test func writesTheFileWhenAsked() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-export-\(UUID().uuidString)/demo-house.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DemoHouse.writeExport(to: url)
        #expect(try Data(contentsOf: url) == DemoHouse.exportJSON())
    }

    /// Not a check: `tools/test_ha/export_demo_house.sh` sets `DEMO_HOUSE_EXPORT` to write the real file.
    @Test func exportsToThePathInTheEnvironment() throws {
        guard let path = ProcessInfo.processInfo.environment["DEMO_HOUSE_EXPORT"], !path.isEmpty else { return }
        try DemoHouse.writeExport(to: URL(fileURLWithPath: path))
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
