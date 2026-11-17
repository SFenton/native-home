import Foundation

// MARK: - Layout compilation (L3)

/// The compile steps of the layout capabilities: tab areas, the tab bar and the tab fallback, the overlay, a state tile's parts and
/// look, and badges. Each is called from one short hook in ``ServerUICompositionCompiler``; the issues, pointers and the
/// capability each part needs follow the Studio's `compiler.ts` (`tabParts`, `overlay`, `tileParts`, `badge`).
extension ServerUICompositionCompiler {
    // MARK: Span

    /// A node's `layout.span`: unset leaves the width to the grid, which reads as one column.
    func layoutSpan(_ c: Cursor) throws -> Int {
        let layout = try c.field("layout")
        return layout.value["span"] == nil ? 1 : try layout.i("span")
    }

    // MARK: Badges (`sh.badges@1`)

    /// Reads the node's `badge` and sets it on `node`. A badge that is `none` still needs the capability, and draws nothing.
    mutating func badge(of c: Cursor, into node: inout D.Node) throws {
        node.badgeValue = try badgeValue(in: c)
    }

    /// The operand of a `badge` field at `c`, or `nil` for none or no badge.
    /// - Parameter noneNeedsCapability: Whether `{type: none}` requires the capability (a chrome button's shipped `none` does not).
    mutating func badgeValue(in c: Cursor, noneNeedsCapability: Bool = true) throws -> ServerUIOperand? {
        guard c.value["badge"] != nil else { return nil }
        let badge = try c.field("badge")
        guard try badge.s("type") == "value" else {
            if noneNeedsCapability { require("badges") }
            return nil
        }
        require("badges")
        let value = try operand(badge.field("value"))
        // A badge is a number or text; a boolean or a structure is refused. An operand whose kind is not known here passes.
        if let kind = value.staticKind, kind != .string, kind != .number { add(.bindingType, badge.path("value")) }
        return value
    }

    // MARK: Tab container (`sh.tab-blocks@1`, `sh.tab-bar@1`, `sh.tab-fallback@1`)

    /// A tab's own `visibleWhen` (`sh.tab-blocks@1`).
    mutating func tabRule(_ tab: Cursor) throws -> ServerUIVisibility? {
        guard tab.value["visibleWhen"] != nil || tab.value["whenUnknown"] != nil else { return nil }
        require("tab-blocks")
        return try visibility(tab)
    }

    /// The parts of a tab container beyond its shipped tabs: the fallback tab, the bar's settings and the areas.
    /// - Parameters:
    ///   - c: The container node.
    ///   - props: The container's `props`.
    ///   - depth: The container's depth, so the areas' children compile one deeper.
    ///   - result: The container, whose tabs are already compiled.
    mutating func tabLayout(_ c: Cursor, props: Cursor, depth: Int, into result: inout D.LocalTabs) throws {
        let tabs = try c.field("tabs").array()
        let tabIds = result.tabs.map(\.id)
        if let fallback = try props.optionalString("fallbackTabId") {
            require("tab-fallback")
            if !tabIds.contains(fallback) { add(.invalidReference, props.path("fallbackTabId")) }
            result.fallbackTabId = fallback
        }
        if props.value["tabBar"] != nil {
            require("tab-bar")
            let bar = try props.field("tabBar")
            let setting = try ServerUITabBar(placement: bar.e("placement"), labels: bar.e("labels"))
            if setting.needsIcons {
                for (index, tab) in result.tabs.enumerated() where tab.icon == nil { add(.missingRequired, tabs[index].path("icon")) }
            }
            if setting.placement == .bottom && !result.pinned || setting.placement == .top && result.pinned {
                add(.invalidCombination, bar.path("placement"))
            }
            result.tabBar = setting
        }
        guard c.value["blocks"] != nil else { return }
        require("tab-blocks")
        for (index, tab) in tabs.enumerated() where result.tabs[index].children.isEmpty == false {
            add(.invalidCombination, tab.path("children"))
        }
        var covered: Set<String> = [], ids: Set<String> = []
        var areas: [ServerUITabArea] = []
        for block in try c.field("blocks").array() {
            let id = try block.s("id")
            if !ids.insert(id).inserted { add(.duplicateID, block.path("id")) }
            let scope: ServerUITabArea.Scope
            let named: [String]
            if block.value["tabs"] == .string("all") {
                scope = .all; named = tabIds
            } else {
                var seen: Set<String> = []
                named = try block.field("tabs").array().map { entry in
                    let tab = try entry.string()
                    if !tabIds.contains(tab) || !seen.insert(tab).inserted { add(.invalidReference, entry.pointer) }
                    return tab
                }
                scope = .tabs(named)
            }
            covered.formUnion(named)
            let rule = try visibility(block)
            let children = try block.field("children").array()
            if named.count != 1 {
                for child in children where ["form", "pinned-actions"].contains(try child.s("type")) { add(.invalidCombination, child.path("type")) }
            }
            areas.append(try ServerUITabArea(id: id, scope: scope, visibility: rule,
                                             children: components(block.field("children"), depth: depth + 1, gridChild: false)))
        }
        for (index, tab) in tabs.enumerated() where !covered.contains(result.tabs[index].id) { add(.invalidCombination, tab.pointer) }
        result.areas = areas
    }

