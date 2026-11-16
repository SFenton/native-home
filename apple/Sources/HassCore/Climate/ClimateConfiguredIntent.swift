import Foundation

// MARK: - Configured climate commands

/// Typed command vocabulary; HA remains responsible for automation, supported modes and actual state.
public enum ClimateConfiguredIntent: Sendable {
    case toggle(String)
    case setSwitch(String, Bool)
    case select(String, String)
    case mode(String, String)
    case fan(String, String)
    case preset(String, String)
    case temperature([String], [String: Double], unit: String)
}

/// Sanitized action rejection, suitable for an explicit failure caption without leaking targets.
public enum ClimateConfiguredError: Error, Equatable {
    case unavailable, invalidIntent, unsupportedOption
}
