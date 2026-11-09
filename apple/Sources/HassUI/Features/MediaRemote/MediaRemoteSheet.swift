import HassCore
import HassDesign
import SwiftUI

/// The media remote sheet (pattern: `.agents/patterns/media-remote.md`; web `MediaRemoteModalContent.tsx`).
///
/// Direction G (`.agents/design/direction-g.md`, Sheets and Controls: Remote): the sections the remote has (Remote,
/// Apps, Devices, Hue Sync) sit in the bottom glass section bar. Remote shows the 3×3 pad (power in its top-right
/// cell), the volume card and the transport keys; the other sections show only their content. Where a split is
/// allowed (iPad and unfolded iPhone Duo in landscape) and the sheet is wide enough, the pad stays in a leading
/// column and the section scrolls in the trailing one; everywhere else it is one column (HIG: Layout, Sheets). A
/// ``ContentGate`` shows a centered spinner until every app's artwork (all sections) has loaded into the
/// ``ImagePipeline``, then fades the whole content in at once.
public struct MediaRemoteSheet {
    private let pipeline: ImagePipeline



    /// The longest side app artwork is decoded at: the largest tile (200 pt) at 3x, bucketed.
    nonisolated static let artworkPixels = ImagePipeline.bucket(600)

    /// Loads every URL into the image pipeline's memory cache, returning when all have loaded or failed, or after
    /// `timeout`; loads still running then keep going and fill their tiles when they land.
    nonisolated static func prefetch(_ urls: [URL], pipeline: ImagePipeline, timeout: Duration = .seconds(4)) async {
        guard !urls.isEmpty else { return }
        let pixels = artworkPixels
        let loads = Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        for await _ in pipeline.images(for: url, maxPixel: pixels) { return }
                    }
                }
            }
        }
        let deadline = Task { try? await Task.sleep(for: timeout) }
        // Whichever ends first: a task group would also wait for its slower child.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task { await loads.value; once.resume() }
            Task { await deadline.value; once.resume() }
        }
        deadline.cancel()
    }

    /// Every app tile's artwork, across all tabs, so switching tabs never shows a tile loading.
    static func artworkURLs(_ config: MediaRemoteConfig, server: HassServer?) -> [URL] {
        guard let server else { return [] }
        return config.apps.compactMap { $0.imagePath.map(server.url) }
    }

    /// The line under the title: the media player's app and state ("Plex · Playing"), or its state alone.
    static func subtitle(_ player: EntityState?) -> String? {
        guard let player else { return nil }
        let state = MediaRemoteState.format(player.state)
        guard !MediaRemoteState.isOff(player.state), let app = player.attributes["app_name"]?.string, !app.isEmpty else { return state }
        return "\(app) · \(state)"
    }





}

// MARK: - Layout policy

/// When the remote uses two columns (owner's split rules, `.agents/design/apple/split-view.md`).
enum MediaRemoteLayout {
    /// The narrowest sheet that holds the d-pad column beside the tab content.
    static let minimumTwoColumnWidth: CGFloat = 640

    /// Two columns only where the window may split (landscape, regular width) and the sheet is wide enough.
    static func usesTwoColumns(window: CGSize, isRegularWidth: Bool, container: CGSize) -> Bool {
        SplitPolicy.allowsSplit(size: window, isRegularWidth: isRegularWidth) && container.width >= minimumTwoColumnWidth
    }
}

/// Resumes a continuation the first time it is asked to.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }

    func resume() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }
}

/// The window the sheet is in. A sheet's own size class is compact on iPad, so layout decisions read the window.
struct WindowMetrics: Equatable {
    var size: CGSize?
    var isRegularWidth = false
}
