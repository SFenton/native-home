import Foundation

// MARK: - Name matching

extension AskResolver {
    /// One entity that can answer to the question's words.
    struct Candidate {
        let entry: AskEntry
        /// Name words the question did not say (0 means the whole name is inside the question).
        let extra: Int
        /// Question words the name covers.
        let overlap: Int
        /// Ordinary words of the question (`left`) that the name also contains.
        var softHits = 0
        /// The ranking number: unsaid name words less the ordinary words the name matched. Lower is closer.
        var rank: Int { extra - softHits }
    }

    /// The words an entity answers to besides its name: its kind, its domain and its device class.
    func kindWords(_ e: AskEntry) -> Set<String> {
        var s = Set(e.kind.nouns.map(AskText.stem))
        switch e.domain {
        case "sensor", "binary_sensor": s.insert("sensor")
        case "switch": s.insert("switch")
        case "cover": s.insert("cover")
        case "media_player": s.formUnion(["tv", "speaker", "player"])
        case "climate": s.insert("thermostat")
        case "weather": s.formUnion(["weather", "outside"])
        case "valve": s.formUnion(["sprinkler", "valve"])
        default: break
        }
        if let dc = e.deviceClass { s.formUnion(AskText.words(dc.replacingOccurrences(of: "_", with: " "))) }
        return s
    }

    /// Entities whose name, room and kind explain every word in `tokens`, within `scopes` when given.
    ///
    /// `soft` holds ordinary words the question said that are also name words (`left`, `open`): they are not needed to match
    /// a name, but a name that contains one is closer to what was said, so it ranks ahead of a sibling that does not.
    func candidates(tokens: [String], scopes: [ScopePhrase], soft: Set<String> = []) -> [Candidate] {
        let q = Set(tokens)
        var out: [Candidate] = []
        let scopeWords = scopes.compactMap { s -> (AskScope, Set<String>)? in
            guard case .room(let key) = s.scope, let room = index.rooms[key] else { return (s.scope, Set(s.words)) }
            return (s.scope, Set(AskText.words(room.title, synonyms: index.configuration.synonyms)))
        }
        for e in index.entries.values where e.askable {
            if !scopeWords.isEmpty {
                let inScope = scopeWords.contains { scope, words in
                    index.contains(scope, e) || e.nameVariants.contains { $0.isSuperset(of: words) }
                }
                if !inScope { continue }
            }
            let kw = kindWords(e)
            var best: Candidate?
            for v in e.nameVariants {
                let covered = v.union(e.roomWords).union(kw)
                guard q.isSubset(of: covered) else { continue }
                let extra = v.subtracting(e.roomWords).subtracting(q).subtracting(kw).subtracting(soft).count
                let overlap = q.intersection(v).count
                if best == nil || extra < best!.extra || (extra == best!.extra && overlap > best!.overlap) {
                    best = Candidate(entry: e, extra: extra, overlap: overlap, softHits: v.intersection(soft).subtracting(q).count)
                }
            }
            if let best { out.append(best) }
        }
        return out.sorted { $0.entry.id < $1.entry.id }
    }

    /// The domains a yes/no state points at.
    static let predicateDomains: [AskPredicate: Set<String>] = [
        .home: ["person"], .away: ["person"], .locked: ["lock"], .unlocked: ["lock"], .playing: ["media_player"],
        .notPlaying: ["media_player"], .recording: ["camera"], .occupied: ["binary_sensor"], .clear: ["binary_sensor"],
        .detected: ["binary_sensor"], .open: ["cover", "binary_sensor", "valve", "lock"], .closed: ["cover", "binary_sensor", "valve", "lock"],
        .enabled: ["automation"], .disabled: ["automation"],
    ]

    /// Domains that hold helpers and automations about a device rather than the device itself.
    static let plumbingDomains: Set<String> = ["automation", "script", "scene", "input_boolean", "timer", "schedule", "input_select", "calendar"]

