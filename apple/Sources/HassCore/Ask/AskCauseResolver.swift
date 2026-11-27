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
            let read = interpret(row)
            return AskCauseResult(cause: read.cause, annotatorLines: lines, sensitivity: read.sensitivity)
        }
        if cfg.inheritGroupCause {
            for parent in entry.parentGroups {
                if let row = await row(for: parent, state: entry.state.state, at: changed, tolerance: cfg.groupInheritanceSeconds) {
                    let read = interpret(row)
                    if read.cause.isNamed { return AskCauseResult(cause: read.cause, annotatorLines: lines, sensitivity: read.sensitivity) }
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

    /// Reads one logbook row as a cause, with the class of the configured entity it names.
    ///
    /// Only a configured, askable entity is ever named or has its state spoken. An automation, script or entity the
    /// configuration does not name becomes ``AskCause/other(ago:)``.
    func interpret(_ row: AskLogbookRow) -> (cause: AskCause, sensitivity: AskSensitivity) {
        let ago = max(0, index.now.timeIntervalSince(row.when))
        func actor(_ domain: String, _ make: (String) -> AskCause) -> (cause: AskCause, sensitivity: AskSensitivity) {
            guard let e = configuredActor(domain: domain, row: row) else { return (.other(ago: ago), .everyday) }
            return (make(e.displayName), e.sensitivity)
        }
        func automation() -> (cause: AskCause, sensitivity: AskSensitivity) {
            actor("automation") { .automation(name: $0, message: row.contextMessage, ago: ago) }
        }
        func script() -> (cause: AskCause, sensitivity: AskSensitivity) { actor("script") { .script(name: $0, ago: ago) } }
        switch row.contextEventType {
        case "automation_triggered":
            return automation()
        case "script_started":
            return script()
        case "call_service":
            if let uid = row.contextUserId { return person(userId: uid, ago: ago) }
            if row.contextDomain == "automation", row.contextName != nil { return automation() }
            if row.contextDomain == "script", row.contextName != nil { return script() }
            return (.service(row.contextService ?? "service", ago: ago), .everyday)
        case "homekit_state_change":
            return (.person(name: "HomeKit", ago: ago), .everyday)
        default:
            if let cid = row.contextEntityId, cid != "" {
                guard let e = configuredEntry(cid) else { return (.other(ago: ago), .everyday) }
                return (.entity(name: e.displayName, state: row.contextState, ago: ago), e.sensitivity)
            }
            if row.contextName != nil, row.contextDomain == "automation" { return automation() }
            if row.hasNoContext { return (.physical(ago: ago), .everyday) }
            return (.service(row.contextService ?? "command", ago: ago), .everyday)
        }
    }

    /// The indexed entity for `id`, only when the configuration names it.
    private func configuredEntry(_ id: String) -> AskEntry? {
        guard let e = index.entry(id), e.askable else { return nil }
        return e
    }

    /// The configured automation or script a row names: by its entity id, else by its exact name.
    private func configuredActor(domain: String, row: AskLogbookRow) -> AskEntry? {
        if let cid = row.contextEntityId, let e = configuredEntry(cid), e.domain == domain { return e }
        guard let name = row.contextName else { return nil }
        let key = AskText.normalize(name)
        return index.entries.values.filter { $0.askable && $0.domain == domain && AskText.normalize($0.displayName) == key }.min { $0.id < $1.id }
    }

    private func person(userId: String, ago: TimeInterval) -> (cause: AskCause, sensitivity: AskSensitivity) {
        let match = index.entries.values.filter { $0.askable && $0.domain == "person" && $0.state.attributes["user_id"]?.string == userId }.min { $0.id < $1.id }
        guard let match else { return (.person(name: "a household member", ago: ago), .everyday) }
        return (.person(name: match.displayName, ago: ago), match.sensitivity)
    }

    // MARK: Annotators

    /// Lines from the annotators that explain `entry`.
    func annotatorLines(for entry: AskEntry) -> [String] {
        var out: [String] = []
        let never = index.configuration.sensitivity.neverAttributes
        for hit in index.annotators[entry.id] ?? [] where hit.rule.role == .why {
            var parts: [String] = []
            for key in hit.rule.attributes where key.split(separator: ".").allSatisfy({ !never.contains(String($0)) }) {
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
