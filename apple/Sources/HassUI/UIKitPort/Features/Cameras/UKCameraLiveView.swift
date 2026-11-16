#if os(iOS)
import AVFoundation
import HassCore
import HassDesign
import UIKit
#if canImport(WebRTC)
import WebRTC
#endif

/// Live video for one camera over its latest snapshot (`CameraLiveView`), in UIKit.
///
/// The stream comes from ``CameraStreamPool``, so a tile and the viewer it opens show the same frames. The order and fallback are the
/// SwiftUI view's: WebRTC (`RTCMTLVideoView`), then HLS (`AVPlayerLayer`), then the snapshot. The snapshot stays on top until the
/// stream shows a frame, then cross-fades out; if every mode fails it stays (with a retry in the viewer). With
/// `FENTON_REDACT_PRIVATE` the blurred snapshot always covers the video.
///
/// The view tells the pool when it shows the camera: it counts as a viewer while it is in a window (an unselected tab's and a
/// covered page's views are out of the window, which is what `\.sectionIsShowing` and `onDisappear` say in SwiftUI), and the pool
/// owns the pause rule (`.agents/patterns/camera-streams.md`).
///
/// ```swift
/// let live = UKCameraLiveView(camera: camera, style: .tile, context: context)   // fills and crops, not hit-testable
/// let viewer = UKCameraLiveView(camera: camera, style: .viewer, context: context) // fits, badge, retry, one accessibility element
/// ```
@MainActor
final class UKCameraLiveView: UIView {
    typealias Style = CameraLiveView.Style

    let camera: HomeConfig.Camera
    let style: Style
    private let context: UKContext
    private let pool: CameraStreamPool
    private let configuration: ServerUICameraDescriptor?
    private let privacy: @MainActor () -> Bool
    private let reader: UKCameraReadProvider?
    private let bag = UKObservationBag()

    private let content = UIView()
    private let hlsView = HLSPlayerView.PlayerLayerView()
    #if canImport(WebRTC)
    private var rtcView: LiveVideoSurface?
    private weak var attachedTrack: RTCVideoTrack?
    #endif
    private let snapshotLayer = UIView()
    private let snapshot: UKCameraSnapshotView
    private let pausedView = UIImageView()
    private let badge = UKCameraBadgeView()
    private let retryButton = UIButton(type: .system)
    private let videoElement = UIView()
    private let stateLabel = UILabel.uk(.body, ink: .white)

    private var onScreen = false
    /// Whether the view is really on screen (scroll viewport, hidden chain, active scene, no rotation in flight), not just in a window.
    private lazy var monitor = OnScreenMonitor(view: self) { [weak self] shows in
        self?.onScreen = shows
        self?.syncPresence()
    }
    private var counted = false
    private var lastPhase: CameraStreamState.Phase?