    /// Resolves the words of a chunk against entity names, or nil when nothing explains them.
    func resolveName(reading: ChunkReading, tokens: [String], intent: AskIntent, requireExact: Bool = false) -> AskPart? {
        // Words that are all ordinary English ("humidity level") name nothing.
        guard !tokens.isEmpty else { return nil }
        var cands = candidates(tokens: tokens, scopes: reading.scopes, soft: reading.soft)
        var usedScopes = reading.scopes
        if cands.isEmpty, !reading.scopes.isEmpty {
            // The room words may be part of the name rather than a place: retry with them as name words.
            let withScope = tokens + reading.scopes.flatMap { s -> [String] in
                if case .room(let key) = s.scope, let room = index.rooms[key] { return AskText.words(room.title, synonyms: index.configuration.synonyms) }
                return s.words
            }
            cands = candidates(tokens: withScope, scopes: [], soft: reading.soft)
            usedScopes = []
        }
        guard !cands.isEmpty else { return nil }
        // A group entity (a room's light group) stands for its members: "the theater light" is one of them, not the group.
        if !reading.plural, intent.comparison == nil, cands.contains(where: { !$0.entry.isGroup }) { cands = cands.filter { !$0.entry.isGroup } }
        let exact = cands.filter { $0.extra == 0 }
        let cfg = index.configuration
        // A lock, garage, alarm or presence match is not settled by being the only exact name: another candidate close behind
        // it keeps the whole field in play until the margin below decides.
        let guarded = cfg.securityGuard && exact.count == 1 && cfg.guardedKinds.contains(exact[0].entry.kind) && cands.count > 1
        var pool = exact.isEmpty || guarded ? cands : exact
        // A state the question asks about points at the kinds of entity that have it ("locked" is a lock).
        if let p = intent.predicate, let domains = Self.predicateDomains[p] {
            let filtered = pool.filter { domains.contains($0.entry.domain) }
            if !filtered.isEmpty { pool = filtered }
        }
        // Plumbing that mentions a device ("dishwasher clean notification") is not the device unless the question asks for it.
        let asksPlumbing = tokens.contains { ["automation", "script", "scene", "routine", "helper", "toggle", "enable", "notification"].contains($0) }
            || intent.predicate == .enabled || intent.predicate == .disabled
        if !asksPlumbing {
            let primary = pool.filter { !Self.plumbingDomains.contains($0.entry.domain) }
            if !primary.isEmpty, primary.count < pool.count { pool = primary }
        }
        // Sensors that sit beside a device (a dishwasher's door, a faucet's fault) are not the device when it is asked about by state.
        let sensorWords: Set<String> = ["sensor", "motion", "occupancy", "presence", "contact", "humidity", "temperature", "battery", "level", "pm25", "aqi", "power", "status", "quality", "illuminance", "detection"]
        if intent.valueKind == nil, !intent.wantsValue, !tokens.contains(where: sensorWords.contains) {
            let devices = pool.filter { $0.entry.domain != "sensor" && $0.entry.domain != "binary_sensor" }
            // ... but only when the device is at least as close a name as the sensor beside it.
            if let d = devices.map(\.rank).min(), let all = pool.map(\.rank).min(), d <= all, devices.count < pool.count, intent.predicate != .open, intent.predicate != .closed { pool = devices }
        }
        if intent.predicate == .open || intent.predicate == .closed, !tokens.contains("lock") {
            // "Is the front door shut" reads the door, not the lock on it.
            let doors = pool.filter { $0.entry.domain != "lock" }
            if !doors.isEmpty { pool = doors }
        }
        if intent.predicate == .open || intent.predicate == .closed {
            // A door or window question reads the contact sensor, not a presence sensor that shares its room.
            let contact: Set<String> = ["door", "window", "garage_door", "opening"]
            let contacts = pool.filter { $0.entry.domain != "binary_sensor" || contact.contains($0.entry.deviceClass ?? "") }
            if !contacts.isEmpty { pool = contacts }
        }
        // Several candidates that differ in how much of the name the question left unsaid: one clearly closest name is the one
        // meant. "Clearly" is a margin in unsaid words; a lock, garage, alarm or presence answer needs a wider one, and below it
        // the answer is "which one?" with the candidates rather than a guess.
        var guardedPick: String?
        var pluralSet = false
        if !reading.plural, intent.comparison == nil, pool.count > 1 {
            // The document's own list for a kind (its garage doors) is what the kind means: a sensor of that kind beside it is not.
            for (kind, list) in index.deviceLists {
                let listed = Set(list)
                if pool.contains(where: { $0.entry.kind == kind && listed.contains($0.entry.id) }) {
                    pool = pool.filter { $0.entry.kind != kind || listed.contains($0.entry.id) }
                }
            }
            // "Why is it on", "how long has it been on", "when did it last": the question says the state, so the candidates in it.
            if intent.wantsWhy || intent.wantsHowLong || intent.wantsLast, let p = intent.predicate, pool.count > 1,
               !pool.contains(where: { cfg.guardedKinds.contains($0.entry.kind) })
            {
                let inState = pool.filter { AskStateWords.matches($0.entry, p) == true }
                if inState.count == 1 { pool = inState }
            }
            let ranked = pool.sorted { ($0.rank, $0.entry.id) < ($1.rank, $1.entry.id) }
            let best = ranked[0], next = ranked.count > 1 ? ranked[1] : ranked[0]
            let isGuarded = cfg.securityGuard && cfg.guardedKinds.contains(best.entry.kind)
            let margin = max(cfg.nameMargin, isGuarded ? cfg.securityNameMargin : cfg.nameMargin)
            if reading.pluralName, next.rank == best.rank {
                pluralSet = true
            } else if next.rank - best.rank >= margin {
                pool = [best]
            } else if next.rank - best.rank >= cfg.nameMargin, isGuarded {
                guardedPick = best.entry.id
            }
        }
        if requireExact, pool.count != 1 || pool[0].extra != 0 { return nil }
        if !reading.plural, intent.comparison == nil {
            let leaves = pool.filter { !$0.entry.isGroup }
            if !leaves.isEmpty, leaves.count < pool.count { pool = leaves }
        }
        // Duplicate bulbs: the same spoken name in one room is one answer; prefer the one the document names.
        pool = collapseDuplicates(pool)
        // One thing reported twice (a door's cover and its contact sensor, an overlay "same as" set) is one answer.
        let kept = Set(aggregator.collapsingSameThing(pool.map(\.entry)).map(\.id))
        if kept.count < pool.count { pool = pool.filter { kept.contains($0.entry.id) } }
        let ids = pool.map(\.entry.id)
        let phrase = reading.rawContent.joined(separator: " ")
        let title = usedScopes.map(\.title).joined(separator: " and ")
        let kind = pool.first?.entry.kind
        if pool.count == 1 {
            return AskPart(phrase: phrase, kind: .found, entityIds: ids, scope: usedScopes.first?.scope, scopeTitle: title.isEmpty ? nil : title, entityKind: kind)
        }
        let rooms = Set(pool.map { $0.entry.roomKey ?? "" })
        let sameName = Set(pool.map { AskText.normalize($0.entry.displayName) }).count == 1
        let climate = pool.allSatisfy { $0.entry.kind == .climate }
        if reading.plural || pluralSet || climate || (sameName && rooms.count == 1) {
            return AskPart(phrase: phrase, kind: .group, entityIds: ids, scope: usedScopes.first?.scope, scopeTitle: title.isEmpty ? nil : title, entityKind: kind)
        }
        var several = AskPart(phrase: phrase, kind: .several, candidateIds: ids, scopeTitle: title.isEmpty ? nil : title, entityKind: kind)
        several.guardedPick = guardedPick
        return several
    }

