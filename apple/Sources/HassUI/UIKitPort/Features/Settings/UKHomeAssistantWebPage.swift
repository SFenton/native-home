#if os(iOS)
import HassCore
import HassDesign
import UIKit
import WebKit

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
