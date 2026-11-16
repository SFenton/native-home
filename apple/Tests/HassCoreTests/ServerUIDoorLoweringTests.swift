import Foundation
import Testing
@testable import HassCore

// MARK: - A door lowers to a state tile that reads as the door did

/// The lowered style, state for state, against the table the bespoke door atom drew (its golden is
/// `Apps/iOSTests/Fixtures/ServerUIDoorGolden.json`; the hosted equivalence test compares the drawn tiles).
struct ServerUIDoorLoweringTests {
    private func lowered(_ tile: String) throws -> (StateStyle, ServerUICompositionDocument.StateTile) {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let nodes = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ServerUISecurityNodes.json")))
        let component = try #require(nodes["components"]?.array?.first { $0["id"]?.string == tile })
        let props = try #require(component["props"])
        func appearance(_ json: JSONValue) -> ServerUICompositionDocument.AlarmAppearance {
            .init(icon: .init(name: json["icon"]?["name"]?.string ?? "", rendering: .canonical, unavailable: .reject),
                  fill: .solidRGB(red: Int(json["fill"]?["red"]?.number ?? 0), green: Int(json["fill"]?["green"]?.number ?? 0),
                                  blue: Int(json["fill"]?["blue"]?.number ?? 0)), text: json["text"]?.string ?? "")
        }
        let kind: ServerUICompositionDocument.DoorKind = props["kind"]?.string == "lock" ? .lock : .garage
        let states = (props["states"]?.array ?? []).map {
            ServerUICompositionDocument.DoorStateAppearance(state: $0["state"]?.string ?? "", appearance: appearance($0["appearance"] ?? .null),
                                                            active: $0["active"]?.bool ?? false, error: $0["error"]?.bool ?? false)
        }
        func text(_ key: String) -> String { props[key]?.string ?? "" }
        let result = ServerUIDoorLowering.lower(.init(
            node: .init(id: tile, title: component["title"]?.string ?? "", span: 1), sourceId: text("sourceId"), kind: kind, states: states,
            fallback: appearance(props["fallback"] ?? .null), loadingText: text("loadingText"), hiddenText: text("hiddenText"),
            unavailableText: text("unavailableText"), errorText: text("errorText"), sendingOpenText: text("sendingOpenText"),
            sendingCloseText: text("sendingCloseText"), openLabel: text("openLabel"), closeLabel: text("closeLabel"),
            reverseLabel: text("reverseLabel")), entityId: kind == .lock ? "lock.demo_unit" : "cover.demo_unit")
        return (result.style.style, result.tile)
    }

    private func read(_ style: StateStyle, _ state: String, _ entity: String, features: Int? = nil) -> (StateResolution, TileActionSpec?) {
        let live = EntityState(entityId: entity, state: state, attributes: features.map { ["supported_features": .number(Double($0))] } ?? [:])
        return (style.resolve(live, entityId: entity), style.spec(for: live, entityId: entity))
    }

