import Foundation

// MARK: - Compiling the style parts

/// The compile steps of the four style capabilities, following the Studio's `compiler.ts` (`stack`, the `text` case, `symbol`, local
/// choice options): which ids each field needs, and the checks the closed shape cannot hold.
extension ServerUICompositionCompiler {
    // MARK: Ink

    private func rgb(_ c: Cursor) throws -> ServerUIRGB {
        try .init(red: c.i("red"), green: c.i("green"), blue: c.i("blue"))
    }

    private func inkColor(_ c: Cursor) throws -> ServerUIInk.Color {
        switch try c.s("type") {
        case "rgba": return try .init(rgb: rgb(c), alpha: c.n("alpha"))
        default: return try .init(rgb: rgb(c))
        }
    }

    /// A colour of a slot `sh.text-style@1` adds: one exact colour with or without opacity, or one for each appearance.
    func ink(_ c: Cursor) throws -> ServerUIInk {
        if try c.s("type") == "solid-appearance" {
            return try .init(light: inkColor(c.field("light")), dark: inkColor(c.field("dark")))
        }
        return try .init(inkColor(c))
    }

    // MARK: Text

    /// The look fields of a text and the ids they need (`sh.text-style@1`): a style the older six do not name, or any of `font`, `ink`,
    /// `lines`, `align` and `overflow`, even an empty `font`.
    mutating func textLook(_ props: Cursor, style: D.TextStyle) throws -> ServerUITextLook {
        var look = ServerUITextLook()
        let declared = ["font", "ink", "lines", "align", "overflow"].contains { props.value[$0] != nil }
        if style.needsTextStyle || declared { require("text-style") }
        guard declared else { return look }
        look.isDeclared = true
        if props.value["font"] != nil {
            let font = try props.field("font")
            look.weight = try font.value["weight"] == nil ? nil : font.e("weight")
            look.digits = try font.value["digits"] == nil ? nil : font.e("digits")
            if font.value["scale"] != nil {
                let scale = try font.field("scale")
                let points = try scale.n("points")
                let cap = try scale.value["maxPoints"] == nil ? nil : scale.n("maxPoints")
                if let cap, cap < points { add(.invalidValue, scale.path("maxPoints")) }
                look.scale = try .init(points: points, relativeTo: scale.e("relativeTo"), maxPoints: cap)
            }
        }
        if props.value["ink"] != nil { look.ink = try ink(props.field("ink")) }
        if props.value["lines"] != nil { look.lines = try props.i("lines") }
        look.align = try props.value["align"] == nil ? nil : props.e("align")
        look.overflow = try props.value["overflow"] == nil ? nil : props.e("overflow")
        // A ticker slides one line.
        if look.overflow == .ticker, look.lines != 1 { add(.invalidCombination, props.path("overflow")) }
        return look
    }

    // MARK: Stack

