#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The Settings page, the last tab (``SettingsScreen``): the web's household topics (`SETTINGS_PAGE_ITEMS`: Vacation, the admin
/// To-Do, then the household topics), Appearance, Notifications, Home Assistant Settings (a full-screen modal), Performance, the
/// two feedback forms and About. The system inset grouped list on the wallpaper, every row a module (direction G, Layers).
///
/// **Columns (owner, 2026-11-01).** Where the window splits (``SplitPolicy``: the unfolded Duo landscape, iPad landscape) the list is
/// the left column and the right column shows "Select a setting to see more options" until a row is tapped; the row's whole page
/// (Vacation, To-Do, a household topic, Performance) then opens on the right. A page drilled into from there (Vacation, then
/// Vacation Mode) slides left into the first column and the new page comes in on the right; Back reverses it
/// (``UKColumnsViewController``). The navigator stays the source of truth: the columns show its routes, and a tap writes them
/// there. Everywhere else a tap pushes on the section's stack as before, and a fold or rotation that stops splitting hands the
/// open pages to that stack, so nothing is lost.
///
/// Nothing in ``sections()`` reads observable state: the observers below copy what they watch into stored properties and rebuild
/// only when it changed, so dragging the blur slider costs the slider and nothing else.
final class UKSettingsViewController: UKPageViewController, UKColumnsHosting {
    private let driver = UKSettingsStackDriver(style: .wallpaper)
    private let about = AboutSettingsModel()
    private let iconStore = AppIconPickerModelStore()
    private let standaloneBlur = BackdropBlurSettings()
    private weak var blurSlider: UKPercentSliderRow?

    // What the list shows, copied from the models that change it.
    private var viewerUserId: String?
    private var showsIconBadge = true
    private var blurIsDefault = true
    private var pushAuthorization: PushAuthorization?
    private var pushTimeSensitive: TimeSensitiveSetting?
    private var selectedIcon = AppIconChoice.default
    private var iconsSupported = false
    private var footerText = ""
    private var observers: UKObserverTokens?

    /// The list (column one) and the pages open beside it.
    private(set) lazy var columns = UKColumnsViewController(rootView: driver.scrollView, shell: context.shell) {
        UKPanePlaceholderViewController(symbol: "gearshape", text: "Select a setting to see more options", identifier: "settings.pane.placeholder")
    }
    private var columnsPending = false

    /// A page a tap opens, in a column or as a push.
    private enum PaneTarget: Equatable {
        case route(SettingsRoute)
        case household(HouseholdSettingsPage)

        var shellRoute: ShellRoute {
            switch self {
            case let .route(route): .settings(route)
            case let .household(page): .household(page)
            }
        }
    }

    init(context: UKContext) {
        super.init(context: context, title: "Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var blur: BackdropBlurSettings { context.backdrop?.blur ?? standaloneBlur }

    override func viewDidLoad() {
        super.viewDidLoad()
        let scroll = driver.scrollView
        scroll.accessibilityIdentifier = "settings.list"
        buildColumns(scroll)
        footerText = about.footer
        readDefaults()
        let model = iconModel
        iconsSupported = model.isSupported
        selectedIcon = model.selected
        blurIsDefault = blur.isDefault
        pushAuthorization = context.push?.authorization
        pushTimeSensitive = context.push?.timeSensitive
        rebuild()
        observeModels()
        let defaults = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
        let transparency = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.driver.setSections([])
                self?.rebuild()
            }
        }
        observers = UKObserverTokens([defaults, transparency])
    }

    private var iconModel: AppIconPickerModel { iconStore.model(for: .system) }