    /// - Parameters:
    ///   - camera: The camera.
    ///   - style: `.tile` fills and crops with no badge; `.viewer` fits, with the status badge and a retry.
    ///   - context: Gives the store (snapshot), the connection (stream, offline) and the section.
    ///   - pool: The stream pool; the app's shared one by default (the viewer gallery passes one with no modes).
    init(camera: HomeConfig.Camera, style: Style, context: UKContext, pool: CameraStreamPool = .shared,
         configuration: ServerUICameraDescriptor? = nil, reader: UKCameraReadProvider? = nil,
         privacy: @escaping @MainActor () -> Bool = { ScreenshotPrivacy.isRedacting }) {
        self.camera = camera
        self.style = style
        self.context = context
        self.pool = pool
        self.configuration = configuration
        self.privacy = privacy
        self.reader = reader
        snapshot = UKCameraSnapshotView(entityId: configuration?.snapshotEntityId ?? camera.entityId, context: context, reader: reader)
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        content.isUserInteractionEnabled = false
        content.clipsToBounds = true
        addSubview(content)
        hlsView.playerLayer.videoGravity = style == .tile ? .resizeAspectFill : .resizeAspect
        hlsView.clipsToBounds = true
        hlsView.isHidden = true
        content.addSubview(hlsView)
        snapshotLayer.isUserInteractionEnabled = false
        snapshotLayer.clipsToBounds = true
        snapshotLayer.addSubview(snapshot)
        pausedView.contentMode = style == .tile ? .scaleAspectFill : .scaleAspectFit
        pausedView.clipsToBounds = true
        pausedView.isHidden = true
        snapshotLayer.addSubview(pausedView)
        content.addSubview(snapshotLayer)
        stateLabel.numberOfLines = 0
        stateLabel.textAlignment = .center
        stateLabel.isHidden = true
        addSubview(stateLabel)
        isAccessibilityElement = false
        switch style {
        case .tile:
            // A tile's button names the camera and reads its state, and takes the tap.
            isUserInteractionEnabled = false
        case .viewer:
            buildViewer()
        }
        let model = pool.model(for: camera)
        bag.observe { [weak self] in self?.render(model) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        MainActor.assumeIsolated {
            if counted {
                if let reader { reader.setVisible(camera, false) } else { pool.disappear(camera) }
            }
        }
    }

    // MARK: Viewer chrome

    private func buildViewer() {
        addSubview(badge)
        var configuration = UIButton.Configuration.filled()
        configuration.title = self.configuration?.labels.retry ?? "Retry Live Video"
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = HassTokens.Spacing.s
        retryButton.configuration = configuration
        retryButton.isHidden = true
        retryButton.accessibilityIdentifier = "camera.viewer.retry"
        retryButton.addAction(UIAction { [weak self] _ in
            guard let self, !privacy() else { return }
            if let reader { reader.retry(camera) }
            else if let connection = context.connection { pool.retry(camera, connection: connection) }
        }, for: .touchUpInside)
        // A clear shape of the video's own size is the one element that reads its state: an element's frame is the union of its
        // children's, and the fill-cropped snapshot is wider than the video (the SwiftUI zero-frame fix, 2026-10-17).
        videoElement.isAccessibilityElement = true
        videoElement.isUserInteractionEnabled = false
        videoElement.accessibilityLabel = self.configuration == nil ? "\(camera.title) camera" : camera.title
        videoElement.accessibilityIdentifier = "camera.viewer.video"
        insertSubview(videoElement, aboveSubview: content)
        addSubview(retryButton)
    }

    // MARK: Binding

    private func render(_ model: CameraLiveModel) {
        let state = model.state
        let redacting = privacy()
        let entity = context.store.entity(camera.entityId).state
        let unavailable = configuration != nil && (context.valuesPending || EntityState.isUnavailable(entity?.state))
        // Configured privacy is opaque, including the snapshot and last-live frame.
        let concealed = configuration != nil && (redacting || unavailable)
        content.isHidden = concealed
        stateLabel.isHidden = !concealed
        let status = configuration?.status(state: state, entityState: entity?.state, pending: context.valuesPending,
                                           hidden: redacting, offline: reader?.isOffline ?? context.connection?.isOffline ?? false)
        stateLabel.text = status
        stateLabel.accessibilityLabel = status
        if concealed { model.setMuted(true) }
        syncPresence()
        let animated = lastPhase != nil && lastPhase != state.phase && window != nil
        lastPhase = state.phase

        // Players: redacted runs keep decoding (so the state still reaches Live) but never show it.
        hlsView.isHidden = model.hlsPlayer == nil
        if hlsView.playerLayer.player !== model.hlsPlayer { hlsView.playerLayer.player = model.hlsPlayer }
        hlsView.alpha = redacting ? 0 : 1
        #if canImport(WebRTC)
        updateRTC(model.webRTCPeer?.videoTrack)
        rtcView?.alpha = redacting ? 0 : 1
        #endif

        // The snapshot stays over the player whenever the phase is not live.
        let coversVideo = state.phase != .live || redacting
        let paused = redacting ? nil : model.pausedFrame
        pausedView.image = paused.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
        pausedView.isHidden = paused == nil
        let alpha: CGFloat = coversVideo ? 1 : 0
        if animated {
            UKMotion.animate(.quick, reduced: .quick) { self.snapshotLayer.alpha = alpha }
        } else {
            snapshotLayer.alpha = alpha
        }

        if style == .viewer {
            videoElement.accessibilityValue = status ?? CameraLiveView.statusText(state)
            badge.isHidden = concealed
            badge.update(state: state, lastLive: model.lastLiveAt, animated: animated,
                         text: state.phase == .live ? configuration?.labels.live : status)
            let showsRetry = !concealed && state.phase == .failed && !state.modes.isEmpty
            if retryButton.isHidden == showsRetry {
                retryButton.isHidden = !showsRetry
                accessibilityElements = [videoElement] + (showsRetry ? [retryButton] : [])
            }
            setNeedsLayout()
        }
    }

    #if canImport(WebRTC)
    private func updateRTC(_ track: RTCVideoTrack?) {
        guard track !== attachedTrack else { return }
        attachedTrack = nil
        guard let track else {
            rtcView?.setTrack(nil)
            rtcView?.removeFromSuperview()
            rtcView = nil
            return
        }
        let view = rtcView ?? {
            let created = LiveVideoSurface()
            created.fills = style == .tile
            content.insertSubview(created, belowSubview: snapshotLayer)
            rtcView = created
            setNeedsLayout()
            return created
        }()
        // The surface attaches itself to the track only while it is on screen (`OnScreenMonitor`).
        view.setTrack(track)
        attachedTrack = track
    }
    #endif

    // MARK: Presence

    override func didMoveToWindow() {
        super.didMoveToWindow()
        monitor.windowDidChange()
    }

    /// Tells the pool when this view starts or stops showing the camera.
    private func syncPresence() {
        guard reader != nil || context.connection != nil else { return }
        let permitted = configuration == nil || (!privacy() && !context.valuesPending &&
            !EntityState.isUnavailable(context.store.entity(camera.entityId).state?.state))
        let visible = onScreen && permitted
        guard visible != counted else { return }
        counted = visible
        if let reader { reader.setVisible(camera, visible) }
        else if visible, let connection = context.connection { pool.appear(camera, connection: connection) }
        else { pool.disappear(camera) }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        monitor.layoutDidRun()
        content.frame = bounds
        stateLabel.frame = bounds.insetBy(dx: HassTokens.Spacing.s, dy: HassTokens.Spacing.s)
        hlsView.frame = bounds
        #if canImport(WebRTC)
        rtcView?.frame = bounds
        #endif
        snapshotLayer.frame = bounds
        snapshot.frame = bounds
        pausedView.frame = bounds
        guard style == .viewer else { return }
        videoElement.frame = bounds
        let pad = HassTokens.Spacing.s
        let badgeSize = badge.sizeThatFits(CGSize(width: max(0, bounds.width - 2 * pad), height: CGFloat.greatestFiniteMagnitude))
        let leading = effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - pad - badgeSize.width : pad
        badge.frame = CGRect(x: leading, y: pad, width: badgeSize.width, height: badgeSize.height)
        let retryHeight = max(HassTokens.minTarget, retryButton.sizeThatFits(CGSize(width: max(0, bounds.width - 2 * pad), height: CGFloat.greatestFiniteMagnitude)).height)
        let retryWidth = min(max(0, bounds.width - 2 * pad), retryButton.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: retryHeight)).width)
        retryButton.frame = CGRect(x: (bounds.width - retryWidth) / 2, y: bounds.height - pad - retryHeight, width: retryWidth, height: retryHeight)
    }
}

