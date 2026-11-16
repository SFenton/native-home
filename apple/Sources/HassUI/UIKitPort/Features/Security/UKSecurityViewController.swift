#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Security tab (web `SecurityDashboard.tsx`; SwiftUI `SecurityPage`). Spec: `.agents/pages/security/spec.md`.
///
/// Direction G mockup n3: the status chips, the alarm card, the Doors tiles, guests, cameras and the car. The page body is shared by
/// the tab and the debug gallery (which passes a recording caller and no cameras, so journeys never reach the house).
@MainActor
class UKSecurityViewController: UKPageViewController {
    private let caller: any HassServiceCalling
    private let canSend: () -> Bool
    private let showsCameras: Bool
    private let showsVehicle: Bool
    private let pool: CameraStreamPool

    private let columns: UKFoldColumns
    private(set) var scroll: UKColumnScrollView
    private var rail: UKChipRailView?
    private var alarmHost: UKAlarmCardHost?
    private var tileSections: [UKSecurityTileSection] = []
    private var hinge: CGRect?
    private var guests: UKGuestPresenceSectionView?
    private var cameras: UKCameraGridSectionView?
    /// Holds the observations of the parts built from the house document, so a rebuild ends the old ones.
    private let structureBag = UKObservationBag()
    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    /// - Parameters:
    ///   - caller: Where commands go.
    ///   - canSend: Whether a command can go out now (`SecurityScreen.canSend`); read inside an observation, so it follows the connection.
    ///   - showsCameras: False in the gallery, where cameras need a live connection.
    ///   - showsVehicle: Whether the Car section shows.
    ///   - pool: The camera stream pool; the app's shared one by default.
    init(context: UKContext, caller: any HassServiceCalling, canSend: @escaping () -> Bool, showsCameras: Bool, showsVehicle: Bool,
         pool: CameraStreamPool = .shared) {
        self.caller = caller
        self.canSend = canSend
        self.showsCameras = showsCameras
        self.showsVehicle = showsVehicle
        self.pool = pool
        let columns = UKFoldColumns(spacing: HassTokens.Spacing.xl,
                                    insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: 0, bottom: HassTokens.Spacing.m, right: 0))
        self.columns = columns
        scroll = UKColumnScrollView(content: columns)
        super.init(context: context, title: "Security")
        columns.isRegular = { [weak self] in self?.traitCollection.horizontalSizeClass == .regular }
        columns.offeredHeight = { [weak self] in self?.scroll.bounds.height ?? 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The Security and Contact Sensors chips, the locks and garage doors in web order (the alarm tile became the card above them).
    static var doorTiles: [SecurityConfig.Tile] { SecurityPage.doorTiles }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildStructure()
        scroll.accessibilityIdentifier = "security.scroll"
        install(scrollView: scroll)

        // The hinge: grids keep tiles off it, and the card moves off it.
        bag.observe { [weak self] in
            guard let self else { return }
            applyHinge(context.shell?.windowHinge)
        }
    }

    override func houseLayoutDidChange() {
        buildStructure()
        applyHinge(hinge)
    }

    private func applyHinge(_ hinge: CGRect?) {
        self.hinge = hinge
        rail?.hinge = columns.isSplit ? nil : hinge
        alarmHost?.setHinge(hinge)
        for section in tileSections { section.hinge = hinge }
        columns.hinge = hinge
        guests?.hinge = hinge
        cameras?.hinge = hinge
    }

