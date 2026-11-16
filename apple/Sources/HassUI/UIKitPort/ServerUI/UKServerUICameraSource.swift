#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Native camera intent adapter

/// One document attachment to the app's pool and EntityBoxes, retaining commands through publications.
@MainActor
@Observable
final class UKServerUICameraSource {
    let configuration: ServerUICameraDescriptor
    let camera: HomeConfig.Camera
    let pool: CameraStreamPool
    let model: CameraLiveModel
    let context: UKContext
    let reader: UKCameraReadProvider?
    @ObservationIgnored private let privacy: @MainActor () -> Bool
    @ObservationIgnored private let saveSnapshot: @MainActor (CameraLiveModel, URL?) async -> CameraSnapshotSaver.Result
    private(set) var snapshot = CameraSnapshotFeedback.idle
    private(set) var recordingInFlight = false
    private(set) var photosDenied = false
    private(set) var actions: OptimisticActions?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    init(configuration: ServerUICameraDescriptor, context: UKContext, pool: CameraStreamPool,
         reader: UKCameraReadProvider? = nil,
         privacy: @escaping @MainActor () -> Bool = { ScreenshotPrivacy.isRedacting },
         saveSnapshot: @escaping @MainActor (CameraLiveModel, URL?) async -> CameraSnapshotSaver.Result = { model, url in
             let frame = model.liveFrameSource()
             return await CameraSnapshotSaver.save(frame: await frame?.image(), fallbackURL: url)
         }) {
        self.configuration = configuration
        self.context = context
        self.pool = pool
        self.reader = reader
        self.privacy = privacy
        self.saveSnapshot = saveSnapshot
        camera = configuration.camera(title: "")
        model = pool.model(for: camera)
    }

    var isPrivate: Bool { privacy() }
    var isAvailable: Bool {
        !isPrivate && !context.valuesPending && !(reader?.isOffline ?? context.connection?.isOffline ?? false)
            && !EntityState.isUnavailable(context.store.entity(camera.entityId).state?.state)
    }
    var hasPendingIntent: Bool {
        recordingInFlight || snapshot == .saving || photosDenied
            || camera.recordingEntityId.map { actions?.isPending($0) == true } == true
    }
    var isRecording: Bool {
        guard let id = camera.recordingEntityId else { return false }
        return (actions?.shown(id) ?? context.store.entity(id).state?.state) == "on"
    }
    var recordingFailed: Bool {
        camera.recordingEntityId.map { actions?.isFailed($0) == true } == true
    }
    var status: String {
        configuration.status(state: model.state, entityState: context.store.entity(camera.entityId).state?.state,
                             pending: context.valuesPending, hidden: isPrivate, offline: reader?.isOffline ?? context.connection?.isOffline ?? false)
    }

    func canPerform(_ intent: ServerUICompositionDocument.CameraIntent) -> Bool {
        guard isAvailable else { return false }
        switch intent {
        case .sound: return true
        case .snapshot: return snapshot != .saving && !photosDenied
        case .record:
            guard context.caller != nil, let id = camera.recordingEntityId, camera.recordCall != nil else { return false }
            let state = context.store.entity(id).state?.state
            return !recordingInFlight && (state == "on" || state == "off")
        }
    }

    /// Revalidates native policy at the gesture, not only when the enabled face was rendered.
    func perform(_ intent: ServerUICompositionDocument.CameraIntent) throws(UKServerUIRendererError) {
        guard canPerform(intent) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        switch intent {
        case .sound: model.setMuted(!model.isMuted)
        case .snapshot: snapshotIntent()
        case .record: recordIntent()
        }
    }

    private func recordIntent() {
        guard let caller = context.caller, let id = camera.recordingEntityId, let call = camera.recordCall else { return }
        let actions = actions ?? OptimisticActions(store: context.store, rules: [id: .confirmation], caller: caller)
        self.actions = actions
        recordingInFlight = true
        let task = actions.perform(call, showing: [.init(id, isRecording ? "off" : "on", revertAfter: .seconds(6))])
        // The optimistic timeout is not the lifetime of the underlying service command.
        Task { @MainActor [self] in
            await task.value
            recordingInFlight = false
            if recordingFailed { Announcer.announce(configuration.labels.recordFailed) }
        }
    }

    private func snapshotIntent() {
        resetTask?.cancel()
        snapshot = .saving
        let picture = context.store.entity(configuration.snapshotEntityId).state?.attributes["entity_picture"]?.string
        let url = reader?.snapshotURL(configuration.snapshotEntityId)
            ?? picture.flatMap { value in context.connection.flatMap { URL(string: value, relativeTo: $0.server.baseURL)?.absoluteURL } }
        snapshotTask = Task { @MainActor [self] in
            let result = await saveSnapshot(model, url)
            switch result {
            case .saved: snapshot = .saved
            case .denied: snapshot = .idle; photosDenied = true
            case .failed: snapshot = .failed; UKTapFeedback.failure()
            }
            snapshotTask = nil
            if snapshot == .saved {
                resetTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.snapshot = .idle
                }
            }
        }
    }

    func acknowledgePhotosDenied() { photosDenied = false }

    /// Awaiting the injected saver is also useful to the parent-owned hosted regression suite.
    func waitForSnapshot() async { await snapshotTask?.value }
}
#endif
