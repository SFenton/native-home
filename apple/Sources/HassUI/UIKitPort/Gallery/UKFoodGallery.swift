#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Food lane. Pages: food, inventory.
extension UKGallery {
    static func food(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .food: UKFoodGallery.makeFood()
        case .inventory: UKFoodGallery.makeInventory()
        default: nil
        }
    }
}

/// The Food and Inventory galleries in the port: the same fixture pages as ``FoodGallery`` and ``InventoryGallery``.
///
/// `FENTON_GALLERY=food`:
/// - `FENTON_GALLERY_ROUTE=hub|recipes` opens that page (default `hub`); `none` starts on the gallery list, e.g. to open a page with the
///   debug launch route (`FENTON_OPEN_FOOD=hub|recipes`).
/// - `FENTON_GALLERY_FOOD_MODE=error|empty|slow` makes the service fail, return nothing, or stay loading.
/// - `FENTON_GALLERY_FOOD_DELAY_MS=<ms>` sets how long each answer takes (default 300).
/// - `FENTON_GALLERY_FOOD_TABS=1` hosts the pages in a tab bar like the signed-in app.
///
/// `FENTON_GALLERY=inventory`:
/// - `FENTON_GALLERY_SPACE`: `all-food`, `pantry` (default), `fridge`, `freezer`, `spice-rack` or `cabinet`.
/// - `FENTON_GALLERY_OPEN`: `sort`, `filter`, `scan` or `editor:<item name>` once rows load.
/// - `FENTON_GALLERY_STATE`: `empty`, `error` or `loading`.
/// - `FENTON_GALLERY_LATENCY_MS=<ms>`: how long each answer takes (default 150), so a journey can watch the spinner.
/// - `FENTON_GALLERY_SORT=expiry`: sorts by expiration date, so rows group under Expired, Expiring Soon and Later.
/// - `FENTON_SCAN_CAMERA=simulated`: the Add Item camera draws a viewfinder with a Simulate Scan button.
/// - `FENTON_GALLERY_CLEAN=1`: hides the last-call line (screenshots).
/// - `FENTON_GALLERY_HOLD_ADDED=1`: keeps a row's "added to shopping list" check for 30 s instead of 3 s.
@MainActor
enum UKFoodGallery {
    // MARK: Food

    static func makeFood() -> UIViewController {
        let environment = ProcessInfo.processInfo.environment
        // FENTON_GALLERY_FOOD_DELAY_MS stretches every answer, so a journey can watch the load gate's spinner.
        let delay = environment["FENTON_GALLERY_FOOD_DELAY_MS"].flatMap { Int($0) }.map { Duration.milliseconds($0) } ?? .milliseconds(300)
        let service = FixtureRecipeService(mode: environment["FENTON_GALLERY_FOOD_MODE"].flatMap(FixtureRecipeService.Mode.init(rawValue:)) ?? .normal, delay: delay)
        let server = EverShelfFixtureServer.sample()
        server.latency = .milliseconds(150)
        let inventory = InventoryModels(client: EverShelfClient(caller: server))
        let context = UKGalleryChrome.context(store: FoodFixtures.store())
        let models = FoodModels(service: service)
        let root = UKFoodGalleryRoot(context: context, models: models, inventory: inventory, route: environment["FENTON_GALLERY_ROUTE"] ?? "hub")
        let host = UKGalleryChrome.wrap(root, context: context)
        // The last service call, which journeys read to check what a control sent: leading and narrow, as the Recipes page's floating
        // actions sit at the trailing edge.
        UKGalleryLastCallBar.install(on: host, edge: .bottom, narrow: true, hidesAtAccessibilitySizes: true) { service.lastCall }
        guard environment["FENTON_GALLERY_FOOD_TABS"] == "1" else { return host }
        // The pages in a tab bar, like MainTabView (the live app's presentation context).
        let tabs = UITabBarController()
        host.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), selectedImage: nil)
        let other = UIViewController()
        other.view.backgroundColor = .black
        other.tabBarItem = UITabBarItem(title: "Other", image: UIImage(systemName: "gearshape"), selectedImage: nil)
        tabs.viewControllers = [host, other]
        tabs.overrideUserInterfaceStyle = .dark
        return tabs
    }

    // MARK: Inventory

    static func makeInventory() -> UIViewController {
        let environment = ProcessInfo.processInfo.environment
        let server = EverShelfFixtureServer.sample()
        switch environment["FENTON_GALLERY_STATE"] {
        case "empty": server.rows = []
        case "error": server.failing = ["evershelf.list_inventory"]
        case "loading": server.latency = .seconds(3600)
        default: server.latency = .milliseconds(environment["FENTON_GALLERY_LATENCY_MS"].flatMap { Int($0) } ?? 150)
        }
        let models = InventoryModels(client: EverShelfClient(caller: server))
        let space = environment["FENTON_GALLERY_SPACE"].flatMap(InventorySpace.init(rawValue:)) ?? .pantry
        if environment["FENTON_GALLERY_HOLD_ADDED"] == "1" {
            // Journeys on a loaded host can miss the web's 3 s "added" check; hold it so they can read it.
            models.model(for: space).addedVisibleFor = .seconds(30)
        }
        if environment["FENTON_GALLERY_SORT"] == "expiry" {
            // The page as the Sort sheet's Expiration Date leaves it: grouped under Expired, Expiring Soon, Later.
            models.model(for: space).sortMode = .expiry
        }
        let launch = environment["FENTON_GALLERY_OPEN"].flatMap(InventoryLaunch.init)
        let context = UKGalleryChrome.context()
        let page = UKInventoryViewController(context: context, model: models.model(for: space), models: models, launch: launch)
        let host = UKGalleryChrome.wrap(page, context: context)
        UKGalleryLastCallBar.install(on: host, edge: .top, narrow: false) { server.lastCall }
        return host
    }
}

