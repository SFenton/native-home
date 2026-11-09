import AVFoundation
import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebRTC) && canImport(UIKit)
import WebRTC
#endif

/// Live video for one camera, over its latest snapshot.
///
/// The stream comes from ``CameraStreamPool``, so a tile and the viewer it opens show the same frames. The
/// snapshot stays on top until the stream shows a frame, then cross-fades out; if every mode fails it stays
/// (with a retry in the viewer). With `FENTON_REDACT_PRIVATE` the blurred snapshot always covers the video,
/// so shared screenshots show the live badge but never the picture.
struct CameraLiveView {
    /// Where the video is shown.
    enum Style {
        /// A grid tile: fills and crops, no badge, not hit-testable (the tile's button takes the tap).
        case tile
        /// The camera viewer: fits, with the status badge and a retry.
        case viewer
    }

    var camera: HomeConfig.Camera
    var style: Style = .viewer




    /// Whether the view is on screen, and whether the pool counts it as a viewer.
    private final class Presence {
        var onScreen = false
        var counted = false
    }




    // MARK: - Text

    /// The short badge text. A live stream says "Live" whichever mode carries it: HLS runs a few seconds behind WebRTC,
    /// which the person cannot change, so the pill does not say so (VoiceOver's value still does). While a stream that was live reconnects (its frames stopped, or the app went away) the
    /// snapshot stays up and the pill says when the picture was last live (direction G's "Snapshot from" pill; the
    /// time is when frames stopped, since the snapshot's own age is not known).
    static func badgeText(_ state: CameraStreamState, lastLive: Date? = nil) -> String {
        switch state.phase {
        case .connecting:
            if let lastLive { "Last live \(lastLive.formatted(date: .omitted, time: .shortened))" } else { "Connecting" }
        case .live: "Live"
        case .failed: "Snapshot"
        }
    }

    /// The VoiceOver value for the video.
    static func statusText(_ state: CameraStreamState) -> String {
        switch state.phase {
        case .connecting: "Connecting to live video"
        case .live: state.mode == .hls ? "Live, a few seconds behind" : "Live"
        case .failed: state.modes.isEmpty ? "Latest snapshot" : "Live video unavailable, showing the latest snapshot"
        }
    }
}

#if canImport(UIKit)
/// An `AVPlayerLayer` host with no controls (live HLS has nothing to scrub). Several layers can show one
/// player (a tile and its viewer).
struct HLSPlayerView {
    var player: AVPlayer
    /// Fill crops to the frame (tiles); fit letterboxes (the viewer).
    var fills = false



    /// A view backed by `AVPlayerLayer`.
    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }
}
#endif
