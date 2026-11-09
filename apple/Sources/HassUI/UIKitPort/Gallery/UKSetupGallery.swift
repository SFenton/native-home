#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the Setup and Settings catch-up lane. Pages: setup, notification-settings.
extension UKGallery {
    static func setup(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .setup:
            return UKSetupGalleryHost(fixtures: SetupGalleryFixtures())
        case .notificationSettings:
            let context = UKGalleryChrome.context()
            return UKGalleryChrome.wrap(UKNotificationSettingsGalleryPage(context: context, push: NotificationSettingsGallery.makePush(environment: ProcessInfo.processInfo.environment)), context: context)
        default:
            return nil
        }
    }
}

/// `FENTON_GALLERY=setup` (``SetupGallery``): the real Setup sheet and coordinator over a plain black page, on a scripted system. The
/// flow starts as after sign-in (or at one step) and the journey walks it with the buttons.
@MainActor
final class UKSetupGalleryHost: UIViewController {
    private let fixtures: SetupGalleryFixtures
    private let lastAction = UKGalleryLastCallView(title: "Last action")
    private var presenter: UKSetupPresenter?
    private var started = false

    init(fixtures: SetupGalleryFixtures) {
        self.fixtures = fixtures
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        lastAction.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lastAction)
        NSLayoutConstraint.activate([
            lastAction.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            lastAction.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HassTokens.Spacing.l),
        ])
        let fixtures = fixtures
        let lastAction = lastAction
        presenter = UKSetupPresenter(setup: fixtures.setup, host: self, openURL: { [weak self] _ in
            // The journey stands in for the person turning the switch on in iOS Settings and coming back.
            fixtures.system.timeSensitive = .enabled
            lastAction.record("open settings")
            Task { await fixtures.setup.didBecomeActive() }
            _ = self
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presenter?.refresh()
        guard !started else { return }
        started = true
        let setup = fixtures.setup
        Task { @MainActor in
            switch fixtures.start {
            case "notifications": setup.showForTesting(.notifications)
            case "time-sensitive":
                await setup.push.refreshSettings()
                setup.showForTesting(.timeSensitive)
            case "location": setup.showForTesting(.location)
            default: await setup.offerIfNeeded()
            }
        }
    }
}

/// `FENTON_GALLERY=notification-settings` (``NotificationSettingsGallery``): the Settings → Notifications section in each state,
/// in a list. Opening a row is recorded on the `Last action` line instead of leaving the app.
@MainActor
final class UKNotificationSettingsGalleryPage: UKPageViewController {
    private let push: PushCoordinator
    private let driver = UKSettingsListDriver(style: .sheet)
    private let lastAction = UKGalleryLastCallView(title: "Last action")
    private var barHeight: CGFloat = 36
    private var authorization: PushAuthorization?
    private var timeSensitive: TimeSensitiveSetting?

    init(context: UKContext, push: PushCoordinator) {
        self.push = push
        super.init(context: context, title: "Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let collection = driver.collectionView!
        collection.accessibilityIdentifier = "settings.list"
        install(scrollView: collection)
        if !GalleryEnvironment.isClean {
            additionalSafeAreaInsets.top = barHeight
            lastAction.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(lastAction)
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let authorization = self.push.authorization
            let timeSensitive = self.push.timeSensitive
            guard authorization != self.authorization || timeSensitive != self.timeSensitive else { return }
            self.authorization = authorization
            self.timeSensitive = timeSensitive
            self.driver.setSections([UKNotificationsSettings.section(push: self.push, openURL: { [weak self] _ in self?.lastAction.record("open settings") })])
        }
        Task { await push.refreshSettings() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard lastAction.superview != nil else { return }
        // The line grows with the text size, and so does the room the page leaves for it.
        let width = view.bounds.width - 2 * HassTokens.Spacing.l
        let needed = ceil(lastAction.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) + 8
        if abs(needed - barHeight) > 0.5 {
            barHeight = needed
            additionalSafeAreaInsets.top = needed
        }
        let top = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        lastAction.frame = CGRect(x: HassTokens.Spacing.l, y: top + 4, width: width, height: needed - 8)
    }
}
#endif
