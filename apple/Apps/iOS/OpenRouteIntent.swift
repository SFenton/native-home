import AppIntents
import HassCore
import HassUI

/// Opens S+H on one authored route. The system runs it in the app's own process, so the page opens through the same path as a
/// notification's link (``AppShortcutRouter``). `target` is the parameter name Spotlight looks for when it opens an entity.
struct OpenRouteIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open a Page"
    static let description = IntentDescription(
        "Opens a page of S+H.",
        categoryName: "Navigation",
        searchKeywords: ["Home Assistant", "HASS", "Fenton Home", "Smart Home"]
    )
    /// Earlier systems; iOS 26 deprecates it for ``supportedModes``.
    static let openAppWhenRun = true

    /// iOS 26 and later: the intent runs with the app in the foreground.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Page") var target: RouteEntity

    init() {}

    init(target: RouteEntity) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppShortcutRouter.route(RouteRequest(path: target.path))
        return .result()
    }
}

/// Opens S+H on the publication's initial page, the way a link with no path does.
struct OpenStartPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Start Page"
    static let description = IntentDescription(
        "Opens S+H on its first page.",
        categoryName: "Navigation",
        searchKeywords: ["Home Assistant", "HASS", "Fenton Home", "Smart Home"]
    )
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppShortcutRouter.route(RouteRequest())
        return .result()
    }
}