/// The gallery's root list (``FoodGallery``'s `List`): a link to each page and the last call, under the title "Food". Starts on the page
/// the route names, and opens the page `FENTON_OPEN_FOOD` asks for.
final class UKFoodGalleryRoot: UKPageViewController {
    private let models: FoodModels
    private let inventory: InventoryModels
    private let launchRoute: String
    private var started = false

    init(context: UKContext, models: FoodModels, inventory: InventoryModels, route: String) {
        self.models = models
        self.inventory = inventory
        self.launchRoute = route
        super.init(context: context, title: "Food")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        func link(_ title: String, _ identifier: String, _ open: @escaping () -> Void) -> UIView {
            let row = UKRowButton(UKRowView(.init(title, showsChevron: true))) { open() }
            row.accessibilityIdentifier = identifier
            return row
        }
        let list = UKModuleListView(rows: [
            link("Food & Recipes", "gallery.food.hub") { [weak self] in self?.pushHub() },
            link("Recipes", "gallery.food.recipes") { [weak self] in self?.pushRecipes() },
        ])
        let column = UKColumnView(spacing: HassTokens.Spacing.m, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.l, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.l))
        column.setViews([list])
        let scroll = UKColumnScrollView(content: column)
        install(scrollView: scroll)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !started else { return }
        started = true
        switch launchRoute {
        case "recipes":
            pushHub(animated: false)
            pushRecipes(animated: false)
        case "none":
            if let navigation = navigationController {
                UKFoodLaunch.pushRequested(on: navigation, context: context, inventory: inventory, models: models)
            }
        default:
            pushHub(animated: false)
        }
    }

    private func pushHub(animated: Bool = true) {
        let page = UKFoodHubViewController(context: context, models: models, inventory: inventory)
        navigationController?.pushViewController(UKPageHost.wrapped(page, context: context), animated: animated)
    }

    private func pushRecipes(animated: Bool = true) {
        let page = UKRecipesViewController(context: context, models: models)
        navigationController?.pushViewController(UKPageHost.wrapped(page, context: context), animated: animated)
    }
}

/// The debug line over the bottom or top of a gallery (`safeAreaInset(edge:)` + `GalleryLastCall` on `.bar`), following `text`. Hidden by
/// `FENTON_GALLERY_CLEAN=1` and at accessibility text sizes, where it would be clipped and cover the page.
@MainActor
final class UKGalleryLastCallBar: UIVisualEffectView {
    enum Edge { case top, bottom }
    private let label = UKGalleryLastCallView()
    private let bag = UKObservationBag()

    private init() {
        super.init(effect: UIBlurEffect(style: .systemChromeMaterial))
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4), label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: HassTokens.Spacing.s),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -HassTokens.Spacing.s),
        ])
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func install(on host: UIViewController, edge: Edge, narrow: Bool, hidesAtAccessibilitySizes: Bool = false, text: @escaping @MainActor () -> String) {
        let bar = UKGalleryLastCallBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.label.isHidden = GalleryEnvironment.isClean
        bar.isHidden = GalleryEnvironment.isClean
        host.loadViewIfNeeded()
        host.view.addSubview(bar)
        var constraints: [NSLayoutConstraint] = [
            bar.leadingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
        ]
        constraints.append(narrow ? bar.widthAnchor.constraint(equalToConstant: 180) : bar.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l))
        // Below the navigation bar at the top (an inline bar and a large title are both clear of it by the page's own content).
        constraints.append(edge == .bottom ? bar.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -4)
                                           : bar.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor, constant: 48))
        NSLayoutConstraint.activate(constraints)
        bar.bag.observe { [weak bar] in
            guard let bar else { return }
            bar.label.record(text())
            bar.isHidden = GalleryEnvironment.isClean || (hidesAtAccessibilitySizes && bar.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        }
    }
}
#endif