    /// Builds the sections that come from the house document (the chips, the doors, guests, cameras, the car) and hands them to the
    /// columns. Called from `viewDidLoad` and again by ``houseLayoutDidChange()``, which replaces the old sections.
    private func buildStructure() {
        structureBag.removeAll()
        let bag = structureBag
        tileSections = []
        cameras = nil
        let margin = HassTokens.Spacing.l
        let sideInsets = UIEdgeInsets(top: 0, left: margin, bottom: 0, right: margin)
        var sections: [UKFoldColumns.Section] = []

        // The status rail spans the top; the alarm card leads (modes in one row while split).
        let rail = UKSecurityStatusRail.make(context: context, bag: bag) { [weak self] sheet in self?.open(.chip(sheet)) }
        self.rail = rail
        sections.append(.init(rail, side: .top, wrappedSide: .leading))
        let card = UKAlarmPanelView(context: context, caller: caller) { [weak self] in self }
        let host = UKAlarmCardHost(card: card, avoidsHinge: true)
        alarmHost = host
        sections.append(.init(UKSecurityInsetView(host, insets: sideInsets), side: .leading, flatGapAbove: HassTokens.Spacing.l))

        // Doors lead.
        let doors = UKSecurityTileSection("Doors", tiles: Self.doorTiles, context: context, caller: caller, canSend: canSend)
        tileSections.append(doors)
        sections.append(.init(UKSecurityInsetView(doors, insets: sideInsets), side: .leading))

        // Guests trail, under Cameras (rank 1), although the flat order has them first.
        let guests = UKGuestPresenceSectionView(context: context, caller: caller)
        self.guests = guests
        let guestsWrapper = UKSecurityInsetView(guests, insets: sideInsets)
        guestsWrapper.isHidden = guests.isHidden
        guests.onVisibilityChange = { [weak self, weak guestsWrapper] hidden in
            guestsWrapper?.isHidden = hidden
            self?.columns.ukSetNeedsLayoutUpward()
        }
        sections.append(.init(guestsWrapper, side: .trailing, splitRank: 1))

        // Cameras are the first trailing section: level with the alarm card, directly under the rail (owner, 2026-11-03).
        if showsCameras {
            let cameras = UKCameraGridSectionView(context: context, identifierPrefix: "security.camera", bag: bag, pool: pool) { [weak self] camera, source in
                self?.open(.camera(camera), source: source)
            }
            self.cameras = cameras
            sections.append(.init(UKSecurityInsetView(cameras, insets: sideInsets), side: .trailing, splitRank: 0))
        }
        if showsVehicle {
            let vehicle = UKSecurityTileSection("Car", tiles: SecurityConfig.vehicleTiles, context: context, caller: caller, canSend: canSend)
            tileSections.append(vehicle)
            sections.append(.init(UKSecurityInsetView(vehicle, insets: sideInsets), side: .leading))
        }
        columns.splitIdentifier = "security.columns.split"
        columns.onSplitChange = { [weak self] split in
            // The rail spans the page above both columns, so the band does not stop it (E1).
            self?.rail?.hinge = split ? nil : self?.hinge
        }
        columns.setSections(sections)
    }

    private var startedAtTop = false

    /// The page starts at its top, under the large title: the scroll view's first offset can be 0 before the bar's inset applies, which
    /// reads as already scrolled and collapses the title.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !startedAtTop, scroll.adjustedContentInset.top > 0 else { return }
        startedAtTop = true
        if !scroll.isDragging, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 0.5 {
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        }
    }

    #if DEBUG
    private var didAutoOpen = false

    /// `FENTON_GALLERY_SHEET=contacts|system` opens that sheet at launch (screenshots), as the SwiftUI page does.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutoOpen, let name = ProcessInfo.processInfo.environment["FENTON_GALLERY_SHEET"] else { return }
        didAutoOpen = true
        switch name {
        case "contacts": open(.contacts)
        case "system": open(.system)
        default: break
        }
    }
    #endif

    // MARK: Sheets

    /// Sheets presented from Security (web hash modals).
    enum Sheet {
        case system
        case contacts
        case camera(HomeConfig.Camera)

        /// The sheet a status chip opens.
        static func chip(_ kind: HomeConfig.ChipSheet) -> Sheet { kind == .security ? .system : .contacts }
    }

    func open(_ sheet: Sheet, source: UIView? = nil) {
        switch sheet {
        case .system:
            let page = UKSecuritySystemViewController(context: context, caller: caller)
            var options = UKHassModalOptions(title: nil, fitKey: "security.system")
            options.closeStaysInBar = true
            options.width = .page
            UKHassModalController(root: page, options: options).present(from: self)
        case .contacts:
            // Navigates to a room group, so it opens at full height (page width).
            UKRoomOverviewSheet.controller(context: context, kind: .contacts).present(from: self)
        case let .camera(camera):
            UKCameraViewer.present(camera, from: self, context: context, pool: pool, source: source)
        }
    }
}
#endif
