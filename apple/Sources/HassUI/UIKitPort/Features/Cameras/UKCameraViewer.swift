#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Presents the camera viewer (web `CameraModalContent`): the camera's shared live stream with Snapshot, Sound and Record under
/// it, in a dark content-fitted page sheet (`CameraViewer` + `hassSheet(.page, appearance: .dark)`).
@MainActor
enum UKCameraViewer {
    /// - Parameters:
    ///   - presenter: The page the sheet rises from.
    ///   - context: The page's context (store, connection, caller); the viewer takes its sheet copy.
    ///   - pool: The stream pool; the app's shared one by default.
    ///   - caller: Where the Record call goes; nil uses the context's.
    ///   - source: The card the sheet grows out of (iOS 18 zoom); nil keeps the plain sheet. No zoom where every sheet fills the height
    ///     from the bottom (``DuoSheetPolicy``, owner 2026-10-31).
    ///   - onDismissed: Runs once the sheet has gone.
    static func present(_ camera: HomeConfig.Camera, from presenter: UIViewController, context: UKContext, pool: CameraStreamPool = .shared,
                        caller: (any HassServiceCalling)? = nil, source: UIView? = nil, onDismissed: (() -> Void)? = nil) {
        let page = UKCameraViewerViewController(camera: camera, context: context.with { $0.surface = .sheet }, pool: pool, caller: caller)
        // Each camera keeps its own remembered height (Driveway, 10:3, is not Front Door, 4:3), and where the width is known before the
        // sheet opens the height is computed up front, so even the first presentation opens at its final height (owner, 2026-10-26).
        var options = UKHassModalOptions(title: camera.title, fitKey: "CameraViewer.\(camera.id)")
        options.predictedContentHeight = page.predictedContentHeight()
        // Dark in either system appearance: it frames live video.
        options.appearance = .dark
        options.closeStaysInBar = true
        options.width = .page
        options.onDismissed = onDismissed
        let modal = UKHassModalController(root: page, options: options)
        if #available(iOS 18.0, *), let source, !UKSheetPlacement.fillsHeight(in: presenter.view.window) {
            modal.preferredTransition = .zoom { [weak source] _ in source }
        }
        modal.present(from: presenter)
    }
}

/// The viewer's page: the video and its controls in one page scroller the sheet fits itself to (`SheetFit`).
///
/// Where the window may split (iPad and unfolded iPhone Duo in landscape) the video takes the leading half and the controls stack in
/// the trailing half (web `media-split`); everywhere else the controls sit in a row under the video. HIG: Playing video (live
/// content shows its state), Buttons (44 pt targets, labels under icons), Sheets.
@MainActor
final class UKCameraViewerViewController: UKPageViewController, UKSheetFitting {
    let camera: HomeConfig.Camera
    private let pool: CameraStreamPool
    private let scroll = UKCameraViewerScrollView()
    private let live: UKCameraLiveView
    private let controls: UKCameraControlsView

    var sheetFitScrollView: UIScrollView? { scroll }

    init(camera: HomeConfig.Camera, context: UKContext, pool: CameraStreamPool, caller: (any HassServiceCalling)?) {
        self.camera = camera
        self.pool = pool
        live = UKCameraLiveView(camera: camera, style: .viewer, context: context, pool: pool)
        controls = UKCameraControlsView(camera: camera, context: context, pool: pool, caller: caller)
        super.init(context: context, title: camera.title)
        scroll.build(live: live, controls: controls, aspect: camera.aspectRatio)
        controls.presenter = { [weak self] in self }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: scroll)
    }

    /// The height of the page's scroll content, computed before the sheet opens, where the width is known: compact width (iPhone, the
    /// folded Duo), where the sheet is the window's width and never splits (`CameraViewer.predictedContentHeight`). A regular-width page
    /// sheet's width is not known until it opens, so there nothing is predicted and the sheet opens at the camera's remembered height.
    func predictedContentHeight() -> CGFloat? {
        let window = WindowMetrics.current
        guard !window.isRegularWidth, let size = window.size, size.width > 0,
              !CameraViewerLayout.usesSplit(window: size, isRegularWidth: false, container: size) else { return nil }
        // The page is laid out at the window's width less what sheets taught (none on an iPhone, 16 pt on the folded Duo).
        return scroll.stackedHeight(forWidth: SheetMemory.pageWidth(inWindowOfWidth: size.width)).rounded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Cameras reopen muted, like the web's pooled cards.
        if isBeingDismissed || navigationController?.isBeingDismissed == true || view.window == nil {
            pool.model(for: camera).setMuted(true)
        }
    }
}

