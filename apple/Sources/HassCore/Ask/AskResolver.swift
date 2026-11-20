import Foundation

// MARK: - Resolver

/// Reads one spoken question and decides, in code, what it is about and where it goes.
///
/// No model runs here. The resolver strips spoken lead-ins, declines action requests and questions that are not about the
/// home, reads what the words ask for (``AskIntent``), then resolves each noun phrase against the ``AskableIndex`` to one
/// entity, a clear group, several candidates, or nothing. A verb or filler word the home does not know (`recording`) is not
/// a device word, so it never turns a real device into "none"; a word that could only be a device (`loft`) does.
public struct AskResolver: Sendable {
    /// The index questions resolve against.
    public let index: AskableIndex
    let aggregator: AskAggregator
    let functionStems: Set<String>
    let fillerStems: Set<String>
    let kindStems: [String: AskKind]
    let valueStems: [String: AskKind]
    let scopePhrases: [ScopePhrase]
    let knownWords: Set<String>

    /// A phrase that names a room or floor.
    struct ScopePhrase {
        let words: [String]
        let scope: AskScope
        let title: String
    }

    /// Creates a resolver over `index`.
    public init(index: AskableIndex) {
        self.index = index
        aggregator = AskAggregator(index: index)
        let syn = index.configuration.synonyms
        functionStems = Set(AskLexicon.function.flatMap { AskText.words($0, synonyms: [:]) })
        fillerStems = Set(AskLexicon.filler.flatMap { AskText.words($0, synonyms: [:]) })
        kindStems = Dictionary(uniqueKeysWithValues: AskLexicon.kindNouns.map { (AskText.stem($0.key), $0.value) })
        valueStems = Dictionary(uniqueKeysWithValues: AskLexicon.valueWords.map { (AskText.stem($0.key), $0.value) })
        var phrases: [ScopePhrase] = []
        for room in index.rooms.values {
            for p in room.phrases { phrases.append(ScopePhrase(words: p, scope: .room(room.key), title: room.title)) }
        }
        for floor in index.floors.values {
            for p in floor.phrases { phrases.append(ScopePhrase(words: p, scope: .floor(floor.id), title: floor.name)) }
        }
        let levels = index.floors.values.compactMap { f in f.level.map { (f.id, f.name, $0) } }
        if let top = levels.max(by: { $0.2 < $1.2 }), let bottom = levels.min(by: { $0.2 < $1.2 }), top.0 != bottom.0 {
            phrases.append(ScopePhrase(words: AskText.words("upstairs"), scope: .floor(top.0), title: top.1))
            phrases.append(ScopePhrase(words: AskText.words("downstairs"), scope: .floor(bottom.0), title: bottom.1))
        }
        scopePhrases = phrases.sorted { $0.words.count > $1.words.count }
        var known = index.vocabulary
        known.formUnion(kindStems.keys)
        known.formUnion(valueStems.keys)
        known.formUnion(AskLexicon.personWords)
        // The device words a name rarely carries but a person says ("the den presence sensor"): `kindWords` matches them.
        known.formUnion(["sensor", "switch", "cover"])
        known.formUnion(syn.values.flatMap { AskText.words($0) })
        knownWords = known
    }

    // MARK: Resolve

    /// Resolves one question.
    public func resolve(_ question: String) -> AskResolution {
        var words = AskText.normalize(question).split(separator: " ").map(String.init)
        words = stripLeadIns(words)
        words = Self.removing(words, phrases: [["right", "now"], ["at", "the", "moment"], ["at", "this", "moment"], ["for", "me"], ["these", "days"]])
        if isAction(words) { return AskResolution(route: .declineAction, type: .state) }
        var intent = readIntent(words)
        let chunks = splitChunks(words)
        // "Is the living room the coolest room": a ranking over every room, whatever room the question names.
        if intent.superlative, intent.comparison != .longest, let kind = intent.valueKind, chunks.map({ read($0).scopes.count }).reduce(0, +) <= 1 {
            return resolveRanking(kind: kind, intent: intent, words: words)
        }
        var parts: [AskPart] = []
        var unmatched: [String] = []
        var carryKind: AskKind?
        for chunk in chunks {
            if let kind = intent.comparison, kind != .longest {
                let reading = read(chunk)
                if reading.scopes.count >= 2 {
                    let valueKind = intent.valueKind ?? .temperature
                    for s in reading.scopes {
                        let members = aggregator.members(kind: valueKind, scope: s.scope)
                        let outside = !aggregator.outsiders(kind: valueKind, scope: s.scope).isEmpty
                        let kind: AskPart.Kind = !members.isEmpty ? .group : (outside ? .notConfigured : .none)
                        parts.append(AskPart(phrase: kind == .notConfigured ? "\(valueKind.nouns.first ?? "that") in the \(s.title)" : s.title, kind: kind, entityIds: members.map(\.id), scope: s.scope, scopeTitle: s.title, entityKind: valueKind))
                    }
                    continue
                }
            }
            guard let result = resolveChunk(chunk, intent: intent, carryKind: carryKind) else { continue }
            if let kind = result.part.entityKind { carryKind = kind }
            parts.append(result.part)
            if result.part.kind == .none { unmatched.append(result.part.phrase) }
        }
        if intent.comparison == .longest {
            parts = parts.map { p in
                var q = p
                q.entityIds = p.entityIds.filter { index.entry($0).map { AskStateWords.matches($0, .on) == true } ?? false }
                return q
            }
        }
        if parts.isEmpty { return resolveWithoutSubject(words, intent: &intent) }
        return assemble(parts: parts, intent: intent, unmatched: unmatched, words: words)
    }

