import Foundation
import HassCore

/// The debug switches that put every layout-driven page, and the Home Assistant modal's House Layout row, in a house-layout state
/// without a server (galleries, screenshots and journeys).
///
/// - `FENTON_GALLERY_HOUSECONFIG=loading|offline|missing|notconfigured|invalid|newer|timeout|cached-missing|entity-missing`
/// - `FENTON_HOUSECONFIG_ROLE=admin|member`
enum HouseLayoutDebug {
    /// A forced state: what the store and the document would have to be.
    struct Forced: Equatable {
        var status: HouseConfigStore.Status
        var hasDocument: Bool
        /// The configured entity ids reported missing, for the House Layout row.
        var missing: [String] = []
    }

    /// The ids `entity-missing` reports (generic, not a real house's).
    static let sampleMissing = ["light.sample_missing", "sensor.sample_missing"]

    /// The state a `FENTON_GALLERY_HOUSECONFIG` value forces, or nil for an unset or unknown value.
    static func forced(_ value: String?) -> Forced? {
        switch value {
        case "loading", "offline": Forced(status: .loading, hasDocument: false)
        case "missing": Forced(status: .integrationMissing, hasDocument: false)
        case "notconfigured": Forced(status: .notConfigured, hasDocument: false)
        case "invalid": Forced(status: .invalid, hasDocument: false)
        case "newer": Forced(status: .newerSchema(found: 99), hasDocument: false)
        case "timeout": Forced(status: .timedOut, hasDocument: false)
        case "cached-missing": Forced(status: .integrationMissing, hasDocument: true)
        case "entity-missing": Forced(status: .ready, hasDocument: true, missing: sampleMissing)
        default: nil
        }
    }

    /// The role a `FENTON_HOUSECONFIG_ROLE` value forces, or nil.
    static func role(_ value: String?) -> HouseLayoutState.Role? {
        switch value {
        case "admin": .admin
        case "member": .member
        default: nil
        }
    }

    /// The forced state of this process (debug builds only).
    static var current: Forced? {
        #if DEBUG
        forced(ProcessInfo.processInfo.environment["FENTON_GALLERY_HOUSECONFIG"])
        #else
        nil
        #endif
    }

    /// The forced role of this process (debug builds only).
    static var currentRole: HouseLayoutState.Role? {
        #if DEBUG
        role(ProcessInfo.processInfo.environment["FENTON_HOUSECONFIG_ROLE"])
        #else
        nil
        #endif
    }
}
