#if DEBUG
import Foundation
import HassCore

extension DemoHouse {
    /// The export format version written to `build/ha/demo-house.json`; `tools/test_ha/gen_demo_package.py` refuses another.
    public static let exportVersion = 1

    /// The demo house as the test Home Assistant instance serves it: the house-config document plus one resting state per
    /// entity id the document names, so `tools/test_ha/gen_demo_package.py` builds the entities from the same source the app
    /// tests read (one truth for the ids and their resting values).
    ///
    /// Keys are sorted so the file is stable between runs. Only demo values appear: the export is ``config`` and ``states``.
    /// - Returns: JSON `{"version", "document", "entities": [{"entity_id", "state", "attributes"}]}`.
    public static func exportJSON() throws -> Data {
        let document = try JSONSerialization.jsonObject(with: config.encoded())
        let encoder = JSONEncoder()
        let entities: [Any] = try states.map { entity in
            let attributes = try JSONSerialization.jsonObject(with: encoder.encode(entity.attributes))
            return ["entity_id": entity.entityId, "state": entity.state, "attributes": attributes] as [String: Any]
        }
        let root: [String: Any] = ["version": exportVersion, "document": document, "entities": entities]
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }

    /// Writes ``exportJSON()`` to `url`, creating the folder. Called by the DEBUG-only `DemoHouseExportTests` when
    /// `DEMO_HOUSE_EXPORT` names a path (`tools/test_ha/export_demo_house.sh` sets it).
    public static func writeExport(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try exportJSON().write(to: url, options: .atomic)
    }
}
#endif