// MARK: - Scroller

/// The page scroller: lays the video and the controls out as stacked or split from its own size and the window, and reports a
/// content size the sheet can fit (`CameraViewer.body`).
@MainActor
final class UKCameraViewerScrollView: UIScrollView {
    private let layoutGroup = UIView()
    private let videoHost = UIView()
    private var live: UKCameraLiveView?
    private var controls: UKCameraControlsView?
    private var aspect: CGFloat = 4.0 / 3.0
    private var isSplit = false

    /// The page's padding (`HassTokens.Spacing.l`).
    private let padding = UKPageMetrics.side
    /// The widest the stacked layout runs.
    private static let stackedMaxWidth: CGFloat = 720

    override init(frame: CGRect) {
        super.init(frame: frame)
        alwaysBounceVertical = true
        backgroundColor = .clear
        // One container, so the layout identifier doesn't replace the video's and the controls' own.
        layoutGroup.accessibilityContainerType = .semanticGroup
        layoutGroup.accessibilityIdentifier = "camera.layout.stacked"
        videoHost.clipsToBounds = true
        videoHost.layer.cornerRadius = HassTokens.Radius.tile
        videoHost.layer.cornerCurve = .continuous
        addSubview(layoutGroup)
        layoutGroup.addSubview(videoHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func build(live: UKCameraLiveView, controls: UKCameraControlsView, aspect: Double) {
        self.live = live
        self.controls = controls
        self.aspect = CGFloat(aspect)
        videoHost.addSubview(live)
        layoutGroup.addSubview(controls)
    }

    /// The size that decides between the layouts: the scroller's, else the window's.
    private func usesSplit(container: CGSize) -> Bool {
        let window = WindowMetrics.current
        let size = container.width > 0 ? container : (window.size ?? .zero)
        let regular = window.size != nil ? window.isRegularWidth : traitCollection.horizontalSizeClass == .regular
        return CameraViewerLayout.usesSplit(window: window.size ?? size, isRegularWidth: regular, container: size)
    }

    private struct Plan {
        var video: CGRect
        var controls: CGRect
        var controlsAxis: UKCameraControlsView.LayoutAxis
        var height: CGFloat
    }

    private func plan(width: CGFloat, split: Bool) -> Plan {
        let inner = max(0, width - 2 * padding)
        guard let controls else { return Plan(video: .zero, controls: .zero, controlsAxis: .horizontal, height: 0) }
        if split {
            // Equal halves that need no measured width.
            let half = max(0, (inner - padding) / 2)
            let videoHeight = half / aspect
            let controlsHeight = controls.measuredHeight(forWidth: half, axis: .vertical)
            let top = padding
            return Plan(video: CGRect(x: padding, y: top, width: half, height: videoHeight),
                        controls: CGRect(x: padding + half + padding, y: top, width: half, height: controlsHeight),
                        controlsAxis: .vertical, height: top + max(videoHeight, controlsHeight) + padding)
        }
        let columnWidth = min(inner, Self.stackedMaxWidth)
        let x = padding + (inner - columnWidth) / 2
        let videoHeight = columnWidth / aspect
        let controlsHeight = controls.measuredHeight(forWidth: columnWidth, axis: .horizontal)
        let gap = HassTokens.Spacing.xl
        return Plan(video: CGRect(x: x, y: padding, width: columnWidth, height: videoHeight),
                    controls: CGRect(x: x, y: padding + videoHeight + gap, width: columnWidth, height: controlsHeight),
                    controlsAxis: .horizontal, height: padding + videoHeight + gap + controlsHeight + padding)
    }

    /// The stacked layout's content height at a width: what the sheet's height is computed from before it opens.
    func stackedHeight(forWidth width: CGFloat) -> CGFloat { plan(width: width, split: false).height }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - adjustedContentInset.left - adjustedContentInset.right
        guard width > 0 else { return }
        let split = usesSplit(container: bounds.size)
        if split != isSplit || layoutGroup.accessibilityIdentifier == nil {
            isSplit = split
            layoutGroup.accessibilityIdentifier = split ? "camera.layout.split" : "camera.layout.stacked"
        }
        let plan = plan(width: width, split: split)
        layoutGroup.frame = CGRect(x: 0, y: 0, width: width, height: plan.height)
        videoHost.frame = plan.video
        live?.frame = videoHost.bounds
        controls?.axis = plan.controlsAxis
        controls?.frame = plan.controls
        let size = CGSize(width: width, height: plan.height)
        if contentSize != size { contentSize = size }
    }
}

// MARK: - Controls

/// Snapshot, Sound and Record (web `ActionPill`s in `CameraModalContent`; `CameraControls`).
@MainActor
final class UKCameraControlsView: UIView {
    enum LayoutAxis { case horizontal, vertical }

