#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Atomic camera hosts

/// A keyed host for domain primitives only; modal and grid composition remain shell-owned.
@MainActor
final class UKServerUICameraView: UIView, UKGridMeasuring {
    private var definition: ServerUICompositionDocument.Component?
    private var descriptor: ServerUICameraDescriptor?
    private var content: UIView?
    private var source: UKServerUICameraSource?
    private var tileAspect = false

    func apply(_ component: ServerUICompositionDocument.Component, source: UKServerUICameraSource,
               presenter: @escaping () -> UIViewController?, open: @escaping (ServerUICompositionDocument.Action, UIView) -> Void,
               error: @escaping (UKServerUIRendererError) -> Void) {
        guard definition != component || descriptor != source.configuration || self.source !== source else { return }
        if let previous = self.source, previous.model !== source.model {
            switch definition {
            case .cameraVideo, .cameraControls, .cameraViewer: previous.model.setMuted(true)
            default: break
            }
        }
        content?.removeFromSuperview()
        definition = component
        descriptor = source.configuration
        self.source = source
        tileAspect = false
        switch component {
        case .cameraTile(let tile):
            tileAspect = true
            let view = UKCameraTileView(camera: source.configuration.camera(title: tile.node.title), context: source.context,
                                        identifier: tile.node.id, pool: source.pool, configuration: source.configuration,
                                        openHint: tile.openHint, reader: source.reader, privacy: { [weak source] in source?.isPrivate ?? true })
            view.onOpen = { open(tile.action, $0) }
            content = view
        case .cameraVideo(let video):
            let view = UKCameraLiveView(camera: source.configuration.camera(title: video.node.title), style: .viewer,
                                        context: source.context, pool: source.pool, configuration: source.configuration,
                                        reader: source.reader, privacy: { [weak source] in source?.isPrivate ?? true })
            view.accessibilityIdentifier = video.node.id
            content = view
        case .cameraControls(let controls):
            content = UKServerUICameraControls(controls: controls, source: source, presenter: presenter, error: error)
        case .cameraViewer(let controls):
            let live = UKCameraLiveView(camera: source.configuration.camera(title: controls.node.title), style: .viewer,
                                        context: source.context, pool: source.pool, configuration: source.configuration,
                                        reader: source.reader, privacy: { [weak source] in source?.isPrivate ?? true })
            let buttons = UKServerUICameraControls(controls: controls, source: source, presenter: presenter, error: error)
            content = UKServerUICameraViewerContent(video: live, controls: buttons, aspect: source.configuration.aspectRatio)
        default: content = nil
        }
        if let content { addSubview(content) }
        ukRemeasureContainers(includingSelf: true)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        if let content = content as? UKGridMeasuring { return content.gridHeight(forWidth: width) }
        guard let descriptor else { return 0 }
        return width / (tileAspect ? CameraTile.aspectRatio : descriptor.aspectRatio)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); content?.frame = bounds }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            switch definition {
            case .cameraVideo, .cameraControls, .cameraViewer: source?.model.setMuted(true)
            default: break
            }
        }
    }
}

// MARK: - Configured controls and Photos recovery

/// Authored values over the same circle buttons and AX layout as the canonical camera viewer.
@MainActor
final class UKServerUICameraControls: UIView, UKGridMeasuring {
    private let source: UKServerUICameraSource
    private let controls: ServerUICompositionDocument.CameraControls
    private let buttons: [UKCameraControlButton]
    private let feedback = UILabel.uk(.footnote, ink: UKInk.danger)
    private let strip: UKCameraControlStripView
    private let bag = UKObservationBag()
    private let presenter: () -> UIViewController?
    private var presentingDenied = false
    private var lastAnnouncement: String?

