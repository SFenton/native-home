import Foundation

// MARK: - Cause resolver

/// Finds why an entity is in its state: integration annotators first, then one logbook lookup.
///
/// The logbook names a cause for very few state rows, so an annotator's attributes (a presence-lighting reason, a thermostat's
/// action reason) are read first and kept as lines. The logbook is then asked once for a window around the change; a named
/// automation, script or person wins as *the* cause, and an actor-less row or a missing row leaves the annotator line as the
/// answer. A group member with no row of its own may take its group's row from the same instant. The restart reset is
/// never read as a change: there is no row to find.
public struct AskCauseResolver: Sendable {
    /// The index the resolver reads.
    public let index: AskableIndex
    /// Where the logbook comes from.
    public let dataSource: AskDataSource

    /// Creates a resolver.
    public init(index: AskableIndex, dataSource: AskDataSource) {
        self.index = index
        self.dataSource = dataSource
    }

    /// The cause for `entry`.
    public func resolve(_ entry: AskEntry) async -> AskCauseResult {
        let lines = annotatorLines(for: entry)
        let cfg = index.configuration
        let changed = entry.state.lastChanged
        guard changed > .distantPast else { return AskCauseResult(cause: .none, annotatorLines: lines) }
        if AskRestartGuard.isRestartReset(entry.state, restart: index.restartTime, configuration: cfg) {
            return AskCauseResult(cause: .restart, annotatorLines: lines)
        }
        if let row = await row(for: entry.id, state: entry.state.state, at: changed) {
            return AskCauseResult(cause: interpret(row), annotatorLines: lines)
        }
        if cfg.inheritGroupCause {
            for parent in entry.parentGroups {
                if let row = await row(for: parent, state: entry.state.state, at: changed, tolerance: cfg.groupInheritanceSeconds) {
                    let cause = interpret(row)
                    if cause.isNamed { return AskCauseResult(cause: cause, annotatorLines: lines) }
                }
            }
        }
        return AskCauseResult(cause: .none, annotatorLines: lines)
    }

    // MARK: Logbook

    private func row(for id: String, state: String, at changed: Date, tolerance: Double? = nil) async -> AskLogbookRow? {
        let window = tolerance ?? index.configuration.causeWindowSeconds
        let source = dataSource
        let rows = try? await AskDeadline.run(seconds: index.configuration.callDeadlineSeconds) {
            try await source.logbook(entityId: id, from: changed.addingTimeInterval(-window), to: changed.addingTimeInterval(window))
        }
        guard let rows else { return nil }
        let matching = rows.filter { $0.state == nil || $0.state == state }
        return matching.min { abs($0.when.timeIntervalSince(changed)) < abs($1.when.timeIntervalSince(changed)) }
    }

    /// Reads one logbook row as a cause.
    func interpret(_ row: AskLogbookRow) -> AskCause {
        let ago = max(0, index.now.timeIntervalSince(row.when))
        switch row.contextEventType {
        case "automation_triggered":
            return .automation(name: row.contextName ?? "an automation", message: row.contextMessage, ago: ago)
        case "script_started":
            return .script(name: row.contextName ?? "a script", ago: ago)
        case "call_service":
            if let uid = row.contextUserId { return .person(name: personName(uid), ago: ago) }
            if row.contextDomain == "automation", let name = row.contextName { return .automation(name: name, message: row.contextMessage, ago: ago) }
            if row.contextDomain == "script", let name = row.contextName { return .script(name: name, ago: ago) }
            return .service(row.contextService ?? "service", ago: ago)
        case "homekit_state_change":
            return .person(name: "HomeKit", ago: ago)
        default:
            if let cid = row.contextEntityId, cid != "" {
                let name = index.entry(cid)?.displayName ?? row.contextName ?? cid
                return .entity(name: name, state: row.contextState, ago: ago)
            }
            if let name = row.contextName, row.contextDomain == "automation" { return .automation(name: name, message: row.contextMessage, ago: ago) }
            if row.hasNoContext { return .physical(ago: ago) }
            return .service(row.contextService ?? "command", ago: ago)
        }
    }

    private func personName(_ userId: String) -> String {
        for e in index.entries.values where e.domain == "person" && e.state.attributes["user_id"]?.string == userId { return e.displayName }
        return "a household member"
    }

    // MARK: Annotators

    /// Lines from the annotators that explain `entry`.
    func annotatorLines(for entry: AskEntry) -> [String] {
        var out: [String] = []
        for hit in index.annotators[entry.id] ?? [] where hit.rule.role == .why {
            var parts: [String] = []
            for key in hit.rule.attributes {
                guard let value = Self.read(key, in: hit.state.attributes) else { continue }
                let phrase = hit.rule.valuePhrases[key]?[value] ?? value
                if ["", "none", "null", "false", "unknown"].contains(value.lowercased()) { continue }
                parts.append("\(key.replacingOccurrences(of: "_", with: " ")): \(phrase)")
            }
            if !parts.isEmpty { out.append(parts.joined(separator: "; ")) }
        }
        return out
    }

    /// Reads an attribute by dotted path as text.
    static func read(_ path: String, in attributes: [String: JSONValue]) -> String? {
        var current: JSONValue? = .object(attributes)
        for part in path.split(separator: ".") { current = current?[String(part)] }
        switch current {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
}
