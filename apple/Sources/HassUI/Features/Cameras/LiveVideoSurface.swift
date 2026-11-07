#if canImport(WebRTC) && canImport(UIKit)
import UIKit
@preconcurrency import WebRTC

/// A WebRTC video track drawn in a Metal view that is attached to the track only while it is on screen (``OnScreenMonitor``).
///
/// `RTCMTLVideoView` draws from `renderFrame` on the main thread and `CAMetalLayer.nextDrawable` can block there for up to a second
/// per frame when the layer is covered, clipped away or mid-rotation, so a surface that is not visible must not be a renderer at
/// all: it removes itself from the track (no frames, no draws; the last drawn frame stays in the layer) and joins it again the
/// moment it is visible. The one place both apps draw live video: ``WebRTCVideoView`` (SwiftUI) and `UKCameraLiveView` (UIKit).
@MainActor
final class LiveVideoSurface: UIView {
    private let video = RTCMTLVideoView()
    private var monitor: OnScreenMonitor?
    private weak var track: RTCVideoTrack?
    private var attached = false

    /// Fill crops to the frame (tiles); fit letterboxes (the viewer).
    var fills = false {
        didSet { video.videoContentMode = fills ? .scaleAspectFill : .scaleAspectFit }
    }

    /// Whether the surface is attached to its track right now (tests and diagnostics).
    var isDrawing: Bool { attached }

    /// Whether the surface is on screen, as the monitor last judged.
    var isOnScreen: Bool { monitor?.isOnScreen ?? false }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        video.clipsToBounds = true
        video.isUserInteractionEnabled = false
        video.isAccessibilityElement = false
        video.videoContentMode = .scaleAspectFit
        addSubview(video)
        video.isEnabled = false
        monitor = OnScreenMonitor(view: self) { [weak self] _ in self?.sync() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The track to show (nil clears it).
    func setTrack(_ newTrack: RTCVideoTrack?) {
        guard newTrack !== track else { return }
        detach()
        track = newTrack
        sync()
    }

    private func sync() {
        let wanted = track != nil && (monitor?.isOnScreen ?? false)
        guard wanted != attached else { return }
        // `isEnabled` pauses the MTKView's display link, which otherwise ticks and draws on the main thread whether or not frames arrive.
        if wanted {
            video.isEnabled = true
            track?.add(video)
        } else {
            track?.remove(video)
            video.isEnabled = false
        }
        attached = wanted
    }

    private func detach() {
        if attached { track?.remove(video) }
        attached = false
        video.isEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        monitor?.windowDidChange()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        video.frame = bounds
        monitor?.layoutDidRun()
    }
}
#endif
