#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The models the Summary sheet's tabs read besides the store: the Chores tab's shared model and the Food page's, when the
/// shell (or a gallery) has them. Without them the sheet makes its own from the connection, as `SummaryPanel` does.
struct UKSummaryModels {
    var chores: ChoresModel?
    var inventory: InventoryModels?
}

// MARK: - Panel

/// The selected tab's content, cross-faded when the tab changes (`SummaryPanel`; HIG Motion: Reduce Motion shows the change at
/// once).
@MainActor
final class UKSummaryPanelViewController: UKPaneViewController {
    private(set) var current: UIViewController?
    private(set) var currentTab: SummaryTab?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    /// Shows `child` for `tab`. The page that hosts the panel names the child's scroller (``UKSheetFitting``) as its own.
    func show(_ child: UIViewController, for tab: SummaryTab, animated: Bool) {
        let old = current
        let swap = {
            old?.willMove(toParent: nil)
            old?.view.removeFromSuperview()
            old?.removeFromParent()
            self.addChild(child)
            child.view.frame = self.view.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(child.view)
            child.didMove(toParent: self)
        }
        current = child
        currentTab = tab
        if animated, old != nil, view.window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: view, duration: MotionTokens.contentFadeDuration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: swap)
        } else {
            swap()
        }
    }
}

// MARK: - Sheet

/// "Your Summary", the sheet behind the header Profile button (`YourSummarySheet`): the web's Daily Report modal with four bottom
/// tabs: Profile (the app's own extras), Overdue Chores, Upcoming Chores and Expired Food. Spec: `.agents/pages/settings/profile.md`.
///
/// It opens on Overdue Chores, so the summary comes first and the account is one tab away. The title reads "Your Summary" for a
/// household resident and "Summary" for anyone else, who sees Profile and Expired Food only. The tabs use the shared modal bar:
/// icons on compact width, icon over title on iPad and the unfolded Duo, a menu at accessibility text sizes.
@MainActor
final class UKYourSummaryViewController: UKPageViewController {
    /// The context the tabs are made with (the page itself has the sheet copy).
    private let tabContext: UKContext
    private let models: UKSummaryModels
    private let panel = UKSummaryPanelViewController()
    private let barHost = UIView()
    private var pinnedBar: UKPagePinnedBar?
    private var tabBar: UKModalTabBar<SummaryTab>?
    private var barKey = ""
    /// The tab the reader picked, or the one the sheet was asked to open on; nil until then (Profile is the default).
    private var requested: SummaryTab?
    private var hostedChores: ChoresModel?
    private var profile: UKProfileTabViewController?
    private var isSigningOut = false { didSet { applySigningOut() } }
    private var defaultsTokens: UKObserverTokens?
    private var shownKey = ""

    /// Where the sheet closes: the shell's sheet state, else a plain dismissal.
    var closeSheet: (() -> Void)?
    /// A gallery's last-call line, drawn under the navigation bar (`safeAreaInset(edge: .top)`).
    var topAccessory: UIView?