    // MARK: Exact names, groups, outsiders

    /// The one configured entity whose own name is exactly the plural words the question said, or nil. "Lights" means the thing
    /// called Lights, when exactly one thing is, and not every light. Singular words and group entities never take this path.
    func exactNameEntity(chunk: [String], reading: ChunkReading, kinds: Set<AskKind>) -> AskEntry? {
        guard reading.plural else { return nil }
        let want = chunk.filter { !functionStems.contains(AskText.stem($0)) && !fillerStems.contains(AskText.stem($0)) }.joined(separator: " ")
        guard !want.isEmpty else { return nil }
        let roomGroups = Set(index.documentGroups.values.compactMap(\.lightGroupEntity)).subtracting(index.documentGroups.values.flatMap(\.lights))
        let hits = index.entries.values.filter { $0.askable && !roomGroups.contains($0.id) && !$0.isGroup && kinds.contains($0.kind) && $0.ownNames.contains(want) }
        let pool = aggregator.collapsingSameThing(hits.sorted { $0.id < $1.id })
        return pool.count == 1 ? pool[0] : nil
    }

    /// The configured group whose phrase is the whole of the chunk, or nil. A chunk with a room or an extra name word is not it.
    func overlayGroup(_ reading: ChunkReading) -> AskPart? {
        guard reading.scopes.isEmpty, !index.configuration.groups.isEmpty else { return nil }
        let syn = index.configuration.synonyms
        var best: (group: AskGroup, words: [String])?
        for g in index.configuration.groups {
            for phrase in g.say {
                let words = AskText.words(phrase, synonyms: syn)
                guard !words.isEmpty, AskText.containsRun(reading.toks, words) != nil else { continue }
                let covered = Set(words)
                guard reading.content.allSatisfy({ covered.contains($0) }) else { continue }
                if best == nil || words.count > best!.words.count { best = (g, words) }
            }
        }
        guard let (group, _) = best else { return nil }
        let members = aggregator.collapsingSameThing(group.entityIds.compactMap { index.entry($0) }.filter { $0.askable })
        guard !members.isEmpty else { return nil }
        return AskPart(phrase: reading.setPhrase, kind: .group, entityIds: members.map(\.id), entityKind: group.kind ?? members[0].kind)
    }

