import Foundation
@testable import HassCore
import HassTestSupport
import Testing

private func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
    EntityState(entityId: id, state: state, attributes: attributes)
}

// MARK: - Parity with the retired fixed shapes

/// The fixed shapes `CoverActions`, `LockActions` and `AlarmModeActions` were deleted once these tables matched them state for state. Each row is
/// what the shape returned (its own doc table, run against the styles with the shapes still in the tree before they were removed): verb, glyph,
/// service, whether the disc reports on, and the phase. The styles must keep giving it, so a change to a style that moves a glyph, a word, a
/// call or a tap rule fails here (`.agents/design/state-styles.md`, Parity with the fixed shapes).
@Suite(.demoHouse) struct StateStyleParityTests {
    private let door = "cover.demo_garage_door_1"
    private let lockId = "lock.demo_front"
    private var panel: String { SecurityConfig.alarmEntityId }

    private struct Row {
        var state: String?
        var verb: String
        var symbol: String
        var service: String?
        var isOn: Bool?
        var phase: TileActionSpec.Phase
        var isError = false
    }

    private func check(_ style: StateStyle, _ id: String, _ rows: [Row], attributes: [String: JSONValue] = [:],
                       sourceLocation: SourceLocation = #_sourceLocation) {
        for row in rows {
            let live = row.state.map { entity(id, $0, attributes) }
            let spec = style.spec(for: live, entityId: id)
            let name = Comment(rawValue: "\(style.id) \(row.state ?? "nil")")
            #expect(spec?.verb == row.verb && spec?.symbol == row.symbol && spec?.isOn == row.isOn && spec?.phase == row.phase, name, sourceLocation: sourceLocation)
            #expect(spec?.call == row.service.map { ServiceCall(style.domain, $0, target: id) }, name, sourceLocation: sourceLocation)
            #expect(spec?.isError == row.isError && spec?.id == style.actionId && spec?.feedback == .tracked, name, sourceLocation: sourceLocation)
        }
    }

    // MARK: Garage door

    @Test(arguments: [0, 3, 11])
    func garageDoorMatchesCoverActions(_ features: Int) {
        let attributes: [String: JSONValue] = features == 0 ? [:] : ["supported_features": .number(Double(features))]
        let stops = features & 8 != 0
        check(.garageDoor, door, [
            Row(state: "closed", verb: "Open", symbol: "door.garage.closed", service: "open_cover", isOn: false, phase: .ready),
            Row(state: "open", verb: "Close", symbol: "door.garage.open", service: "close_cover", isOn: true, phase: .ready),
            Row(state: "opening", verb: stops ? "Stop" : "Reverse", symbol: stops ? "stop.fill" : "arrow.uturn.down",
                service: stops ? "stop_cover" : "close_cover", isOn: true, phase: .ready),
            Row(state: "closing", verb: stops ? "Stop" : "Reverse", symbol: stops ? "stop.fill" : "arrow.uturn.up",
                service: stops ? "stop_cover" : "open_cover", isOn: true, phase: .ready),
            Row(state: "unavailable", verb: "Open", symbol: "door.garage.closed", service: nil, isOn: false, phase: .unavailable),
            Row(state: "unknown", verb: "Open", symbol: "door.garage.closed", service: nil, isOn: false, phase: .unavailable),
            Row(state: "stopped", verb: "Open", symbol: "door.garage.closed", service: nil, isOn: false, phase: .unavailable),
            Row(state: nil, verb: "Open", symbol: "door.garage.closed", service: nil, isOn: false, phase: .unavailable),
        ], attributes: attributes)
    }

    @Test func aRequestInFlightHoldsTheDiscWhateverTheStateSays() {
        for state in ["closed", "open", "opening", "closing"] {
            let live = entity(door, state, ["supported_features": .number(11)])
            let held = StateStyle.garageDoor.spec(for: live, entityId: door, requestInFlight: true)
            #expect(held?.phase == .inFlight && held?.verb == StateStyle.garageDoor.spec(for: live, entityId: door)?.verb, Comment(rawValue: state))
        }
    }

    @Test func garageDoorReverseUsesTheOppositeCommand() {
        for (state, service) in [("opening", "close_cover"), ("closing", "open_cover")] {
            let spec = StateStyle.garageDoor.spec(for: entity(door, state), entityId: door)
            #expect(spec?.call?.service == service, Comment(rawValue: state))
        }
    }