    /// A `stack`: children in a row or a column.
    ///
    /// Its `groups` (and the collapsed arrangement's) must hold every direct child exactly once, by id. A collapse is for a horizontal
    /// stack, and `fits` names direct children and means something only with the `overflow` trigger. A stack with an action is one
    /// accessibility element (a button), so it names it and holds nothing that takes a tap of its own.
    mutating func stackComponent(_ c: Cursor, node: D.Node, props: Cursor, depth: Int) throws -> D.Component {
        require("stack"); require("text-style")
        let ids = Set(try c.field("children").array().compactMap { try? $0.s("id") })
        let children = try components(c.field("children"), depth: depth + 1, gridChild: false)
        var value = try ServerUIStack(node: node, axis: props.e("axis"), spacing: space(props.field("spacing")), children: children)
        if props.value["padding"] != nil {
            let pad = try props.field("padding")
            value.padding = try .init(top: space(pad.field("top")), leading: space(pad.field("leading")),
                                      bottom: space(pad.field("bottom")), trailing: space(pad.field("trailing")))
        }
        value.align = try props.value["align"] == nil ? .start : props.e("align")
        value.distribution = try props.value["distribution"] == nil ? .natural : props.e("distribution")
        if props.value["groups"] != nil { value.groups = try stackGroups(props.field("groups"), ids: ids) }
        if props.value["collapse"] != nil {
            let collapse = try props.field("collapse")
            if value.axis != .horizontal { add(.invalidCombination, collapse.pointer) }
            let when: [ServerUIStack.Trigger] = try collapse.field("when").array().map { try $0.enumeration() }
            if Set(when).count != when.count { add(.invalidValue, collapse.path("when")) }
            var fits: [String] = []
            if collapse.value["fits"] != nil {
                for item in try collapse.field("fits").array() {
                    let named = try item.string()
                    if !ids.contains(named) { add(.invalidReference, item.pointer) }
                    fits.append(named)
                }
                if !fits.isEmpty, !when.contains(.overflow) { add(.invalidCombination, collapse.path("fits")) }
            }
            var rule = try ServerUIStack.Collapse(when: when, fits: fits,
                                                  spacing: collapse.value["spacing"] == nil ? nil : space(collapse.field("spacing")))
            if collapse.value["groups"] != nil { rule.groups = try stackGroups(collapse.field("groups"), ids: ids) }
            value.collapse = rule
        }
        if props.value["dividers"] != nil { value.dividers = try line(props.field("dividers")) }
        if props.value["surface"] != nil { value.surface = try stackSurface(props.field("surface")) }
        try stackAccessibility(c, into: &value)
        return .stack(value)
    }

    /// The groups of a stack, each child named once. Blames a name that is not a direct child, a repeat, and the list when a child is left out.
    private mutating func stackGroups(_ list: Cursor, ids: Set<String>) throws -> [ServerUIStack.Group] {
        var seen: Set<String> = []
        var groups: [ServerUIStack.Group] = []
        for item in try list.array() {
            var members: [String] = []
            for child in try item.field("children").array() {
                let named = try child.string()
                if !ids.contains(named) { add(.invalidReference, child.pointer) }
                else if seen.contains(named) { add(.duplicateID, child.pointer) }
                seen.insert(named)
                members.append(named)
            }
            groups.append(try .init(
                children: members, spacing: item.value["spacing"] == nil ? nil : space(item.field("spacing")),
                distribution: item.value["distribution"] == nil ? .natural : item.e("distribution"),
                align: item.value["align"] == nil ? .start : item.e("align"),
                grow: item.value["grow"] == nil ? false : item.b("grow")))
        }
        if ids.contains(where: { !seen.contains($0) }) { add(.missingRequired, list.pointer) }
        return groups
    }

    private func line(_ c: Cursor) throws -> ServerUIStack.Line { try .init(ink: ink(c.field("ink")), width: c.n("width")) }

    private func stackSurface(_ c: Cursor) throws -> ServerUIStack.Surface {
        if try c.s("type") == "module" { return try .module(density: c.e("density")) }
        var radius: Double?
        if c.value["radius"] != nil {
            let item = try c.field("radius")
            if try item.s("type") == "points" { radius = try item.n("value") }
        }
        return try .fill(ink(c.field("fill")), border: c.value["border"] == nil ? nil : line(c.field("border")), radius: radius)
    }