    /// A part for words that name something that exists in Home Assistant but is not configured, or nil when nothing does.
    ///
    /// It needs a word that is not a kind or a value ("entryway", "iphone") and every word explained by one outsider's names,
    /// so a question about nothing at all is still "none". Only names are read: the outsider's state never is.
    func outsiderPart(reading: ChunkReading, tokens: [String]) -> AskPart? {
        guard tokens.contains(where: { kindStems[$0] == nil && valueStems[$0] == nil }) else { return nil }
        let syn = index.configuration.synonyms
        var q = Set(tokens)
        for s in reading.scopes {
            if case .room(let key) = s.scope, let room = index.rooms[key] { q.formUnion(AskText.words(room.title, synonyms: syn)) } else { q.formUnion(s.words) }
        }
        for e in index.outsiders.values {
            let kw = kindWords(e)
            if e.nameVariants.contains(where: { q.isSubset(of: $0.union(e.roomWords).union(kw)) }) {
                return AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .notConfigured, entityKind: e.kind)
            }
        }
        return nil
    }

    private func collapseDuplicates(_ pool: [Candidate]) -> [Candidate] {
        var byKey: [String: [Candidate]] = [:]
        for c in pool { byKey[AskText.normalize(c.entry.displayName) + "|" + (c.entry.roomKey ?? "") + "|" + c.entry.domain, default: []].append(c) }
        var out: [Candidate] = []
        for (_, list) in byKey {
            if list.count > 1, let doc = list.first(where: { $0.entry.documentReferenced }), list.filter(\.entry.documentReferenced).count == 1 { out.append(doc) } else { out += list }
        }
        return out.sorted { $0.entry.id < $1.entry.id }
    }
}
