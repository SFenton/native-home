import Foundation

// MARK: - Cause

/// Why an entity is in its state, as far as the home can say.
public enum AskCause: Sendable, Equatable {
    /// A named automation changed it.
    case automation(name: String, message: String?, ago: TimeInterval)
    /// A named script changed it.
    case script(name: String, ago: TimeInterval)
    /// A named person changed it (an app or HomeKit change carrying a user).
    case person(name: String, ago: TimeInterval)
    /// Another entity's change caused it (a group or an occupancy aggregate).
    case entity(name: String, state: String?, ago: TimeInterval)
    /// Something the configuration does not name (an automation, a script or an entity outside it) did it. Nothing about it is spoken.
    case other(ago: TimeInterval)
    /// A service call with no actor in the log.
    case service(String, ago: TimeInterval)
    /// A state row with no context at all: the device reported it itself (a wall switch, a sensor, the device).
    case physical(ago: TimeInterval)
    /// The state was only re-reported when Home Assistant restarted; no change is recorded.
    case restart
    /// Nothing is recorded.
    case none

    /// Whether the cause names who or what did it.
    public var isNamed: Bool {
        switch self {
        case .automation, .script, .person, .entity: true
        default: false
        }
    }
}

extension AskCause {
    /// The words for a cause that is not configured, so its name and state are never spoken.
    public static let otherWording = "something else in the house"
}

/// The result of a cause lookup: the logbook's cause and the integration annotators' lines.
public struct AskCauseResult: Sendable, Equatable {
    /// The cause the logbook gave (or ``AskCause/none``).
    public var cause: AskCause
    /// Lines from integration annotators, in configuration order, each already phrased.
    public var annotatorLines: [String]
    /// The most private class among the configured entities the cause names (``AskSensitivity/everyday`` when it names none).
    public var sensitivity: AskSensitivity = .everyday
}
