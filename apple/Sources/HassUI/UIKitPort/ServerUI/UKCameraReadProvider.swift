#if os(iOS)
import HassCore
import Foundation

// MARK: - Scoped camera reads

/// Leases the existing stream pool and resolves snapshots without exposing a session or service caller.
/// Recording remains on the host's separate (rejecting in preview) command path.
@MainActor
final class UKCameraReadProvider {
    private let descriptors: [ServerUICameraDescriptor]
    private let appear: (HomeConfig.Camera) -> Void
    private let disappear: (HomeConfig.Camera) -> Void
    private let retryStream: (HomeConfig.Camera) -> Void
    private let picture: (String) -> URL?
    private let offline: () -> Bool

    convenience init(descriptors: [ServerUICameraDescriptor], connection: HassConnection, store: EntityStore,
                     pool: CameraStreamPool = .shared) {
        self.init(descriptors: descriptors,
                  appear: { pool.appear($0, connection: connection) },
                  disappear: { pool.disappear($0) },
                  retry: { pool.retry($0, connection: connection) },
                  snapshotURL: { id in
                      guard let path = store.entity(id).state?.attributes["entity_picture"]?.string,
                            let url = URL(string: path, relativeTo: connection.server.baseURL)?.absoluteURL,
                            url.scheme == connection.server.baseURL.scheme,
                            url.host == connection.server.baseURL.host,
                            url.port == connection.server.baseURL.port else { return nil }
                      return url
                  }, offline: { connection.isOffline })
    }

    init(descriptors: [ServerUICameraDescriptor], appear: @escaping (HomeConfig.Camera) -> Void,
         disappear: @escaping (HomeConfig.Camera) -> Void, retry: @escaping (HomeConfig.Camera) -> Void,
         snapshotURL: @escaping (String) -> URL?, offline: @escaping () -> Bool) {
        self.descriptors = descriptors
        self.appear = appear
        self.disappear = disappear
        retryStream = retry
        picture = snapshotURL
        self.offline = offline
    }

    var isOffline: Bool { offline() }

    func accepts(_ descriptor: ServerUICameraDescriptor) -> Bool {
        descriptors.contains {
            $0.entityId == descriptor.entityId && $0.rtcStreamId == descriptor.rtcStreamId
                && $0.snapshotEntityId == descriptor.snapshotEntityId
        }
    }

    func setVisible(_ camera: HomeConfig.Camera, _ visible: Bool) {
        guard permits(camera) else { NSLog("ServerUI camera lease rejected: unapproved source."); return }
        if visible { appear(camera) } else { disappear(camera) }
    }

    func retry(_ camera: HomeConfig.Camera) {
        guard permits(camera) else { NSLog("ServerUI camera retry rejected: unapproved source."); return }
        retryStream(camera)
    }

    func snapshotURL(_ entityId: String) -> URL? {
        guard descriptors.contains(where: { $0.snapshotEntityId == entityId }) else {
            NSLog("ServerUI camera snapshot rejected: unapproved source.")
            return nil
        }
        return picture(entityId)
    }

    private func permits(_ camera: HomeConfig.Camera) -> Bool {
        descriptors.contains { $0.entityId == camera.entityId && $0.rtcStreamId == camera.rtcStreamId }
    }
}
#endif