    var axis: LayoutAxis = .horizontal { didSet { if axis != oldValue { setNeedsLayout() } } }
    /// The controller the Photos-access alert is presented from.
    var presenter: () -> UIViewController? = { nil }

    private let camera: HomeConfig.Camera
    private let context: UKContext
    private let model: CameraLiveModel
    private let caller: any HassServiceCalling
    private let group = UIView()
    private let snapshotButton = UKCameraControlButton()
    private let soundButton = UKCameraControlButton()
    private let recordButton = UKCameraControlButton()
    private let failureCaption: UKFailureCaptionView
    private let recordFailure = TransientFailure()
    private let bag = UKObservationBag()
    private let recordingBag = UKObservationBag()

    private var snapshot = CameraSnapshotFeedback.idle
    private var snapshotTask: Task<Void, Never>?
    private var actions: OptimisticActions?
    private var recordingFailed = false

    init(camera: HomeConfig.Camera, context: UKContext, pool: CameraStreamPool, caller: (any HassServiceCalling)?) {
        self.camera = camera
        self.context = context
        model = pool.model(for: camera)
        // A viewer with no caller never sends (the gallery's dummy connection is the SwiftUI viewer's too).
        if let caller {
            self.caller = caller
        } else if let contextCaller = context.caller {
            self.caller = contextCaller
        } else if let connection = context.connection {
            self.caller = connection
        } else {
            self.caller = CameraControlsNoCaller()
        }
        failureCaption = UKFailureCaptionView(recordFailure)
        super.init(frame: .zero)
        group.accessibilityContainerType = .semanticGroup
        group.accessibilityLabel = "\(camera.title) camera controls"
        addSubview(group)
        group.addSubview(snapshotButton)
        group.addSubview(soundButton)
        if camera.recordCall != nil { group.addSubview(recordButton) }
        addSubview(failureCaption)
        snapshotButton.onTap = { [weak self] in self?.snapshot = .saving; self?.snapshotChanged() }
        soundButton.onTap = { [weak self] in
            guard let self else { return }
            model.setMuted(!model.isMuted)
        }
        recordButton.onTap = { [weak self] in self?.record() }
        bag.observe { [weak self] in self?.renderSnapshotAndSound() }
        bindRecording()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { MainActor.assumeIsolated { snapshotTask?.cancel() } }

    // MARK: Rendering

    private func renderSnapshotAndSound() {
        let muted = model.isMuted
        soundButton.configure(.init(
            title: muted ? "Muted" : "Sound On", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", isActive: !muted,
            tint: UKInk.action, pulses: false, accessibilityLabel: "Sound", accessibilityValue: muted ? "Off" : "On", isToggle: true,
            identifier: "camera.control.sound"))
        renderSnapshot()
    }

    private func renderSnapshot() {
        snapshotButton.configure(.init(
            title: snapshot.title, symbol: snapshot.symbol, isActive: snapshot != .idle, tint: UKInk.action, pulses: snapshot == .saving,
            accessibilityLabel: "Snapshot", accessibilityValue: snapshot.accessibilityValue, isToggle: false,
            identifier: "camera.control.snapshot", isEnabled: snapshot != .saving))
    }

    /// Recording as shown: the pending tap, else the live `input_boolean`.
    private func isRecording() -> Bool {
        guard let id = camera.recordingEntityId else { return false }
        let live = context.store.entity(id).state?.state == "on"
        guard let shown = actions?.shown(id) else { return live }
        return shown == "on"
    }

    /// (Re)binds the record button to the recording state and the optimistic path, which exists only after the first tap.
    private func bindRecording() {
        recordingBag.removeAll()
        guard camera.recordCall != nil else { return }
        recordingBag.observe { [weak self] in
            guard let self else { return }
            let recording = isRecording()
            recordButton.configure(.init(
                title: recording ? "Recording" : "Record", symbol: "record.circle", isActive: recording, tint: UKInk.danger, pulses: recording,
                accessibilityLabel: "Record", accessibilityValue: recording ? "Recording" : "Not recording", isToggle: true,
                identifier: "camera.control.record"))
            let failed = camera.recordingEntityId.map { actions?.isFailed($0) ?? false } ?? false
            if failed, !recordingFailed { recordFailure.show("Couldn't change recording. Check the connection.") }
            recordingFailed = failed
        }
    }

    // MARK: Record

    private func record() {
        guard let call = camera.recordCall else { return }
        guard let id = camera.recordingEntityId else {
            // No state to show or roll back, but a failed command still says so.
            let caller = caller
            Task { @MainActor [weak self] in
                do { try await caller.call(call) } catch { self?.recordFailure.show("Couldn't change recording. Check the connection.") }
            }
            return
        }
        let created = actions == nil
        let actions = actions ?? OptimisticActions(store: context.store, rules: [id: .confirmation], caller: caller)
        self.actions = actions
        if created { bindRecording() }
        // The script toggles the recording; it can take a few seconds to report.
        actions.perform(call, showing: [OptimisticIntent(id, isRecording() ? "off" : "on", revertAfter: .seconds(6))])
    }

    // MARK: Snapshot

    /// Runs the snapshot's steps as `snapshot` changes: save while `.saving`, then announce and settle back to `.idle`. A new state
    /// cancels the previous step, as the SwiftUI `.task(id: snapshot)` does, so leaving the viewer cancels a pending save.
    private func snapshotChanged() {
        renderSnapshot()
        snapshotTask?.cancel()
        // The error haptic when the save fails (not a late success buzz; owner, 2026-10-24).
        if snapshot == .failed { UKTapFeedback.failure() }
        if snapshot == .saving { UKTapFeedback.tap() }
        snapshotTask = Task { @MainActor [weak self] in await self?.runSnapshot() }
    }

    private func runSnapshot() async {
        switch snapshot {
        case .idle:
            return
        case .saving:
            let frame = model.liveFrameSource()
            let result = await CameraSnapshotSaver.save(frame: await frame?.image(), fallbackURL: snapshotURL)
            guard !Task.isCancelled else { return }
            switch result {
            case .saved:
                snapshot = .saved
            case .denied:
                snapshot = .idle
                showPhotosDenied()
            case .failed:
                snapshot = .failed
            }
            snapshotChanged()
        case .saved, .failed:
            Announcer.announce(snapshot.accessibilityValue)
            // "Saved" settles back after 2 s; "Not Saved" stays until the next snapshot or the viewer closes.
            guard snapshot == .saved else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                snapshot = .idle
                snapshotChanged()
            }
        }
    }

