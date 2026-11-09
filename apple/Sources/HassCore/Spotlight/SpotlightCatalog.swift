import Foundation

/// The small set of pages the app puts in Spotlight (`CSSearchableItem`), and the way back from a tapped result.
///
/// Core Spotlight gives an installed app's own pages, not the app icon, extra search words. Every entry carries
/// ``AppBranding/searchTerms`` so "Home Assistant", "HASS", "Fenton" or "Smart Home" lists the app's pages, each of
/// which opens S+H on that page.
public enum SpotlightCatalog {
    /// Groups the app's items so they can all be removed at once (sign-out).
    public static let domainIdentifier = "com.sfenton.home.pages"

    /// Every item: the five root sections, then the sixteen rooms.
    public static var entries: [SpotlightEntry] { sections + rooms }

    /// Every item as `source`'s house document defines it; none without one.
    ///
    /// The rooms come from the document, so the reindexer reads this inside an observation scope on its own source:
    /// the scope below makes the facades read `source` and register with it.
    /// - Parameter source: The source whose document names the rooms.
    /// - Returns: The same list as ``entries`` would give were `source` the active one.
    public static func entries(in source: HouseConfigSource) -> [SpotlightEntry] {
        HouseConfigSource.$scoped.withValue(source) { entries }
    }

    /// The page a tapped result opens.
    /// - Parameter identifier: The tapped item's unique identifier.
    /// - Returns: The destination, or nil for an identifier from an older version of the app.
    public static func destination(forIdentifier identifier: String) -> PushDestination? {
        entriesById[identifier]?.destination
    }

    private static var entriesById: [String: SpotlightEntry] { Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }

    // MARK: - Sections

    private static let sections: [SpotlightEntry] = [
        section(.home, "Home", "Rooms, lights and everything in the house",
                ["rooms", "lights", "house", "dashboard", "overview"], "mdi:home"),
        section(.security, "Security", "Cameras, locks, doors and alarms",
                ["cameras", "locks", "doors", "alarm", "garage"], "mdi:shield"),
        section(.climate, "Climate", "Thermostat, humidity and air quality",
                ["thermostat", "temperature", "heat", "cooling", "humidity", "air quality"], "mdi:thermostat"),
        section(.chores, "Chores", "Tasks, groceries and what is overdue",
                ["tasks", "to do", "groceries", "overdue"], "mdi:clipboard-list"),
        section(.settings, "Settings", "Profile, household settings and feedback",
                ["preferences", "account", "feedback", "profile"], "mdi:cog"),
    ]

    private static func section(_ section: PushSection, _ title: String, _ summary: String, _ words: [String],
                                _ icon: String) -> SpotlightEntry {
        SpotlightEntry(id: "section.\(section.rawValue)", title: title, summary: summary,
                       keywords: words + AppBranding.searchTerms, mdiIcon: icon, destination: .section(section))
    }

    // MARK: - Rooms

    private static var rooms: [SpotlightEntry] { RoomsConfig.pages.map { page in
        SpotlightEntry(id: "room.\(page.id)", title: page.title, summary: "\(page.title) lights, climate and devices",
                       keywords: [page.title, "room"] + AppBranding.searchTerms, mdiIcon: "mdi:home",
                       destination: .homePage(page.id))
    } }
}
