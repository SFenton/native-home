import Foundation

// MARK: - Facts that needed a read

extension AskComposer {
    // MARK: Why

    /// The "why" sentence for one entity, from the cause the logbook and annotators gave.
    func why(_ e: AskEntry, facts: AskFacts) -> String {
        if e.isUnavailable { return unavailable(e) }
        let result = facts.causes[e.id] ?? AskCauseResult(cause: .none, annotatorLines: [])
        let word = AskStateWords.word(for: e)
        func ago(_ s: TimeInterval) -> String { AskDuration.phrase(seconds: s) + " ago" }
        var base: String
        switch result.cause {
        case .automation(let name, let message, let s):
            base = "\(e.displayName) became \(word) \(ago(s)), changed by the automation \"\(name)\"\(message.map { " (\($0))" } ?? "")."
        case .script(let name, let s):
            base = "\(e.displayName) became \(word) \(ago(s)), changed by the script \"\(name)\"."
        case .person(let name, let s):
            base = "\(name) changed \(e.displayName) to \(word) \(ago(s))."
        case .entity(let name, let state, let s):
            base = "\(name) changed\(state.map { " to \($0)" } ?? "") \(ago(s)), which set \(e.displayName) to \(word)."
        case .other(let s):
            base = "\(e.displayName) became \(word) \(ago(s)), set by \(AskCause.otherWording)."
        case .service(let service, let s):
            base = "\(e.displayName) became \(word) \(ago(s)) from a \(service) command, but who sent it is not recorded."
        case .physical(let s):
            base = "\(e.displayName) became \(word) \(ago(s)). No automation or person is recorded, so it was a physical or manual change at the device."
        case .restart:
            base = "\(e.displayName) was only re-reported as \(word) when Home Assistant restarted, so why it changed is not recorded."
        case .none:
            base = "There is no record of why \(e.displayName) is \(word); the cause is not recorded."
        }
        if !result.annotatorLines.isEmpty { base += " Its controller reports " + result.annotatorLines.joined(separator: "; ") + "." }
        return base
    }

    // MARK: How long

    func howLong(_ entries: [AskEntry], facts: AskFacts) -> String {
        entries.prefix(4).map { e -> String in
            if e.isUnavailable { return unavailable(e) }
            if let at = e.stampedAt { return "\(e.displayName) was \(AskDuration.phrase(seconds: index.now.timeIntervalSince(at))) ago." }
            let d = facts.durations[e.id] ?? AskDuration(seconds: index.now.timeIntervalSince(e.state.lastChanged), since: e.state.lastChanged, atLeast: false, source: .lastChanged)
            return "\(e.displayName) has been \(AskStateWords.word(for: e)) for \(d.spoken)."
        }.joined(separator: " ")
    }

    // MARK: Last time

    func lastTime(_ e: AskEntry, intent i: AskIntent, facts: AskFacts) -> String {
        if e.isUnavailable { return unavailable(e) }
        if let at = e.stampedAt { return "\(e.displayName) was \(AskDuration.phrase(seconds: index.now.timeIntervalSince(at))) ago." }
        let p = i.predicate ?? AskStateWords.defaultPredicate(for: e.kind)
        let label = AskStateWords.label(p)
        switch facts.lastTimes[e.id] {
        case .ran(let s)?: return "\(e.displayName) last ran \(AskDuration.phrase(seconds: s)) ago."
        case .neverRan?: return "\(e.displayName) has never run."
        case .current(let d)?: return "\(e.displayName) last became \(label) \(d.spoken) ago, and it still is."
        case .past(let s, _)?: return "\(e.displayName) last became \(label) \(AskDuration.phrase(seconds: s)) ago."
        case .notRecorded(let days)?: return "There is no record of \(e.displayName) being \(label) in the last \(Int(days)) days."
        case nil: return "There is no record of when \(e.displayName) was last \(label)."
        }
    }

    // MARK: Comparison