    // MARK: Diagnostics

    /// How the resolver read each chunk of `question`: scopes, content words and unknown words. For logs and tests, not for speech.
    public func explain(_ question: String) -> String {
        var words = AskText.normalize(question).split(separator: " ").map(String.init)
        words = stripLeadIns(words)
        var lines = ["words: \(words.joined(separator: " "))", "action: \(isAction(words))", "intent: \(readIntent(words))"]
        for chunk in splitChunks(words) {
            let r = read(chunk)
            lines.append("chunk \(chunk): scopes \(r.scopes.map(\.title)) content \(r.content) unknown \(unknownTokens(r.content)) plural \(r.plural) house \(r.wholeHouse)")
            let ranked = candidates(tokens: r.content.map(corrected), scopes: r.scopes, soft: r.soft).sorted { ($0.rank, $0.entry.id) < ($1.rank, $1.entry.id) }
            for c in ranked.prefix(6) { lines.append("  candidate \(c.entry.id) extra \(c.extra) soft \(c.softHits) kind \(c.entry.kind.rawValue) display \(c.entry.displayName)") }
        }
        return lines.joined(separator: "\n")
    }

    /// `words` without each run in `phrases`.
    static func removing(_ words: [String], phrases: [[String]]) -> [String] {
        var w = words
        for p in phrases { while let ix = AskText.containsRun(w, p) { w.removeSubrange(ix..<(ix + p.count)) } }
        return w
    }

    // MARK: Lead-ins and actions

    func stripLeadIns(_ words: [String]) -> [String] {
        var w = words
        var changed = true
        while changed, !w.isEmpty {
            changed = false
            for lead in AskLexicon.leadIns where w.count > lead.count && Array(w.prefix(lead.count)) == lead {
                // "check" opens a question only when something follows that is not an action verb.
                w.removeFirst(lead.count)
                changed = true
                break
            }
        }
        return w
    }

    func isAction(_ words: [String]) -> Bool {
        var w = words
        var changed = true
        while changed, !w.isEmpty {
            changed = false
            for p in AskLexicon.polite where w.count > p.count && Array(w.prefix(p.count)) == p {
                w.removeFirst(p.count)
                changed = true
                break
            }
        }
        guard let first = w.first else { return false }
        if first == "remind" || first == "set" { return true }
        // "Lower deck camera idle": a place that starts with an action word is a place when a room is named that way.
        if w.count > 1, scopePhrases.contains(where: { $0.words.count > 1 && AskText.containsRun(w.flatMap { AskText.words($0) }, $0.words) == 0 }) { return false }
        return AskLexicon.actionVerbs.contains(first)
    }

    // MARK: Chunks

    func splitChunks(_ words: [String]) -> [[String]] {
        var chunks: [[String]] = [[]]
        for w in words {
            if w == "and" || w == "or" || w == "plus" { chunks.append([]) } else { chunks[chunks.count - 1].append(w) }
        }
        return chunks.filter { !$0.isEmpty }
    }

    // MARK: No subject

    func resolveWithoutSubject(_ words: [String], intent: inout AskIntent) -> AskResolution {
        let stems = words.flatMap { AskText.words($0, synonyms: index.configuration.synonyms) }
        // "Is anyone home", "who is home", "are we all home": the household.
        if intent.household || stems.contains(where: { ["we", "us", "everyone", "everybody", "anyone", "anybody", "someone", "somebody", "who"].contains($0) }),
           intent.predicate == .home || intent.predicate == .away || intent.predicate == .occupied || stems.contains("home") || stems.contains("who") || stems.contains("house")
        {
            let people = aggregator.members(kind: .person, scope: .house)
            if !people.isEmpty {
                let part = AskPart(phrase: "household", kind: .group, entityIds: people.map(\.id), scope: .house, entityKind: .person)
                intent.household = true
                return assemble(parts: [part], intent: intent, unmatched: [], words: words)
            }
        }
        // A yes/no about a state with no device named reads as the matching kinds across the house.
        if let predicate = intent.predicate {
            let kinds: [AskKind]
            switch predicate {
            case .open, .closed: kinds = [.door, .window, .garage]
            case .locked, .unlocked: kinds = [.lock]
            case .playing, .notPlaying: kinds = [.mediaPlayer]
            case .recording: kinds = [.camera]
            case .on, .off: kinds = [.light]
            default: kinds = []
            }
            let members = kinds.flatMap { aggregator.members(kind: $0, scope: .house) }
            let houseWord = words.contains { AskLexicon.houseWords.contains($0) }
            if !members.isEmpty, intent.wantsAny || intent.wantsCount || intent.wantsWhich || intent.wantsAll || (intent.yesNo && houseWord) {
                let part = AskPart(phrase: "house", kind: .group, entityIds: members.map(\.id), scope: .house, entityKind: kinds.first)
                return assemble(parts: [part], intent: intent, unmatched: [], words: words)
            }
        }
        // "What is the coldest room": every room's reading.
        if let c = intent.comparison, c != .longest, let kind = intent.valueKind {
            return resolveRanking(kind: kind, intent: intent, words: words)
        }
        return AskResolution(route: .declineOfftopic, type: .state, intent: intent)
    }

