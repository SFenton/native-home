import Foundation

// MARK: - Configured camera values

/// A camera attachment, never a URL, credential, service expression or independent connection.
public struct ServerUICameraDescriptor: Equatable, Sendable {
    public let entityId: String
    public let snapshotEntityId: String
    public let rtcStreamId: String
    public let aspectRatio: Double
    public let recording: Recording
    public let labels: Labels

    /// The authored recording choices.
    public enum Recording: Equatable, Sendable {
        case disabled
        case script(stateEntityId: String, scriptEntityId: String)
    }

    /// Copy belongs to the document; native code owns the meaning and safety of each state.
    public struct Labels: Equatable, Sendable {
        public let loading: String
        public let unavailable: String
        public let hidden: String
        public let connecting: String
        public let live: String
        public let delayed: String
        public let snapshot: String
        public let retry: String
        public let recordFailed: String
        public let photosTitle: String
        public let photosMessage: String
        public let settings: String
        public let cancel: String
    }

    /// Uses the canonical script toggle and recording feedback semantics.
    public func camera(title: String) -> HomeConfig.Camera {
        switch recording {
        case .disabled:
            return .init(title: title, entityId: entityId, rtcStreamId: rtcStreamId, aspectRatio: aspectRatio)
        case .script(let state, let script):
            return .init(title: title, entityId: entityId, rtcStreamId: rtcStreamId, aspectRatio: aspectRatio,
                         recordingEntityId: state, recordingScriptEntityId: script)
        }
    }

    /// Availability and privacy never turn a missing entity into a successful snapshot.
    public func status(state: CameraStreamState, entityState: String?, pending: Bool, hidden: Bool, offline: Bool) -> String {
        if hidden { return labels.hidden }
        if pending { return labels.loading }
        if EntityState.isUnavailable(entityState) { return labels.unavailable }
        if state.phase == .live { return state.mode == .hls ? labels.delayed : labels.live }
        if offline { return labels.unavailable }
        return state.phase == .connecting ? labels.connecting : labels.snapshot
    }
}

public extension ServerUICompositionDocument {
    /// Canonical intents only. Photos authorization is always checked by the native saver.
    enum CameraIntent: String, Sendable { case snapshot, sound, record }
    enum CameraTint: String, Sendable { case action, danger }
    struct CameraControl: Equatable, Sendable {
        public let intent: CameraIntent
        public let title: String
        public let activeTitle: String
        public let busyTitle: String
        public let failureTitle: String
        public let icon: Symbol
        public let activeIcon: Symbol
        public let failureIcon: Symbol
        public let tint: CameraTint
    }
    struct CameraTile: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let openHint: String
        public let action: Action
    }
    struct CameraVideo: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
    }
    struct CameraControls: Equatable, Sendable {
        public let node: Node
        public let sourceId: String
        public let controls: [CameraControl]
    }
}
