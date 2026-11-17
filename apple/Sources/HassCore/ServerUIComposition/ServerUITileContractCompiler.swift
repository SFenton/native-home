import Foundation

// MARK: - Compiling swipe, words and groups

/// The words of room overviews, held until the sources are known: their keys follow the source's projection.
struct ServerUITileContractRefs {
    var overviewWords: [(sourceId: String, words: ServerUIStateWords, pointer: String)] = []
}

extension ServerUICompositionCompiler {
    /// Decodes `props.swipe` of a tile, or `nil` when the document authors none.
    ///
    /// The shape has checked the fields. Here are the checks it cannot hold: the range, the detent, the fields one tile type owns, a `value` that
    /// is a number, a call that uses `control` and does not ask first.
    mutating func tileSwipe(_ props: Cursor, tile: ServerUITileSwipe.Tile) throws -> ServerUITileSwipe? {
        guard props.value["swipe"] != nil else { return nil }
        let c = try props.field("swipe")
        require("tile-swipe")
        let range = try c.field("range")
        var swipe = try ServerUITileSwipe(range: .init(min: range.n("min"), max: range.n("max"), step: range.n("step")))
        swipe.authoredDetent = try c.value["detent"].map { _ in try c.n("detent") }
        swipe.format = try c.optionalString("format")
        swipe.label = try c.optionalString("label")
        if c.value["haptic"] != nil { swipe.haptic = try c.e("haptic") }
        if c.value["band"] != nil { swipe.showsBand = try c.b("band") }
        let present = Set(["value", "action", "format", "label"].filter { c.value[$0] != nil })
        for problem in ServerUITileSwipe.problems(range: swipe.range, detent: swipe.authoredDetent, format: swipe.format, present: present, tile: tile) {
            add(problem.code, c.pointer + problem.at)
        }
        if c.value["value"] != nil {
            let operand = try operand(c.field("value"))
            if let kind = operand.staticKind, kind != .number { add(.bindingType, c.path("value")) }
            swipe.value = operand
        }
        if c.value["action"] != nil {
            let outer = controlContext
            controlContext = true
            defer { controlContext = outer }
            let call = try callService(c.field("action"))
            let usesControl = call.data.values.contains(where: \.usesControl) || call.target.values.contains(where: \.usesControl)
            if !usesControl { add(.invalidCombination, c.path("action")) }
            if case .additional = call.confirmation { add(.invalidCombination, c.path("action") + "/confirmation") }
            swipe.action = call
        }
        return swipe
    }

    /// Decodes `props.words`, or `nil`. The keys the tile draws are `allowed`; a room overview's are checked once its source is known (pass `nil`).
    mutating func stateWords(_ props: Cursor, allowed: Set<ServerUIStateWords.Key>?) throws -> ServerUIStateWords? {
        guard props.value["words"] != nil else { return nil }
        let c = try props.field("words")
        require("state-words")
        var words = ServerUIStateWords()
        words.on = try c.optionalString("on")
        words.off = try c.optionalString("off")
        words.unavailable = try c.optionalString("unavailable")
        words.count = try c.optionalString("count")
        words.level = try c.optionalString("level")
        if let allowed {
            for problem in words.problems(allowed: allowed) { add(problem.code, c.path(problem.key.rawValue)) }
        }
        return words
    }

    /// Decodes a grid's `groups`, or `nil`.
    mutating func gridGroups(_ props: Cursor) throws -> ServerUIGridGroups? {
        guard props.value["groups"] != nil else { return nil }
        let c = try props.field("groups")
        require("grid-state-groups")
        let items = try c.field("items").array().map { item in
            ServerUIGridGroups.Group(id: try item.s("id"), title: try item.s("title"),
                                     states: try item.field("states").array().map { try $0.enumeration() })
        }
        for problem in ServerUIGridGroups.problems(items.map { ($0.id, $0.states) }) { add(problem.code, c.pointer + problem.at) }
        return .init(items: items)
    }

    /// Checks each room overview's words against its source's projection, after every source is known.
    mutating func checkOverviewWords(_ document: ServerUICompositionDocument) {
        let sources = Dictionary(document.dataSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for ref in tileContract.overviewWords {
            guard case .homeStatus(_, let status)? = sources[ref.sourceId] else { continue }
            for problem in ref.words.problems(allowed: ServerUIStateWords.overviewKeys(projection: status.projection.rawValue)) {
                add(problem.code, ServerUICompositionJSON.pointer(ref.pointer, problem.key.rawValue))
            }
        }
    }
}
