#if os(iOS) && DEBUG
import HassCore
import HassDesign
import ObjectiveC
import UIKit

nonisolated(unsafe) private var householdLineBagKey: UInt8 = 0

// Owned by the Household lane. Pages: household-settings, vacation, location, profile.
extension UKGallery {
    static func household(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .householdSettings: UKHouseholdGalleryPages.householdSettings()
        case .vacation: UKHouseholdGalleryPages.vacation()
        case .location: UKHouseholdGalleryPages.location()
        case .profile: UKHouseholdGalleryPages.profile()
        default: nil
        }
    }
}

@MainActor
enum UKHouseholdGalleryPages {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: household-settings

    /// The household topics on fixture state with a recording service caller (`HouseholdSettingsGallery`):
    /// `FENTON_GALLERY_HOUSEHOLD=<page>` opens a page at launch, `FENTON_GALLERY_UNAVAILABLE=1` makes every entity unavailable.
    static func householdSettings() -> UIViewController {
        let store = HouseholdSettingsFixtures.store(unavailable: environment["FENTON_GALLERY_UNAVAILABLE"] == "1")
        let recorder = HouseholdGalleryRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let open = environment["FENTON_GALLERY_HOUSEHOLD"].flatMap(HouseholdSettingsPage.init(rawValue:))
        let list = UKHouseholdGalleryList(context: context, recorder: recorder, open: open)
        return UKGalleryChrome.wrap(list, context: context)
    }

    // MARK: vacation

    /// Vacation and Solo Trip on a fixture house that answers like Home Assistant (`VacationGallery`);
    /// `FENTON_GALLERY_AWAY=<scenario>` picks the starting state.
    static func vacation() -> UIViewController {
        let scenario = environment["FENTON_GALLERY_AWAY"].flatMap(VacationFixtures.Scenario.init(rawValue:)) ?? .idle
        let house = VacationGalleryHouse(store: VacationFixtures.store(scenario))
        let context = UKGalleryChrome.context(store: house.store, caller: house)
        let bar: UKGalleryLastCallView? = GalleryEnvironment.isClean ? nil : UKGalleryLastCallView()
        nonisolated(unsafe) weak var weakHouse = house
        var subpageLine: (@MainActor () -> UIView?)?
        if !GalleryEnvironment.isClean { subpageLine = { @MainActor in Self.followingLine(weakHouse) } }
        let page = UKVacationViewController(context: context, responder: house, caller: house,
                                            currentUserId: { HouseholdResident.resident1.haUserId }, accessoryBar: bar,
                                            subpageBar: subpageLine)
        if let bar { page.bag.observe { bar.record(house.lastCall) } }
        return UKGalleryChrome.wrap(page, context: context)
    }

    /// A pushed page covers the first, so it carries its own last-call line, following the same recorder.
    private static func followingLine(_ house: VacationGalleryHouse?) -> UIView? {
        guard let house else { return nil }
        let line = UKGalleryLastCallView()
        let follower = UKObservationBag()
        follower.observe { line.record(house.lastCall) }
        objc_setAssociatedObject(line, &householdLineBagKey, follower, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return line
    }

    // MARK: location

    /// The location permission screen, presented as the app will, over a plain page, starting at one permission stage
    /// (`LocationGallery`): `FENTON_GALLERY_LOCATION=not-determined|when-in-use|always|denied|reduced-accuracy|when-in-use-asked`.
    static func location() -> UIViewController {
        let requested = environment["FENTON_GALLERY_LOCATION"]
        let asked = requested == LocationGallery.askedStage
        let stage = asked ? .whenInUse : requested.flatMap(LocationPermission.Stage.init(rawValue:)) ?? .notDetermined
        return UKLocationGalleryHost(permission: LocationGallery.permission(for: stage), canAskForAlways: !asked)
    }

    // MARK: profile

    /// Your Summary as the app presents it, over a plain page, on fixtures with a recording service (`ProfileGallery`):
    /// `FENTON_GALLERY_VIEWER`, `FENTON_GALLERY_TAB`, `FENTON_GALLERY_VACATION`, `FENTON_GALLERY_EMPTY`, `FENTON_GALLERY_CHORES`.
    static func profile() -> UIViewController {
        UKProfileGalleryHost(fixtures: ProfileGalleryFixtures(environment: environment))
    }
}

// MARK: - Household settings list

/// The gallery's list of topics: a row each (`settings.topic.<id>`), opening the page; with `open`, the page is pushed at launch.
@MainActor
final class UKHouseholdGalleryList: UKHouseholdColumnPage {
    private let recorder: HouseholdGalleryRecorder
    private let open: HouseholdSettingsPage?
    private var opened = false
    private let lastCallView = UKGalleryLastCallView()

