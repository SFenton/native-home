import Foundation

// MARK: - Composer

/// Writes the sentence for an answer from facts code already holds. No model, no I/O.
///
/// Every sentence is deliberate about two things: the state word comes from `AskStateWords` (so "open" is never "on"), and a
/// negative answer never repeats the active phrase ("no, all 4 lights are off", not "none are on"), so a sentence that says
/// no cannot also contain the words of a yes.
struct AskComposer: Sendable {
    let index: AskableIndex
    let lines: AskLineFormatter

    init(index: AskableIndex) {
        self.index = index
        lines = AskLineFormatter(index: index)
    }

    // MARK: Fixed sentences

    var declineAction: String { "I can only answer questions about the home, and I can't control anything." }
    var declineOfftopic: String { "I can only answer questions about the home, so I can't help with that." }
    var locked: String { "Unlock your phone to ask about that." }

    func none(_ phrase: String?) -> String {
        let p = (phrase ?? "").trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? "I couldn't find that in \(index.houseName)." : "I couldn't find \"\(p)\" in \(index.houseName)."
    }

    /// The fixed answer for something the configuration does not cover. It names what was asked, never a state.
    func notConfigured(_ parts: [AskPart]) -> String {
        let named = parts.filter { $0.kind == .notConfigured }.map { $0.phrase.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !named.isEmpty else { return "That isn't set up in \(index.houseName), so I can't tell you." }
        return "I don't have \(named.joined(separator: " or ")) set up in \(index.houseName), so I can't tell you about it."
    }

    func several(_ ids: [String]) -> String {
        var seen = Set<String>()
        let names = ids.compactMap(index.entry).map(lines.label).filter { seen.insert($0).inserted }
        let shown = names.prefix(12).joined(separator: ", ")
        return "Which one do you mean: \(shown)\(names.count > 12 ? ", or \(names.count - 12) more" : "")?"
    }

    func unavailable(_ e: AskEntry) -> String {
        "\(e.displayName) is unavailable right now, so I can't tell its state."
    }

    // MARK: Entry point

    /// The sentence for a found or group resolution.
    func sentence(_ r: AskResolution, facts: AskFacts) -> String {
        let i = r.intent
        let ids = r.parts.flatMap(\.entityIds)
        if i.wantsWhy { return ids.prefix(4).compactMap(index.entry).map { why($0, facts: facts) }.joined(separator: " ") }
        if i.wantsHowLong { return howLong(ids.compactMap(index.entry), facts: facts) }
        if i.wantsLast { return ids.prefix(4).compactMap(index.entry).map { lastTime($0, intent: i, facts: facts) }.joined(separator: " ") }
        if i.comparison != nil { return comparison(r, facts: facts) }
        return r.parts.map { part($0, intent: i) }.joined(separator: " ")
    }

    // MARK: Parts

    private func part(_ p: AskPart, intent i: AskIntent) -> String {
        switch p.kind {
        case .none: return none(p.phrase)
        case .notConfigured: return notConfigured([p])
        case .several: return several(p.candidateIds)
        case .found:
            guard let e = index.entry(p.entityIds[0]) else { return none(p.phrase) }
            if e.isUnavailable { return unavailable(e) }
            return single(e, intent: i)
        case .group:
            return group(p, members: p.entityIds.compactMap(index.entry), intent: i)
        }
    }

    func single(_ e: AskEntry, intent i: AskIntent) -> String {
        if e.domain == "automation" || e.domain == "script", i.today { return ranToday(e) }
        let numeric = Double(e.state.state) != nil && e.domain == "sensor"
        if i.wantsValue || numeric || (e.domain == "weather" && i.predicate == nil) { return value(e, intent: i) }
        let word = AskStateWords.word(for: e)
        if let p = i.predicate, let m = AskStateWords.matches(e, p), i.yesNo { return "\(m ? "Yes" : "No"), \(e.displayName) is \(word)." }
        return "\(e.displayName) is \(word)."
    }

    func ranToday(_ e: AskEntry) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = index.timeZone
        let midnight = cal.startOfDay(for: index.now)
        if let text = e.state.attributes["last_triggered"]?.string, let d = AskDurationResolver.parse(text), d >= midnight {
            return "Yes, \(e.displayName) ran today, \(AskDuration.phrase(seconds: index.now.timeIntervalSince(d))) ago."
        }
        return "No, \(e.displayName) hasn't run today."
    }

