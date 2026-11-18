import Foundation
import HassCore

// The golden probe: runs the frozen old HassCore's state-to-text and glyph functions over the generic state space
// (tools/state_space/generate.py) and prints one JSON object per row. Built only in a temp checkout of the pinned
// commit by tools/state_golden/generate.py; never part of the app or the tests.

struct Row: Decodable {
    var id: String
    var kind: String
    var entity_id: String
    var state: String?
    var attributes: [String: JSONValue]
    var options: [Option]?
    struct Option: Decodable { var value: String; var label: String }
}

struct Space: Decodable {
    var rows: [Row]
}

/// The registry facts the probe needs per kind, passed in a second file so the probe holds no kind list of its own.
struct Registry: Decodable {
    struct Kind: Decodable { var id: String; var evaluator: String; var room_kind: String?; var old: String? }
    var kinds: [Kind]
}

typealias Fields = [String: Any]

func spec(_ spec: TileActionSpec) -> Fields {
    ["verb": spec.verb, "symbol": spec.symbol, "isOn": spec.isOn as Any? ?? NSNull(), "phase": "\(spec.phase)",
     "confirms": spec.confirmation != nil]
}

func provider(_ name: String, entityId: String) -> (any TileActionProviding)? {
    switch name {
    case "LockActions": LockActions(entityId: entityId)
    case "CoverActions": CoverActions(entityId: entityId)
    case "AlarmModeActions": AlarmModeActions(entityId: entityId)
    case "VacuumActions": VacuumActions(entityId: entityId)
    default: nil
    }
}

func evaluate(_ row: Row, kind: Registry.Kind) -> Fields? {
    let entity = row.state.map { EntityState(entityId: row.entity_id, state: $0, attributes: row.attributes) }
    switch kind.evaluator {
    case "room-text":
        var out: Fields = ["text": RoomFormat.withUnit(entity), "compact": RoomFormat.compact(entity), "active": RoomFormat.isActive(entity)]
        if kind.room_kind == "occupancy" { out["occupancy"] = RoomFormat.occupancy(entity); out["occupied"] = RoomFormat.isOccupied(entity) }
        if kind.room_kind == "contact" {
            out["contact"] = RoomFormat.contact(entity); out["open"] = RoomFormat.isOpen(entity)
            out["tileSubtitle"] = RoomFormat.contactTileSubtitle(entity)
        }
        return out
    case "remote-device":
        // The old device rule: `device.stateLabels[shown] ?? MediaRemoteState.format(shown)`; a missing entity reads as unavailable.
        let shown = row.state ?? "unavailable"
        let labels = Dictionary(uniqueKeysWithValues: (row.options ?? []).map { ($0.value, $0.label) })
        return ["line": labels[shown] ?? MediaRemoteState.format(shown), "unavailable": EntityState.isUnavailable(shown)]
    case "style":
        guard let name = kind.old, let provider = provider(name, entityId: row.entity_id) else { return nil }
        var out: Fields = ["candidates": provider.stateTextCandidates]
        let specs = provider.actions(for: entity)
        if name == "VacuumActions" { out["actions"] = specs.map { ["id": $0.id, "verb": $0.verb, "phase": "\($0.phase)"] } }
        else if let first = specs.first { out.merge(spec(first)) { $1 } }
        return out
    default:
        return nil
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: StateGoldenProbe SPACE.json KINDS.json OUT.json\n".utf8))
    exit(2)
}
do {
    let space = try JSONDecoder().decode(Space.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    let registry = try JSONDecoder().decode(Registry.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
    let kinds = Dictionary(uniqueKeysWithValues: registry.kinds.map { ($0.id, $0) })
    var lines: [String] = []
    for row in space.rows {
        guard let kind = kinds[row.kind], let fields = evaluate(row, kind: kind) else { continue }
        let key = String(data: try JSONSerialization.data(withJSONObject: row.id, options: .fragmentsAllowed), encoding: .utf8)!
        let body = String(data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
        lines.append("\(key): \(body)")
    }
    try ("{\n" + lines.joined(separator: ",\n") + "\n}\n").write(toFile: arguments[3], atomically: true, encoding: .utf8)
    print("probe: \(lines.count) rows")
} catch {
    FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
    exit(1)
}