    init(context: UKContext, recorder: HouseholdGalleryRecorder, open: HouseholdSettingsPage?) {
        self.recorder = recorder
        self.open = open
        super.init(context: context, title: "Household Settings", accessoryBar: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let rows = HouseholdSettingsPage.allCases.map { page -> UIView in
            let row = UKRowView(UKRowContent(page.rowTitle, subtitle: page.subtitle, symbol: SymbolMap.symbol(for: page.symbol), showsChevron: true))
            let button = UKRowButton(row) { [weak self] in self?.show(page) }
            button.accessibilityIdentifier = "settings.topic.\(page.rawValue)"
            return button
        }
        column.addArrangedSubview(UKModuleListView(hasGlyphs: true, rows: rows))
        if !GalleryEnvironment.isClean { column.addArrangedSubview(lastCallView) }
        bag.observe { [weak self] in
            guard let self else { return }
            self.lastCallView.record(self.recorder.lastCall)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !opened, let open else { return }
        opened = true
        show(open, animated: false)
    }

    private func show(_ page: HouseholdSettingsPage, animated: Bool = true) {
        let bar: UIView? = GalleryEnvironment.isClean ? nil : UKGalleryLastCallView()
        let screen = UKHouseholdSettingsViewController.make(page: page, context: context, accessoryBar: bar)
        if let bar = bar as? UKGalleryLastCallView, let screen = screen as? UKPageViewController {
            screen.bag.observe { [weak self] in
                guard let self else { return }
                bar.record(self.recorder.lastCall)
            }
        }
        navigationController?.pushViewController(screen, animated: animated)
    }
}

// MARK: - Location

/// A blank presenting page that opens the location permission screen as a page sheet, as the SwiftUI gallery does. Continue plays
/// the system's answer (While Using, then Always) so journeys can walk the steps; Open Settings and Close are recorded on the
/// `Last action` line.
@MainActor
final class UKLocationGalleryHost: UIViewController {
    private var permission: LocationPermission
    private let canAskForAlways: Bool
    private var page: UKLocationPermissionViewController?
    private let opener = UKGalleryAutoOpener(label: "household-sheet")
    private let lastAction = UKGalleryLastCallView(title: "Last action")

    init(permission: LocationPermission, canAskForAlways: Bool) {
        self.permission = permission
        self.canAskForAlways = canAskForAlways
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        opener.start(on: self) { [weak self] in self?.presentSheet() }
    }

    private func presentSheet() {
        let page = UKLocationPermissionViewController(
            permission: permission, canAskForAlways: canAskForAlways,
            onRequestPermission: { [weak self] in self?.answer() },
            onOpenSettings: { [weak self] in self?.lastAction.record("open settings") },
            onClose: { [weak self] in self?.lastAction.record("close") },
            footer: GalleryEnvironment.isClean ? nil : lastAction)
        self.page = page
        var options = UKHassModalOptions(title: "Location Settings", fitKey: "location.gallery")
        options.showsClose = false
        options.appearance = .dark
        options.width = .page
        UKHassModalController(root: page, options: options).present(from: self)
    }

    /// What iOS answers to the request at each step, as if the person chose the highlighted option.
    private func answer() {
        lastAction.record("request \(permission.stage.rawValue)")
        permission = LocationGallery.answer(to: permission)
        page?.permission = permission
    }
}

// MARK: - Profile

/// A blank presenting page that opens Your Summary, as the SwiftUI gallery does, with the last service call under the bar.
@MainActor
final class UKProfileGalleryHost: UIViewController {
    private let fixtures: ProfileGalleryFixtures
    private let opener = UKGalleryAutoOpener(label: "household-sheet")
    private let lastCallView = UKGalleryLastCallView()
    private let bag = UKObservationBag()

    init(fixtures: ProfileGalleryFixtures) {
        self.fixtures = fixtures
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        opener.start(on: self) { [weak self] in self?.presentSheet() }
    }

    private func presentSheet() {
        var context = UKGalleryChrome.context(store: fixtures.store)
        context.surface = .sheet
        context.navigator = fixtures.navigator
        context.avatars = fixtures.avatars
        let root = UKYourSummaryViewController(context: context, models: UKSummaryModels(chores: fixtures.chores, inventory: fixtures.models),
                                               opening: fixtures.opening)
        root.closeSheet = { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
        if !GalleryEnvironment.isClean {
            root.topAccessory = lastCallView
            bag.observe { [weak self] in
                guard let self else { return }
                self.lastCallView.record(self.fixtures.lastCall)
            }
        }
        var options = UKHassModalOptions(title: nil, fitKey: "profile.gallery")
        options.closeIdentifier = "account.close"
        options.width = .form
        options.height = .full
        options.onClose = root.closeSheet
        UKHassModalController(root: root, options: options).present(from: self)
    }
}
#endif
