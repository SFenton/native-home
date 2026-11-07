import AVFoundation
import HassCore
import Observation
import UIKit

/// Loads the camera for the expanded notification: Home Assistant's MJPEG stream at once (plain HTTP with the
/// token, so it works even when the websocket can't connect), and its HLS stream when that comes up, which then
/// takes over. The first to deliver frames turns on the Live badge.
@MainActor
@Observable
final class CameraNotificationModel {
    var title = ""
    var snapshot: UIImage?
    var player: AVPlayer?
    var isLive = false
    /// No stream will come: signed out, or both the MJPEG and the HLS stream failed before any frame arrived. The badge
    /// then reads "Stream unavailable" instead of leaving a black box or a stale snapshot.
    var failed = false
    private var mjpegEnded = false
    private var hlsEnded = false
    /// What the model is doing, shown in debug builds.
    var status = "starting"
    private var connection: HassConnection?
    private var observation: NSKeyValueObservation?
    private var mjpeg: Task<Void, Never>?
    private let trace = PushTrace.shared

    func start(entityID: String) {
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        guard let credentials = store.load() else {
            note("not signed in")
            failed = true
            return
        }
        let tokens = TokenManager(store: store)
        mjpeg = Task { await streamMJPEG(entityID: entityID, server: credentials.server, tokens: tokens) }
        startHLS(entityID: entityID, server: credentials.server, tokens: tokens)
    }

    func stop() {
        mjpeg?.cancel()
        player?.pause()
        connection?.disconnect()
    }

    /// Records that one stream gave up; when both have and nothing is live, the view says so.
    private func streamEnded(mjpeg isMJPEG: Bool) {
        if isMJPEG { mjpegEnded = true } else { hlsEnded = true }
        if mjpegEnded, hlsEnded, !isLive { failed = true }
    }

    private func note(_ text: String) {
        status = text
        trace.record("content: \(text)")
    }

    // MARK: - MJPEG

    private func streamMJPEG(entityID: String, server: HassServer, tokens: TokenManager) async {
        do {
            let token = try await tokens.validAccessToken()
            var request = URLRequest(url: server.url("/api/camera_proxy_stream/\(entityID)"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let stream = MJPEGChunkStream.open(request)
            let code = await stream.statusCode()
            note("mjpeg HTTP \(code)")
            guard code == 200 else { streamEnded(mjpeg: true); return }
            var scanner = MJPEGFrameScanner()
            for try await chunk in stream.chunks {
                if let frame = scanner.append(chunk).last, player == nil || !isLive, let image = UIImage(data: frame) {
                    snapshot = image
                    if !isLive { isLive = true; note("mjpeg live") }
                }
            }
            streamEnded(mjpeg: true)
        } catch is CancellationError {
        } catch {
            note("mjpeg failed \(type(of: error)) \((error as NSError).code)")
            streamEnded(mjpeg: true)
        }
    }

    // MARK: - HLS

    private func startHLS(entityID: String, server: HassServer, tokens: TokenManager) {
        let connection = HassConnection(server: server, tokens: tokens, store: EntityStore(),
                                        snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory
                                            .appendingPathComponent("notification-snapshot.json")))
        self.connection = connection
        connection.connect(subscribingToStates: false)
        Task {
            do {
                let path = try await connection.cameraStreamPath(entityId: entityID)
                trace.record("content: hls path received")
                guard let url = CameraStreamEndpoints.hlsURL(path: path, baseURL: server.baseURL) else { streamEnded(mjpeg: false); return }
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                observation = item.observe(\.status) { [weak self] item, _ in
                    let ready = item.status == .readyToPlay
                    let reason = item.error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" } ?? ""
                    Task { @MainActor in
                        guard let self else { return }
                        if ready {
                            self.player = player
                            self.isLive = true
                            self.mjpeg?.cancel()
                            self.note("hls playing")
                        } else if item.status == .failed {
                            self.trace.record("content: hls failed \(reason)")
                            self.streamEnded(mjpeg: false)
                        }
                    }
                }
                player.play()
                hlsPlayer = player
            } catch {
                trace.record("content: hls request failed \(type(of: error))")
                streamEnded(mjpeg: false)
            }
        }
    }

    /// Holds the HLS player while it loads, before it is shown.
    private var hlsPlayer: AVPlayer?
}
