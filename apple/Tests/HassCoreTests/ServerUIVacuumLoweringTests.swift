import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - The oracle: what the vacuum atoms drew before they were lowered

/// The Vacuums page's tile face, as the old page format and `VacuumFormat.tileSubtitle` drew it before the card was lowered.
/// Kept here, frozen, as the reference the lowered tile is checked against (the two functions are deleted).
private struct OldCardFace: Equatable {
    var subtitle: String
    var isActive: Bool
    var isError: Bool
    var progress: Double?

    init(state: String?, battery: String?, error: String?) {
        let visual = VacuumVisual.state(state)
        isError = visual.tone == .danger
        var text = Self.subtitle(state: state, battery: battery)
        let issue = VacuumStatusResolver.nativeIssue(error)
        if isError, issue.status == .present, let code = issue.code, !code.isEmpty { text += " • \(StateText.titleCase(code))" }
        subtitle = text
        isActive = [.active, .returning, .warning].contains(visual.tone)
        let level = battery.flatMap { Double($0.trimmed) }.map { min(max($0 / 100, 0), 1) }
        progress = state?.trimmed.lowercased() == "cleaning" ? level : nil
    }

    /// `Docked • 87%` (`VacuumFormat.tileSubtitle`).
    private static func subtitle(state: String?, battery: String?) -> String {
        let normalized = state?.trimmed.lowercased() ?? ""
        let label = StateText.titleCase(normalized.isEmpty ? "unavailable" : normalized)
        guard !VacuumStatusResolver.isUnavailable(normalized), let battery = battery?.trimmed, let value = Double(battery) else { return label }
        let shown = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(label) • \(shown)%"
    }
}

private typealias F = VacuumLoweringFixture
private typealias D = ServerUICompositionDocument

private let robotStates: [String?] = ["docked", "cleaning", "returning", "paused", "idle", "error", "unavailable", "unknown", nil]

private func table(_ vacuum: String?, battery: String? = "87", error: String? = "No error", flag: String? = "none",
                   dock: String? = "idle") -> VacuumStateTable {
    var states: [String: String] = [:]
    for (entity, value) in [(F.vacuum, vacuum), (F.battery, battery), (F.error, error), (F.flag, flag), (F.dock, dock)] {
        if let value { states[entity] = value }
    }
    return VacuumStateTable(states: states)
}

// MARK: - Card

@Suite struct ServerUIVacuumCardLoweringTests {
    private func tile() throws -> D.StateTile {
        let component = try F.component(["kind": "card", "icon": F.icon, "commands": ["start_pause", "dock"], "destination": F.destination])
        guard case .stateTile(let tile) = component else { Issue.record("a card lowers to a state tile, got \(component)"); throw CancellationError() }
        return tile
    }

    @Test func aCardIsAStateTileWithPartsAndLook() throws {
        let tile = try tile()
        #expect(tile.node.id == "robot-control" && tile.node.title == "Configured Robot")
        #expect(tile.binding.entityId == F.vacuum && tile.binding.builtIn == "robot" && tile.binding.styleId == "lowered.robot")
        #expect(tile.parts.discs.map(\.id) == ["start_pause", "dock"])
        #expect(tile.parts.subtitle != nil && tile.parts.progress != nil)
        #expect(tile.look.activeWhen != nil && tile.look.errorWhen != nil && tile.look.filledWhen == nil)
        guard case .push(let push)? = tile.action else { Issue.record("the card opens its destination"); return }
        #expect(push.pageId == "page-echo")
    }

    @Test func theCommandsKeepTheirOrderAndOnlyThoseAsked() throws {
        let component = try F.component(["kind": "card", "icon": F.icon, "commands": ["dock"], "destination": F.destination])
        guard case .stateTile(let tile) = component else { Issue.record("not a state tile"); return }
        #expect(tile.parts.discs.map(\.id) == ["dock"])
    }

