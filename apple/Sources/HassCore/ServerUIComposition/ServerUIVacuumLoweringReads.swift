import Foundation

// MARK: - The generic parts one vacuum lowers to

extension ServerUIVacuumLowering {
    /// Builds the parts for the controls of one vacuum descriptor. Every entity it reads goes through ``Context/source(for:)``.
    struct Reads {
        let descriptor: ServerUIVacuumDescriptor
        let context: Context

        // MARK: Vocabulary

        /// The words the Vacuums page drew for a robot state (`VacuumFormat.state`); a state with no words reads as it came.
        static let robotWords = [("cleaning", "Cleaning"), ("docked", "Docked"), ("error", "Error"), ("idle", "Idle"),
                                 ("paused", "Paused"), ("returning", "Returning")]
        /// The error sensor's states that mean no error (`VacuumStatusResolver.clearErrorStates`, as the sensors spell them).
        static let clearIssues = ["", "none", "None", "no error", "No error", "No Error", "ok", "OK", "Ok", "unavailable", "unknown"]
        /// The states of a sensor that cannot be read.
        static let unreadable = ["unavailable", "unknown", ""]
        /// The states a start or pause can act in.
        static let startPauseStates = ["cleaning", "returning", "paused", "idle", "docked"]
        /// The states a dock command can act in.
        static let dockableStates = ["cleaning", "paused", "idle", "error"]
        /// The id of the saved style every lowered robot tile names.
        static let robotStyleId = "lowered.robot"
        /// The purple a robot's tile draws while it works: `ColorFamily.cleaning`'s fill (`HassCore` sits below the design layer, so it is
        /// mirrored here and a test keeps the two equal).
        static let robotPurple: UInt32 = 0x7A3FB0
        /// The glyph of an Auto-Clean row: `ColorFamily.cleaning`'s glyph in the dark appearance.
        static let cleaningGlyph = (red: 0xC8, green: 0x8C, blue: 0xFA)
        /// The same glyph in the light appearance (`ColorFamily.glyphLightRGB`).
        static let cleaningGlyphLight = (red: 0x9C, green: 0x6D, blue: 0xC3)
        /// The tile icon of a resting robot (docked, idle): `ColorFamily.cleaning`'s off glyph under tinted glass, the glyph mixed 88% with
        /// grey (`TileFinish.offGlyphKeep`, `ColorFamily.offGlyphRGB(_:keep:)`, read by `TileFaceInk.glyphToken` on an `.off` face). Dark `#C18CEE`,
        /// light `#8E6DAC`.
        static let tileGlyphTint = (dark: ServerUIRGB(red: 0xC1, green: 0x8C, blue: 0xEE), light: ServerUIRGB(red: 0x8E, green: 0x6D, blue: 0xAC))
        /// The button icons of a resting robot: the family's off glyph, the glyph mixed 72% with grey (`ColorFamily.offGlyphToken`, read by
        /// `TileActionInk.resolveTokens` on a `.dark` disc face, `TileActionInk.swift:28-33`). Dark `#B88DDD`, light `#8F6DAC`.
        static let discGlyphTint = (dark: ServerUIRGB(red: 0xB8, green: 0x8D, blue: 0xDD), light: ServerUIRGB(red: 0x8F, green: 0x6D, blue: 0xAC))
        /// How many robots sit across a row at least.
        static let robotsAcross = 2
        /// How long a shown value stands in for Home Assistant's answer (`VacuumController.optimisticRevert`).
        static let revert = 8.0

        var vacuum: String { descriptor.entityId }

        // MARK: Building blocks

        func symbol(_ name: String) -> D.Symbol { D.Symbol(name: name, rendering: .canonical, unavailable: .fallback) }
        func literal(_ text: String) -> ServerUIOperand { .literal(.string(text)) }
        func text(_ entityId: String) -> ServerUIOperand { .read(sourceId: context.source(for: entityId), path: ["state"], as: .string) }
        func number(_ entityId: String) -> ServerUIOperand { .read(sourceId: context.source(for: entityId), path: ["state"], as: .number) }
        /// The entity's state exactly as Home Assistant holds it, `unavailable` and `unknown` included (`sh.raw-state@1`).
        func raw(_ entityId: String) -> ServerUIOperand { .rawState(sourceId: context.source(for: entityId)) }
        func state(_ entityId: String, _ values: [String]) -> ServerUIPredicate {
            .state(sourceId: context.source(for: entityId), path: ["state"], values: values)
        }

