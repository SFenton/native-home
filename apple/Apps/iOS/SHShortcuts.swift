import AppIntents

/// The shortcuts that appear in Spotlight, Siri and the Shortcuts app.
///
/// Two shortcuts, each with its own symbol so Spotlight's rows tell apart. The first names any page the publication authors
/// ("Open Security in S+H"): its phrase takes one ``RouteEntity`` parameter whose values come from ``RouteQuery``. The app
/// calls `updateAppShortcutParameters()` at launch and whenever the accepted routes change. The second opens the first page,
/// so there is always a phrase that works before any route is known.
///
/// Every phrase must contain the app's name (`\(.applicationName)`); Siri accepts the `INAlternativeAppNames` in its
/// place. Apple's limits: at most ten shortcuts per app, one parameter per phrase.
struct SHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRouteIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
                "Open a page in \(.applicationName)",
            ],
            shortTitle: "Open a Page",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: OpenStartPageIntent(),
            phrases: [
                "Open \(.applicationName)",
            ],
            shortTitle: "Open Start Page",
            systemImageName: "house"
        )
    }
}