    @Test func theLoweredFaceEqualsTheOldFaceInEveryState() throws {
        let tile = try tile()
        var compared = 0
        for state in robotStates {
            for battery in ["87", "12.5", "100", "unavailable"] {
                for error in ["No error", "Wheel stuck", "unavailable"] {
                    let read = table(state, battery: battery, error: error)
                    let available = !EntityState.isUnavailable(state)
                    let batteryArgument = available && !EntityState.isUnavailable(battery) ? battery : "Unknown"
                    let old = OldCardFace(state: state, battery: batteryArgument, error: error)

                    // The subtitle: the document's text, or (while it has none) the style's own words, as the tile draws them.
                    let entity = state.map { EntityState(entityId: F.vacuum, state: $0) }
                    let words = StateStyle.robot.resolve(entity, entityId: F.vacuum).words
                    let drawn = tile.parts.subtitle.flatMap(read.text) ?? words
                    let label = "\(state ?? "-") \(battery) \(error)"
                    let batteryGone = EntityState.isUnavailable(battery)
                    #expect(drawn == old.subtitle, "\(label)")

                    let faces = ServerUILayoutRules.faces(tile.look, in: read)
                    #expect((faces.active ?? false) == old.isActive, "active \(state ?? "-")")
                    #expect((faces.error ?? false) == old.isError, "error \(state ?? "-")")
                    #expect(ServerUILayoutRules.progress(tile.parts.progress, in: read) == old.progress, "progress \(state ?? "-") \(battery)")
                    compared += 1
                }
            }
        }
        #expect(compared == robotStates.count * 12)
    }

    @Test func theLoweredDiscsEqualTheOldProvidersInEveryState() throws {
        let tile = try tile()
        for state in robotStates {
            let read = table(state)
            let entity = state.map { EntityState(entityId: F.vacuum, state: $0) }
            let old = VacuumActions(entityId: F.vacuum).actions(for: entity)
            for disc in tile.parts.discs {
                let spec = try #require(old.first { $0.id == disc.id })
                let enabled = ServerUIEnabledRule.allows(disc.enabledWhen, previous: nil, in: read)
                #expect(enabled == (spec.phase == .ready), "\(disc.id) in \(state ?? "-")")
                guard enabled else { continue }
                guard case .callService(let call)? = disc.action.resolved(read) else { Issue.record("\(disc.id) runs a service in \(state ?? "-")"); continue }
                #expect(call.domain == spec.call?.domain && call.service == spec.call?.service, "\(disc.id) in \(state ?? "-")")
                #expect(call.target["entity_id"] == .literal(.string(F.vacuum)))
                #expect(call.optimistic.map(\.value) == spec.optimistic.map(\.value), "\(disc.id) shows what the old disc showed in \(state ?? "-")")
            }
        }
    }
}

// MARK: - The generic parts keep the old look

@MainActor
@Suite struct ServerUIVacuumLookLoweringTests {
    private func tile() throws -> D.StateTile {
        guard case .stateTile(let tile) = try F.component(["kind": "card", "icon": F.icon, "commands": ["start_pause", "dock"], "destination": F.destination]) else {
            Issue.record("not a state tile"); throw CancellationError()
        }
        return tile
    }

    @Test func theRobotTileIsPurpleWhileItWorksAndNotOtherwise() throws {
        let publication = try F.publication(primitive: ["kind": "card", "icon": F.icon, "commands": ["start_pause"], "destination": F.destination])
        let style = try #require(publication.document.stateStyles?.style(id: "lowered.robot"))
        for state in ["cleaning", "returning", "paused"] {
            #expect(style.resolve(EntityState(entityId: F.vacuum, state: state), entityId: F.vacuum).fill == 0x7A3FB0, "\(state)")
        }
        for state in ["docked", "idle", "error", "unavailable"] {
            #expect(style.resolve(EntityState(entityId: F.vacuum, state: state), entityId: F.vacuum).fill == nil, "\(state)")
        }
    }

    @Test func theCardKeepsTheOldFamilyInkHeightAndStateLine() throws {
        let card = try tile()
        #expect(card.ink.isDeclared && card.ink.cellFit == .natural, "the old tile drew 72 pt at the top of a 112 pt cell")
        #expect(card.ink.glyphTint?.packed(isDark: true) == 0xC18CEE && card.ink.glyphTint?.packed(isDark: false) == 0x8E6DAC)
        #expect(card.ink.discGlyphTint?.packed(isDark: true) == 0xB88DDD && card.ink.discGlyphTint?.packed(isDark: false) == 0x8F6DAC)
        let publication = try F.publication(primitive: ["kind": "card", "icon": F.icon, "commands": ["start_pause"], "destination": F.destination])
        let style = try #require(publication.document.stateStyles?.style(id: "lowered.robot"))
        for state in ["cleaning", "returning", "paused"] {
            #expect(style.resolve(EntityState(entityId: F.vacuum, state: state), entityId: F.vacuum).fillInk == .soft, "\(state)")
        }
        #expect(style.resolve(EntityState(entityId: F.vacuum, state: "docked"), entityId: F.vacuum).fillInk == .white, "no fill: the default ink, which is never drawn")
    }

