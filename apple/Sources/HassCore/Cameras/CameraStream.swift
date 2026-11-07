import Foundation

// MARK: - Modes

/// How a camera plays live video, in preference order.
public enum CameraStreamMode: String, Sendable, CaseIterable {
    /// Low latency through go2rtc, signalled over the WebRTC integration's `/api/webrtc/ws`
    /// (`SFenton/WebRTC`, the same path the web `webrtc-camera-sfenton` card uses).
    case webRTC
    /// Home Assistant's own HLS stream (`camera/stream`): a few seconds behind, but needs nothing beyond core.
    case hls

    /// How long this mode may take to show its first frame before the next mode is tried.
    ///
    /// Home Assistant holds the first HLS playlist request until a cold stream has its first segment
    /// (9.5 to 12.7 s on the Home cameras, measured 2026-10-10), so HLS gets a longer budget than WebRTC.
    public var firstFrameTimeout: Duration {
        switch self {
        case .webRTC: .seconds(10)
        case .hls: .seconds(25)
        }
    }
}

// MARK: - State

/// The live-video state machine for one camera view: try each mode in order and fall back on failure.
///
/// The view keeps the snapshot on screen until ``phase`` is ``Phase/live``, so a slow or failed stream
/// never blanks the camera.
public struct CameraStreamState: Equatable, Sendable {
    /// Where the stream is.
    public enum Phase: Equatable, Sendable {
        /// The current mode is connecting; the snapshot stays up.
        case connecting
        /// The current mode is showing frames.
        case live
        /// Every mode failed; the snapshot stays up with a retry.
        case failed
    }

    /// Modes to try, in order.
    public let modes: [CameraStreamMode]
    /// Current phase.
    public private(set) var phase: Phase
    private var index = 0

    /// Creates a state that starts connecting the first mode.
    /// - Parameter modes: Modes to try, in order. Empty means no live video.
    public init(modes: [CameraStreamMode] = CameraStreamMode.allCases) {
        self.modes = modes
        phase = modes.isEmpty ? .failed : .connecting
    }

    /// The mode being connected or shown; `nil` once every mode failed.
    public var mode: CameraStreamMode? { phase == .failed ? nil : modes[index] }

    /// The current mode showed its first frame. Events for any other mode are stale and ignored.
    public mutating func firstFrame(_ mode: CameraStreamMode) {
        guard mode == self.mode, phase == .connecting else { return }
        phase = .live
    }

    /// The current mode failed (or dropped while live): move to the next mode, or to ``Phase/failed``.
    public mutating func failed(_ mode: CameraStreamMode) {
        guard mode == self.mode else { return }
        if index + 1 < modes.count {
            index += 1
            phase = .connecting
        } else {
            phase = .failed
        }
    }

    /// Whether the live stream is a fallback that a more preferred mode could replace (HLS playing after WebRTC failed).
    public var canUpgrade: Bool { phase == .live && index > 0 }

    /// A more preferred mode than the live one is now showing frames: switch to it, staying live. Ignored unless the
    /// stream is live on a mode after `mode` in the order.
    public mutating func upgrade(to mode: CameraStreamMode) {
        guard phase == .live, let target = modes.firstIndex(of: mode), target < index else { return }
        index = target
    }

    /// Starts over from the first mode (retry, or returning to the foreground).
    public mutating func restart() {
        index = 0
        phase = modes.isEmpty ? .failed : .connecting
    }
}

// MARK: - Endpoints

/// URLs for camera streams on a Home Assistant server.
public enum CameraStreamEndpoints {
    /// The WebRTC integration's signalling socket, signed with `auth/sign_path` before connecting.
    public static let webRTCSocketPath = "/api/webrtc/ws"

    /// Resolves the tokenized playlist path `camera/stream` returns (`/api/hls/<token>/master_playlist.m3u8`).
    /// - Parameters:
    ///   - path: The returned path.
    ///   - baseURL: The server origin.
    /// - Returns: The absolute playlist URL.
    public static func hlsURL(path: String, baseURL: URL) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Builds the signalling websocket URL for a go2rtc stream.
    /// - Parameters:
    ///   - signedPath: `auth/sign_path` output for ``webRTCSocketPath`` (`/api/webrtc/ws?authSig=…`).
    ///   - streamId: The go2rtc stream name, e.g. `front_door`.
    ///   - baseURL: The server origin.
    /// - Returns: A `ws`/`wss` URL with the stream appended as `url=`.
    public static func webRTCSocketURL(signedPath: String, streamId: String, baseURL: URL) -> URL? {
        guard let absolute = URL(string: signedPath, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let stream = streamId.addingPercentEncoding(withAllowedCharacters: allowed) ?? streamId
        let existing = components.percentEncodedQuery.map { $0 + "&" } ?? ""
        components.percentEncodedQuery = existing + "url=" + stream
        return components.url
    }
}

// MARK: - Signalling

/// One message on the WebRTC integration's signalling socket (go2rtc's JSON protocol).
public enum WebRTCSignal: Equatable, Sendable {
    /// Our SDP offer.
    case offer(String)
    /// The server's SDP answer.
    case answer(String)
    /// A trickled ICE candidate line (`candidate:…`), either direction.
    case candidate(String)
    /// The server could not open the stream.
    case error(String)