    init(controls: ServerUICompositionDocument.CameraControls, source: UKServerUICameraSource,
         presenter: @escaping () -> UIViewController?, error onError: @escaping (UKServerUIRendererError) -> Void) {
        self.controls = controls
        self.source = source
        self.presenter = presenter
        buttons = controls.controls.map { _ in UKCameraControlButton() }
        strip = UKCameraControlStripView(buttons: buttons, caption: feedback)
        super.init(frame: .zero)
        feedback.numberOfLines = 0
        addSubview(strip)
        strip.accessibilityLabel = controls.node.title
        for (control, button) in zip(controls.controls, buttons) {
            button.onTap = { [weak source] in
                guard let source else { return }
                do throws(UKServerUIRendererError) { try source.perform(control.intent) }
                catch { onError(error) }
            }
        }
        bag.observe { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func render() {
        let concealed = source.isPrivate
        if concealed { source.model.setMuted(true) }
        for (control, button) in zip(controls.controls, buttons) {
            let active: Bool
            let busy: Bool
            let failed: Bool
            switch control.intent {
            case .sound: active = !source.model.isMuted; busy = false; failed = false
            case .snapshot: active = source.snapshot == .saved; busy = source.snapshot == .saving; failed = source.snapshot == .failed
            case .record: active = source.isRecording; busy = source.recordingInFlight; failed = source.recordingFailed
            }
            let title = concealed ? source.status : failed ? control.failureTitle : busy ? control.busyTitle : active ? control.activeTitle : control.title
            let enabled = source.canPerform(control.intent)
            let symbol = concealed ? control.icon.drawn : failed ? control.failureIcon.drawn : active ? control.activeIcon.drawn : control.icon.drawn
            button.configure(.init(title: title, symbol: symbol,
                                   isActive: !concealed && (active || busy), tint: control.tint == .danger ? UKInk.danger : UKInk.action,
                                   pulses: !concealed && (busy || (control.intent == .record && active)),
                                   accessibilityLabel: control.title, accessibilityValue: enabled || busy ? title : source.status,
                                   isToggle: control.intent != .snapshot, identifier: "\(controls.node.id).\(control.intent.rawValue)",
                                   isEnabled: enabled))
        }
        feedback.text = source.recordingFailed && !concealed ? source.configuration.labels.recordFailed : nil
        if let snapshotControl = controls.controls.first(where: { $0.intent == .snapshot }),
           !concealed && (source.snapshot == .saved || source.snapshot == .failed) {
            let announcement = source.snapshot == .saved ? snapshotControl.activeTitle : snapshotControl.failureTitle
            if announcement != lastAnnouncement { Announcer.announce(announcement); lastAnnouncement = announcement }
        } else { lastAnnouncement = nil }
        if source.photosDenied, !presentingDenied, window != nil { presentDenied() }
        ukRemeasureContainers(includingSelf: true)
    }

    private func presentDenied() {
        guard let presenter = presenter(), presenter.presentedViewController == nil else { return }
        presentingDenied = true
        let copy = source.configuration.labels
        let alert = UIAlertController(title: copy.photosTitle, message: copy.photosMessage, preferredStyle: .alert)
        alert.view.accessibilityIdentifier = "camera-photos-denied"
        let acknowledge = { [weak self, source] in source.acknowledgePhotosDenied(); self?.presentingDenied = false }
        alert.addAction(UIAlertAction(title: copy.settings, style: .default) { _ in
            acknowledge()
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        alert.addAction(UIAlertAction(title: copy.cancel, style: .cancel) { _ in acknowledge() })
        presenter.present(alert, animated: true)
    }

    override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { render() } }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { strip.measuredHeight(forWidth: width, axis: .horizontal) }
    func measuredHeight(forWidth width: CGFloat, axis: UKCameraControlStripView.LayoutAxis) -> CGFloat {
        strip.measuredHeight(forWidth: width, axis: axis)
    }
    var axis: UKCameraControlStripView.LayoutAxis {
        get { strip.axis }
        set { strip.axis = newValue }
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); strip.frame = bounds }
}

// MARK: - Shared stacked/split viewer content

/// Video and closure-driven controls, not a feature controller or a modal dispatcher.
@MainActor
final class UKServerUICameraViewerContent: UIView, UKGridMeasuring {
    private let video: UIView
    private let controls: UKServerUICameraControls
    private let aspect: CGFloat

    init(video: UIView, controls: UKServerUICameraControls, aspect: Double) {
        self.video = video
        self.controls = controls
        self.aspect = CGFloat(aspect)
        super.init(frame: .zero)
        video.layer.cornerRadius = HassTokens.Radius.tile
        video.layer.cornerCurve = .continuous
        video.clipsToBounds = true
        addSubview(video)
        addSubview(controls)
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func plan(width: CGFloat) -> UKCameraViewerGeometry.Plan {
        let window = WindowMetrics.current
        let size = window.size ?? CGSize(width: width, height: bounds.height)
        let split = CameraViewerLayout.usesSplit(window: size, isRegularWidth: window.size != nil
                                                ? window.isRegularWidth : traitCollection.horizontalSizeClass == .regular,
                                                container: CGSize(width: width, height: bounds.height))
        return UKCameraViewerGeometry.plan(width: width, split: split, aspect: aspect) { [controls] width, axis in
            controls.measuredHeight(forWidth: width, axis: axis)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { plan(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        let plan = plan(width: bounds.width)
        video.frame = plan.video
        controls.axis = plan.controlsAxis
        controls.frame = plan.controls
        accessibilityIdentifier = plan.controlsAxis == .horizontal ? "camera.layout.stacked" : "camera.layout.split"
    }
}
#endif