    /// - Parameters:
    ///   - opening: The tab to open on, when it is not the viewer's default (tests and the gallery).
    init(context: UKContext, models: UKSummaryModels = UKSummaryModels(), opening: SummaryTab? = nil) {
        tabContext = context
        self.models = models
        requested = opening
        super.init(context: context.with { $0.surface = .sheet })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: State

    private var choresModel: ChoresModel? { models.chores ?? hostedChores }

    /// The household resident viewing: a shared chores model's when there is one (the gallery's, which is authoritative even for a
    /// guest), else the remembered Home Assistant user.
    private var viewer: ChoresConfig.Resident? {
        guard let chores = models.chores else {
            return ChoresConfig.Resident.forUserId(UserDefaults.standard.string(forKey: ChoresModel.viewerDefaultsKey) ?? hostedChores?.viewerUserId)
        }
        return chores.viewer
    }

    private var tabs: [SummaryTab] { SummaryTab.tabs(viewer: viewer) }

    private var selected: SummaryTab {
        requested.flatMap { tabs.contains($0) ? $0 : nil } ?? .profile // Opens on Profile for everyone (owner, 2026-11-01), not the viewer's chores tab
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(panel)
        panel.view.frame = contentView.bounds
        panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(panel.view)
        panel.didMove(toParent: self)
        let pinnedBar = UKPagePinnedBar(bar: barHost)
        self.pinnedBar = pinnedBar
        pinnedBar.install(in: self)
        view.accessibilityIdentifier = "account.sheet"
        if let topAccessory { view.addSubview(topAccessory) }

        // A hosted chores model refreshes its viewer once, and the remembered user then decides the tabs.
        if models.chores == nil, let connection = tabContext.connection {
            let hosted = ChoresModel.live(connection: connection, session: tabContext.session)
            hostedChores = hosted
            Task { await hosted.refreshViewer() }
        }
        defaultsTokens = UKObserverTokens([
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ])
        bag.observe { [weak self] in self?.refresh() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pinnedBar?.layoutChanged()
        guard let accessory = topAccessory else { return }
        let side = HassTokens.Spacing.l
        let width = max(0, view.bounds.width - 2 * side)
        let height = ceil(accessory.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let systemTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        accessory.frame = CGRect(x: side, y: systemTop + 4, width: width, height: height)
        view.bringSubviewToFront(accessory)
        let inset = height + 8
        if abs(additionalSafeAreaInsets.top - inset) > 0.5 { additionalSafeAreaInsets.top = inset }
    }

    private func refresh() {
        let viewer = viewer
        let tabs = tabs
        let selected = selected
        let counts = ProfileSummary.counts(viewer: viewer, store: tabContext.store)
        navigationItem.title = ProfileSummary.title(viewer: viewer)

        // The bar is rebuilt when its tabs or badges change; a pick only moves its selection.
        let key = tabs.map(\.rawValue).joined(separator: ",") + "|\(counts.overdue)|\(counts.expiredFood)"
        if key != barKey {
            barKey = key
            tabBar?.superview?.removeFromSuperview()
            let bar = UKModalTabBar(tabs: tabs, label: SummaryTab.barLabel, title: { $0.title }, symbol: { SymbolMap.symbol(for: $0.mdiIcon) },
                                    badge: { counts.badge(for: $0) }, selection: selected, identifier: "summary.tabs") { [weak self] tab in
                self?.requested = tab
                self?.refresh()
            }
            tabBar = bar
            let wrapper = bar.inset()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            barHost.addSubview(wrapper)
            wrapper.ukPin(to: barHost)
        }
        if tabBar?.selection != selected { tabBar?.selection = selected }

        // The tab's content: a different viewer or model makes new content for the same tab.
        let contentKey = "\(selected.rawValue)|\(viewer?.key ?? "-")|\(choresModel == nil)"
        if contentKey != shownKey {
            let animated = !shownKey.isEmpty
            shownKey = contentKey
            let content = makeContent(for: selected, viewer: viewer)
            panel.show(content, for: selected, animated: animated)
            // The standard page rules (soft top edge, header fade, scroll only when needed) follow the tab that is showing.
            setPageScrollView((content as? UKSheetFitting)?.sheetFitScrollView)
        }
        applySigningOut()
    }

    private func makeContent(for tab: SummaryTab, viewer: ChoresConfig.Resident?) -> UIViewController {
        switch tab {
        case .profile:
            let page = UKProfileTabViewController(context: tabContext, confirmSignOut: { [weak self] in self?.confirmSignOut() },
                                                  showLocation: { [weak self] in self?.showLocation() })
            page.isSigningOut = isSigningOut
            profile = page
            return page
        case .overdue, .upcoming:
            if let chores = choresModel, let viewer {
                return UKSummaryChoresViewController(tab: tab, viewer: viewer, store: tabContext.store, chores: chores, connection: tabContext.connection) { [weak self] form in
                    (self?.navigationController as? UKHassModalController)?.push(form)
                }
            }
            return UIViewController()
        case .expiredFood:
            return UKSummaryExpiredFoodViewController(context: tabContext, models: models.inventory ?? connectionInventory)
        }
    }

    private var connectionInventory: InventoryModels? {
        tabContext.connection.map { tabContext.sessionModels?.inventory(for: $0) ?? InventoryModels.shared(for: $0) }
    }

    // MARK: Sign out and Location

    private func applySigningOut() {
        profile?.isSigningOut = isSigningOut
        // The server is being asked to unlink this phone: the sheet stays until it answers.
        navigationController?.isModalInPresentation = isSigningOut
        navigationItem.rightBarButtonItem?.isEnabled = !isSigningOut
    }

    private func confirmSignOut() {
        guard let presenter = navigationController else { return }
        UKAlerts.alert(AlertCopy.signOut, from: presenter, confirmID: "account.signOut.confirm", cancelID: "account.signOut.cancel") { [weak self] in
            self?.signOut()
        }
    }

    private func signOut() {
        guard let session = tabContext.session, !isSigningOut else { return }
        isSigningOut = true
        Task { [weak self] in
            do {
                try await session.confirmedSignOut()
                self?.isSigningOut = false
                self?.closeSheet?()
            } catch {
                self?.isSigningOut = false
                if let presenter = self?.navigationController {
                    UKAlerts.alert(AlertCopy.signOutFailed, from: presenter, confirmID: "account.signOut.failed.retry", cancelID: "account.signOut.failed.cancel") {
                        self?.signOut()
                    }
                }
            }
        }
    }

    /// Pushed, not a second sheet over this one (HIG: Sheets; owner, 2026-10-24, `sheet-stacking-close`).
    private func showLocation() {
        guard let location = tabContext.location, let modal = navigationController as? UKHassModalController else { return }
        modal.push(UKLocationPermission.make(location: location, onClose: { [weak self] in self?.closeSheet?() }, isPushed: true))
    }
}

// MARK: - Entry

@MainActor
enum UKYourSummary {
    /// The sheet as the section stack presents it: a full-height modal with the circle-X `account.close`.
    static func make(context: UKContext, models: UKSummaryModels = UKSummaryModels(), opening: SummaryTab? = nil) -> UKHassModalController {
        let root = UKYourSummaryViewController(context: context, models: models, opening: opening)
        let close: () -> Void = { [weak root] in
            if let navigator = context.navigator, let section = context.section {
                navigator.sheet(in: section).wrappedValue = nil
            } else {
                root?.navigationController?.dismiss(animated: true)
            }
        }
        var options = UKHassModalOptions(title: nil, fitKey: "account.sheet")
        options.closeIdentifier = "account.close"
        options.width = .form
        options.height = .full
        options.onClose = close
        root.closeSheet = close
        let modal = UKHassModalController(root: root, options: options)
        return modal
    }
}
#endif