    // MARK: Value

    func value(_ e: AskEntry, intent i: AskIntent) -> String {
        let a = e.state.attributes
        switch e.domain {
        case "weather":
            let unit = a["temperature_unit"]?.string ?? "°F"
            if i.valueKind == .humidity, let h = a["humidity"]?.finiteNumber { return "The humidity outside is \(AskLineFormatter.number(h))%." }
            if let t = a["temperature"]?.finiteNumber { return "It's \(AskLineFormatter.number(t))\(unit) outside." }
            return "\(e.displayName) is \(e.state.state)."
        case "climate":
            if let t = a["current_temperature"]?.finiteNumber { return "\(e.displayName) reads \(AskLineFormatter.number(t))°." }
            return "\(e.displayName) is \(AskStateWords.word(for: e))."
        case "humidifier":
            if let h = a["current_humidity"]?.finiteNumber { return "\(e.displayName) reads \(AskLineFormatter.number(h))% humidity." }
            return "\(e.displayName) is \(e.state.state)."
        default:
            if Double(e.state.state) == nil { return "\(e.displayName) is \(AskStateWords.word(for: e))." }
            return "\(e.displayName) is \(AskLineFormatter.reading(e))."
        }
    }

    // MARK: Groups

    private func group(_ p: AskPart, members: [AskEntry], intent i: AskIntent) -> String {
        let kind = p.entityKind ?? members.first?.kind ?? .other
        let title = p.scopeTitle
        switch kind {
        case .temperature, .humidity, .airQuality, .battery, .power:
            return reading(kind, members: members, title: title)
        case .climate:
            return members.map { value($0, intent: i) }.joined(separator: " ")
        case .person:
            return people(members, intent: i)
        case .occupancy:
            return occupancy(members, title: title, intent: i)
        default:
            return counts(kind, members: members, title: title, intent: i)
        }
    }

    private func reading(_ kind: AskKind, members: [AskEntry], title: String?) -> String {
        let nums = members.filter { !$0.isUnavailable }.compactMap { m in Double(m.state.state).map { (m, $0) } }
        guard !nums.isEmpty else { return "I can't read \(title.map { "the \($0)" } ?? "those sensors") right now." }
        let mean = nums.map(\.1).reduce(0, +) / Double(nums.count)
        let unit = nums.first?.0.state.attributes["unit_of_measurement"]?.string ?? ""
        let spaced = ["%", "°F", "°C", "°"].contains(unit) || unit.isEmpty ? "" : " "
        let label = kind == .humidity ? "humidity" : (kind == .temperature ? "temperature" : "reading")
        let place = title.map { "the \($0)" } ?? "the house"
        if nums.count == 1 { return "The \(label) in \(place) is \(AskLineFormatter.number(mean))\(spaced)\(unit)." }
        let lo = nums.map(\.1).min() ?? mean, hi = nums.map(\.1).max() ?? mean
        return "The \(label) in \(place) is about \(AskLineFormatter.number(mean))\(spaced)\(unit), from \(AskLineFormatter.number(lo)) to \(AskLineFormatter.number(hi)) across \(nums.count) sensors."
    }

    private func people(_ members: [AskEntry], intent i: AskIntent) -> String {
        let home = members.filter { $0.state.state == "home" }
        let away = members.filter { $0.state.state != "home" }
        func names(_ l: [AskEntry]) -> String { l.map(\.displayName).joined(separator: ", ") }
        if i.wantsCount {
            return "\(home.count) of \(members.count) \(home.count == 1 ? "person is" : "people are") home\(home.isEmpty ? "" : ": \(names(home))")."
        }
        if i.wantsAll || i.predicate == .away || (i.predicate == .home && i.negated) {
            if away.isEmpty { return "Yes, everyone is home: \(names(home))." }
            let homePart = home.isEmpty ? "" : "\(names(home)) \(home.count == 1 ? "is" : "are") home and "
            return "No, not all of the \(members.count) people are home: \(homePart)\(names(away)) \(away.count == 1 ? "is" : "are") away."
        }
        if home.isEmpty { return "No, nobody is home." }
        return "Yes, \(home.count) \(home.count == 1 ? "person is" : "people are") home: \(names(home))."
    }