    @Test func aPausedRobotIsALitRestingFaceNotAWarning() throws {
        let publication = try F.publication(primitive: ["kind": "card", "icon": F.icon, "commands": ["start_pause"], "destination": F.destination])
        let style = try #require(publication.document.stateStyles?.style(id: "lowered.robot"))
        let paused = style.resolve(EntityState(entityId: F.vacuum, state: "paused"), entityId: F.vacuum)
        #expect(paused.stateClass == .resting && paused.isActive, "the old tile lit a paused robot; the built-in warning's amber ground wins over a fill")
    }

    @Test func theStartDiscFollowsTheStateAndNamesTheRobot() throws {
        let disc = try #require(try tile().parts.discs.first)
        #expect(disc.namesTile)
        let expected: [(String, String, String)] = [("cleaning", "pause.fill", "Pause"), ("returning", "pause.fill", "Pause"),
                                                   ("paused", "play.fill", "Resume"), ("docked", "play.fill", "Start"), ("idle", "play.fill", "Start")]
        for (state, symbol, label) in expected {
            let read = table(state)
            #expect(disc.resolvedIcon(in: read).name == symbol, "\(state) glyph")
            #expect(disc.resolvedLabel(read: { read.read(sourceId: $0.sourceId, path: $0.path) }, in: read) == label, "\(state) label")
            // The old actions said the same words and drew the same glyph (`VacuumActions`).
            let old = VacuumActions(entityId: F.vacuum).actions(for: EntityState(entityId: F.vacuum, state: state)).first { $0.id == "start_pause" }
            #expect(old?.symbol == symbol && old?.verb == label, "\(state) old")
        }
    }

    @Test func aGridOfRobotsKeepsTwoColumnsAndAnyOtherGridDoesNot() throws {
        let card: [String: Any] = ["kind": "card", "icon": F.icon, "commands": ["start_pause"], "destination": F.destination]
        func grid(columns: Int) throws -> D.Grid {
            let publication = try F.publication(primitive: card, gridColumns: columns)
            guard case .grid(let grid)? = publication.document.pages[0].surface.components.last else { Issue.record("not a grid"); throw CancellationError() }
            return grid
        }
        #expect(try grid(columns: 3).minimumColumns == 2)
        #expect(try grid(columns: 2).minimumColumns == 2)
        #expect(try grid(columns: 1).minimumColumns == nil, "a one-column grid cannot keep two")
        // A grid of anything else is untouched (the sample page's own grid).
        let other = try F.publication(primitive: F.command("dock"))
        guard case .grid(let sample)? = other.document.pages[0].surface.components.first else { Issue.record("no sample grid"); return }
        #expect(sample.minimumColumns == nil)
    }

    @Test func theAutoCleanRowSaysEnabledOrPausedAndKeepsItsGlyph() throws {
        guard case .boundControl(let control) = try F.component(["kind": "auto-clean"]) else { Issue.record("not a bound control"); return }
        #expect(control.row.drawsIcon && control.row.metrics == .module && control.row.hint == "Turns automatic cleaning on or off.")
        #expect(control.row.glyph == .solidAppearance(light: .init(red: 0x9C, green: 0x6D, blue: 0xC3), dark: .init(red: 0xC8, green: 0x8C, blue: 0xFA)))
        // The pause switch: off is enabled.
        for (state, words) in [("off", "Enabled"), ("on", "Paused"), ("unavailable", "Unavailable")] {
            let read = VacuumStateTable(states: [F.pause: state])
            #expect(read.text(try #require(control.row.subtitle)) == words, "\(state)")
        }
    }
}

// MARK: - Auto-clean

