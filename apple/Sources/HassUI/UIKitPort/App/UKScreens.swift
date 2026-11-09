#if os(iOS)
import HassCore
import UIKit

/// Where the shell finds every screen of the port. Each feature lane owns one extension file,
/// `Features/<Feature>/UK<Feature>Entry.swift`, and replaces its placeholder with its screen; the shell (tabs, pushed
/// routes, header sheets) only ever calls these. The counterpart of `MainTabView.sectionStack`, `HomeRouteDestination`,
/// `HouseholdSettingsDestination`, `SettingsRouteDestination` and `ShellSheets`.
@MainActor
enum UKScreens {
    /// A tab's root page.
    static func root(for section: AppSection, context: UKContext) -> UIViewController {
        switch section {
        case .home: home(context)
        case .security: security(context)
        case .climate: climate(context)
        case .chores: chores(context)
        case .settings: settings(context)
        }
    }

    /// A pushed Home route's page (`HomeRouteDestination`).
    static func destination(for route: HomeRoute, context: UKContext) -> UIViewController {
        switch route {
        case let .room(id): room(id, context)
        case .vacuums: vacuums(context)
        case .media: media(context)
        case .customLights: customLights(context)
        case .sprinklers: sprinklers(context)
        case .groceryList: groceryList(context)
        case .food: food(context)
        }
    }
}

/// What a screen shows until its lane lands it: the route's title and symbol, like ``PlaceholderScreen``.
final class UKPlaceholderViewController: UIViewController {
    private let symbol: String

    init(title: String, symbol: String = "hammer") {
        self.symbol = symbol
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = .secondaryLabel
        image.preferredSymbolConfiguration = .init(textStyle: .largeTitle)
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .title2)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [image, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
#endif