    @Test func garageDoorWordsCoverEveryStateTheFixedShapeSpoke() {
        let words = ["closed", "open", "opening", "closing"].map { StateStyle.garageDoor.resolve(entity(door, $0), entityId: door).words }
        #expect(words == ["Closed", "Open", "Opening", "Closing"])
        let request = StateStyle.garageDoor.request
        for candidate in ["Sending Open…", "Sending Close…", "Stopping…", "Error"] {
            #expect(request?.pendingWords.values.contains(candidate) == true || request?.errorWords == candidate, Comment(rawValue: candidate))
        }
    }

    // MARK: Lock

    @Test func lockMatchesLockActions() {
        check(.lock, lockId, [
            Row(state: "locked", verb: "Unlock", symbol: "lock.fill", service: "unlock", isOn: false, phase: .ready),
            Row(state: "unlocked", verb: "Lock", symbol: "lock.open", service: "lock", isOn: true, phase: .ready),
            Row(state: "open", verb: "Lock", symbol: "lock.open", service: "lock", isOn: true, phase: .ready),
            Row(state: "locking", verb: "Unlock", symbol: "lock.fill", service: "unlock", isOn: false, phase: .inFlight),
            Row(state: "unlocking", verb: "Lock", symbol: "lock.open", service: "lock", isOn: true, phase: .inFlight),
            Row(state: "jammed", verb: "Lock", symbol: "lock.trianglebadge.exclamationmark", service: "lock", isOn: true, phase: .ready, isError: true),
            Row(state: "unavailable", verb: "Unlock", symbol: "lock.fill", service: "unlock", isOn: false, phase: .unavailable),
            Row(state: "unknown", verb: "Unlock", symbol: "lock.fill", service: "unlock", isOn: false, phase: .unavailable),
            Row(state: nil, verb: "Unlock", symbol: "lock.fill", service: "unlock", isOn: false, phase: .unavailable),
        ])
    }

    @Test func lockServicesFollowTheSecurityConfigsRule() {
        for state in ["locked", "unlocked", "open", "locking", "unlocking"] {
            let spec = StateStyle.lock.spec(for: entity(lockId, state), entityId: lockId)
            #expect(spec?.call?.service == SecurityConfig.lockService(for: state), Comment(rawValue: state))
        }
    }