@MainActor
@Suite struct ServerUIVacuumAutoCleanLoweringTests {
    @Test func theSwitchEqualsTheOldControllerInEveryState() throws {
        guard case .boundControl(let control) = try F.component(["kind": "auto-clean"]) else { Issue.record("not a bound control"); return }
        #expect(control.kind == .toggle && control.surface == .row)
        let configuration = Vacuums.AutoCleanControl(title: "Demo", entityId: F.pause, icon: "", kind: .pause)
        for state in ["on", "off", "unavailable", "unknown"] {
            // What `VacuumAutoCleanController.display` said: unavailable for an unreadable switch, else `isEnabled(state:)`.
            let unavailable = VacuumStatusResolver.isUnavailable(state)
            let answer = try #require(control.isOn).evaluate(VacuumStateTable(states: [F.pause: state]))
            if unavailable { #expect(answer == .unknown, "unavailable \(state)") }
            else { #expect(answer == (configuration.isEnabled(state: state) ? .yes : .no), "\(state)") }
        }
        // Enabling a pause switch turns it off; disabling turns it on (`VacuumAutoCleanController.toggle`).
        #expect(control.onAction?.service == "turn_off" && control.onAction?.domain == "switch")
        #expect(control.offAction?.service == "turn_on")
        #expect(control.onAction?.optimistic.first?.value == "off" && control.onAction?.optimistic.first?.failsOnTimeout == true)
    }

    @Test func aRoomIsIncludedWhileItsSkipSwitchIsOff() throws {
        guard case .boundControl(let control) = try F.component(["kind": "choice", "selection": "autoClean", "entityId": F.skip]) else {
            Issue.record("not a bound control"); return
        }
        #expect(control.kind == .toggle && control.surface == .tile)
        for state in ["on", "off", "unavailable"] {
            let store = EntityStore()
            _ = store.replaceAll([EntityState(entityId: F.skip, state: state)])
            let descriptor = try JSONDecoder().decode(ServerUIVacuumDescriptor.self, from: JSONSerialization.data(withJSONObject: F.descriptorJSON()))
            let controller = VacuumController(vacuum: descriptor.configuration, store: store, caller: RecordingCaller(), reconciliationEntities: [:])
            let old = try #require(controller.autoCleanTiles.first { $0.room.entityId == F.skip }).tile
            let answer = try #require(control.isOn).evaluate(VacuumStateTable(states: [F.skip: state]))
            if old.isUnavailable { #expect(answer == .unknown) } else { #expect(answer == (old.isChosen ? .yes : .no), "\(state)") }
        }
        #expect(control.onAction?.service == "turn_off" && control.offAction?.service == "turn_on")
    }
}

// MARK: - What stays, and what the document still says

@Suite struct ServerUIVacuumLoweringScopeTests {
    @Test func nativeKindsAreLeftAlone() throws {
        let destination = F.destination
        let natives: [[String: Any]] = [
            ["kind": "map", "overlay": "rooms", "height": 300, "runtimeHeight": 460, "label": "Map", "loadingText": "Reading map", "unavailableText": "Map unavailable", "locate": true],
            ["kind": "status", "metric": "status"], ["kind": "status", "metric": "battery"], ["kind": "status", "metric": "dock"],
            ["kind": "consumable", "entityId": F.brush], ["kind": "consumable", "entityId": F.filter],
            F.command("dock"), F.command("stop"), F.command("pause"), F.command("resume"),
            F.command("clean"), F.command("cleanArea"), F.command("emptyBin"),
            ["kind": "notices"], ["kind": "outcomes"], ["kind": "report", "destination": destination],
            ["kind": "target", "mode": "area", "icon": F.icon, "destination": destination], ["kind": "clear-area", "icon": F.icon],
            ["kind": "settings", "rows": [["role": "passes", "title": "Repeats", "hint": "Select repeats"]]],
            ["kind": "choice", "selection": "rooms", "entityId": "input_boolean.demo_room"],
            ["kind": "area-editor", "height": 650, "onUse": ["type": "back"], "discardLabel": "Discard", "onDiscard": ["type": "back"]],
        ]
        for primitive in natives {
            guard case .vacuum = try F.component(primitive) else { Issue.record("\(primitive["kind"] ?? "") lowered"); continue }
        }
    }

    @Test func theDocumentKeepsItsCapabilitiesAndGainsOneSourcePerEntity() throws {
        let result = try F.publication(primitive: ["kind": "card", "icon": F.icon, "commands": ["start_pause", "dock"], "destination": F.destination])
        #expect(result.capabilities.contains("sh.vacuum@1") && result.capabilities.contains("sh.vacuum-controls@1"))
        #expect(!result.capabilities.contains("sh.tile-parts@1") && !result.capabilities.contains("sh.state-style@1"))
        let lowered = result.document.dataSources.map(\.id).filter { $0.hasPrefix("lowered.") }
        #expect(Set(lowered).count == lowered.count)
        #expect(Set(lowered) == ["lowered." + F.vacuum, "lowered." + F.battery, "lowered." + F.error])
        for source in result.document.dataSources where source.id.hasPrefix("lowered.") {
            guard case .haEntity(_, .literal(let entity)) = source else { Issue.record("a lowered source is an entity"); continue }
            #expect("lowered." + entity == source.id)
        }
        #expect(result.document.dataSources.contains { if case .vacuum = $0 { true } else { false } })
    }

    @Test func aDocumentWithoutAVacuumIsReturnedUntouched() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ServerUICompositionFixture.json")
        let publication = try ServerUICompositionPublication.decode(Data(contentsOf: url))
        #expect(ServerUIVacuumLowering.lower(publication.document) == publication.document)
    }
}
