import Foundation

// MARK: - Noun phrases

extension AskResolver {
    /// What one chunk of a question names.
    struct ChunkResult {
        var part: AskPart
    }

    /// Words, scopes and kinds of one noun phrase, ready to resolve.
    struct ChunkReading {
        var scopes: [ScopePhrase]
        var content: [String]
        var rawContent: [String]
        var plural: Bool
        var wholeHouse: Bool
        var garageDoor: Bool
        /// The question's words, stemmed and synonym-mapped, in order, scope words included.
        var toks: [String]
        /// The words that name the set when it is not set up ("outdoor lights"): everything but function words.
        var setPhrase: String
        /// Whether a qualifier word ("outdoor") narrows the kind to a place no room names.
        var qualifier: Bool
        /// Ordinary words of the question that may also be name words (`left`, `open`, `display`).
        var soft: Set<String>
        /// A plural word that is not a kind noun but is a name word ("bollards"): more than one thing is meant.
        var pluralName: Bool
    }

    /// Resolves one chunk to a part, or nil when it names nothing (only function words).
    func resolveChunk(_ chunk: [String], intent: AskIntent, carryKind: AskKind?) -> ChunkResult? {
        let reading = read(chunk)
        if let group = overlayGroup(reading) { return ChunkResult(part: group) }
        let unknown = unknownTokens(reading.content)
        if !unknown.isEmpty {
            return ChunkResult(part: outsiderPart(reading: reading, tokens: reading.content) ?? AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .none))
        }
        let tokens = reading.content.map(corrected).filter { !($0.hasSuffix("ing") && $0.count > 4 && !index.vocabulary.contains($0)) }
        let kindTokens = tokens.filter { kindStems[$0] != nil || valueStems[$0] != nil }
        let distinctKinds = Set(kindTokens.compactMap { kindStems[$0] ?? valueStems[$0] })
        let hasName = tokens.contains { kindStems[$0] == nil && valueStems[$0] == nil }
        let scopeTitle = reading.scopes.map(\.title).joined(separator: " and ")

