#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// What a Home page shows and where its services come from. The shell uses the defaults; the galleries narrow it to the part under
/// test and inject fixtures (`HomeScreen`'s environment: `roomServiceCaller`, `weatherForecastStore`, `weatherForecastCaller`).
struct UKHomeConfiguration {
    /// The parts of the page, in the order the page draws them.
    struct Parts: OptionSet {
        let rawValue: Int
        static let banner = Parts(rawValue: 1)
        static let statusRail = Parts(rawValue: 2)
        static let weather = Parts(rawValue: 4)
        static let guests = Parts(rawValue: 8)
        static let cameras = Parts(rawValue: 16)
        static let all: Parts = [.banner, .statusRail, .weather, .guests, .cameras]
    }

    var parts: Parts = .all
    /// A fixture forecast store (the gallery); nil makes the card's own.
    var weatherStore: WeatherForecastStore?
    /// A fixture service for `weather.get_forecasts`.
    var weatherCaller: (any WeatherForecastCalling)?
    /// Opens the Weather sheet when the card appears.
    var weatherStartsOpen = false
    /// Where the guest toggles and the security sheet send calls; nil uses the connection.
    var caller: (any HassServiceCalling)?
    /// Empty space under the content, so the page scrolls for the scroll cost probe (`FENTON_GALLERY_WEATHER_FILL`).
    var fill: CGFloat = 0
    var scrollIdentifier = "home.scroll"
}

/// Home (web At a Glance overview). Spec: `.agents/pages/home/spec.md`. One column everywhere, except the unfolded Duo in landscape: two
/// halves on the hinge (mockup n1-duo-unfolded), with chips and weather leading and cameras and guests trailing.
///
/// The page is one scroll view over hand-laid sections: nothing here is created or measured per frame, every tile binds to its own
/// entity box, and the only continuous motion is the weather card's hours and a ticking condition.
@MainActor
final class UKHomeViewController: UKPageViewController {
    private let configuration: UKHomeConfiguration
    private var homeContent: UKHomeContentView!
    private var scroll: UKColumnScrollView!
    private var weatherCard: UKWeatherCardView?
    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .home }

    init(context: UKContext, configuration: UKHomeConfiguration = UKHomeConfiguration()) {
        self.configuration = configuration
        super.init(context: context, title: "Home")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let parts = configuration.parts
        var banner: UIView?
        var rail: UKChipRailView?
        var guests: UKGuestPresenceSectionView?
        var cameras: UKCameraGridSectionView?
        var card: UKWeatherCardView?
        if parts.contains(.banner) {
            let view = UKNotificationPermissionBannerView(push: context.push)
            banner = UKFittingBox(view, insets: UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))
        }
        if parts.contains(.statusRail) {
            let view = UKStatusRail.make(context: context, bag: bag) { [weak self] in self?.open(chip: $0) }
            UKArrivalMotion.apply(to: view, shell: context.shell, kind: .slideIn, bag: bag)
            rail = view
        }
        if parts.contains(.weather) {
            let view = UKWeatherCardView(context: context, store: configuration.weatherStore, caller: configuration.weatherCaller, isNarrow: false,
                                         startsOpen: configuration.weatherStartsOpen) { [weak self] modal in modal.present(from: self ?? modal) }
            UKArrivalMotion.apply(to: view, shell: context.shell, kind: .rise, index: 0, bag: bag)
            weatherCard = view
            card = view
        }
        if parts.contains(.guests) { guests = UKGuestPresenceSectionView(context: context, caller: configuration.caller) }
        if parts.contains(.cameras) {
            cameras = UKCameraGridSectionView(context: context, bag: bag) { [weak self] camera, source in self?.open(camera: camera, source: source) }
        }
        homeContent = UKHomeContentView(banner: banner, rail: rail, weather: card, guests: guests, cameras: cameras, fill: configuration.fill,
                                        isRegular: { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }) { [weak self] in
            self?.scroll.bounds.height ?? 0
        }
        scroll = UKColumnScrollView(content: homeContent.columns)
        scroll.accessibilityIdentifier = configuration.scrollIdentifier
        scroll.ukPausesTickersWhileScrolling()
        install(scrollView: scroll)
        bag.observe { [weak self] in
            guard let self else { return }
            homeContent.hinge = context.shell?.windowHinge
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        weatherCard?.setSectionOnScreen(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        weatherCard?.setSectionOnScreen(false)
    }

    // MARK: Sheets

    /// The sheet a chip opens: the Security page's alarm controls (web `SecurityControls`), else a room overview.
    private func open(chip kind: HomeConfig.ChipSheet) {
        if let overview = kind.overview {
            UKRoomOverviewSheet.controller(context: context, kind: overview).present(from: self)
        } else {
            guard let caller = configuration.caller ?? context.connection else { return }
            let page = UKHomeHooks.securitySystemSheet(context.with { $0.surface = .sheet }, caller)
            if let modal = page as? UKHassModalController {
                modal.present(from: self)
            } else {
                var options = UKHassModalOptions(title: nil)
                options.height = .fitted
                options.width = .page
                UKHassModalController(root: page, options: options).present(from: self)
            }
        }
    }

    private func open(camera: HomeConfig.Camera, source: UIView?) {
        UKHomeHooks.cameraViewer(camera, self, context, source)
    }
}

