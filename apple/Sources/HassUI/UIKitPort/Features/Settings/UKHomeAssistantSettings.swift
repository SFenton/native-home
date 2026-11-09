#if os(iOS)
import HassCore
import HassDesign
import UIKit
import WebKit

/// Presents Home Assistant settings: a full-screen modal over the app, which stays usable underneath it
/// (``HomeAssistantSettingsView``; `homeAssistantSettingsCover`).
@MainActor
enum UKHomeAssistantSettings {
    /// - Parameter initialPage: A Home Assistant page to push as soon as the modal is up (a missing-layout message's action); Back
    ///   returns to the modal, Close to the page underneath.
    /// - Returns: The modal, or nil when there is no signed-in session (a gallery).
    @discardableResult
    static func present(context: UKContext, from presenter: UIViewController, user: HassUser? = nil,
                        initialPage: HomeAssistantSettingsView.WebPage? = nil) -> UKHassModalController? {
        guard let session = context.session, let connection = context.connection else { return nil }
        let page = UKHomeAssistantSettingsViewController(session: session, connection: connection, user: user, initialPage: initialPage)
        var options = UKHassModalOptions(title: "Home Assistant")
        options.closeIdentifier = "haSettings.done"
        options.isFullScreen = true
        let modal = UKHassModalController(root: page, options: options)
        page.modal = modal
        modal.present(from: presenter)
        return modal
    }
}

/// Home Assistant settings (``HomeAssistantSettingsView``): the server and its connection, the signed-in account, Home Assistant's
/// own Settings and Profile pages (a signed-in web view) and Sign Out. A grouped form on the sheet ground.
final class UKHomeAssistantSettingsViewController: UKPageViewController {
    private let session: AppSession
    private let connection: HassConnection
    private let driver = UKSettingsListDriver(style: .sheet)
    weak var modal: UKHassModalController?

    private var user: HassUser?
    private var userError = false
    private var isSigningOut = false
    /// The page to push once the modal is up; cleared when it has been.
    private var initialPage: HomeAssistantSettingsView.WebPage?