    @Test func lockTapsAreIgnoredOnlyWhileMoving() {
        for state in ["locking", "unlocking"] { #expect(StateStyle.lock.spec(for: entity(lockId, state), entityId: lockId)?.phase == .inFlight) }
        for state in ["locked", "unlocked", "open", "jammed"] { #expect(StateStyle.lock.spec(for: entity(lockId, state), entityId: lockId)?.phase == .ready) }
    }

    // MARK: Alarm

    @Test func alarmMatchesAlarmModeActions() {
        let arm = Row(state: "disarmed", verb: "Arm Home", symbol: "shield.lefthalf.filled", service: "alarm_arm_home", isOn: nil, phase: .ready)
        func disarm(_ state: String) -> Row { Row(state: state, verb: "Disarm", symbol: "shield.slash", service: "alarm_disarm", isOn: nil, phase: .ready) }
        var rows = [arm]
        for state in ["armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass", "triggered", "arming", "pending"] { rows.append(disarm(state)) }
        rows.append(Row(state: "disarming", verb: "Arm Home", symbol: "shield.lefthalf.filled", service: "alarm_arm_home", isOn: nil, phase: .inFlight))
        for state in ["unavailable", "unknown"] as [String?] + [nil] {
            rows.append(Row(state: state, verb: "Arm Home", symbol: "shield.lefthalf.filled", service: "alarm_arm_home", isOn: nil, phase: .unavailable))
        }
        check(.alarm, panel, rows)
    }

    @Test func alarmServicesAndQuestionComeFromTheSecurityConfig() throws {
        #expect(SecurityConfig.alarmModes[0].service == "alarm_arm_home" && SecurityConfig.disarmMode.service == "alarm_disarm")
        let disarm = try #require(StateStyle.alarm.spec(for: entity(panel, "armed_home"), entityId: panel))
        #expect(disarm.confirmation == StateStyle.alarmDisarmConfirmation)
        #expect(disarm.confirmation?.confirmVerb == SecurityConfig.disarmMode.buttonTitle)
        for state in ["disarmed", "disarming", "unavailable"] {
            #expect(StateStyle.alarm.spec(for: entity(panel, state), entityId: panel)?.confirmation == nil, "only Disarm asks first")
        }
    }

    @Test func disarmStaysTappableThroughArmingAndPendingAndDisarmingIgnoresTaps() throws {
        for state in ["arming", "pending", "armed_home", "triggered"] {
            let spec = try #require(StateStyle.alarm.spec(for: entity(panel, state), entityId: panel))
            #expect(spec.verb == "Disarm" && spec.phase == .ready, Comment(rawValue: state))
        }
        #expect(StateStyle.alarm.spec(for: entity(panel, "disarming"), entityId: panel)?.phase == .inFlight)
    }

    // MARK: The two recorded differences

    /// The arc stands in the disc's place with the disc hidden, where the fixed shapes drew it inside the disc. So the arc shows exactly
    /// where the fixed disc was in flight, and in no state whose tap does something.
    @Test func theArcShowsExactlyWhereTheFixedDiscWasInFlight() {
        let inFlight: [(StateStyle, String, [String])] = [
            (.lock, lockId, ["locking", "unlocking"]), (.alarm, panel, ["disarming"]), (.garageDoor, door, []),
        ]
        let ready: [(StateStyle, String, [String])] = [
            (.lock, lockId, ["locked", "unlocked", "open", "jammed", "unavailable"]),
            (.alarm, panel, ["disarmed", "armed_home", "arming", "pending", "triggered", "unavailable"]),
            (.garageDoor, door, ["closed", "open", "opening", "closing", "unavailable"]),
        ]
        for (style, id, states) in inFlight {
            for state in states { #expect(style.resolve(entity(id, state), entityId: id).indicator == .arcSpinner, Comment(rawValue: "\(style.id) \(state)")) }
        }
        for (style, id, states) in ready {
            for state in states { #expect(style.resolve(entity(id, state), entityId: id).indicator != .arcSpinner, Comment(rawValue: "\(style.id) \(state)")) }
        }
    }

    /// Alarm `pending` and lock `open` draw the warning face; the fixed shapes drew the resting face.
    @Test func alarmPendingAndLockOpenDrawTheWarningFace() {
        let alarm = StateStyle.alarm.resolve(entity(panel, "pending"), entityId: panel)
        let lock = StateStyle.lock.resolve(entity(lockId, "open"), entityId: lockId)
        #expect(alarm.stateClass == .warning && lock.stateClass == .warning)
        // Everything else about the disc is the fixed shape's: the verb, the glyph, the call.
        #expect(alarm.action?.verb == "Disarm" && lock.action?.verb == "Lock" && lock.glyph == "lock.open")
    }

    @Test func noOtherStateOfTheThreeStylesIsAWarning() {
        let others: [(StateStyle, [String])] = [
            (.lock, ["locked", "unlocked", "locking", "unlocking", "jammed", "unavailable"]),
            (.alarm, ["disarmed", "armed_home", "arming", "disarming", "triggered", "unavailable"]),
            (.garageDoor, ["closed", "open", "opening", "closing", "unavailable"]),
        ]
        for (style, states) in others {
            for state in states {
                #expect(style.resolve(entity("x.demo", state), entityId: "x.demo").stateClass != .warning, Comment(rawValue: "\(style.id) \(state)"))
            }
        }
    }

    // MARK: The two judged differences, pinned

    /// A locking lock draws unlit, as the deleted `LockActions` disc did (`state-styles.md`, Lock row: only unlocked and unlocking are lit).
    @Test func aLockingLockDrawsUnlitAndNoOtherMovingStateOfTheLockIsLitButUnlocking() {
        for (state, lit) in [("locked", false), ("locking", false), ("unlocked", true), ("unlocking", true), ("open", true), ("jammed", true)] {
            let resolved = StateStyle.lock.resolve(entity(lockId, state), entityId: lockId)
            #expect(resolved.isActive == lit, Comment(rawValue: "lock \(state)"))
            #expect(StateStyle.lock.spec(for: entity(lockId, state), entityId: lockId)?.isOn == lit, Comment(rawValue: "lock \(state)"))
        }
    }

    /// A state Home Assistant adds later reads as unknown, with an action that does nothing: inert is safer than a stale Lock or Disarm.
    @Test func aStateTheBuiltInStyleDoesNotListFallsToUnknownWithAnInertAction() throws {
        for (style, id) in [(StateStyle.lock, lockId), (.alarm, panel), (.garageDoor, door)] {
            let resolved = style.resolve(entity(id, "demo_new_state"), entityId: id)
            #expect(resolved.stateClass == .unknown, Comment(rawValue: style.id))
            #expect(resolved.action?.isTappable == false, Comment(rawValue: style.id))
            #expect(style.spec(for: entity(id, "demo_new_state"), entityId: id)?.phase == .unavailable, Comment(rawValue: style.id))
        }
    }
}