    private var snapshotURL: URL? {
        guard let picture = context.store.entity(camera.entityId).state?.attributes["entity_picture"]?.string,
              let base = context.connection?.server.baseURL else { return nil }
        return URL(string: picture, relativeTo: base)?.absoluteURL
    }

    private func showPhotosDenied() {
        let alert = UIAlertController(title: "Allow Photos Access",
                                      message: "Snapshots are saved to your photo library. Allow S+H to add photos in Settings.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presenter()?.present(alert, animated: true)
    }

    // MARK: Layout

    private var buttons: [UKCameraControlButton] { camera.recordCall != nil ? [snapshotButton, soundButton, recordButton] : [snapshotButton, soundButton] }

    /// Accessibility sizes stack the controls: three across break their labels mid-word at AX5.
    private func effectiveAxis(_ axis: LayoutAxis) -> LayoutAxis {
        axis == .horizontal && !traitCollection.ukIsAccessibilitySize ? .horizontal : .vertical
    }

    private func buttonFrames(width: CGFloat, axis: LayoutAxis) -> (frames: [CGRect], height: CGFloat) {
        let spacing = HassTokens.Spacing.m
        let items = buttons
        switch effectiveAxis(axis) {
        case .horizontal:
            let each = max(0, (width - spacing * CGFloat(items.count - 1)) / CGFloat(items.count))
            let height = items.map { $0.height(forWidth: each) }.max() ?? 0
            return (items.indices.map { CGRect(x: CGFloat($0) * (each + spacing), y: 0, width: each, height: height) }, height)
        case .vertical:
            var y: CGFloat = 0
            var frames: [CGRect] = []
            for item in items {
                let height = item.height(forWidth: width)
                frames.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height + spacing
            }
            return (frames, max(0, y - spacing))
        }
    }

    private func captionHeight(width: CGFloat) -> CGFloat {
        failureCaption.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                               withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }

    func measuredHeight(forWidth width: CGFloat, axis: LayoutAxis) -> CGFloat {
        let layout = buttonFrames(width: width, axis: axis)
        let caption = captionHeight(width: width)
        return layout.height + (caption > 0 ? HassTokens.Spacing.s + caption : 0)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: measuredHeight(forWidth: size.width, axis: axis)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = buttonFrames(width: bounds.width, axis: axis)
        group.frame = CGRect(x: 0, y: 0, width: bounds.width, height: layout.height)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (button, frame) in zip(buttons, layout.frames) {
            button.frame = mirror ? CGRect(x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        let caption = captionHeight(width: bounds.width)
        failureCaption.frame = CGRect(x: 0, y: layout.height + (caption > 0 ? HassTokens.Spacing.s : 0), width: bounds.width, height: caption)
    }
}

/// A caller for a viewer that has none (a gallery without a connection): every call fails.
@MainActor
private final class CameraControlsNoCaller: HassServiceCalling {
    struct Unavailable: Error {}
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws { throw Unavailable() }
}

// MARK: - Control button

/// One camera control: a circle over its label, the glyph tinted while on (direction G mockup n2 camera; HIG Buttons: labels under
/// icons). The circle is the sheet's cell colour, not Liquid Glass: these controls sit on the sheet ground under the video.
@MainActor
final class UKCameraControlButton: UIControl {
    struct Model {
        var title: String
        var symbol: String
        var isActive: Bool
        var tint: UIColor
        var pulses: Bool
        var accessibilityLabel: String
        var accessibilityValue: String
        var isToggle: Bool
        var identifier: String
        var isEnabled = true
    }

    var onTap: (() -> Void)?

    private let circle = UIView()
    private let wash = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private var model: Model?
    private var symbol: String?
    private var pulsing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        circle.isUserInteractionEnabled = false
        circle.backgroundColor = UKInk.sheetCell
        // The on tint (`wash`) fills the circle's bounds; without clipping it draws as a square around the round circle.
        circle.clipsToBounds = true
        wash.isUserInteractionEnabled = false
        circle.addSubview(wash)
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        circle.addSubview(icon)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UKInk.primary
        label.isUserInteractionEnabled = false
        addSubview(circle)
        addSubview(label)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            label.font = UKFont.footnoteEmphasis(traitCollection)
            applySymbolConfiguration()
            setNeedsLayout()
            superview?.setNeedsLayout()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKCameraControlButton, _) in view.refreshColors(animated: false) }
        NotificationCenter.default.addObserver(self, selector: #selector(motionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func tapped() {
        UKTapFeedback.tap()
        onTap?()
    }

    @objc private func motionChanged() { updatePulse() }

    private func applySymbolConfiguration() {
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.preferred(.title2, traits: traitCollection))
    }

