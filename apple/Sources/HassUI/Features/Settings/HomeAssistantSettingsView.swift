import HassCore
import HassDesign
import SwiftUI

/// Home Assistant settings: the server and its connection, the signed-in account, Home Assistant's own
/// Settings and Profile pages (signed-in web view), and Sign Out.
///
/// The web dashboard runs inside Home Assistant, so its "Home Assistant Settings" row just links to
/// `/config` (`portedDashboard.ts` `SETTINGS_PAGE_ITEMS`). The app owns its sign-in, so the server,
/// account and sign-out live here natively, with the backend pages one tap further.
struct HomeAssistantSettingsView {
    /// Row title in Settings (`pages/settings.json` `items.homeAssistant.title`).
    static let linkTitle = "Home Assistant Settings"
    /// Row subtitle in Settings (`pages/settings.json` `items.homeAssistant.subtitle`).
    static let linkSubtitle = "Access more in-depth Home Assistant details and settings."

    /// A Home Assistant web page the modal can open: Settings and Profile are listed in the modal's Home Assistant section; the
    /// others are opened by a missing-layout message's action (``HouseConfigCopy/Action``) and are never listed.
    enum WebPage: String, Hashable, Identifiable, CaseIterable {
        case settings, profile
        /// Home Assistant's Integrations dashboard (the S+H Home Integration is missing).
        case integrations
        /// The S+H Home Integration's own page (installed, no house layout yet).
        case houseIntegration
        /// Home Assistant's Repairs page (the house layout file is invalid).
        case repairs

        /// The pages the modal lists, in order.
        static let listed: [WebPage] = [.settings, .profile]

        var id: String { rawValue }
        var path: String {
            switch self {
            case .settings: "/config"
            case .profile: "/profile"
            case .integrations: "/config/integrations/dashboard"
            case .houseIntegration: "/config/integrations/integration/fenton_home"
            case .repairs: "/config/repairs"
            }
        }
        var title: String {
            switch self {
            case .settings: "Settings"
            case .profile: "Profile"
            case .integrations: "Integrations"
            case .houseIntegration: HouseConfigCopy.integrationName
            case .repairs: "Repairs"
            }
        }
        var symbol: String {
            switch self {
            case .settings: "gearshape"
            case .profile: "person.crop.circle"
            case .integrations: "puzzlepiece.extension"
            case .houseIntegration: "house"
            case .repairs: "wrench.and.screwdriver"
            }
        }
        var subtitle: String {
            switch self {
            case .settings: "Devices, integrations, automations and system."
            case .profile: "Language, theme and security for this account."
            case .integrations: "Add or update integrations."
            case .houseIntegration: "Set up the house layout S+H reads."
            case .repairs: "What Home Assistant says needs fixing."
            }
        }
    }










    /// The account rows after a load: the server's user while connected, otherwise the last one
    /// loaded, flagged as failed when there is none and the connection isn't still coming up.
    @MainActor static func loadedUser(_ current: HassUser?, from connection: HassConnection) async -> (HassUser?, Bool) {
        guard case .connected = connection.status else {
            return (current, current == nil && connection.status != .connecting)
        }
        do {
            return (try await connection.currentUser(), false)
        } catch {
            return (current, current == nil)
        }
    }




    // MARK: - Formatting (unit-tested)

    /// The server's host (with a non-default port), hidden in redacted screenshots.
    static func displayedServer(_ server: HassServer, redacting: Bool = ScreenshotPrivacy.isRedacting) -> String {
        if redacting { return "Hidden for screenshot" }
        let url = server.baseURL
        guard let host = url.host() else { return url.absoluteString }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// The user's name, hidden in redacted screenshots.
    static func displayedName(_ user: HassUser, redacting: Bool = ScreenshotPrivacy.isRedacting) -> String {
        if redacting { return "Hidden for screenshot" }
        return user.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed user"
    }

    /// Connection status in words.
    static func statusText(_ status: HassConnection.Status, isOffline: Bool = false) -> String {
        if isOffline { return "Offline" }
        return switch status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .waitingToReconnect: "Reconnecting…"
        case .rejected: "Signed out by server"
        }
    }

    /// Home Assistant's version while connected.
    static func version(_ status: HassConnection.Status) -> String? {
        if case let .connected(version) = status, !version.isEmpty { return version }
        return nil
    }

    /// Settings needs an administrator; Profile is always available. Unknown users see both, and
    /// Home Assistant itself refuses Settings if the role turns out to be wrong.
    static func webPages(for user: HassUser?) -> [WebPage] {
        guard let user, !user.isAdmin, !user.isOwner else { return WebPage.listed }
        return [.profile]
    }
}