    /// A ranking over the rooms: valid only when the configuration defines the house-wide set of that reading.
    func resolveRanking(kind: AskKind, intent: AskIntent, words: [String]) -> AskResolution {
        let label = (kind.nouns.first ?? "reading")
        if !aggregator.definesHouseSet(kind) {
            let part = AskPart(phrase: "room \(label)", kind: .notConfigured, entityKind: kind)
            return assemble(parts: [part], intent: intent, unmatched: [], words: words)
        }
        let members = aggregator.members(kind: kind, scope: .house)
        guard !members.isEmpty else { return AskResolution(route: .declineOfftopic, type: .state, intent: intent) }
        let part = AskPart(phrase: "rooms", kind: .group, entityIds: members.map(\.id), scope: .house, entityKind: kind)
        return assemble(parts: [part], intent: intent, unmatched: [], words: words)
    }

    // MARK: Assembly

    func assemble(parts: [AskPart], intent: AskIntent, unmatched: [String], words: [String]) -> AskResolution {
        var ids: [String] = []
        var cands: [String] = []
        for p in parts {
            for id in p.entityIds where !ids.contains(id) { ids.append(id) }
            for id in p.candidateIds where !cands.contains(id) { cands.append(id) }
        }
        let route: AskRoute
        if parts.allSatisfy({ $0.kind == .none }) {
            // Nothing matched: a question that names no device word at all is not about the home.
            if !parts.contains(where: { $0.phrase.isEmpty }), isHomeShaped(intent: intent, parts: parts, words: words) {
                route = .none
            } else {
                return AskResolution(route: .declineOfftopic, type: .state, intent: intent)
            }
        } else if parts.contains(where: { $0.kind == .several }) {
            route = .several
        } else if parts.contains(where: { $0.kind == .notConfigured }) {
            route = .notConfigured
        } else if parts.contains(where: { $0.kind == .none }) {
            route = .none
        } else if parts.count == 1, parts[0].kind == .found {
            route = index.entry(parts[0].entityIds[0])?.isUnavailable == true ? .unavailable : .found
        } else {
            route = .group
        }
        if route == .group, parts.count == 1, parts[0].kind == .group {
            if intent.whatsOn {
                ids = ids.filter { id in index.entry(id).map { ["on", "playing", "open", "unlocked", "heat", "cool", "cleaning"].contains($0.state.state) } ?? false }
            }
        }
        var type = questionType(parts: parts, intent: intent)
        if route == .none || route == .several || route == .notConfigured { type = parts.count > 1 ? .compound : type }
        let empty = route == .several || route == .none || route == .notConfigured
        return AskResolution(
            route: route, type: type, entityIds: empty ? [] : ids, candidateIds: route == .several ? cands : [],
            parts: parts, intent: intent, unmatchedPhrase: unmatched.isEmpty ? nil : unmatched.joined(separator: " and ")
        )
    }

    /// Whether a question with nothing matched still reads as about a device (so it is "none", not off-topic).
    func isHomeShaped(intent: AskIntent, parts: [AskPart], words: [String]) -> Bool {
        if intent.predicate != nil || intent.wantsValue || intent.wantsHowLong || intent.wantsLast || intent.wantsWhy { return true }
        let stems = words.flatMap { AskText.words($0, synonyms: index.configuration.synonyms) }
        return stems.contains { kindStems[$0] != nil || valueStems[$0] != nil }
    }

    func questionType(parts: [AskPart], intent: AskIntent) -> AskQuestionType {
        if intent.wantsWhy { return .why }
        if intent.wantsHowLong { return .howLong }
        if intent.wantsLast { return .lastTime }
        if intent.comparison != nil { return .comparison }
        if parts.count > 1 { return .compound }
        let first = parts[0]
        if let kind = first.entityKind {
            switch kind {
            case .person: return .people
            case .automation, .script, .scene: return .automation
            case .mediaPlayer: return .media
            default: break
            }
        }
        if first.kind == .group, case .room? = first.scope { return .room }
        if first.kind == .group { return .aggregate }
        if let id = first.entityIds.first, let e = index.entry(id) {
            switch e.domain {
            case "person": return .people
            case "automation", "script", "scene": return .automation
            case "media_player": return .media
            default: break
            }
        }
        return intent.wantsValue ? .value : .state
    }
}
