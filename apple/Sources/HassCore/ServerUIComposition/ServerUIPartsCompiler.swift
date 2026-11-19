import Foundation

// MARK: - Generic part compilation (TC3)

/// The compile steps of the five generic part capabilities. Each is called from one short hook in ``ServerUICompositionCompiler``;
/// the issues, pointers and the capability each part needs follow the Studio's `compiler.ts` (`boundRow`, `tileParts`, `tile-grid`).
extension ServerUICompositionCompiler {
    // MARK: Choice options read from an entity (`sh.bound-options-read@1`)

    /// A bound choice's `optionsFrom`; `nil` when there is none.
    ///
    /// Needs `sh.list-read@1` and `sh.bindings@1` as well, since the list is read from an entity attribute.
    mutating func optionsFrom(_ props: Cursor, kind: D.BoundControl.Kind) throws -> ServerUIOptionsRead? {
        guard props.value["optionsFrom"] != nil else { return nil }
        let read = try props.field("optionsFrom")
        require("bound-options-read"); require("list-read"); require("bindings")
        if kind != .choice { add(.invalidCombination, read.pointer) }
        let from = try read.field("from")
        let sourceId = try from.s("sourceId")
        let path = try from.field("path").array().map { try $0.string() }
        expressionRefs.append(.init(sourceId: sourceId, path: path, pointer: read.pointer, kind: nil, access: .list))
        // The chosen item is the one value `control` stands for, so only the call may use it; `current` reads the entity.
        let outer = controlContext
        defer { controlContext = outer }
        controlContext = false
        let current = try operand(read.field("current"))
        if let shown = current.staticKind, shown != .string { add(.bindingType, read.path("current")) }
        controlContext = true
        let action = try callService(read.field("action"))
        return ServerUIOptionsRead(sourceId: sourceId, path: path, current: current, labels: try read.e("labels"), action: action)
    }

    // MARK: A toggle row's parts and face (`sh.bound-row-parts@1`, `sh.check-face@1`)

    /// A bound control's row parts and face. The parts are for a toggle drawn as a row; a check face keeps only the hint, the failure
    /// caption and its tint.
    mutating func rowParts(_ c: Cursor, props: Cursor, kind: D.BoundControl.Kind, surface: D.BoundControl.Surface) throws -> ServerUIRowParts {
        var parts = ServerUIRowParts()
        let asRow = kind == .toggle && surface == .row
        let check = props.value["face"] == .string("check")
        for key in ["subtitle", "hint", "metrics", "failureText", "glyph"] where props.value[key] != nil {
            require("bound-row-parts")
            if !asRow || (check && key != "hint" && key != "failureText") { add(.invalidCombination, props.path(key)) }
        }
        if props.value["subtitle"] != nil { parts.subtitle = try stringValue(props.field("subtitle")) }
        parts.hint = try props.optionalString("hint")
        parts.failureText = try props.optionalString("failureText")
        if props.value["metrics"] != nil { parts.metrics = try props.e("metrics") }
        if props.value["glyph"] != nil {
            var rules = ServerUIRuleDecoder(scope: repeatScope)
            let slot = try rules.fill(props.field("glyph").value, at: props.path("glyph"))
            try absorb(rules)
            guard let slot else { throw Issue(.invalidValue, props.path("glyph")) }
            (parts.glyph, parts.glyphRule) = slot
            if c.value["icon"] == nil { add(.invalidCombination, props.path("glyph")) }
        }
        if props.value["face"] != nil {
            require("check-face")
            parts.face = try props.e("face")
            if !asRow { add(.invalidCombination, props.path("face")) }
            if check, c.value["icon"] != nil { add(.invalidCombination, c.path("icon")) }
        }
        if props.value["checkTint"] != nil {
            require("check-face")
            parts.checkTint = try props.e("checkTint")
            if !check { add(.invalidCombination, props.path("checkTint")) }
        }
        return parts
    }

    // MARK: A tile button that follows a rule (`sh.tile-disc-rules@1`)

    /// One disc of a state tile: its symbol and label, each plain or following a rule, and whether it names the tile.
    mutating func disc(_ disc: Cursor, id: String, action: D.Action) throws -> ServerUITileParts.Disc {
        var rules = ServerUIRuleDecoder(scope: repeatScope)
        let icon = try rules.symbol(disc.field("icon").value, at: disc.path("icon"))
        try absorb(rules)
        guard let icon else { throw Issue(.invalidValue, disc.path("icon")) }
        let labelCursor = try disc.field("label")
        var label = ""
        var labelValue: D.StringValue?
        if case .string(let text) = labelCursor.value {
            label = text
        } else {
            let value = try stringValue(labelCursor)
            labelValue = value
            if case .literal(let text) = value { label = text }
            if case .read(_, let fallback, _) = value { label = fallback ?? "" }
            if case .expression(_, let fallback, _) = value { label = fallback ?? "" }
        }
        let names = disc.value["namesTile"] != nil
        if icon.1 != nil || labelValue != nil || names { require("tile-disc-rules") }
        var result = try ServerUITileParts.Disc(id: id, icon: icon.0, label: label, action: action, visibility: visibility(disc),
                                                enabledWhen: enabled(disc))
        result.iconRule = icon.1
        result.labelValue = labelValue
        result.namesTile = try names ? disc.b("namesTile") : false
        return result
    }

    // MARK: A grid's least columns (`sh.grid-min-columns@1`)

    /// A tile grid's `minimumColumns`, at most its `maxColumns`.
    mutating func minimumColumns(_ props: Cursor) throws -> Int? {
        guard props.value["minimumColumns"] != nil else { return nil }
        require("grid-min-columns")
        let least = try props.i("minimumColumns")
        if least > (try props.i("maxColumns")) { add(.invalidValue, props.path("minimumColumns")) }
        return least
    }
}