    /// Encodes the message as the JSON text the socket expects.
    public func encoded() -> String {
        let (type, value): (String, String) = switch self {
        case let .offer(sdp): ("webrtc/offer", sdp)
        case let .answer(sdp): ("webrtc/answer", sdp)
        case let .candidate(line): ("webrtc/candidate", line)
        case let .error(message): ("error", message)
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["type": type, "value": value])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes a message from the socket. Unknown types (e.g. go2rtc's `mse`) return `nil`.
    /// - Parameter text: The JSON text.
    public init?(text: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        let value = object["value"] as? String ?? ""
        switch type {
        case "webrtc/offer": self = .offer(value)
        case "webrtc/answer": self = .answer(value)
        case "webrtc/candidate": self = .candidate(value)
        case "error": self = .error(value)
        default: return nil
        }
    }
}

// MARK: - Sharing

/// Which camera streams run, for the app-wide stream pool (web `rtcStreamRetention.ts` and the shared
/// `stream-manager.js`).
///
/// One stream per camera serves every tile and viewer, so opening a camera from its tile shows the frames
/// the tile is already playing. A camera that has been shown stays retained while views come and go, so a viewer
/// opened from a tile and a Home to Security switch attach to it at once; the pool releases it once no view has shown
/// it for a few seconds (``release(_:)``), because a stream decoding behind a page with no camera costs CPU, heat and
/// battery for nothing. A failed stream drops its retention so the next viewer starts fresh. Every stream stops in the
/// background and the retained ones restart on return.
public struct CameraStreamRetention: Equatable, Sendable {
    /// What the pool should do to a stream after an event.
    public enum Action: Equatable, Sendable {
        /// Start (or restart) the stream.
        case start
        /// Stop the stream.
        case stop
        /// Leave it as it is.
        case none
    }

    /// Visible views per camera id.
    public private(set) var viewers: [String: Int] = [:]
    /// Cameras kept running while no view shows them.
    public private(set) var retained: Set<String> = []
    /// Whether the app is in the background.
    public private(set) var isBackground = false
    /// Whether shown cameras stay retained (the web's session retention); off, a stream stops with its last view.
    public let retainsShownStreams: Bool

    /// - Parameter retainsShownStreams: Keep shown streams running for the session (web parity).
    public init(retainsShownStreams: Bool = true) {
        self.retainsShownStreams = retainsShownStreams
    }

    /// Whether a camera's stream should be running now.
    public func shouldRun(_ id: String) -> Bool {
        !isBackground && (viewers[id, default: 0] > 0 || retained.contains(id))
    }

    /// Every camera whose stream should be running now: shown or retained, and the app is in the foreground.
    public var wanted: Set<String> {
        isBackground ? [] : Set(viewers.keys).union(retained)
    }

    /// A view showing `id` appeared.
    /// - Parameters:
    ///   - id: The camera.
    ///   - isRunning: Whether its stream is already connecting or live (not stopped or failed).
    public mutating func appear(_ id: String, isRunning: Bool) -> Action {
        viewers[id, default: 0] += 1
        if retainsShownStreams { retained.insert(id) }
        return !isBackground && !isRunning ? .start : .none
    }

    /// A view showing `id` disappeared.
    public mutating func disappear(_ id: String) -> Action {
        let remaining = max(viewers[id, default: 0] - 1, 0)
        viewers[id] = remaining == 0 ? nil : remaining
        return shouldRun(id) ? .none : .stop
    }

    /// No view has shown `id` for a while: the session stops retaining it, so it is no longer wanted until a view shows it
    /// again (``appear(_:isRunning:)`` retains it afresh). The pool calls this after its pause delay, so moving between
    /// Home and Security, whose tiles share one stream, never stops it.
    /// - Returns: ``Action/stop`` when the stream should stop now, else ``Action/none`` (a view shows it again).
    public mutating func release(_ id: String) -> Action {
        retained.remove(id)
        return shouldRun(id) ? .none : .stop
    }

    /// The stream for `id` failed every mode: forget it so the next view starts fresh.
    public mutating func failed(_ id: String) {
        retained.remove(id)
    }

    /// The viewer retried a failed stream: retain it again, as a newly shown stream would be.
    public mutating func retry(_ id: String) {
        if retainsShownStreams { retained.insert(id) }
    }

    /// The app went to the background: every running stream stops.
    /// - Returns: The cameras to stop.
    public mutating func enterBackground() -> Set<String> {
        let running = Set(viewers.keys).union(retained)
        isBackground = true
        return running
    }

    /// The app returned: shown and retained streams restart (the pool starts them once the connection is
    /// confirmed alive, since a stream requested from a dead socket never gets its answer).
    /// - Returns: The cameras to start.
    public mutating func enterForeground() -> Set<String> {
        isBackground = false
        return Set(viewers.keys).union(retained)
    }
}
