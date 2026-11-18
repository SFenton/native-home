import Foundation

// MARK: - Entity reads beyond the scalar

/// The evaluation of the operands that read an entity beyond a typed scalar: `raw-state` (`sh.raw-state@1`), `last-changed` (`sh.entity-time@1`) and
/// `list-count` and `list-includes` (`sh.list-read@1`). A flow reads none of them: the gap is `null` there.
extension ServerUIOperand {
    /// Evaluates a `rawState`, `lastChanged`, `listCount` or `listIncludes`. Total: nothing throws.
    func evaluateEntityRead(_ environment: some ServerUIReading) -> ServerUIReadResult {
        if environment.isFlow { return .unavailable }
        switch self {
        case .rawState(let sourceId):
            let result = environment.readRaw(sourceId: sourceId)
            guard case .value(let value) = result else { return result }
            if case .string = value { return result }
            return .unavailable
        case .lastChanged(let sourceId):
            let result = environment.readChanged(sourceId: sourceId)
            guard case .value(let value) = result else { return result }
            if case .string = value { return result }
            return .unavailable
        case .listCount(let sourceId, let path):
            let list = environment.read(sourceId: sourceId, path: path)
            guard case .value(let value) = list else { return list }
            guard case .array(let items) = value else { return .unavailable }
            return .value(.number(Double(items.count)))
        case .listIncludes(let sourceId, let path, let wanted):
            let list = environment.read(sourceId: sourceId, path: path)
            let needle = wanted.evaluate(environment)
            if let blocked = ServerUIReadResult.combine([list, needle]) { return blocked }
            guard case .array(let items)? = list.json, let needle = needle.json, Self.isScalar(needle) else { return .unavailable }
            return .value(.bool(items.contains { Self.isScalar($0) && Self.matches($0, needle) }))
        default: return .unavailable
        }
    }

    private static func isScalar(_ value: JSONValue) -> Bool {
        switch value {
        case .string, .number, .bool: true
        case .null, .array, .object: false
        }
    }
}

// MARK: - The raw state of an entity

extension ServerUIReadResult {
    /// What `raw-state` reads from an entity box: any state text is a value, `unknown` and `unavailable` included; no entity is `unavailable`;
    /// states not loaded yet is `loading`.
    public static func rawState(of entity: EntityState?, statesLoaded: Bool) -> ServerUIReadResult {
        guard statesLoaded else { return .loading }
        guard let entity else { return .unavailable }
        return .value(.string(entity.state))
    }

    /// What `last-changed` reads from an entity box (`sh.entity-time@1`): the moment the state last changed, as `YYYY-MM-DDTHH:MM:SS.sssZ`.
    /// States not loaded yet is `loading`; no entity, or a moment the box never learned (`.distantPast`), is `unavailable`.
    public static func lastChanged(of entity: EntityState?, statesLoaded: Bool) -> ServerUIReadResult {
        guard statesLoaded else { return .loading }
        guard let entity, entity.lastChanged > .distantPast else { return .unavailable }
        return .value(.string(ServerUIDates.instantText(entity.lastChanged)))
    }
}