        /// The entity's state drawn with `words`; an unavailable entity is unavailable, a state with no words reads as it came.
        func words(_ entityId: String, _ words: [(String, String)]) -> ServerUIOperand {
            .map(of: text(entityId), cases: words.map { .init(equals: .string($0.0), then: literal($0.1)) }, otherwise: text(entityId))
        }

        func call(_ domain: String, _ service: String, on entityId: String, showing value: String? = nil, failing: Bool = false) -> ServerUICallService {
            ServerUICallService(
                domain: domain, service: service, target: ["entity_id": literal(entityId)],
                optimistic: value.map { [.init(sourceId: context.source(for: entityId), value: $0, revertAfterSeconds: Self.revert, failsOnTimeout: failing)] } ?? [])
        }

        // MARK: Card

        /// The robot style every lowered card names: the built-in `robot`, with the purple the cleaning family draws on the states that are
        /// lit (cleaning, returning and paused). An error and an idle robot keep the class face. A paused robot is a resting, lit face, as
        /// the old tile drew it (the built-in class is a warning, whose amber ground wins over a fill).
        static var robotStyle: ServerUIStateStyleLibrary.Entry {
            let rules = StateStyle.robot.rules.map { rule -> StateRule in
                var rule = rule
                if rule.states.contains(where: { ["cleaning", "mowing", "paused", "returning"].contains($0) }) {
                    rule.fill = robotPurple
                    // The old family fill drew its state line white at 92% (`ColorFamily.secondaryInkToken`, `ColorFamily.swift:195`).
                    rule.fillInk = .soft
                }
                if rule.states == ["paused"] { rule.stateClass = .resting; rule.isActive = true }
                return rule
            }
            var style = StateStyle.robot.replacingRules(rules)
            style.id = robotStyleId
            return .init(style: style, base: StateStyle.robot.id)
        }

        func card(node: D.Node, icon: D.Symbol, commands: [D.VacuumCardCommand], destination: D.Action) -> D.StateTile {
            context.use(Self.robotStyle)
            let battery = number(descriptor.batteryEntityId)
            let label = words(vacuum, Self.robotWords)
            let issue = text(descriptor.errorEntityId)
            let args: [String: ServerUIOperand] = ["state": label, "battery": battery, "issue": issue]
            // The sensor's own words, every word capitalised as the old tile did (`sh.text-case-words@1`).
            let issueWords: [String: ServerUIFormatSpec] = ["issue": .text(.words)]
            let hasIssue = ServerUIPredicate.all([
                state(vacuum, ["error"]),
                .not(.in(value: raw(descriptor.errorEntityId), options: Self.clearIssues.map(literal)))
            ])
            let noBattery = ServerUIPredicate.in(value: raw(descriptor.batteryEntityId), options: Self.unreadable.map(literal))
            var parts = ServerUITileParts()
            parts.subtitle = .expression(.choose(cases: [
                .init(when: .all([hasIssue, noBattery]), then: .format(pattern: "{state} • {issue}", args: ["state": label, "issue": issue], formats: issueWords)),
                .init(when: hasIssue, then: .format(pattern: "{state} • {battery}% • {issue}", args: args, formats: issueWords))
            ], otherwise: .format(pattern: "{state} • {battery}%", args: ["state": label, "battery": battery], formats: [:])), fallback: nil)
            parts.progress = .choose(
                cases: [.init(when: state(vacuum, ["cleaning"]), then: .math(.divide, [battery, .literal(.number(100))]))],
                otherwise: .literal(.null))
            parts.discs = commands.map(disc)
            var look = ServerUITileLook()
            look.activeWhen = state(vacuum, ["cleaning", "returning", "paused"])
            look.errorWhen = state(vacuum, ["error"])
            // The tile ink (`sh.tile-ink@1`): the purple icon and button icons the old family tile drew, and the old tile's own height in the
            // equal-height row (it drew 72 pt at the top of a 112 pt cell, `UKServerUIVacuumView.swift:186-204`).
            var ink = ServerUITileInk()
            ink.glyphTint = .init(light: Self.tileGlyphTint.light, dark: Self.tileGlyphTint.dark)
            ink.discGlyphTint = .init(light: Self.discGlyphTint.light, dark: Self.discGlyphTint.dark)
            ink.cellFit = .natural
            ink.isDeclared = true
            var tile = D.StateTile(node: node, icon: icon, binding: .init(entityId: vacuum, styleId: Self.robotStyleId, builtIn: "robot", overrides: []),
                                   parts: parts, action: destination, look: look)
            tile.ink = ink
            return tile
        }

