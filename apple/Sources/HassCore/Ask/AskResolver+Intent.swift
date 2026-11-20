import Foundation

// MARK: - Intent reading

extension AskResolver {
    /// Reads what the words of a question ask for, apart from which entities they name.
    func readIntent(_ words: [String]) -> AskIntent {
        var i = AskIntent()
        let set = Set(words)
        let joined = " " + words.joined(separator: " ") + " "
        func has(_ list: [String]) -> Bool { list.contains { set.contains($0) } }
        func phrase(_ list: [String]) -> Bool { list.contains { joined.contains(" \($0) ") } }

        i.wantsWhy = has(["why", "whys", "reason", "because", "caused", "cause"])
            || phrase(["who turned", "who opened", "who closed", "who locked", "who unlocked", "who switched", "who put", "who or what", "what made", "what put", "what turned", "what switched", "what opened", "what closed", "how come", "what triggered", "what started"])
            || (set.contains("who") && has(["turned", "opened", "closed", "locked", "unlocked", "switched", "left", "set"]) && !set.contains("home"))
        i.wantsHowLong = phrase(["how long", "since when", "for how long", "how many hours", "how many minutes", "how many days", "for how many", "for long", "for a long time", "been so long"])
        let leaveVerbs = ["leave", "left", "head", "headed", "arrive", "arrived", "depart", "departed", "got", "get", "come", "came", "return", "returned", "go", "went"]
        i.leaving = (set.contains("when") || set.contains("whens")) && has(leaveVerbs) && !set.contains("last")
        i.wantsLast = ((set.contains("when") || set.contains("whens")) && (set.contains("last") || has(leaveVerbs)))
            || phrase(["last time", "most recently", "last happened"])
        i.wantsCount = phrase(["how many", "how much"]) && !i.wantsHowLong
        i.wantsWhich = (words.first == "which") || phrase(["which ones", "what are", "what is on", "what is open", "what is playing", "what is turned", "what is active", "what is running", "list"])
            || (words.first == "what" && (set.contains("on") || set.contains("open") || set.contains("playing") || set.contains("active") || set.contains("running") || set.contains("turned")))
        i.wantsAny = has(["any", "anyone", "anybody", "anything", "someone", "somebody"]) || phrase(["is there", "are there"])
        i.wantsAll = has(["all", "both", "every", "everything", "everyone", "everybody", "each"])
        i.whatsOn = phrase(["what is on", "whats on", "what is turned on", "what is active", "what is running", "what all is on", "anything on", "anything turned on", "anything running", "anything active", "what is currently on", "what is playing"])
        i.today = set.contains("today")
        i.negated = has(["not", "isnt", "arent", "wasnt", "didnt", "never"])
        i.household = has(["we", "us", "everyone", "everybody"]) && (set.contains("home") || set.contains("here") || has(["away", "out", "gone", "left"]))

        // Comparison.
        if has(["warmer", "hotter", "warmest", "hottest"]) { i.comparison = .warmer; i.valueKind = .temperature }
        else if has(["colder", "cooler", "coldest", "coolest"]) { i.comparison = .colder; i.valueKind = .temperature }
        else if has(["humidest", "muggiest"]) || phrase(["most humid", "more humid", "stuffiest"]) { i.comparison = .humid; i.valueKind = .humidity }
        else if has(["driest", "drier"]) || phrase(["least humid", "less humid"]) { i.comparison = .dry; i.valueKind = .humidity }
        else if has(["longest"]) { i.comparison = .longest }
        else if phrase(["difference between", "difference in"]) || has(["difference"]) { i.comparison = .difference; i.valueKind = .temperature }
        i.superlative = has(["warmest", "hottest", "coldest", "coolest", "humidest", "driest", "longest", "muggiest"])
            || phrase(["most humid", "least humid", "stuffiest"])
        i.inOut = (set.contains("inside") || set.contains("indoors") || set.contains("indoor")) && (set.contains("outside") || set.contains("outdoors") || set.contains("outdoor"))

        // Value.
        for w in words {
            let s = AskText.stem(w)
            if let k = valueStems[s] ?? valueStems[w] { i.wantsValue = true; if i.valueKind == nil { i.valueKind = k } }
        }
        if phrase(["air quality"]) { i.wantsValue = true; i.valueKind = .airQuality }
        if phrase(["how much charge", "how much battery"]) { i.valueKind = .battery }
        if i.wantsCount, i.valueKind != nil, !set.contains("many") { i.wantsCount = false }

        // Predicate: the state a yes/no asks about.
        i.predicate = readPredicate(words, joined: joined)
        // "Music" is a media word, unless it is part of a room's name ("music room").
        if i.predicate == .playing, !set.contains("play"), !set.contains("playing") {
            let stems = words.flatMap { AskText.words($0) }
            if scopePhrases.contains(where: { $0.words.contains("music") && AskText.containsRun(stems, $0.words) != nil }) { i.predicate = readPredicate(words, joined: joined, musicIsRoom: true) }
        }
        let first = words.first ?? ""
        i.yesNo = ["is", "are", "was", "were", "does", "do", "did", "has", "have", "isnt", "arent", "can", "could", "should"].contains(first)
            || (i.wantsAny && !i.wantsWhich && !i.wantsCount)
        return i
    }

    private func readPredicate(_ words: [String], joined: String, musicIsRoom: Bool = false) -> AskPredicate? {
        let set = Set(words)
        func next(_ w: String) -> String? {
            guard let ix = words.firstIndex(of: w), ix + 1 < words.count else { return nil }
            return words[ix + 1]
        }
        let locationFollowers: Set<String> = ["the", "a", "an", "my", "our", "this", "that", "your", "floor", "level", "side"]
        func onPredicate(_ w: String) -> Bool {
            guard set.contains(w) else { return false }
            // `on` or `off` is a state unless it is a preposition ("on the porch").
            for (ix, word) in words.enumerated() where word == w {
                if ix + 1 >= words.count { return true }
                if !locationFollowers.contains(words[ix + 1]) { return true }
            }
            return false
        }
        if set.contains("unlocked") || set.contains("unlock") { return .unlocked }
        if set.contains("locked") || set.contains("lock") && (set.contains("did") || set.contains("i") || set.contains("we")) { return .locked }
        if set.contains("closed") || set.contains("shut") || set.contains("close") { return .closed }
        if set.contains("open") || set.contains("opened") || set.contains("ajar") { return .open }
        if set.contains("recording") || set.contains("record") || set.contains("recorded") { return .recording }
        if set.contains("playing") || set.contains("play") { return .playing }
        if set.contains("idle") || set.contains("paused") { return .notPlaying }
        if set.contains("occupied") || set.contains("anyone") || set.contains("someone") || set.contains("somebody") || set.contains("anybody") { if !set.contains("home") && !set.contains("here") { return .occupied } }
        if set.contains("empty") || set.contains("vacant") || set.contains("nobody") { return .clear }
        if set.contains("moving") || set.contains("motion") && !set.contains("sensor") { return .detected }
        if set.contains("running") || set.contains("run") || set.contains("watering") { return .running }
        if set.contains("enabled") { return .enabled }
        if set.contains("disabled") { return .disabled }
        if set.contains("away") || set.contains("gone") || set.contains("out") && !set.contains("outside") || set.contains("left") { return .away }
        if set.contains("home") || set.contains("here") { return .home }
        if set.contains("music"), !musicIsRoom, onPredicate("on") { return .playing }
        if onPredicate("off") { return .off }
        if onPredicate("on") { return .on }
        return nil
    }
}