        // The weather: "how cold is it outside".
        if !hasName, (chunk.contains("outside") || chunk.contains("outdoors") || chunk.contains("outdoor")), reading.scopes.isEmpty,
           intent.valueKind == .temperature || intent.valueKind == .humidity || kindTokens.contains("weather"),
           let weather = index.primaryWeatherId.flatMap({ index.entries[$0] }) ?? index.entries.values.filter({ $0.askable && $0.domain == "weather" }).sorted(by: { $0.id < $1.id }).first
        {
            return ChunkResult(part: AskPart(phrase: "outside", kind: .found, entityIds: [weather.id], entityKind: .weather))
        }
        if tokens.isEmpty, reading.scopes.isEmpty, !reading.wholeHouse { return nil }
        // "Left" is ordinary English and also a name word ("left garage door"): when a name carries it, the name path decides.
        let positional = reading.soft.contains("left") && index.vocabulary.contains("left")
        let nameFirst = hasName || distinctKinds.count > 1 || (tokens.count >= 2 && !reading.garageDoor) || positional
        if nameFirst {
            if let named = resolveName(reading: reading, tokens: tokens, intent: intent, requireExact: !hasName && distinctKinds.count <= 1) {
                return ChunkResult(part: named)
            }
            if hasName {
                return ChunkResult(part: outsiderPart(reading: reading, tokens: tokens) ?? AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .none))
            }
        }
        // A word that is also one entity's exact name means that entity ("lights" when one thing is called "Lights").
        if !hasName, let exact = exactNameEntity(chunk: chunk, reading: reading, kinds: distinctKinds) {
            return ChunkResult(part: AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .found, entityIds: [exact.id], entityKind: exact.kind))
        }
        // A kind with or without a scope: "the lights", "windows in the office", "temperature in the kitchen".
        var kind: AskKind? = kindTokens.compactMap { kindStems[$0] ?? valueStems[$0] }.first
        var scopesForKind = reading.scopes
        if reading.garageDoor, !hasName { kind = .garage; scopesForKind = [] }
        if kind == nil {
            if chunk.contains(where: { AskLexicon.personWords.contains($0) }) && !reading.scopes.isEmpty { kind = .occupancy }
            else if reading.scopes.isEmpty && !reading.wholeHouse { kind = carryKind ?? intent.valueKind }
            else { kind = intent.valueKind ?? carryKind }
        }
        if kind == nil, !reading.scopes.isEmpty, let p = intent.predicate, let k = Self.predicateKind[p] { kind = k }
        if kind == nil, !reading.scopes.isEmpty {
            // "What is on in the office": the room's lights, else its media.
            kind = intent.wantsWhich || intent.predicate == .on || intent.wantsAny || intent.wantsCount ? .light : nil
        }
        guard let kind else {
            if reading.scopes.isEmpty { return nil }
            return ChunkResult(part: AskPart(phrase: scopeTitle, kind: .none))
        }
        if kind == .climate, !reading.plural, scopesForKind.isEmpty, !reading.wholeHouse, let primary = index.primaryThermostatId, index.entry(primary) != nil {
            return ChunkResult(part: AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .found, entityIds: [primary], entityKind: .climate))
        }
        let scopes: [AskScope] = scopesForKind.isEmpty ? [.house] : scopesForKind.map(\.scope)
        let asksSet = intent.wantsAny || intent.wantsCount || intent.wantsWhich || intent.wantsAll || intent.comparison != nil
        // A set across the house is valid only when the configuration defines it. A plural kind with no such list, a subset
        // noun ("TVs") or a qualifier ("outdoor lights") is a set nobody has configured: "not set up", never what matches.
        if scopesForKind.isEmpty, reading.plural || asksSet || reading.wholeHouse {
            let subset = tokens.contains { index.configuration.subsetNouns.contains($0) }
            if !aggregator.definesHouseSet(kind) || subset || reading.qualifier {
                return ChunkResult(part: AskPart(phrase: reading.setPhrase, kind: .notConfigured, entityKind: kind))
            }
        }
        var members: [AskEntry] = []
        for scope in scopes { for m in aggregator.members(kind: kind, scope: scope) where !members.contains(where: { $0.id == m.id }) { members.append(m) } }
        if members.isEmpty {
            // No entity of that kind in the scope: the kind word may be part of a name ("master bathroom fan" is a switch).
            if let named = resolveName(reading: reading, tokens: tokens, intent: intent, requireExact: false) { return ChunkResult(part: named) }
            // Something of that kind exists in the scope in Home Assistant, but the configuration does not name it.
            if scopes.contains(where: { !aggregator.outsiders(kind: kind, scope: $0).isEmpty }) {
                return ChunkResult(part: AskPart(phrase: reading.setPhrase, kind: .notConfigured, scopeTitle: scopeTitle.isEmpty ? nil : scopeTitle, entityKind: kind))
            }
            return ChunkResult(part: AskPart(phrase: (reading.rawContent + reading.scopes.map(\.title)).joined(separator: " "), kind: .none))
        }
        let ids = members.map(\.id)
        let scoped = !reading.scopes.isEmpty || reading.wholeHouse
        let singularKinds: Set<AskKind> = [.light, .door, .window, .vent, .camera, .fan, .mediaPlayer, .motion, .lock, .garage, .valve, .switchDevice]
        if !reading.plural, !asksSet, members.count > 1, singularKinds.contains(kind), !scoped || kind == .light {
            return ChunkResult(part: AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .several, candidateIds: ids, scopeTitle: scopeTitle.isEmpty ? nil : scopeTitle, entityKind: kind))
        }
        let roomScoped = reading.scopes.contains { if case .room = $0.scope { return true } else { return false } }
        if !reading.plural, !asksSet, members.count == 1, kind != .occupancy, !(roomScoped && !hasName && [.temperature, .humidity, .airQuality].contains(kind)) {
            return ChunkResult(part: AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .found, entityIds: ids, scope: scopes.first, scopeTitle: scopeTitle.isEmpty ? nil : scopeTitle, entityKind: kind))
        }
        return ChunkResult(part: AskPart(phrase: reading.rawContent.joined(separator: " "), kind: .group, entityIds: ids, scope: scopes.first, scopeTitle: scopeTitle.isEmpty ? nil : scopeTitle, entityKind: kind))
    }

    /// The kind a state words points at when the question names a place and no device ("is the music room occupied").
    static let predicateKind: [AskPredicate: AskKind] = [
        .occupied: .occupancy, .clear: .occupancy, .detected: .motion, .playing: .mediaPlayer, .notPlaying: .mediaPlayer,
        .recording: .camera, .locked: .lock, .unlocked: .lock,
    ]

    // MARK: Reading

    func read(_ chunk: [String]) -> ChunkReading {
        let syn = index.configuration.synonyms
        let toks = chunk.flatMap { AskText.words($0, synonyms: syn) }
        let garageDoor = AskText.containsRun(toks, ["garage", "door"]) != nil
        var scopes: [ScopePhrase] = []
        var rest: [String] = []
        var i = 0
        while i < toks.count {
            if let m = scopePhrases.first(where: { p in
                p.words.count <= toks.count - i && Array(toks[i..<(i + p.words.count)]) == p.words
            }) {
                scopes.append(m)
                i += m.words.count
            } else {
                rest.append(toks[i])
                i += 1
            }
        }
        var seen = Set<String>()
        let content = rest.filter { !functionStems.contains($0) && !fillerStems.contains($0) && !AskLexicon.houseWords.contains($0) }.filter { seen.insert($0).inserted }
        let raw = chunk.filter { w in
            let s = AskText.words(w, synonyms: syn)
            return !s.allSatisfy { functionStems.contains($0) || fillerStems.contains($0) }
        }
        let setPhrase = chunk.filter { w in
            !AskText.words(w, synonyms: syn).allSatisfy { functionStems.contains($0) }
        }.joined(separator: " ")
        let qualifier = chunk.contains { index.configuration.qualifierWords.contains($0) }
        let plural = chunk.contains { w in
            w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") && (kindStems[AskText.stem(w)] != nil || w == "sensors")
        } && !chunk.contains("was")
        let whole = chunk.contains { AskLexicon.houseWords.contains($0) && $0 != "home" }
            || chunk.contains("everywhere") || chunk.contains("altogether")
        return ChunkReading(
            scopes: scopes, content: content, rawContent: raw, plural: plural, wholeHouse: whole, garageDoor: garageDoor, toks: toks,
            setPhrase: setPhrase, qualifier: qualifier,
            soft: Set(rest.filter { functionStems.contains($0) || fillerStems.contains($0) }),
            pluralName: chunk.contains { w in
                w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") && !w.hasSuffix("us") && !functionStems.contains(AskText.stem(w)) && !fillerStems.contains(AskText.stem(w))
                    && kindStems[AskText.stem(w)] == nil && index.vocabulary.contains(AskText.stem(w)) && !index.vocabulary.contains(w)
            }
        )
    }

    /// Whether a word is part of ordinary speech or the home's vocabulary.
    func isKnown(_ token: String) -> Bool {
        if knownWords.contains(token) || fillerStems.contains(token) || functionStems.contains(token) { return true }
        if Int(token) != nil || token.count <= 2 { return true }
        if token.hasSuffix("ing") || token.hasSuffix("ed") || token.contains("_") { return true }
        if AskText.number(token) != nil { return true }
        return fuzzyMatch(token) != nil
    }

    func unknownTokens(_ tokens: [String]) -> [String] { tokens.filter { !isKnown($0) } }

    /// A rough pronunciation key: `phillip` and `filip` share one, so a speech recogniser's spelling still finds the name.
    static func phonetic(_ word: String) -> String {
        var w = word
        for (a, b) in [("ph", "f"), ("ck", "k"), ("v", "f"), ("z", "s"), ("w", "v"), ("c", "k"), ("q", "k")] { w = w.replacingOccurrences(of: a, with: b) }
        var out = ""
        for ch in w where out.last != ch { out.append(ch) }
        return out
    }

    /// Near-miss: a unique vocabulary word with the same pronunciation, one or two edits away, or sharing a prefix of 4 or more letters.
    func fuzzyMatch(_ token: String) -> String? {
        guard token.count >= 4 else { return nil }
        if token.count >= 5 {
            let key = Self.phonetic(token)
            let same = index.vocabulary.filter { $0 != token && Self.phonetic($0) == key }
            if same.count == 1 { return same.first }
        }
        let prefixed = index.vocabulary.filter { $0.count > token.count && $0.hasPrefix(token) }
        if token.count >= 4, prefixed.count == 1 { return prefixed.first }
        guard token.count >= 5 else { return nil }
        let limit = token.count >= 8 ? 2 : (token.count >= 6 ? 2 : 1)
        var best: (word: String, distance: Int)?
        var tie = false
        for w in index.vocabulary where abs(w.count - token.count) <= limit {
            let d = Self.editDistance(token, w, limit: limit)
            guard d <= limit else { continue }
            if let b = best { if d < b.distance { best = (w, d); tie = false } else if d == b.distance { tie = true } } else { best = (w, d) }
        }
        return tie ? nil : best?.word
    }

    func corrected(_ token: String) -> String {
        if knownWords.contains(token) || Int(token) != nil { return token }
        return fuzzyMatch(token) ?? token
    }

    /// Damerau-free Levenshtein distance with an early exit above `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            var rowMin = cur[0]
            for j in 1...y.count {
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
                rowMin = Swift.min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            prev = cur
        }
        return prev[y.count]
    }
}
