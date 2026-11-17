#if os(iOS) && DEBUG
import Foundation
import HassCore
import UIKit

// MARK: - Preview state flags

/// DEBUG-only switches that stage an error or edge state in the `--server-ui-preview` route with no live write.
///
/// They mirror the reference app's launch variables (`FENTON_GALLERY_*`, `GalleryFixtureLaunch`), so one state can be staged on both
/// sides of a parity pair. The flags come from the `flags` object of `bootstrap.json`, and from the launch environment, which wins
/// (`simctl launch` sets `SIMCTL_CHILD_FENTON_GALLERY_OFFLINE=1`, and the process sees `FENTON_GALLERY_OFFLINE=1`).
///
/// The flag-to-variable mapping is written once, in `ServerUI/README.md` ("Preview state flags").
///
/// Every flag acts through a seam the app already has, never a branch in a view: the shell header's state (what
/// `HassConnection.isOffline` and ``ReconnectingIndicator`` feed in production), a service caller that answers with an error,
/// empty fixture lists, the load that mounts the page, `UKDesign.animationsPaused` and `UKMotion.reduceMotionOverride`.
/// With no flag set ``isDefault`` holds and the preview behaves exactly as before. Compiled out of release builds.
struct UKServerUIPreviewFlags: Decodable, Equatable, Sendable {
    /// What the shell header shows of the connection.
    enum Connection: String, Decodable, Sendable {
        /// Connected: the default.
        case live
        /// No network path: the Profile button's offline badge.
        case offline
        /// Retrying: the lit reconnecting arc beside Quick Links.
        case reconnecting
    }

    /// The most a gate delay may be, so a typo cannot hold a run for minutes.
    static let maximumGateDelayMs = 60_000

    /// What the shell header shows of the connection: connected, offline or reconnecting.
    var connection: Connection = .live
    /// Every `callService` fails with an error reply.
    var failCalls = false
    /// The fixture lists and records are empty.
    var empty = false
    /// Milliseconds the first layout waits; nil is no delay.
    var gateDelayMs: Int?
    /// Continuous animations (arcs, pending bars, symbol effects) hold still.
    var animationsPaused = false
    /// Reduce Motion is forced on, through ``UKMotion/reduceMotionOverride``.
    var reduceMotion = false

    /// No flags set.
    init() {}

    /// Flags with each field as given; a gate delay is held between 0 and ``maximumGateDelayMs``.
    init(connection: Connection = .live, failCalls: Bool = false, empty: Bool = false, gateDelayMs: Int? = nil,
         animationsPaused: Bool = false, reduceMotion: Bool = false) {
        self.connection = connection
        self.failCalls = failCalls
        self.empty = empty
        self.gateDelayMs = gateDelayMs.map(Self.clamped)
        self.animationsPaused = animationsPaused
        self.reduceMotion = reduceMotion
    }

    private enum CodingKeys: String, CodingKey { case connection, failCalls, empty, gateDelayMs, animationsPaused, reduceMotion }

    /// A flags object where every key is optional; an unknown `connection` is a decoding error, not a silent default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(connection: try values.decodeIfPresent(Connection.self, forKey: .connection) ?? .live,
                  failCalls: try values.decodeIfPresent(Bool.self, forKey: .failCalls) ?? false,
                  empty: try values.decodeIfPresent(Bool.self, forKey: .empty) ?? false,
                  gateDelayMs: try values.decodeIfPresent(Int.self, forKey: .gateDelayMs),
                  animationsPaused: try values.decodeIfPresent(Bool.self, forKey: .animationsPaused) ?? false,
                  reduceMotion: try values.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false)
    }

    private static func clamped(_ milliseconds: Int) -> Int { min(max(milliseconds, 0), maximumGateDelayMs) }

    /// True when no flag is set.
    var isDefault: Bool { self == Self() }

    /// The delay as a duration, or nil when there is none.
    var gateDelay: Duration? { gateDelayMs.map { .milliseconds($0) } }

    // MARK: Environment

    /// These flags with every variable present in `environment` laid over them. A variable set to anything but `1` (or, for the
    /// delay, anything but a number) is ignored, as the reference ignores it.
    func overlaying(environment: [String: String]) -> UKServerUIPreviewFlags {
        var result = self
        func on(_ name: String) -> Bool { environment["FENTON_GALLERY_" + name] == "1" }
        if on("OFFLINE") { result.connection = .offline } else if on("RECONNECTING") { result.connection = .reconnecting }
        if on("FAIL") || on("FAIL_COMPLETE") { result.failCalls = true }
        if on("EMPTY") { result.empty = true }
        if let delay = environment["FENTON_GALLERY_GATE_DELAY_MS"].flatMap({ Int($0) }) { result.gateDelayMs = Self.clamped(delay) }
        if on("PAUSE_CONTINUOUS_ANIMATIONS") { result.animationsPaused = true }
        if on("REDUCE_MOTION") { result.reduceMotion = true }
        return result
    }

    // MARK: Shell header

    /// `state` as the shell header draws it under ``connection``: what production reads from `HassConnection.isOffline` and the
    /// ``ReconnectingIndicator`` (offline hides the arc, as ``ReconnectingPolicy/showsArc(_:isOffline:hasReceivedFirstState:)`` does).
    func applying(to state: UKShellHeaderItems.State) -> UKShellHeaderItems.State {
        var state = state
        switch connection {
        case .live: break
        case .offline: state.isOffline = true
        case .reconnecting: state.reconnectingPresent = true; state.reconnectingLit = true
        }
        return state
    }

    /// Whether the weather panel reports a connection (it draws its offline state otherwise).
    var isConnected: Bool { connection == .live }

    // MARK: Process-wide switches

    /// Sets the two process-wide switches the flags own and returns the call that puts them back.
    ///
    /// Only a flag that is set touches its switch, so an unflagged launch leaves `UKDesign.animationsPaused` and
    /// `UKMotion.reduceMotionOverride` exactly as they were.
    @MainActor
    func applyProcessSwitches() -> () -> Void {
        let paused = UKDesign.animationsPaused, override = UKMotion.reduceMotionOverride
        if animationsPaused { UKDesign.animationsPaused = true }
        if reduceMotion { UKMotion.reduceMotionOverride = true }
        return { UKDesign.animationsPaused = paused; UKMotion.reduceMotionOverride = override }
    }

    /// The flags as they are recorded in the receipt, so a harness can confirm what a run staged. Keys appear only when set.
    var receipt: [String: Any] {
        var value: [String: Any] = [:]
        if connection != .live { value["connection"] = connection.rawValue }
        if failCalls { value["failCalls"] = true }
        if empty { value["empty"] = true }
        if let gateDelayMs { value["gateDelayMs"] = gateDelayMs }
        if animationsPaused { value["animationsPaused"] = true }
        if reduceMotion { value["reduceMotion"] = true }
        return value
    }
}
#endif
