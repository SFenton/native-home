#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// The last-call line of the Custom Lights and Sprinklers galleries (`galleryLastCallBanner()`): the debug line journeys read through
/// `gallery.lastCall` to check what a control sent. It shows above the page, and above the bar of a sheet (the SwiftUI banner sits
/// below the bar), and is left out with `FENTON_GALLERY_CLEAN=1`.
@MainActor
enum UKRoomsLastCall {
    /// The fixture state and the recording service caller both pages use (`HomePageGallery`).
    static func fixture() -> (store: EntityStore, recorder: PageGalleryRecorder) {
        let store = HomePageFixtures.store()
        return (store, PageGalleryRecorder(store: store))
    }

    /// Shows the line above `modal`'s navigation bar when `caller` is the gallery's recorder (a no-op for the app's connection).
    static func attach(to modal: UINavigationController, caller: (any HassServiceCalling)?) {
        guard !GalleryEnvironment.isClean, let recorder = caller as? PageGalleryRecorder else { return }
        let banner = UKRoomsLastCallBanner(recorder: recorder)
        modal.loadViewIfNeeded()
        modal.view.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: modal.view.topAnchor),
            banner.leadingAnchor.constraint(equalTo: modal.view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: modal.view.trailingAnchor),
        ])
        // The bar and the pages sit below the line, as under `safeAreaInset(edge: .top)`.
        modal.additionalSafeAreaInsets.top = banner.height
    }

    /// `child` with the line above it, or `child` itself when the screenshots ask for no line.
    static func container(wrapping child: UIViewController, recorder: PageGalleryRecorder) -> UIViewController {
        guard !GalleryEnvironment.isClean else { return child }
        return UKRoomsBannerContainer(child: child, recorder: recorder)
    }
}

/// The line on a bar material, with the 16 pt side and 4 pt vertical padding of the SwiftUI banner.
@MainActor
final class UKRoomsLastCallBanner: UIView {
    private let label = UKGalleryLastCallView()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private var observation: UKObservation?

    /// The banner's height: one line and its padding.
    var height: CGFloat { ceil(label.font.lineHeight) + 8 }

    init(recorder: PageGalleryRecorder) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        label.numberOfLines = 1
        material.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        addSubview(label)
        material.ukPin(to: self)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.l),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HassTokens.Spacing.l),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        observation = UKObservation { [weak label] in label?.record(recorder.lastCall) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Hosts a gallery page below the line: the page's view starts under the line, so its safe area is the page's own.
@MainActor
final class UKRoomsBannerContainer: UIViewController {
    private let child: UIViewController
    private let banner: UKRoomsLastCallBanner

    init(child: UIViewController, recorder: PageGalleryRecorder) {
        self.child = child
        banner = UKRoomsLastCallBanner(recorder: recorder)
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: banner.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }
}
#endif