// MARK: - Badge

/// The viewer's status pill (`CameraLiveView.badge`): the arc while connecting, the red dot while live, the photo glyph on the
/// snapshot, then the short text, on a black 75% capsule. Decorative: the video element reads the state.
@MainActor
private final class UKCameraBadgeView: UIView {
    private let spinner = UKArcSpinnerView(.inline)
    private let dot = UIView()
    private let photo = UIImageView(image: UIImage(systemName: "photo"))
    private let label = UILabel()
    private var phase: CameraStreamState.Phase = .connecting

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.75)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        spinner.color = .white
        spinner.isAccessibilityElement = false
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 4
        photo.tintColor = .white
        photo.contentMode = .scaleAspectFit
        label.textColor = .white
        label.numberOfLines = 1
        for view in [spinner, dot, photo, label] { addSubview(view) }
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            label.font = UKFont.preferred(.caption1, weight: .semibold, traits: traitCollection)
            photo.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: label.font)
            setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(state: CameraStreamState, lastLive: Date?, animated: Bool, text: String? = nil) {
        let apply = {
            self.phase = state.phase
            self.spinner.isHidden = state.phase != .connecting
            self.dot.isHidden = state.phase != .live
            self.photo.isHidden = state.phase != .failed
            self.label.text = text ?? CameraLiveView.badgeText(state, lastLive: lastLive)
            self.setNeedsLayout()
            self.superview?.setNeedsLayout()
        }
        if animated {
            UIView.transition(with: self, duration: MotionTokens.quickDuration, options: [.transitionCrossDissolve, .curveEaseOut], animations: apply)
        } else {
            apply()
        }
    }

    private var indicatorSize: CGSize {
        switch phase {
        case .connecting: spinner.intrinsicContentSize
        case .live: CGSize(width: 8, height: 8)
        case .failed: photo.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let indicator = indicatorSize
        let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let height = max(indicator.height, ceil(text.height)) + 2 * HassTokens.Spacing.xs
        let width = HassTokens.Spacing.s * 2 + indicator.width + HassTokens.Spacing.xs + ceil(text.width)
        return CGSize(width: min(width, max(size.width, 1)), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let indicator = indicatorSize
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let textSize = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let indicatorX = HassTokens.Spacing.s
        let textX = indicatorX + indicator.width + HassTokens.Spacing.xs
        func place(_ view: UIView, x: CGFloat, size: CGSize) {
            let originX = mirror ? bounds.width - x - size.width : x
            view.frame = CGRect(x: originX, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
        place(spinner, x: indicatorX, size: indicator)
        place(dot, x: indicatorX, size: indicator)
        place(photo, x: indicatorX, size: indicator)
        place(label, x: textX, size: CGSize(width: min(ceil(textSize.width), max(0, bounds.width - textX - HassTokens.Spacing.s)), height: ceil(textSize.height)))
        label.textAlignment = mirror ? .right : .left
    }
}

// MARK: - Snapshot

/// A camera's `entity_picture` snapshot (a tokenized `/api/camera_proxy` URL) through the image pipeline, the last one kept on
/// screen while the next loads (`CameraSnapshotView`). Decorative: the camera's element reads its state.
@MainActor
final class UKCameraSnapshotView: UIView {
    private let image = UKCachedImageView()
    private let placeholder = UKCameraPlaceholderView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let bag = UKObservationBag()

    init(entityId: String, context: UKContext, reader: UKCameraReadProvider? = nil) {
        super.init(frame: .zero)
        backgroundColor = .quaternarySystemFill
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        image.placeholder = placeholder
        addSubview(image)
        // A redacted run blurs the picture (`blur(radius: 40)`).
        blur.isHidden = !ScreenshotPrivacy.isRedacting
        addSubview(blur)
        let box = context.store.entity(entityId)
        let baseURL = context.connection?.server.baseURL
        bag.observe { [weak self] in
            if let reader {
                self?.image.url = reader.snapshotURL(entityId)
                return
            }
            guard let picture = box.state?.attributes["entity_picture"]?.string else {
                self?.image.url = nil
                return
            }
            self?.image.url = URL(string: picture, relativeTo: baseURL)?.absoluteURL
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        blur.frame = bounds
    }
}

/// The `video` glyph (title size, secondary ink) centred where a snapshot has not loaded.
@MainActor
private final class UKCameraPlaceholderView: UIView {
    private let icon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = .secondaryLabel
        icon.contentMode = .center
        addSubview(icon)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            icon.image = UIImage(systemName: "video", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title1, traits: traitCollection)))
            setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds
    }
}
#endif
