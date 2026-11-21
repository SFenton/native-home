#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Pages: room-devices, camera-viewer, state-tile. The components the downloaded layout composes, drawn alone on fixture state.
extension UKGallery {
    static func components(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .roomDevices: UKGalleryChrome.wrap(UKRoomDevicesGalleryViewController(), context: UKGalleryChrome.context())
        case .cameraViewer: UKCameraViewerGallery.make()
        case .stateTile: UKStateTileGallery.make()
        case .textKeep: UKTextKeepGallery.make()
        case .foldSides: UKFoldSidesGallery.make()
        default: nil
        }
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
    private let opener = UKGalleryAutoOpener(label: "camera-viewer")

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
        // `FENTON_GALLERY_CAMERA_VIEWER_OPEN` is the same switch as a gallery setting, so a journey can reset into it without a relaunch;
        // read per appearance, it follows a reset.
        let requested = ProcessInfo.processInfo.environment["FENTON_GALLERY_CAMERA_VIEWER_OPEN"]
        if let stream = requested ?? UserDefaults.standard.string(forKey: "cameraViewerOpen"),
           let camera = HomeConfig.cameras.first(where: { $0.rtcStreamId == stream }) {
            opener.start(on: self) { [weak self] in self?.open(camera) }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    private func open(_ camera: HomeConfig.Camera) {
        UKCameraViewer.present(camera, from: self, context: context, pool: pool)
    }
}
#endif
