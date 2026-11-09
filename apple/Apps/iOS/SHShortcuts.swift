import AppIntents

/// The shortcuts that appear in Spotlight, Siri and the Shortcuts app as soon as the app is installed.
///
/// Every phrase must contain the app's name (`\(.applicationName)`); Siri accepts the `INAlternativeAppNames` in its
/// place ("Open Climate in Home Assistant", "... in HASS"). Apple's limits: at most ten shortcuts per app.
struct SHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPageIntent(page: .home),
            phrases: [
                "Open \(.applicationName)",
                "Open Home in \(.applicationName)",
                "Show my house in \(.applicationName)",
            ],
            shortTitle: "Open Home",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .security),
            phrases: [
                "Open Security in \(.applicationName)",
                "Show cameras in \(.applicationName)",
            ],
            shortTitle: "Open Security",
            systemImageName: "shield.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .climate),
            phrases: [
                "Open Climate in \(.applicationName)",
                "Open the thermostat in \(.applicationName)",
            ],
            shortTitle: "Open Climate",
            systemImageName: "thermometer.medium"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .chores),
            phrases: [
                "Open Chores in \(.applicationName)",
                "Show my chores in \(.applicationName)",
            ],
            shortTitle: "Open Chores",
            systemImageName: "list.clipboard.fill"
        )
        AppShortcut(
            intent: OpenPageIntent(page: .settings),
            phrases: [
                "Open Settings in \(.applicationName)",
            ],
            shortTitle: "Open Settings",
            systemImageName: "gearshape.fill"
        )
    }
}
