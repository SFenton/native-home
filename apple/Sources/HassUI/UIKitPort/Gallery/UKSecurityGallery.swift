#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Security lane. Pages: security, camera-viewer.
extension UKGallery {
    static func security(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .security: UKSecurityGallery.make()
        case .cameraViewer: UKCameraViewerGallery.make()
        default: nil
        }
    }
}

/// Gallery page for Security (`SecurityGallery`): the real page on fixture state with a recording service caller that echoes doors, locks
/// and alarm modes like Home Assistant, so journeys press real controls without touching the house. Cameras are left out (they need a
/// live connection); the hidden Vehicle section is shown so its tile is tested.
///
/// `FENTON_GALLERY_FAIL=1` makes every call fail (garage door error feedback); `FENTON_GALLERY_SCENARIO=unavailable` reports the alarm,
/// locks and doors as unavailable (dimmed tiles), `=triggered` sounds the alarm, `=openHome`, `=openAway` and `=openArmed` open a door
/// in the three house states the Contact Sensors chip tells apart; `FENTON_GALLERY_CLEAN=1` hides the last-call line for screenshots.
@MainActor
enum UKSecurityGallery {
    static func make() -> UIViewController {
        let environment = ProcessInfo.processInfo.environment
        let scenario = SecurityFixtures.Scenario(rawValue: environment["FENTON_GALLERY_SCENARIO"] ?? "") ?? .standard
        let store = SecurityFixtures.store(scenario)
        let recorder = SecurityGalleryRecorder(store: store, fails: environment["FENTON_GALLERY_FAIL"] == "1")
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let page = UKSecurityGalleryViewController(context: context, recorder: recorder)
        return UKGalleryChrome.wrap(page, context: context)
    }
}

/// The Security page with the gallery's Last call bar under it (`safeAreaInset(edge: .bottom)` with a bar material).
@MainActor
final class UKSecurityGalleryViewController: UKSecurityViewController {
    private let recorder: SecurityGalleryRecorder
    private let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let lastCall = UKGalleryLastCallView()

    init(context: UKContext, recorder: SecurityGalleryRecorder) {
        self.recorder = recorder
        super.init(context: context, caller: recorder, canSend: { true }, showsCameras: false, showsVehicle: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bar.isHidden = GalleryEnvironment.isClean
        bar.contentView.addSubview(lastCall)
        view.addSubview(bar)
        bag.observe { [weak self] in
            guard let self else { return }
            lastCall.record(recorder.lastCall)
            view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !bar.isHidden else { return }
        let side = HassTokens.Spacing.l
        let labelHeight = ceil(lastCall.sizeThatFits(CGSize(width: view.bounds.width - 2 * side, height: CGFloat.greatestFiniteMagnitude)).height)
        let content = labelHeight + 8
        if additionalSafeAreaInsets.bottom != content { additionalSafeAreaInsets.bottom = content }
        let system = max(0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        bar.frame = CGRect(x: 0, y: view.bounds.height - content - system, width: view.bounds.width, height: content + system)
        lastCall.frame = CGRect(x: side, y: 4, width: view.bounds.width - 2 * side, height: labelHeight)
    }
}

/// Gallery page for the camera viewer (`CameraViewerGallery`): the real viewer in its content-fitted sheet, on fixture cameras and a
/// pool with no stream modes, so a journey or a screenshot sees the sheet's height with no server. `-cameraViewerOpen <stream id>`
/// (or `FENTON_GALLERY_CAMERA_VIEWER_OPEN`, which wins) opens one at launch. Launch with `FENTON_GALLERY=camera-viewer`.
@MainActor
enum UKCameraViewerGallery {
    static func make() -> UIViewController {
        let store = EntityStore()
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        var context = UKGalleryChrome.context(store: store)
        context.connection = connection
        let pool = CameraStreamPool(modes: [], observesApp: false)
        let page = UKCameraViewerGalleryViewController(context: context, pool: pool)
        return UKGalleryChrome.wrap(page, context: context)
    }
}

@MainActor
final class UKCameraViewerGalleryViewController: UKPageViewController {
    private let pool: CameraStreamPool
    private var opened = false

    init(context: UKContext, pool: CameraStreamPool) {
        self.pool = pool
        super.init(context: context, title: "Camera Viewer")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.m
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.l, leading: HassTokens.Spacing.l,
                                                                 bottom: HassTokens.Spacing.l, trailing: HassTokens.Spacing.l)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for camera in HomeConfig.cameras {
            let button = UKPrimaryButton(camera.title) { [weak self] in self?.open(camera) }
            button.accessibilityIdentifier = "cameraViewer.open.\(camera.rtcStreamId)"
            stack.addArrangedSubview(button)
        }
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        install(scrollView: scroll)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !opened else { return }
        opened = true
        // `FENTON_GALLERY_CAMERA_VIEWER_OPEN` is the same switch as a gallery setting, so a journey can reset into it without a relaunch;
        // read per appearance, it follows a reset.
        let requested = ProcessInfo.processInfo.environment["FENTON_GALLERY_CAMERA_VIEWER_OPEN"]
        if let stream = requested ?? UserDefaults.standard.string(forKey: "cameraViewerOpen"),
           let camera = HomeConfig.cameras.first(where: { $0.rtcStreamId == stream }) {
            open(camera)
        }
    }

    private func open(_ camera: HomeConfig.Camera) {
        UKCameraViewer.present(camera, from: self, context: context, pool: pool)
    }
}
#endif
