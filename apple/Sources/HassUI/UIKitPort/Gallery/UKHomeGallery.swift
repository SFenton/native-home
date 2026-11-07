#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Home lane. Pages: home, weather (live-activity is UKLiveActivityGallery.swift: SwiftUI card views in a hosting controller).
extension UKGallery {
    static func home(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .home: UKHomeGallery.home()
        case .weather: UKHomeGallery.weather()
        default: nil
        }
    }
}

/// The Home lane's gallery pages, on the same fixtures as ``HomeGallery`` and ``WeatherGallery``.
@MainActor
enum UKHomeGallery {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// `FENTON_GALLERY=home`: the Home page on fixture state, a recording caller and no connection (cameras left out, as in
    /// ``HomeGallery``).
    static func home() -> UIViewController {
        let environment = environment
        let store = HomeFixtures.store(environment: environment)
        let recorder = GalleryServiceRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        var configuration = UKHomeConfiguration()
        configuration.parts.remove(.cameras)
        configuration.weatherStore = WeatherForecastStore(requestTimeout: 3600)
        configuration.weatherCaller = WeatherFixtureCaller(mode: WeatherFixtureCaller.Mode(rawValue: environment["FENTON_GALLERY_WEATHER_STATE"] ?? "") ?? .normal)
        configuration.caller = recorder
        let page = UKHomeViewController(context: context, configuration: configuration)
        return UKGalleryLastCallContainer(host: UKGalleryChrome.wrap(page, context: context), recorder: recorder)
    }

    /// `FENTON_GALLERY=weather`: the weather card alone on the page, with every `FENTON_GALLERY_WEATHER_*` switch the SwiftUI gallery
    /// reads: `_CONDITION`, `_NIGHT=1`, `_STATE=loading|error|empty`, `_OPEN=1`, `_NOAQI=1`, `_FILL=<points>`.
    static func weather() -> UIViewController {
        let environment = environment
        let store = EntityStore()
        store.replaceAll(WeatherFixtures.states(
            condition: environment["FENTON_GALLERY_WEATHER_CONDITION"] ?? "rainy", night: environment["FENTON_GALLERY_WEATHER_NIGHT"] == "1",
            airQuality: environment["FENTON_GALLERY_WEATHER_NOAQI"] != "1"))
        let context = UKGalleryChrome.context(store: store)
        var configuration = UKHomeConfiguration()
        configuration.parts = [.weather]
        configuration.weatherStore = WeatherForecastStore(requestTimeout: 3600)
        configuration.weatherCaller = WeatherFixtureCaller(mode: WeatherFixtureCaller.Mode(rawValue: environment["FENTON_GALLERY_WEATHER_STATE"] ?? "") ?? .normal)
        configuration.weatherStartsOpen = environment["FENTON_GALLERY_WEATHER_OPEN"] == "1"
        configuration.fill = environment["FENTON_GALLERY_WEATHER_FILL"].flatMap(Double.init).map { CGFloat($0) } ?? 0
        configuration.scrollIdentifier = "weather.gallery"
        return UKGalleryChrome.wrap(UKHomeViewController(context: context, configuration: configuration), context: context)
    }
}

/// Hosts a gallery page above the `gallery.lastCall` bar (``GalleryLastCall`` as a bottom inset), following the recorder.
@MainActor
final class UKGalleryLastCallContainer: UIViewController {
    private let host: UIViewController
    private let recorder: GalleryServiceRecorder
    private let bag = UKObservationBag()
    private let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let line = UKGalleryLastCallView()

    init(host: UIViewController, recorder: GalleryServiceRecorder) {
        self.host = host
        self.recorder = recorder
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        guard !GalleryEnvironment.isClean else { return }
        line.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(line)
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            line.topAnchor.constraint(equalTo: bar.contentView.topAnchor, constant: 4),
            line.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            line.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -16),
        ])
        bag.observe { [weak self] in
            guard let self else { return }
            line.record(recorder.lastCall)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard bar.superview != nil else { return }
        let height = max(0, view.bounds.maxY - bar.frame.minY - view.safeAreaInsets.bottom)
        if host.additionalSafeAreaInsets.bottom != height { host.additionalSafeAreaInsets.bottom = height }
    }
}
#endif