    private func readDefaults() {
        viewerUserId = UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey)
        showsIconBadge = UserDefaults.standard.object(forKey: AppIconBadgeSync.enabledKey) as? Bool ?? true
    }

    private func defaultsChanged() {
        let id = UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey)
        let badge = UserDefaults.standard.object(forKey: AppIconBadgeSync.enabledKey) as? Bool ?? true
        guard id != viewerUserId || badge != showsIconBadge else { return }
        viewerUserId = id
        showsIconBadge = badge
        rebuild()
    }

    /// Each observer reads one model and rebuilds only when what it read changed.
    private func observeModels() {
        bag.observe { [weak self] in
            guard let self else { return }
            let isDefault = self.blur.isDefault
            self.blurSlider?.value = self.blur.sliderValue
            guard isDefault != self.blurIsDefault else { return }
            self.blurIsDefault = isDefault
            self.rebuild()
        }
        bag.observe { [weak self] in
            guard let self, let push = self.context.push else { return }
            let authorization = push.authorization
            let timeSensitive = push.timeSensitive
            guard authorization != self.pushAuthorization || timeSensitive != self.pushTimeSensitive else { return }
            self.pushAuthorization = authorization
            self.pushTimeSensitive = timeSensitive
            self.rebuild()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let selected = self.iconModel.selected
            guard selected != self.selectedIcon else { return }
            self.selectedIcon = selected
            self.rebuild()
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let footer = self.about.footer
            guard footer != self.footerText else { return }
            self.footerText = footer
            self.rebuild()
        }
    }

    private func rebuild() {
        driver.setSections(sections())
    }

    // MARK: Sections

    func sections() -> [UKSettingsListSection] {
        var result: [UKSettingsListSection] = []

        var top = [
            UKSettingsRows.link(id: "vacation", identifier: "settings.vacation", title: Vacation.Copy.settingsLinkTitle,
                                subtitle: Vacation.Copy.settingsLinkSubtitle, symbol: SymbolMap.symbol(for: "mdi:airplane"), showsChevron: true) { [weak self] in
                self?.show(.route(.vacation))
            },
        ]
        if ChoresConfig.showsAdminTodo(to: ChoresConfig.Resident.forUserId(viewerUserId)) {
            top.append(UKSettingsRows.link(id: "todo", identifier: "settings.todo", title: "To-Do", subtitle: "An admin panel for to-do tasks.",
                                           symbol: SymbolMap.symbol(for: "mdi:clipboard-list"), showsChevron: true) { [weak self] in
                self?.show(.route(.adminTodo))
            })
        }
        result.append(UKSettingsListSection(id: "top", rows: top))

        // Appearance sits with the first sections, above the household topics (owner follow-up, 2026-10-17): Background Blur, then the
        // App Icon row where the system can switch icons.
        result.append(appearanceSection())
        if context.push != nil { result.append(notificationsSection()) }

        result.append(UKSettingsListSection(id: "household", header: .title("Household"), rows: HouseholdSettingsPage.allCases.map { page in
            UKSettingsRows.link(id: "topic.\(page.rawValue)", identifier: "settings.topic.\(page.rawValue)", title: page.rowTitle,
                                subtitle: page.subtitle, symbol: page.symbol, showsChevron: true, traits: [.button, .link]) { [weak self] in
                self?.show(.household(page))
            }
        }))

        result.append(UKSettingsListSection(
            id: "homeAssistant", footer: "Server, account and Home Assistant's own settings pages.",
            rows: [UKSettingsRows.link(id: "homeAssistant", identifier: "settings.homeAssistant", title: HomeAssistantSettingsView.linkTitle,
                                       subtitle: HomeAssistantSettingsView.linkSubtitle, symbol: SymbolMap.symbol(for: "mdi:cog"),
                                       hint: "Opens server, account and sign-out options.", traits: [.button, .link]) { [weak self] in
                self?.openHomeAssistant()
            }]))

        result.append(UKSettingsListSection(id: "performance", rows: [
            UKSettingsRows.link(id: "performance", identifier: "settings.performance", title: "Performance",
                                subtitle: "Scrolling, loading and image cache measurements on this device.",
                                symbol: "gauge.with.dots.needle.67percent", showsChevron: true) { [weak self] in
                self?.show(.route(.performance))
            },
        ]))

        // No section header on the feedback rows: the list sits on the house backdrop, where a bare header measured 1.2:1 on iPad.
        result.append(UKSettingsListSection(id: "feedback", rows: FeedbackKind.allCases.map { kind in
            UKSettingsRows.link(id: "feedback.\(kind.rawValue)", identifier: "settings.feedback.\(kind.rawValue)", title: kind.formTitle,
                                subtitle: kind.rowSubtitle, symbol: kind.symbol, hint: "Opens a form that sends it through Home Assistant.") { [weak self] in
                self?.openFeedback(kind)
            }
        }))

        result.append(aboutSection())
        return result
    }

    private func appearanceSection() -> UKSettingsListSection {
        let settings = blur
        var rows: [UKSettingsListRow] = [
            UKSettingsRows.custom(id: "blur", signature: "blur", insets: NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16), minHeight: HassTokens.minTarget, build: { [weak self] in
                let row = UKPercentSliderRow(BackdropBlurRows.title, value: settings.sliderValue, identifier: "settings.backdropBlur") { settings.sliderValue = $0 }
                self?.blurSlider = row
                return row
            }, elements: { [$0] }),
            UKSettingsRows.button(id: "blur.reset", identifier: "settings.backdropBlur.reset", title: "Reset to Default", isEnabled: !blurIsDefault,
                                  hint: "Sets the background blur to match the web dashboard.") { settings.reset() },
            UKSettingsRows.toggle(id: "badge", identifier: "settings.iconBadge", title: "Show count on app icon", isOn: showsIconBadge) { on in
                UserDefaults.standard.set(on, forKey: AppIconBadgeSync.enabledKey)
            },
        ]
        if iconsSupported {
            let model = iconModel
            rows.append(UKSettingsRows.link(id: "appIcon", identifier: "settings.appIcon", title: AppIconSettingsRow.title,
                                            subtitle: selectedIcon.displayName, symbol: "app.fill", appIcon: selectedIcon,
                                            hint: "Opens the icons you can use on the Home Screen.") { [weak self] in
                guard let self else { return }
                UKAppIconPickerViewController.present(model: model, from: self)
            })
        }
        return UKSettingsListSection(id: "appearance", header: .title("Appearance"),
                                     footer: BackdropBlurRows.footer(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled),
                                     rows: rows)
    }

    private func notificationsSection() -> UKSettingsListSection {
        guard let push = context.push else { return UKSettingsListSection(id: "notifications", rows: []) }
        return UKNotificationsSettings.section(authorization: pushAuthorization ?? push.authorization, timeSensitive: pushTimeSensitive ?? push.timeSensitive,
                                               turnOn: { Task { await push.enableNotifications() } }, openURL: { UIApplication.shared.open($0) })
    }

    private func aboutSection() -> UKSettingsListSection {
        let model = about
        let row = UKSettingsListRow(id: "version", signature: "version|\(model.text)", action: {
            model.copy()
            UKTapFeedback.confirmation()
        }, configure: { cell in
            cell.show(UKRowView.version(text: model.text))
            cell.makeElement(label: "Version", value: model.spokenText, hint: "Copies the version to the clipboard.", traits: .button,
                             identifier: "settings.version")
        })
        return UKSettingsListSection(id: "about", header: .title("About"), footer: footerText, footerIdentifier: "settings.version.footer",
                                     rows: [row])
    }

    #if DEBUG
    private var debugOpened = false

    /// `FENTON_DEBUG_SETTINGS_OPEN=appIcon|homeAssistant`: opens that sheet once the page is on screen, so a host script can capture it
    /// without a tap. A probe, never in a release build.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let pane = ProcessInfo.processInfo.environment["FENTON_DEBUG_SETTINGS_PANE"] {
            // `vacation|todo|performance|guests…`: shows that page in the split pane once the window splits (what a tap does).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                switch pane {
                case "vacation": self?.show(.route(.vacation))
                case "todo": self?.show(.route(.adminTodo))
                case "performance": self?.show(.route(.performance))
                default: if let page = HouseholdSettingsPage(rawValue: pane) { self?.show(.household(page)) }
                }
            }
        }
        guard !debugOpened, let which = ProcessInfo.processInfo.environment["FENTON_DEBUG_SETTINGS_OPEN"] else { return }
        debugOpened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if which == "appIcon" { UKAppIconPickerViewController.present(model: self.iconModel, from: self) } else { self.openHomeAssistant() }
        }
    }
    #endif

    // MARK: Columns

    private func buildColumns(_ scroll: UIScrollView) {
        addChild(columns)
        columns.view.frame = contentView.bounds
        columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(columns.view)
        columns.didMove(toParent: self)
        columns.onUserPop = { [weak self] depth in
            guard let self, let navigator = self.context.navigator, let section = self.context.section else { return }
            navigator.trimPath(in: section, toDepth: depth)
        }
        setPageScrollView(scroll)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Under a section's navigation controller that controller decides (it is on screen whichever page is showing); a page shown
        // alone (the gallery) decides here, one run-loop turn after the layout pass.
        guard !(navigationController is UKSectionNavigationController), let window = view.window, !columnsPending else { return }
        let wanted = SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular)
        guard wanted != columns.isWide else { return }
        columnsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.columnsPending = false
            guard let window = self.view.window else { return }
            self.columns.setWide(SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular))
        }
    }

    /// A tap on a row: a column where the window splits, else a push.
    private func show(_ target: PaneTarget) {
        guard columns.isWide else { return push(target) }
        let route = target.shellRoute
        if let navigator = context.navigator, let section = context.section {
            // The first column's rows replace whatever is open: the navigator is cut back to the root, then the route is added.
            guard navigator.routes(in: section) != [route] else { return }
            navigator.trimPath(in: section, toDepth: 0)
            push(target)
        } else {
            // No navigator (the gallery): the columns hold the page themselves.
            guard columns.entries.first?.tag != AnyHashable(route) else { return }
            columns.open(makePage(route), tag: route, atDepth: 0)
        }
    }

    func syncColumnRoutes(_ routes: [ShellRoute], animated: Bool) {
        guard columns.isWide else { return }
        columns.reconcile(tags: routes.map { AnyHashable($0) }, make: { [unowned self] in self.makePage($0.base as! ShellRoute) }, animated: animated)
    }

    /// A page in a column: it pushes nothing on the section's stack from inside the column (its own drilling goes through
    /// `show(_:sender:)`), and shows no header buttons (the page's own bar above carries Quick Links and Profile).
    private func makePage(_ route: ShellRoute) -> UIViewController {
        let paneContext = context.with {
            $0.navigator = nil
            $0.isPane = true
        }
        let page: UIViewController
        switch route {
        case let .settings(route): page = UKScreens.destination(for: route, context: paneContext)
        case let .household(household): page = UKScreens.destination(for: household, context: paneContext)
        case let .home(home): page = UKScreens.destination(for: home, context: paneContext)
        case .chores, .foodSpace: page = UKPlaceholderViewController(title: "Settings", symbol: "gearshape")
        }
        return UKPageHost.wrapped(page, context: paneContext)
    }

    private func push(_ target: PaneTarget) {
        switch target {
        case let .route(route): open(route)
        case let .household(household): context.push(household)
        }
    }

    // MARK: Presenting

    /// Pushes a Settings topic on the section's stack. The gallery has no shell, and the real pages need a live connection, so there
    /// a marker page lets a journey see that the tap pushed (`SettingsGallery`).
    private func open(_ route: SettingsRoute) {
        #if DEBUG
        if context.navigator == nil {
            let marker = UKPageViewController(context: context, title: "Pushed \(String(describing: route))")
            let label = UILabel.uk(.body, ink: UKDesignInk.onDark)
            label.text = "Pushed \(String(describing: route))"
            label.accessibilityIdentifier = "settings.gallery.pushed"
            label.translatesAutoresizingMaskIntoConstraints = false
            marker.contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: marker.contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: marker.contentView.centerYAnchor),
            ])
            navigationController?.pushViewController(marker, animated: true)
            return
        }
        #endif
        context.push(route)
    }

    private func openHomeAssistant() {
        UKHomeAssistantSettings.present(context: context, from: self)
    }

    private func openFeedback(_ kind: FeedbackKind) {
        UKFeedbackFormViewController.present(kind: kind, context: context, from: self)
    }
}
#endif