    func configure(_ model: Model) {
        let old = self.model
        self.model = model
        label.text = model.title
        isEnabled = model.isEnabled
        accessibilityLabel = model.accessibilityLabel
        accessibilityValue = model.accessibilityValue
        accessibilityIdentifier = model.identifier
        accessibilityUserInputLabels = [model.accessibilityLabel, model.title]
        accessibilityTraits = model.isToggle ? [.button, .toggleButton] : [.button]
        if !model.isEnabled { accessibilityTraits.insert(.notEnabled) }
        isAccessibilityElement = true
        if symbol != model.symbol {
            let image = UIImage(systemName: model.symbol)
            if symbol != nil, !UIAccessibility.isReduceMotionEnabled, window != nil {
                icon.setSymbolImage(image ?? UIImage(), contentTransition: .replace)
            } else {
                icon.image = image
            }
            symbol = model.symbol
        }
        refreshColors(animated: old != nil && old?.isActive != model.isActive && window != nil)
        updatePulse()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    private func refreshColors(animated: Bool) {
        guard let model else { return }
        let apply = {
            self.icon.tintColor = model.isActive ? model.tint : UKInk.primary
            self.wash.backgroundColor = model.tint.withAlphaComponent(model.isActive ? 0.22 : 0)
        }
        if animated {
            UKMotion.stateColor(apply)
        } else {
            apply()
        }
    }

    private func updatePulse() {
        let wants = (model?.pulses ?? false) && !UIAccessibility.isReduceMotionEnabled
        guard wants != pulsing else { return }
        pulsing = wants
        if wants {
            icon.addSymbolEffect(.pulse, options: .repeating)
        } else {
            icon.removeSymbolEffect(ofType: .pulse)
        }
    }

    /// The pressed dimming of `.buttonStyle(.plain)`.
    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? HassTokens.ControlState.pressedOpacity : 1 } }
    }

    private var circleDiameter: CGFloat { max(UKFont.scaled(56, relativeTo: .title2, traits: traitCollection), HassTokens.minTarget) }

    func height(forWidth width: CGFloat) -> CGFloat {
        let text = label.sizeThatFits(CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)).height
        return max(HassTokens.minTarget, circleDiameter + HassTokens.Spacing.s + ceil(text))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: height(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = circleDiameter
        circle.frame = CGRect(x: (bounds.width - diameter) / 2, y: 0, width: diameter, height: diameter)
        circle.layer.cornerRadius = diameter / 2
        wash.frame = circle.bounds
        icon.frame = circle.bounds
        let top = diameter + HassTokens.Spacing.s
        let text = label.sizeThatFits(CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: top, width: bounds.width, height: ceil(text.height))
    }
}
#endif