    // MARK: Overlay (`sh.overlay@1`)

    /// An overlay: the base and up to four small controls at five anchors.
    mutating func overlay(_ c: Cursor, node: D.Node, props: Cursor, depth: Int) throws -> D.Component {
        require("overlay")
        let children = try c.field("children").array()
        if children.isEmpty { throw Issue(.missingRequired, c.path("children")) }
        let onTop = children.dropFirst()
        var anchored: Set<String> = []
        var anchors: [ServerUIOverlay.Placement] = []
        for entry in try props.field("anchors").array() {
            let childId = try entry.s("childId")
            if !onTop.contains(where: { $0.value["id"] == .string(childId) }) {
                add(.invalidReference, entry.path("childId"))
            } else if anchored.contains(childId) { add(.duplicateID, entry.path("childId")) }
            anchored.insert(childId)
            try anchors.append(.init(childId: childId, anchor: entry.e("anchor"), inset: space(entry.field("inset"))))
        }
        for (index, child) in children.enumerated() {
            let type = try child.s("type")
            if type == "overlay" { add(.invalidCombination, child.path("type")) }
            guard index > 0 else { continue }
            if !anchored.contains(try child.s("id")) { add(.missingRequired, props.path("anchors")) }
            let isButton = type == "bound-control" && child.value["props"]?["kind"] == .string("button")
            if !(isButton || ["primary-button", "status-pill", "text"].contains(type)) { add(.invalidCombination, child.path("type")) }
        }
        return try .overlay(.init(node: node, anchors: anchors, children: components(c.field("children"), depth: depth + 1, gridChild: false)))
    }

    // MARK: State tile parts and look (`sh.tile-parts@1`, `sh.tile-look@1`)

    /// Reads a state tile's subtitle, progress, buttons, destination and the three face conditions into `tile`.
    mutating func tileParts(_ c: Cursor, props: Cursor, into tile: inout D.StateTile) throws {
        var parts = ServerUITileParts()
        if props.value["subtitle"] != nil { parts.subtitle = try stringValue(props.field("subtitle")) }
        if props.value["progress"] != nil {
            let value = try operand(props.field("progress"))
            if let kind = value.staticKind, kind != .number { add(.bindingType, props.path("progress")) }
            parts.progress = value
        }
        if props.value["discs"] != nil {
            var ids: Set<String> = []
            for disc in try props.field("discs").array() {
                let id = try disc.s("id")
                if !ids.insert(id).inserted { add(.duplicateID, disc.path("id")) }
                let action = try disc.field("action")
                if try action.s("type") == "domain" { add(.invalidCombination, action.path("type")) }
                let compiled = try self.action(action)
                try parts.discs.append(self.disc(disc, id: id, action: compiled))
            }
        }
        if props.value["subtitle"] != nil || props.value["progress"] != nil || props.value["discs"] != nil || c.value["action"] != nil {
            require("tile-parts")
        }
        tile.parts = parts
        if c.value["action"] != nil { tile.action = try navigationAction(c.field("action")) }
        var look = ServerUITileLook()
        for face in ["activeWhen", "filledWhen", "errorWhen"] where c.value[face] != nil {
            require("tile-look")
            let rule = try predicate(c.field(face))
            switch face {
            case "activeWhen": look.activeWhen = rule
            case "filledWhen": look.filledWhen = rule
            default: look.errorWhen = rule
            }
        }
        tile.look = look
    }

    // MARK: State tile ink (`sh.tile-ink@1`)

    /// Reads a state tile's `glyphTint`, `discGlyphTint` and `cellFit`; the shape check has already made each exact.
    func tileInk(_ c: Cursor) -> ServerUITileInk {
        func tint(_ field: String) -> ServerUITileInk.Tint? {
            guard let json = c.value[field] else { return nil }
            if json["type"] == .string("solid-appearance") {
                guard let light = json["light"].flatMap(ServerUIRuleDecoder.channels),
                      let dark = json["dark"].flatMap(ServerUIRuleDecoder.channels) else { return nil }
                return .init(light: light, dark: dark)
            }
            return ServerUIRuleDecoder.channels(json).map { .init(light: $0, dark: $0) }
        }
        var ink = ServerUITileInk()
        ink.glyphTint = tint("glyphTint")
        ink.discGlyphTint = tint("discGlyphTint")
        ink.cellFit = c.value["cellFit"]?.string.flatMap(ServerUITileInk.CellFit.init(rawValue:)) ?? .fill
        ink.isDeclared = ["glyphTint", "discGlyphTint", "cellFit"].contains { c.value[$0] != nil }
        return ink
    }
}
