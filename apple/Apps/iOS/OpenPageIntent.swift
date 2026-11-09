import AppIntents
import HassUI

/// Opens S+H on one of its root pages. The system runs it in the app's own process (`openAppWhenRun`), so the page
/// opens through the same path as a notification's link (``AppShortcutRouter``).
struct OpenPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Page"
    static let description = IntentDescription(
        "Opens a page of S+H: Home, Security, Climate, Chores or Settings.",
        categoryName: "Navigation",
        searchKeywords: ["Home Assistant", "HASS", "Fenton Home", "Smart Home", "thermostat", "cameras", "tasks"]
    )
    static let openAppWhenRun = true

    @Parameter(title: "Page") var page: AppPageOption

    init() {}

    init(page: AppPageOption) {
        self.page = page
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppShortcutRouter.route(to: page.destination)
        return .result()
    }
}