    /// A stack's `a11y` and `action`: what each word means with the other, and that nothing inside takes a tap of its own.
    private mutating func stackAccessibility(_ c: Cursor, into value: inout ServerUIStack) throws {
        if c.value["a11y"] != nil {
            let a11y = try c.field("a11y")
            let element: ServerUIStack.Accessibility.Element = try a11y.e("element")
            for key in ["role", "label", "value", "hint"] where element != .group && a11y.value[key] != nil {
                add(.invalidCombination, a11y.path(key))
            }
            var description = ServerUIStack.Accessibility(element: element)
            description.role = try a11y.value["role"] == nil ? nil : a11y.e("role")
            description.label = try a11y.value["label"] == nil ? nil : stringValue(a11y.field("label"))
            description.value = try a11y.value["value"] == nil ? nil : stringValue(a11y.field("value"))
            description.hint = try a11y.optionalString("hint")
            if description.role == .button, c.value["action"] == nil { add(.invalidCombination, a11y.path("role")) }
            if c.value["action"] != nil, let role = description.role, role != .button { add(.invalidCombination, a11y.path("role")) }
            value.accessibility = description
        }
        guard c.value["action"] != nil else { return }
        if value.accessibility == nil { add(.missingRequired, c.path("a11y")) }
        else if value.accessibility?.element != .group { add(.invalidCombination, c.path("a11y") + "/element") }
        // The descendants that take a tap are refused by ``ServerUIStackTapCheck``, which reads the document as written.
        value.action = try action(c.field("action"))
    }

    // MARK: Shape and symbol

    /// A `shape`: a capsule, a rectangle or a circle of one colour. Decoration, so it has no accessibility field.
    mutating func shapeComponent(_ node: D.Node, props: Cursor) throws -> D.Component {
        require("stack"); require("text-style")
        return try .shape(.init(node: node, form: props.e("form"), width: props.n("width"), height: props.n("height"), fill: ink(props.field("fill"))))
    }

    /// A `symbol`: a symbol drawn on its own (`sh.symbol-part@1`).
    mutating func symbolComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component {
        require("symbol-part"); require("text-style")
        var rules = ServerUIRuleDecoder()
        let name = try rules.symbol(props.field("name").value, at: props.path("name"))
        try absorb(rules)
        guard let name else { throw Issue(.invalidValue, props.path("name")) }
        let size = try props.field("size")
        let relativeTo: ServerUITextSize? = try size.value["relativeTo"] == nil ? nil : size.e("relativeTo")
        let maxScale = try size.value["maxScale"] == nil ? nil : size.n("maxScale")
        if maxScale != nil, relativeTo == nil { add(.invalidCombination, size.path("maxScale")) }
        let rendering: ServerUISymbolPart.Rendering = try props.e("rendering")
        let a11y = try c.field("a11y")
        let drawn: ServerUISymbolPart.Accessibility = try a11y.s("element") == "image" ? .image(label: stringValue(a11y.field("label"))) : .hidden
        var part = try ServerUISymbolPart(node: node, symbol: name.0, size: .init(points: size.n("points"), relativeTo: relativeTo, maxScale: maxScale),
                                          rendering: rendering, accessibility: drawn)
        part.rule = name.1
        // A multicolor symbol draws its own colours: a tint is for a monochrome one.
        if props.value["tint"] != nil {
            if rendering == .multicolor { add(.invalidCombination, props.path("tint")) }
            part.tint = try ink(props.field("tint"))
        }
        part.trim = try props.value["trim"] == nil ? .none : props.e("trim")
        if props.value["rotate"] != nil {
            let turn = try operand(props.field("rotate"))
            if let kind = turn.staticKind, kind != .number { add(.bindingType, props.path("rotate")) }
            part.rotate = turn
        }
        return .symbol(part)
    }

    // MARK: Choice options

    /// The options of a local choice, with the symbol and hint of a segmented one (`sh.choice-icons@1`): all options carry a symbol or none do.
    mutating func choiceOptions(_ list: Cursor) throws -> [D.LocalField.Option] {
        var options: [D.LocalField.Option] = []
        for item in try list.array() {
            var option = try D.LocalField.Option(id: item.s("id"), label: item.s("label"))
            if item.value["symbol"] != nil { option.symbol = try symbol(item.field("symbol")) }
            option.hint = try item.optionalString("hint")
            options.append(option)
        }
        if options.contains(where: { $0.symbol != nil || $0.hint != nil }) { require("choice-icons") }
        if options.contains(where: { $0.symbol != nil }), let bare = options.firstIndex(where: { $0.symbol == nil }) {
            add(.invalidCombination, list.pointer + "/\(bare)")
        }
        return options
    }
}