        /// The start and pause disc draws `pause.fill` and says Pause while the robot works, else `play.fill` and Resume (paused) or Start,
        /// and names the tile ("Start Main Floor"), as the old disc did (`sh.tile-disc-rules@1`).
        private func disc(_ command: D.VacuumCardCommand) -> ServerUITileParts.Disc {
            switch command {
            case .startPause:
                let rule = ServerUIActionRule(cases: [
                    .init(when: state(vacuum, ["cleaning", "returning"]),
                          then: .callService(call("vacuum", "pause", on: vacuum, showing: "paused"))),
                    .init(when: state(vacuum, ["paused", "idle", "docked"]),
                          then: .callService(call("vacuum", "start", on: vacuum, showing: "cleaning")))
                ], otherwise: nil)
                var disc = ServerUITileParts.Disc(
                    id: "start_pause", icon: symbol("play.fill"), label: "Start", action: .conditional(rule), visibility: nil,
                    enabledWhen: .init(condition: state(vacuum, Self.startPauseStates), whenUnknown: .disabled))
                disc.iconRule = .conditional([.init(when: state(vacuum, ["cleaning", "returning"]), then: symbol("pause.fill"))])
                disc.labelValue = .expression(.map(of: text(vacuum), cases: [
                    .init(equals: .string("cleaning"), then: literal("Pause")), .init(equals: .string("returning"), then: literal("Pause")),
                    .init(equals: .string("paused"), then: literal("Resume"))], otherwise: literal("Start")), fallback: "Start")
                disc.namesTile = true
                return disc
            case .dock:
                var disc = ServerUITileParts.Disc(
                    id: "dock", icon: symbol("house.fill"), label: "Dock",
                    action: .callService(call("vacuum", "return_to_base", on: vacuum)), visibility: nil,
                    enabledWhen: .init(condition: state(vacuum, Self.dockableStates), whenUnknown: .disabled))
                disc.namesTile = true
                return disc
            }
        }

        // MARK: Auto-clean

        /// An Auto-Clean room: included while its skip switch is off (the entity says "disabled", so it is inverted here and nowhere else).
        func autoCleanRoom(node: D.Node, entityId: String) -> D.BoundControl {
            let domain = String(entityId.prefix { $0 != "." })
            return D.BoundControl(
                node: node, icon: nil, kind: .toggle, surface: .tile, isOn: state(entityId, ["off"]), value: nil, range: nil, valueFormat: nil,
                options: [], onAction: call(domain, "turn_off", on: entityId, showing: "off", failing: true),
                offAction: call(domain, "turn_on", on: entityId, showing: "on", failing: true), action: nil, unavailableText: "Unavailable")
        }

        /// The Auto-Clean switch: an automation (on is enabled) or the coordinator's pause switch (off is enabled). Its row draws the clock
        /// glyph in the cleaning purple, "Enabled" or "Paused" under the title, and the words the old row said (`sh.bound-row-parts@1`).
        func autoCleanSwitch(node: D.Node, control: ServerUIVacuumDescriptor.AutoClean) -> D.BoundControl {
            let configuration = control.configuration
            let enabled = control.kind == .pause ? "off" : "on", disabled = control.kind == .pause ? "on" : "off"
            var result = D.BoundControl(
                node: node, icon: symbol("clock.arrow.circlepath"), kind: .toggle, surface: .row,
                isOn: state(control.entityId, [enabled]), value: nil, range: nil, valueFormat: nil, options: [],
                onAction: call(configuration.domain, "turn_\(enabled)", on: control.entityId, showing: enabled, failing: true),
                offAction: call(configuration.domain, "turn_\(disabled)", on: control.entityId, showing: disabled, failing: true),
                action: nil, unavailableText: "Unavailable")
            var row = ServerUIRowParts()
            let glyph = Self.cleaningGlyph
            let light = Self.cleaningGlyphLight
            row.glyph = .solidAppearance(light: ServerUIRGB(red: light.red, green: light.green, blue: light.blue),
                                         dark: ServerUIRGB(red: glyph.red, green: glyph.green, blue: glyph.blue))
            row.subtitle = .expression(.map(of: text(control.entityId), cases: [
                .init(equals: .string(enabled), then: literal("Enabled")), .init(equals: .string(disabled), then: literal("Paused"))],
                otherwise: literal("Unavailable")), fallback: "Unavailable")
            row.hint = "Turns automatic cleaning on or off."
            row.metrics = .module
            row.failureText = "Didn't Respond"
            result.row = row
            return result
        }
    }
}