    func comparison(_ r: AskResolution, facts: AskFacts) -> String {
        let i = r.intent
        let aggregator = AskAggregator(index: index)
        guard let kind = i.comparison else { return "" }
        if kind == .longest {
            let ids = r.parts.flatMap(\.entityIds)
            let on = ids.compactMap(index.entry).filter { !$0.isUnavailable && AskStateWords.matches($0, .on) == true && !$0.excludedFromAggregates }
            let ranked = on.map { e -> (AskEntry, AskDuration) in
                (e, facts.durations[e.id] ?? AskDuration(seconds: index.now.timeIntervalSince(e.state.lastChanged), since: e.state.lastChanged, atLeast: false, source: .lastChanged))
            }.sorted { $0.1.seconds > $1.1.seconds }
            guard let top = ranked.first else { return "None of them are on right now." }
            return "\(top.0.displayName) has been on the longest, for \(top.1.spoken)."
        }
        let valueKind = i.valueKind ?? .temperature
        let unit = valueKind == .humidity ? "%" : "°F"
        func words(_ k: AskComparisonKind) -> (hi: String, lo: String) {
            switch k {
            case .humid, .dry: ("more humid", "drier")
            default: ("warmer", "colder")
            }
        }
        let higherWins = kind == .warmer || kind == .humid || kind == .difference
        let w = words(kind)
        // Inside against outside.
        if i.inOut, let weather = r.parts.flatMap(\.entityIds).compactMap(index.entry).first(where: { $0.domain == "weather" }),
           let outside = weather.state.attributes["temperature"]?.finiteNumber,
           let inside = aggregator.mean(aggregator.members(kind: .temperature, scope: .house).filter { !$0.isUnavailable })
        {
            let warmerInside = inside > outside
            let sentence = warmerInside ? "It's warmer inside than outside" : "It's colder inside than outside"
            return "\(sentence): \(AskLineFormatter.number(inside))\(unit) inside against \(AskLineFormatter.number(outside))\(unit) outside."
        }
        // Readings per part.
        var readings: [(title: String, value: Double)] = []
        for p in r.parts {
            let members = p.entityIds.compactMap(index.entry).filter { !$0.isUnavailable }
            if let v = aggregator.mean(members) { readings.append((p.scopeTitle ?? members.first?.displayName ?? p.phrase, v)) }
        }
        // A superlative over every room.
        if readings.count == 1 || r.parts.count == 1, (r.parts.first?.scope).map({ if case .house = $0 { true } else { false } }) ?? true, r.parts.first?.entityKind == valueKind {
            let ranking = aggregator.roomReadings(kind: valueKind).compactMap { pair -> (String, Double)? in
                guard let title = index.rooms[pair.roomKey]?.title else { return nil }
                return (title, pair.value)
            }
            guard let best = (higherWins ? ranking.max { $0.1 < $1.1 } : ranking.min { $0.1 < $1.1 }) else { return "I can't compare the rooms right now." }
            let superlative: String
            switch kind {
            case .warmer: superlative = "warmest"
            case .colder: superlative = "coldest"
            case .humid: superlative = "most humid"
            default: superlative = "driest"
            }
            return "The \(best.0) is the \(superlative) room, at \(AskLineFormatter.number(best.1))\(unit)."
        }
        guard readings.count >= 2 else { return "I can't compare those right now." }
        let a = readings[0], b = readings[1]
        if kind == .difference {
            let d = abs(a.value - b.value)
            let hi = a.value >= b.value ? a : b, lo = a.value >= b.value ? b : a
            return "The \(hi.title) is \(AskLineFormatter.number(d))\(unit) \(words(.warmer).hi) than the \(lo.title)."
        }
        let aWins = higherWins ? a.value >= b.value : a.value <= b.value
        let winner = aWins ? a : b, loser = aWins ? b : a
        let comparative = higherWins ? w.hi : w.lo
        let tail = "\(AskLineFormatter.number(winner.value))\(unit) against \(AskLineFormatter.number(loser.value))\(unit)"
        if i.yesNo, !i.wantsWhich {
            // "Is A hotter than B": answer for A.
            return aWins ? "Yes, the \(winner.title) is \(comparative) than the \(loser.title): \(tail)." : "No, the \(winner.title) is \(comparative) than the \(loser.title): \(tail)."
        }
        return "The \(winner.title) is \(comparative) than the \(loser.title): \(tail)."
    }
}
