import HassCore
import HassDesign
import SwiftUI
#if os(iOS)
import WebKit
#endif

/// One of Home Assistant's own pages (Settings or Profile), signed in with the app's session.
///
/// Tokens are handed over through ``FrontendSession`` into a non-persistent web data store, so they
/// never reach disk and vanish when the page closes. Links to other sites open in the browser.
struct HomeAssistantWebPage {
    var page: HomeAssistantSettingsView.WebPage
    /// Closes the settings modal this page is pushed in; the page carries Close like every pushed page (HIG: Sheets).
    var close: (() -> Void)?

    @Environment(AppSession.self) private var session





    /// The sign-in hand-off for the web view, with fresh tokens; `nil` when signed out or the refresh fails.
    static func frontendSession(server: HassServer, tokens: TokenManager?) async -> FrontendSession? {
        guard let tokens, let current = try? await tokens.validTokens() else { return nil }
        return FrontendSession(server: server, tokens: current)
    }
}