    init(session: AppSession, connection: HassConnection, user: HassUser? = nil, initialPage: HomeAssistantSettingsView.WebPage? = nil) {
        self.session = session
        self.connection = connection
        self.user = user
        self.initialPage = initialPage
        super.init(sheetTitle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: driver.collectionView)
        rebuild()
        // `.task(id: connection.status)`: load the account again whenever the connection changes.
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.connection.status
            _ = self.connection.isOffline
            self.rebuild()
            Task { await self.loadUser() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Presents the modal, then pushes the page a message's action named.
        if let page = initialPage {
            initialPage = nil
            open(page)
        }
    }

    private func loadUser() async {
        (user, userError) = await HomeAssistantSettingsView.loadedUser(user, from: connection)
        rebuild()
    }

    // MARK: Sections

    private func rebuild() {
        driver.setSections([serverSection(), accountSection(), webSection(), signOutSection()])
    }

    /// A read-only value row (`LabeledContent`): the value in ``HassTokens/Ink/secondary``, one element "Title, value".
    private func info(_ title: String, _ value: String, identifier: String) -> UKSettingsListRow {
        UKSettingsListRow(id: identifier, signature: "info|\(title)|\(value)") { cell in
            cell.show(UKRowView(.init(title, value: value, style: .form)),
                      insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
            cell.makeElement(label: "\(title), \(value)", identifier: identifier)
        }
    }

    private func serverSection() -> UKSettingsListSection {
        var rows = [
            info("Address", HomeAssistantSettingsView.displayedServer(connection.server), identifier: "haSettings.server"),
            info("Connection", HomeAssistantSettingsView.statusText(connection.status, isOffline: connection.isOffline), identifier: "haSettings.status"),
        ]
        if let version = HomeAssistantSettingsView.version(connection.status) {
            rows.append(info("Version", version, identifier: "haSettings.version"))
        }
        let layout = houseLayoutSummary()
        rows.append(info("House Layout", layout.value, identifier: "haSettings.houseLayout"))
        return UKSettingsListSection(id: "server", header: .system("Server"), footer: layout.footer, rows: rows)
    }

    /// The House Layout row: loaded, loaded with entities Home Assistant lacks, a saved copy, or why there is none
    /// (`.agents/design/house-config-states.md` rule 16). Read inside the observation, so it follows the store and the document.
    private func houseLayoutSummary() -> HouseLayoutSummary {
        if let forced = HouseLayoutDebug.current {
            return HouseLayoutSummary(hasDocument: forced.hasDocument, status: forced.status, missing: forced.missing)
        }
        let store = session.houseConfig
        let document = HouseConfigSource.active.current
        let missing = document?.missingEntityIds(hasReceivedFirstState: connection.store.hasReceivedFirstState) { connection.store.value($0) } ?? []
        return HouseLayoutSummary(hasDocument: document != nil, status: store?.status, missing: missing)
    }

    private func accountSection() -> UKSettingsListSection {
        var rows: [UKSettingsListRow] = []
        if let user {
            rows.append(info("Signed in as", HomeAssistantSettingsView.displayedName(user), identifier: "haSettings.user"))
            rows.append(info("Role", user.roleTitle, identifier: "haSettings.role"))
        } else if userError {
            rows.append(info("Signed in as", "Unavailable offline", identifier: "haSettings.user"))
        } else {
            rows.append(UKSettingsListRow(id: "haSettings.user", signature: "loading") { cell in
                let spinner = UKArcSpinnerView(.compact, label: "Loading account")
                spinner.color = UKDesignInk.secondary
                cell.show(UKRowView(.init("Signed in as", style: .form), accessory: spinner),
                          insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
                cell.makeElement(label: "Signed in as", value: "Loading account", identifier: "haSettings.user")
            })
        }
        return UKSettingsListSection(id: "account", header: .system("Account"), rows: rows)
    }

    private func webSection() -> UKSettingsListSection {
        let busy = isSigningOut
        return UKSettingsListSection(
            id: "web", header: .system("Home Assistant"), footer: "Opens Home Assistant's own pages, signed in as you.",
            rows: HomeAssistantSettingsView.webPages(for: user).map { page in
                UKSettingsRows.link(id: "web.\(page.rawValue)", identifier: "haSettings.open.\(page.rawValue)", title: page.title, subtitle: page.subtitle,
                                    symbol: page.symbol, disclosure: true, isEnabled: !busy) { [weak self] in
                    self?.open(page)
                }
            })
    }

    private func signOutSection() -> UKSettingsListSection {
        let busy = isSigningOut
        let row = UKSettingsListRow(id: "signOut", signature: "signOut|\(busy)", action: { [weak self] in
            guard let self, !busy else { return }
            UKAlerts.alert(AlertCopy.signOut, from: self) { [weak self] in self?.signOut() }
        }, configure: { cell in
            let view = UKRowView(.centeredAction("Sign Out", ink: UKDesignInk.danger, busyTitle: SignOutRow.busyTitle, isBusy: busy))
            cell.show(view, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
            cell.makeElement(label: busy ? SignOutRow.busyTitle : "Sign Out", value: busy ? "Busy" : "", traits: .button, identifier: "haSettings.signOut")
        })
        return UKSettingsListSection(id: "signOutSection", rows: [row])
    }

    // MARK: Actions

    private func open(_ page: HomeAssistantSettingsView.WebPage) {
        guard let modal else { return }
        modal.push(UKHomeAssistantWebPageViewController(page: page, session: session, connection: connection) { [weak modal] in modal?.close() })
    }

    private func signOut() {
        guard !isSigningOut else { return }
        setSigningOut(true)
        Task {
            defer { setSigningOut(false) }
            do {
                try await session.confirmedSignOut()
                modal?.close()
            } catch {
                UKAlerts.alert(AlertCopy.signOutFailed, from: self) { [weak self] in self?.signOut() }
            }
        }
    }

    /// Sign Out waits on the server: the rest of the form is disabled, Close is off and the sheet cannot be swiped away.
    private func setSigningOut(_ on: Bool) {
        isSigningOut = on
        navigationItem.rightBarButtonItem?.isEnabled = !on
        modal?.isModalInPresentation = on
        rebuild()
    }
}

// MARK: - Web page

/// One of Home Assistant's own pages (Settings or Profile), signed in with the app's session (``HomeAssistantWebPage``). Tokens go
/// to the web view through ``FrontendSession`` into a non-persistent data store, so they never reach disk and vanish when the page
/// closes. Links to other sites open in the browser. The one place the app uses a web view.
final class UKHomeAssistantWebPageViewController: UKPageViewController, WKNavigationDelegate, WKUIDelegate {
    private let page: HomeAssistantSettingsView.WebPage
    private let session: AppSession
    private let connection: HassConnection
    private let close: (() -> Void)?

    private var frontend: FrontendSession?
    private var failed = false
    private var webView: WKWebView?
    private var spinner: UKArcSpinnerView?
    private var failure: UKCenteredStateMessageView?
    private var historyObservation: NSKeyValueObservation?
    private var canGoBack = false { didSet { if canGoBack != oldValue { updateBarItems() } } }
    private var prepareTask: Task<Void, Never>?

    init(page: HomeAssistantSettingsView.WebPage, session: AppSession, connection: HassConnection, close: (() -> Void)? = nil) {
        self.page = page
        self.session = session
        self.connection = connection
        self.close = close
        super.init(sheetTitle: page.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        updateBarItems()
        showLoading()
        prepare()
    }

    deinit { prepareTask?.cancel() }

    // MARK: Bar

    /// Back (while the web view has history), Reload, then Close: the trailing-most item (owner, 2026-10-24, `sheet-stacking-close`).
    private func updateBarItems() {
        var items: [UIBarButtonItem] = []
        if let close {
            items.append(UKSheetItems.close(identifier: "haSettings.done", action: close))
        }
        let reload = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), primaryAction: UIAction { [weak self] _ in self?.reload() })
        reload.title = "Reload"
        reload.accessibilityLabel = "Reload"
        reload.accessibilityIdentifier = "haWeb.reload"
        reload.isEnabled = frontend != nil
        items.append(reload)
        if canGoBack {
            let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { [weak self] _ in self?.goBack() })
            back.title = "Back"
            back.accessibilityLabel = "Back"
            back.accessibilityHint = "Goes back one page in Home Assistant"
            back.accessibilityIdentifier = "haWeb.back"
            items.append(back)
        }
        navigationItem.rightBarButtonItems = items
    }

    private func reload() { webView?.reload() }

    private func goBack() { if webView?.canGoBack == true { webView?.goBack() } }

    /// The escape gesture goes back through the web history first; with none left it falls to the system's dismiss.
    override func accessibilityPerformEscape() -> Bool {
        if canGoBack { goBack(); return true }
        return false
    }

    // MARK: Content

    private func prepare() {
        failed = false
        showLoading()
        prepareTask?.cancel()
        prepareTask = Task { [weak self] in
            guard let self else { return }
            let made = await HomeAssistantWebPage.frontendSession(server: connection.server, tokens: session.tokens)
            guard !Task.isCancelled else { return }
            frontend = made
            failed = made == nil
            render()
        }
    }

    private func render() {
        failure?.removeFromSuperview()
        failure = nil
        if failed {
            webView?.removeFromSuperview()
            webView = nil
            spinner?.removeFromSuperview()
            spinner = nil
            let state = UKStateMessageView(
                symbol: "wifi.exclamationmark", title: "Can't open \(page.title)",
                message: "Home Assistant couldn't be reached. Check your connection and try again.",
                actionTitle: AlertCopy.tryAgain, actionIdentifier: "haWeb.retry") { [weak self] in self?.prepare() }
            let centered = UKCenteredStateMessageView(state)
            centered.frame = contentView.bounds
            centered.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(centered)
            failure = centered
        } else if let frontend, webView == nil {
            makeWebView(frontend)
        }
        updateBarItems()
    }

    private func showLoading() {
        guard spinner == nil, webView == nil || webView?.isLoading == true else { return }
        let spinner = UKArcSpinnerView(.page, label: "Loading \(page.title)…")
        spinner.color = UKDesignInk.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        self.spinner = spinner
    }

    private func hideLoading() {
        spinner?.removeFromSuperview()
        spinner = nil
    }

    private func makeWebView(_ frontend: FrontendSession) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let script = try? frontend.bootstrapScript() {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        // No edge swipe: it fought the navigation stack's back swipe. The bar's Back and the escape gesture go back.
        web.allowsBackForwardNavigationGestures = false
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.accessibilityIdentifier = "haWeb.\(page.rawValue)"
        web.translatesAutoresizingMaskIntoConstraints = false
        // Behind the loading arc, under the bottom edge (`ignoresSafeArea(edges: .bottom)`).
        contentView.insertSubview(web, at: 0)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), web.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        historyObservation = web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in
            let value = web.canGoBack
            Task { @MainActor in self?.canGoBack = value }
        }
        webView = web
        web.load(URLRequest(url: frontend.server.url(page.path)))
        showLoading()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if frontend?.isInternal(url) == true { return decisionHandler(.allow) }
        // Anything off the server (docs, integrations' sites) opens in the browser.
        if action.targetFrame?.isMainFrame ?? true { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }

    /// `target="_blank"` links: same-server pages load here, others go to the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if frontend?.isInternal(url) == true { webView.load(action.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { showLoading() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { hideLoading() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }

    private func fail(_ error: Error) {
        hideLoading()
        if (error as NSError).code == NSURLErrorCancelled { return }
        failed = true
        render()
    }
}
#endif
