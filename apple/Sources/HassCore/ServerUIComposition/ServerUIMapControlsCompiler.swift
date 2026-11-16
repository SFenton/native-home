import Foundation

// MARK: - Compiling corner groups (`sh.surface-controls@1`)

extension ServerUICompositionCompiler {
    /// Decodes a map's `controls`, or `nil` when the document authors none (the map then draws the default derived from `locate`).
    ///
    /// The shape has checked the fields. Here are the checks it cannot hold: one group for each corner, unique ids across the surface, Locate
    /// once, a command the source knows, the navigation subset, no `visibleWhen` or `enabledWhen` on a map action or a source command (their
    /// state rules are the app's), and that `locate` states whether a Locate button is authored.
    mutating func mapControls(_ primitive: Cursor, locate: Bool) throws -> [ServerUIMapControlGroup]? {
        guard primitive.value["controls"] != nil else { return nil }
        require("surface-controls")
        var corners: Set<MapControlCorner> = []
        var ids: Set<String> = []
        var locates = 0
        var groups: [ServerUIMapControlGroup] = []
        for group in try primitive.field("controls").array() {
            let corner: MapControlCorner = try group.e("corner")
            if !corners.insert(corner).inserted { add(.duplicateID, group.path("corner")) }
            var buttons: [ServerUIMapControlButton] = []
            for item in try group.field("buttons").array() {
                let id = try item.s("id")
                if !ids.insert(id).inserted { add(.duplicateID, item.path("id")) }
                let action = try mapControlAction(item.field("action"), locates: &locates)
                // A map action and a source command have state rules of their own.
                if action.isOwnRules {
                    for key in ["visibleWhen", "enabledWhen"] where item.value[key] != nil { add(.invalidCombination, item.path(key)) }
                }
                var performs: ServerUICompositionDocument.Action = .back
                if case .perform(let intent) = action.value { performs = intent }
                let look = try disc(item, id: id, action: performs)
                let hint = try item.optionalString("hint")
                buttons.append(.init(id: id, hint: hint, action: action.value, look: look))
            }
            let axis: MapControlAxis = try group.e("axis")
            groups.append(.init(corner: corner, axis: axis, buttons: buttons))
        }
        if locate != ServerUIMapControls.hasLocate(groups) { add(.invalidCombination, primitive.path("locate")) }
        return groups
    }

    /// One button's action and whether its state rules are the app's.
    private mutating func mapControlAction(_ c: Cursor, locates: inout Int) throws -> (value: ServerUIMapControlAction, isOwnRules: Bool) {
        switch try c.s("type") {
        case "map":
            locates += 1
            if locates > 1 { add(.invalidCombination, c.pointer) }
            return (.locate, true)
        case "source-command":
            require("vacuum-controls")
            guard let kind = VacuumController.Action.Kind(rawValue: try c.s("command")) else {
                add(.invalidCombination, c.path("command"))
                return (.locate, true)
            }
            return (.sourceCommand(kind), true)
        case "call-service":
            return (.perform(try action(c)), false)
        default:
            let intent = try action(c)
            if case .present(_, _, let ifPresented) = intent, ifPresented != .reject { add(.invalidCombination, c.pointer) }
            return (.perform(intent), false)
        }
    }

    /// The checks on a map's buttons that need the vacuum source: Clean Area needs the source's area cleaning script.
    static func mapControlIssues(_ groups: [ServerUIMapControlGroup], descriptor: ServerUIVacuumDescriptor, at pointer: String) -> [ServerUICompositionError] {
        var issues: [ServerUICompositionError] = []
        for (g, group) in groups.enumerated() {
            for (b, button) in group.buttons.enumerated() where button.action == .sourceCommand(.cleanArea) && descriptor.areaCleaning == nil {
                issues.append(.init(.invalidCombination, "\(pointer)/controls/\(g)/buttons/\(b)/action/command"))
            }
        }
        return issues
    }
}