    @Test func theGarageReadsAsTheDoorDid() throws {
        let (style, tile) = try lowered("demo-garage-control")
        let id = "cover.demo_unit"
        let rows: [(String, String, String, String, Bool)] = [
            ("closed", "Closed", "door.garage.closed", "Open", false), ("open", "Open", "door.garage.open", "Close", true),
            ("opening", "Opening", "door.garage.open", "Reverse", true), ("closing", "Closing", "door.garage.closed", "Reverse", true),
            ("stopped", "Unknown", "door.garage.closed", "Close", false), ("unavailable", "Unavailable", "door.garage.closed", "Close", false),
        ]
        for (state, words, glyph, verb, active) in rows {
            let (resolution, spec) = read(style, state, id)
            #expect(resolution.words == words, "\(state)")
            #expect(resolution.isActive == active, "\(state)")
            #expect(spec?.verb == verb, "\(state)")
            if state != "opening" && state != "closing" { #expect(resolution.glyph == glyph, "\(state)") }
        }
        #expect(tile.binding.entityId == id && tile.binding.styleId == style.id)
        #expect(style.request?.pendingWords["open_cover"] == "Sending Open..." && style.request?.pendingWords["close_cover"] == "Sending Close...")
        #expect(style.request?.errorWords == "Error")
        #expect(style.request?.pendingStates == StateStyle.garageDoor.request?.pendingStates, "the optimistic travel states are the built-in's")
        let stop = read(style, "opening", id, features: StateStyle.coverStopFeature).1
        #expect(stop?.verb == "Stop" && stop?.call?.service == "stop_cover", "a cover that can stop keeps Stop")
        #expect(read(style, "closed", id).1?.call?.service == "open_cover")
    }

    @Test func theAuthoredFillsAndHiddenWordsLiveInTheStyle() throws {
        let (style, _) = try lowered("demo-garage-control")
        let id = "cover.demo_unit"
        func fill(_ state: String) -> UInt32? { read(style, state, id).0.fill }
        // A lit state draws its authored colour as the face; an unlit one has no fill (see `anUnlitStateInksTheDiscGlyphInsteadOfTheFace`).
        #expect(fill("open") == 0xE53935 && fill("opening") == 0x1E88E5 && fill("closing") == 0x1E88E5)
        #expect(fill("closed") == nil && fill("unavailable") == nil && fill("stopped") == nil)
        #expect(style.hiddenWords == "Hidden")
        #expect(style.keepsDiscWhenUnknown, "the dimmed disc the door drew while unavailable stays")
        #expect(StateStyle.garageDoor.rules.allSatisfy { $0.fill == nil } && StateStyle.garageDoor.hiddenWords == nil, "built-ins carry none")
    }

    /// A state that is not `active` draws the unlit face, and its authored colour inks the disc's glyph; an active one draws the colour as
    /// the face and leaves the disc's ink alone (state-styled-tile, "the family fill when `active`").
    @Test func anUnlitStateInksTheDiscGlyphInsteadOfTheFace() throws {
        let garage = try lowered("demo-garage-control").0
        let lock = try lowered("demo-lock-control").0
        let cases: [(StateStyle, String, String, Bool, UInt32)] = [
            (garage, "cover.demo_unit", "closed", false, 0x43A047), (garage, "cover.demo_unit", "open", true, 0xE53935),
            (garage, "cover.demo_unit", "unavailable", false, 0x546E7A), (garage, "cover.demo_unit", "stopped", false, 0x546E7A),
            (lock, "lock.demo_unit", "locked", false, 0x43A047), (lock, "lock.demo_unit", "unlocked", true, 0xE53935),
        ]
        for (style, id, state, active, colour) in cases {
            let resolution = read(style, state, id).0
            #expect(resolution.isActive == active, "\(id) \(state)")
            #expect(resolution.fill == (active ? colour : nil), "\(id) \(state): the face fill is drawn only when active")
            #expect(resolution.discGlyph == (active ? nil : colour), "\(id) \(state): an unlit state inks the disc glyph")
        }
        #expect(StateStyle.builtIn.allSatisfy { $0.rules.allSatisfy { $0.discGlyph == nil } }, "no built-in style carries a disc ink")
    }

    @Test func theLockReadsAsTheDoorDid() throws {
        let (style, _) = try lowered("demo-lock-control")
        let id = "lock.demo_unit"
        let rows: [(String, String, String, Bool, StateClass)] = [
            ("locked", "Locked", "Unlock", false, .resting), ("unlocked", "Unlocked", "Lock", true, .resting),
            ("locking", "Locking", "Unlock", true, .inProgress), ("unlocking", "Unlocking", "Lock", true, .inProgress),
            ("jammed", "Jammed", "Lock", true, .error), ("stuck", "Unknown", "Unlock", false, .unknown),
            ("unknown", "Unavailable", "Unlock", false, .unknown),
        ]
        for (state, words, verb, active, stateClass) in rows {
            let (resolution, spec) = read(style, state, id)
            #expect(resolution.words == words, "\(state)")
            #expect(spec?.verb == verb, "\(state)")
            #expect(resolution.isActive == active, "\(state)")
            #expect(resolution.stateClass == stateClass, "\(state)")
        }
        #expect(style.request?.errorWords == "Didn't Respond")
        #expect(style.request?.pendingStates["unlock"] == "unlocking")
    }

    @Test func loadingWordsAreASubtitleThatSpeaksOnlyWhileLoading() throws {
        let (_, tile) = try lowered("demo-garage-control")
        guard case .expression(.map(let phase, let cases, let otherwise), let fallback)? = tile.parts.subtitle else {
            Issue.record("Expected an expression subtitle"); return
        }
        #expect(phase == .read(sourceId: "demo-garage", path: ["phase"], as: .string))
        #expect(cases.map(\.equals) == [.string("loading")] && cases.first?.then == .literal(.string("Loading")))
        #expect(fallback == nil)
        if case .read(_, let path, _) = otherwise { #expect(path != ["phase"], "any other phase gives no words, so the style's own stay") }
    }
}
