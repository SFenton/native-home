import Foundation

// MARK: - What an operand or a condition may read from a model

/// What a document may read from a model source, in one place for every consumer: a slot `read`, a `read` operand and a condition
/// leaf all resolve a source and a path through here. A source that has no read fields is not readable.
enum ServerUIModelReads {
    typealias D = ServerUICompositionDocument

    /// The capability of the counts a `home-status@1` gives.
    static let homeStatusCounts = "home-status-counts"
    /// The count fields of `home-status@1`, which need `sh.home-status-counts@1`.
    static let homeStatusCountFields = ["count", "total", "unavailableCount"]

    /// What a read of a model found.
    enum Outcome: Equatable {
        /// The source has no read fields: it cannot be read by an operand or a condition.
        case notReadable
        /// A problem with the read: the code and the pointer suffix relative to the reference.
        case issue(ServerUICompositionError.Code, suffix: String)
        /// The read is sound and needs this capability (without `sh.` and `@1`).
        case needs(String)
    }

    /// The read fields of a model source and what each reads as; `nil` when the model is not read by name.
    static func fields(_ source: D.Source) -> [String: D.ScalarKind]? {
        switch source {
        case .powerToggle: ["stateText": .string, "isOn": .boolean, "phase": .string, "isError": .boolean]
        case .inventorySummary, .todoCounts: ["stateText": .string, "phase": .string]
        case .homeStatus:
            ["stateText": .string, "phase": .string, "state": .string, "isActive": .boolean,
             "count": .number, "total": .number, "unavailableCount": .number]
        case .climate(_, let configuration):
            configuration.tracking == nil ? ["phase": .string] : [
                "phase": .string, "selectedCount": .number, "criticalCount": .number, "occupiedOnlyCount": .number,
                "totalRooms": .number, "selectedEnabled": .boolean, "criticalEnabled": .boolean]
        case .sprinklerState:
            ["status": .string, "mode": .string, "phase": .string, "batteryPercent": .number, "batteryLow": .boolean,
             "fault": .boolean, "hubConnected": .boolean, "watering": .boolean, "available": .boolean, "rainDelay": .boolean,
             "smartWatering": .boolean]
        case .vacuum: ["stateText": .string, "batteryText": .string, "phase": .string]
        case .householdAwayStatus: ["mode": .string, "state": .string, "phase": .string]
        case .camera: ["stateText": .string, "phase": .string]
        case .alarmMode, .securityDoor: ["phase": .string]
        case .appState(_, let topic): ServerUIAppState.fields(topic)
        default: nil
        }
    }

    /// Checks a read of a model source by an operand or a condition leaf. `kind` is what a `read` operand asked for; a condition leaf
    /// passes none. `nil` when the read is sound and needs nothing beyond the source's own capability.
    static func check(_ source: D.Source, path: [String], kind: D.ScalarKind?) -> Outcome? {
        let at = kind == nil ? "/path" : "/from/path"
        if case .pipeline(_, let flow) = source {
            guard let found = ServerUIFlowCompiler.checkRead(flow, path: path, as: kind ?? .string) else { return nil }
            return .issue(found.code, suffix: found.suffix == "/as" ? "/as" : at)
        }
        guard let fields = fields(source) else { return .notReadable }
        guard path.count == 1, let found = fields[path[0]] else { return .issue(.invalidReference, suffix: at) }
        if let kind, found != kind { return .issue(.bindingType, suffix: "/as") }
        if case .homeStatus = source, homeStatusCountFields.contains(path[0]) { return .needs(homeStatusCounts) }
        return nil
    }
}
