import Foundation
import Testing
@testable import HassCore

// MARK: - Fixtures for the vacuum lowering tests

/// The synthetic vacuum the lowering tests compile: the shared descriptor fixture plus a dock, a status consumable and an Auto-Clean switch.
enum VacuumLoweringFixture {
    typealias D = ServerUICompositionDocument

    static let vacuum = "vacuum.demo_robot"
    static let battery = "sensor.demo_battery"
    static let error = "sensor.demo_error"
    static let flag = "input_text.demo_flag"
    static let dock = "sensor.demo_dock"
    static let brush = "sensor.demo_brush"
    static let filter = "sensor.demo_filter"
    static let pause = "switch.demo_pause"
    static let skip = "switch.demo_room_skip"

    /// The descriptor as JSON, with a dock, two consumables and an Auto-Clean pause switch.
    static func descriptorJSON(dock hasDock: Bool = true) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUIVacuumDescriptorFixture.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        if hasDock {
            json["dockControls"] = ["cleanScript": "script.demo_dock_clean", "dryScript": "script.demo_dock_dry",
                                    "dockStatusEntityId": dock, "mopAttachmentEntityId": "binary_sensor.demo_mop"]
        }
        json["consumables"] = [["title": "Brush", "entityId": brush, "icon": "mdi:brush", "kind": "duration"],
                               ["title": "Filter", "entityId": filter, "icon": "mdi:air-filter", "kind": "status"]]
        json["autoCleanControl"] = ["title": "Demo", "entityId": pause, "kind": "pause"]
        return json
    }

    static var icon: [String: Any] { ["type": "sf-symbol", "name": "play", "rendering": "canonical", "unavailable": "reject"] }
    static var destination: [String: Any] {
        ["type": "push", "pageId": "page-echo", "arguments": [:], "origin": "sender", "duplicate": "reuse-nearest"]
    }

    /// The publication with one `vacuum-control` of `primitive`, compiled by the real compiler.
    static func publication(primitive: [String: Any], dock hasDock: Bool = true,
                            visibleWhen: [String: Any]? = nil, gridColumns: Int? = nil) throws -> ServerUICompositionPublication {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("ServerUICompositionFixture.json"))) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var sources = try #require(document["dataSources"] as? [[String: Any]])
        sources.append(["id": "source-robot", "kind": "model", "model": "vacuum@1", "inputs": try descriptorJSON(dock: hasDock)])
        document["dataSources"] = sources
        var pages = try #require(document["pages"] as? [[String: Any]])
        var nodes = try #require(pages[0]["components"] as? [[String: Any]])
        var node: [String: Any] = ["id": "robot-control", "title": "Configured Robot", "type": "vacuum-control",
                                   "layout": ["span": 1], "props": ["sourceId": "source-robot", "primitive": primitive]]
        if let visibleWhen { node["visibleWhen"] = visibleWhen; node["whenUnknown"] = "show" }
        if let gridColumns {
            node = ["id": "robot-grid", "title": "Robots", "type": "tile-grid", "layout": ["span": 1],
                    "props": ["minimum": "tile@1", "maxColumns": gridColumns, "spacing": ["type": "token", "name": "m"],
                              "equalRowHeights": false, "shortRow": "share", "fold": "page"], "children": [node]]
        }
        nodes.append(node)
        pages[0]["components"] = nodes
        document["pages"] = pages
        root["document"] = document
        let kind = primitive["kind"] as? String
        let extra = kind == "auto-clean" ? ["sh.vacuum-auto-clean@1"] : kind == "map" ? ["sh.vacuum-map@1"]
            : kind == "area-editor" ? ["sh.vacuum-map@1", "sh.vacuum-area@1"]
            : kind == "report" || kind == "outcomes" ? ["sh.vacuum-outcomes@1"] : ["sh.vacuum-controls@1"]
        var capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.vacuum@1"] + extra
        if visibleWhen != nil { capabilities.append("sh.visible-when@1") }
        root["capabilities"] = capabilities.sorted()
        return try ServerUICompositionPublication.decode(JSONSerialization.data(withJSONObject: root))
    }

    /// The control the compiler produced for `primitive`.
    static func component(_ primitive: [String: Any], dock hasDock: Bool = true) throws -> D.Component {
        let result = try publication(primitive: primitive, dock: hasDock)
        return try #require(result.document.pages[0].surface.components.last)
    }

    static func command(_ name: String) -> [String: Any] { ["kind": "command", "command": name, "icon": icon] }
}

// MARK: - Reading a table of states

/// Reads entity states from a table the way the app does: an unavailable or missing entity has no value.
struct VacuumStateTable: ServerUIReading {
    var states: [String: String]
    var viewer: ServerUIViewer? { nil }

    func read(sourceId: String, path: [String]) -> ServerUIReadResult {
        guard sourceId.hasPrefix("lowered.") else { return .unavailable }
        let entity = String(sourceId.dropFirst("lowered.".count))
        guard let state = states[entity], !EntityState.isUnavailable(state) else { return .unavailable }
        return path == ["state"] ? .value(.string(state)) : .unavailable
    }

    func readRaw(sourceId: String) -> ServerUIReadResult {
        guard sourceId.hasPrefix("lowered."), let state = states[String(sourceId.dropFirst("lowered.".count))] else { return .unavailable }
        return .value(.string(state))
    }

    func viewerPersonState() -> ServerUIReadResult { .unavailable }

    /// The text a string slot draws for `value`, or `nil` while it is loading or unavailable.
    func text(_ value: ServerUICompositionDocument.StringValue) -> String? {
        ServerUIStringResolver.resolve(value, read: { _ in .unavailable }, in: self).json.flatMap { if case .string(let text) = $0 { text } else { nil } }
    }
}
