#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Climate lane. Pages: climate, bedroom, room-devices.
extension UKGallery {
    static func climate(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .climate: climatePage()
        case .bedroom: UKGalleryChrome.wrap(UKBedroomGalleryViewController(), context: UKGalleryChrome.context())
        case .roomDevices: UKGalleryChrome.wrap(UKRoomDevicesGalleryViewController(), context: UKGalleryChrome.context())
        default: nil
        }
    }

    /// `FENTON_GALLERY=climate`: the real page on fixture state with a recording caller. `FENTON_GALLERY_CLIMATE_SCENARIO=away` loads the
    /// away fixture; `FENTON_GALLERY_CLIMATE_OPEN=<tab>` or `=<route>` (`room:living_room`, `predictive`, `eco-critical`,
    /// `selected-rooms`…) opens the sheet at launch; `FENTON_GALLERY_CLEAN=1` leaves the last-call line out.
    @MainActor
    private static func climatePage() -> UIViewController {
        let environment = ProcessInfo.processInfo.environment
        let scenario = ClimateFixtures.Scenario(rawValue: environment["FENTON_GALLERY_CLIMATE_SCENARIO"] ?? "") ?? .home
        let store = ClimateFixtures.store(scenario: scenario)
        let recorder = GalleryServiceRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let controller = ClimateController(store: store, caller: recorder)
        let initial = environment["FENTON_GALLERY_CLIMATE_OPEN"].flatMap(ClimateGallery.request(token:))
        let page = UKClimateViewController(context: context, controller: controller, initialSheet: initial)
        if !GalleryEnvironment.isClean {
            page.bottomAccessory = UKLastCallBar { recorder.lastCall }
            page.sheetAccessory = { UKLastCallBar { recorder.lastCall } }
        }
        return UKGalleryChrome.wrap(page, context: context)
    }
}

/// The debug line a lane gallery shows on a bar (`GalleryLastCall` on `.background(.bar)`): the last service call, which journeys
/// read through `gallery.lastCall`. It follows the recorder by observation.
@MainActor
final class UKLastCallBar: UIVisualEffectView {
    private let label = UKGalleryLastCallView()
    private let bag = UKObservationBag()

    /// - Parameter text: Reads the recorder's last call; observed.
    init(text: @escaping @MainActor () -> String) {
        super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
        bag.observe { [weak self] in self?.label.record(text()) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