/// Home's sections, in one column or in two halves on a hinge: the first consumer of ``UKFoldColumns``.
///
/// Flat order: banner, chip rail, weather, guests, cameras. Partly folded: the banner (a leading half wide) and the rail span the top;
/// weather leads; cameras, then guests, trail. Cameras start level with the weather card (owner, 2026-11-03).
@MainActor
final class UKHomeContentView {
    /// The sections' container, which the page scrolls.
    let columns: UKFoldColumns
    private let rail: UKChipRailView?
    private let weather: UKWeatherCardView?
    private let guests: UKGuestPresenceSectionView?
    private let cameras: UKCameraGridSectionView?
    private let guestsInset: UKSecurityInsetView?

    /// The window's hinge in window coordinates, if any.
    var hinge: CGRect? {
        didSet {
            guard hinge != oldValue else { return }
            rail?.hinge = columns.isSplit ? nil : hinge
            cameras?.hinge = hinge
            guests?.hinge = hinge
            columns.hinge = hinge
        }
    }

    init(banner: UIView?, rail: UKChipRailView?, weather: UKWeatherCardView?, guests: UKGuestPresenceSectionView?, cameras: UKCameraGridSectionView?,
         fill: CGFloat, isRegular: @escaping () -> Bool, offeredHeight: @escaping () -> CGFloat) {
        self.rail = rail
        self.weather = weather
        self.guests = guests
        self.cameras = cameras
        let side = UIEdgeInsets(top: 0, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l)
        let camerasInset = cameras.map { UKSecurityInsetView($0, insets: side) }
        let guestsInset = guests.map { UKSecurityInsetView($0, insets: side) }
        let weatherInset = weather.map { UKSecurityInsetView($0, insets: side) }
        self.guestsInset = guestsInset
        let columns = UKFoldColumns(spacing: HassTokens.Spacing.xl, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0),
                                    isRegular: isRegular, offeredHeight: offeredHeight)
        columns.extraHeight = fill
        self.columns = columns
        var sections: [UKFoldColumns.Section] = []
        if let banner { sections.append(.init(banner, side: .top, topSpansLeadingOnly: true)) }
        if let rail { sections.append(.init(rail, side: .top, wrappedSide: .leading)) }
        if let weatherInset { sections.append(.init(weatherInset, side: .leading)) }
        // Cameras come first on the trailing side, under the rail and level with the weather card; the flat order is unchanged.
        if let guestsInset { sections.append(.init(guestsInset, side: .trailing, splitRank: 1)) }
        if let camerasInset { sections.append(.init(camerasInset, side: .trailing, splitRank: 0)) }
        columns.setSections(sections)
        guests?.onVisibilityChange = { [weak self] hidden in
            self?.guestsInset?.isHidden = hidden
            self?.columns.ukSetNeedsLayoutUpward()
        }
        guestsInset?.isHidden = guests?.isHidden ?? false
        (banner as? UKFittingBox)?.onVisibilityChange = { [weak columns] in columns?.ukSetNeedsLayoutUpward() }
        columns.splitIdentifier = "home.columns.split"
        columns.onSplitChange = { [weak self] split in
            // The rail spans the page above both columns, so the hinge band does not stop it.
            self?.rail?.hinge = split ? nil : self?.hinge
            self?.weather?.isNarrow = split
        }
    }
}
#endif
