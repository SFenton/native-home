#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Where the shell finds the Food area: the Food & Recipes hub, pushed from Quick Links (`HomeRoute.food`, `FoodEntryScreen`).
///
/// The hub's tiles push the Recipes grid and the inventory pages on the same navigation stack, through
/// ``UKFoodNavigation``; the area's models are the session's (a revisit shows Suggested Recipes at once), or the page's own outside
/// the shell.
extension UKScreens {
    static func food(_ context: UKContext) -> UIViewController {
        let models = context.sessionModels?.food ?? FoodModels()
        UKFoodNavigation.connect(models, context: context)
        return UKFoodHubViewController(context: context, models: models)
    }
}

extension UKScreens {
    /// A Food space a hub tile opened, pushed by the section's stack (``ShellRoute/foodSpace(_:)``); in a window that splits the hub shows
    /// it as a column instead.
    static func foodSpace(_ raw: String, context: UKContext) -> UIViewController {
        guard let space = InventorySpace(rawValue: raw) else { return UKPlaceholderViewController(title: "Food", symbol: "refrigerator") }
        return UKFoodNavigation.inventoryPage(space, context: context, models: UKFoodNavigation.inventoryModels(context: context, injected: nil))
    }
}

/// What the Food and Inventory pages share: the recipe service, the inventory models, and pushing one page on the stack.
@MainActor
enum UKFoodNavigation {
    /// Gives `models` the recipe service of the signed-in connection (``FoodNavigation/connect()`` and ``FoodEntryScreen``).
    /// - Parameter override: A service to use instead (the gallery's fixtures).
    static func connect(_ models: FoodModels, context: UKContext, override: (any RecipeServing)? = nil) {
        #if DEBUG
        // FENTON_FOOD_FIXTURES=1: the signed-in app's Food pages answer from fixtures (journeys that separate live data from the app).
        if override == nil, ProcessInfo.processInfo.environment["FENTON_FOOD_FIXTURES"] == "1" {
            if !(models.service is FixtureRecipeService) {
                models.service = FixtureRecipeService()
                // The hub's own appearance may have run first, without a service (the wider Duo and iPad hubs appear before the
                // shell hands the context over): suggestions are asked again, as with the live service below.
                models.suggestions.appear()
            }
            return
        }
        #endif
        if let override {
            if models.service !== override { models.service = override }
        } else if let connection = context.connection, !(models.service is EverShelfRecipeService) {
            models.service = EverShelfRecipeService(caller: connection)
            // The hub's own appearance may have run first, without a service.
            models.suggestions.appear()
        }
    }

    /// The signed-in connection's inventory page models (the session's, else the shared registry's), or `injected` (the gallery's
    /// fixture server). Nil while signed out.
    static func inventoryModels(context: UKContext, injected: InventoryModels?) -> InventoryModels? {
        if let injected { return injected }
        guard let connection = context.connection else { return nil }
        return context.sessionModels?.inventory(for: connection) ?? InventoryModels.shared(for: connection)
    }

    /// The inventory page of `space` (``InventoryDestinationScreen``): Not Signed In without models.
    static func inventoryPage(_ space: InventorySpace, context: UKContext, models: InventoryModels?, launch: InventoryLaunch? = nil) -> UIViewController {
        guard let models else { return UKNotSignedInViewController(context: context) }
        return UKInventoryViewController(context: context, model: models.model(for: space), models: models, launch: launch)
    }

    /// Pushes `page` on the stack that holds `presenter`, with the page chrome. Food pages are pushed on the stack itself rather
    /// than through the navigator: they are not shell routes (the stack keeps them above the hub, and a back swipe pops them).
    static func push(_ page: UIViewController, from presenter: UIViewController, context: UKContext) {
        let wrapped = UKPageHost.wrapped(page, context: context)
        presenter.navigationController?.pushViewController(wrapped, animated: true)
    }
}

/// `FENTON_OPEN_FOOD=hub|recipes` and `FENTON_OPEN_INVENTORY=<space>` (debug builds): open that page at launch, the way
/// ``FoodNavigation`` and ``InventoryDestinations`` push it on the Home stack.
///
/// The Home screen calls ``pushRequested(on:context:)`` once its stack is on screen (the SwiftUI app does it with
/// `navigationDestination(item:)` at the stack root); a gallery calls it after its first page.
@MainActor
enum UKFoodLaunch {
    /// The page the environment asks for, if any.
    static func requestedPage(context: UKContext, inventory injected: InventoryModels? = nil, models: FoodModels? = nil) -> UIViewController? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let food = models ?? context.sessionModels?.food ?? FoodModels()
        switch environment["FENTON_OPEN_FOOD"] {
        case "hub":
            UKFoodNavigation.connect(food, context: context)
            return UKFoodHubViewController(context: context, models: food, inventory: injected)
        case "recipes":
            UKFoodNavigation.connect(food, context: context)
            return UKRecipesViewController(context: context, models: food)
        default:
            break
        }
        if let space = environment["FENTON_OPEN_INVENTORY"].flatMap(InventorySpace.init(rawValue:)) {
            return UKFoodNavigation.inventoryPage(space, context: context, models: UKFoodNavigation.inventoryModels(context: context, injected: injected))
        }
        #endif
        return nil
    }

    /// Pushes the requested page on `navigation`, if the environment asks for one.
    static func pushRequested(on navigation: UINavigationController, context: UKContext, inventory injected: InventoryModels? = nil, models: FoodModels? = nil) {
        guard let page = requestedPage(context: context, inventory: injected, models: models) else { return }
        navigation.pushViewController(UKPageHost.wrapped(page, context: context), animated: false)
    }
}

/// `CenteredStateMessage(StateMessage(symbol: "person.crop.circle.badge.exclamationmark", title: "Not Signed In"))`.
final class UKNotSignedInViewController: UKPageViewController {
    init(context: UKContext) { super.init(context: context, title: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let state = UKCenteredStateMessageView(UKStateMessageView(symbol: "person.crop.circle.badge.exclamationmark", title: "Not Signed In"))
        install(scrollView: state)
    }
}
#endif