    private func occupancy(_ members: [AskEntry], title: String?, intent i: AskIntent) -> String {
        let usable = members.filter { !$0.isUnavailable }
        let hits = usable.filter { $0.state.state == "on" }
        let place = title.map { "the \($0)" } ?? "the house"
        if i.wantsCount { return "\(hits.count) of \(usable.count) occupancy sensors show someone in \(place)." }
        if hits.isEmpty { return "No, nobody is in \(place); it looks empty." }
        return "Yes, someone is in \(place): \(hits.prefix(8).map(\.displayName).joined(separator: ", "))."
    }

    // MARK: Counts

    private func counts(_ kind: AskKind, members: [AskEntry], title: String?, intent i: AskIntent) -> String {
        let p = Self.applicable(i.predicate, to: members) ?? AskStateWords.defaultPredicate(for: kind)
        let usable = members.filter { !$0.isUnavailable }
        let hits = usable.filter { AskStateWords.matches($0, p) == true }.sorted { $0.state.lastChanged < $1.state.lastChanged }
        let label = AskStateWords.label(p)
        let opposite = AskStateWords.opposite(p, kind: kind)
        let place = title.map { " in the \($0)" } ?? ""
        let total = usable.count
        let plural = Self.noun(kind, count: 2)
        let unavailable = members.count - usable.count
        let note = unavailable > 0 ? " (\(unavailable) unavailable)" : ""
        let closure: Set<AskPredicate> = [.closed, .locked, .off, .clear, .home, .notPlaying]
        let allPolarity = i.wantsAll || (!i.wantsAny && !i.wantsCount && !i.wantsWhich && closure.contains(p) && total > 1)
        let limit = index.configuration.budget.maxListedNames
        let names = Self.list(hits.map(\.displayName), limit: limit)
        func verb(_ n: Int) -> String { n == 1 ? "is" : "are" }
        if i.wantsCount {
            if hits.isEmpty { return "None: all \(total) \(plural) are \(opposite)\(place)\(note)." }
            return "\(hits.count) of the \(total) \(plural) \(verb(hits.count)) \(label)\(place)\(note): \(names)."
        }
        if allPolarity {
            if hits.count == total, total > 0 {
                return "Yes, all \(total) \(plural) are \(label)\(place)\(note)" + (p == .locked ? ", no exceptions" : "") + (total <= 3 ? ": \(names)." : ".")
            }
            let rest = usable.filter { AskStateWords.matches($0, p) != true }
            return "No, \(rest.count) of the \(total) \(plural) \(verb(rest.count)) not \(label)\(place)\(note): \(Self.list(rest.map(\.displayName), limit: limit))."
        }
        if hits.isEmpty { return "No, all \(total) \(plural) are \(opposite)\(place)\(note)." }
        if i.wantsWhich { return "\(hits.count) \(Self.noun(kind, count: hits.count)) \(verb(hits.count)) \(label)\(place)\(note): \(names)." }
        return "Yes, \(hits.count) \(Self.noun(kind, count: hits.count)) \(verb(hits.count)) \(label)\(place)\(note): \(names)."
    }

    /// The predicate when it applies to the members' kind, else nil.
    static func applicable(_ p: AskPredicate?, to members: [AskEntry]) -> AskPredicate? {
        guard let p, let sample = members.first, AskStateWords.matches(sample, p) != nil else { return nil }
        return p
    }

    static func list(_ names: [String], limit: Int) -> String {
        let shown = names.prefix(limit).joined(separator: ", ")
        return names.count > limit ? "\(shown), and \(names.count - limit) more" : shown
    }

    /// The noun for a kind, singular or plural.
    static func noun(_ kind: AskKind, count: Int) -> String {
        let s: String
        switch kind {
        case .light: s = "light"
        case .window: s = "window"
        case .door: s = "door"
        case .garage: s = "garage door"
        case .lock: s = "lock"
        case .camera: s = "camera"
        case .vent: s = "vent"
        case .motion: s = "motion sensor"
        case .occupancy: s = "occupancy sensor"
        case .mediaPlayer: s = "media player"
        case .fan: s = "fan"
        case .valve: s = "valve"
        case .switchDevice: s = "switch"
        case .person: return count == 1 ? "person" : "people"
        case .climate: s = "thermostat"
        default: s = "device"
        }
        return count == 1 ? s : s + "s"
    }
}
