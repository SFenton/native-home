import FentonActivityModel
import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// The app's name and the pages it puts in Spotlight (`.agents/platforms/apple/app-name.md`).
@Suite(.demoHouse)
struct SpotlightCatalogTests {
    @Test func theAppIsCalledSPlusHAndSpokenAsSAndH() {
        #expect(AppBranding.displayName == "S+H")
        #expect(AppBranding.spokenName == "S and H")
    }

    @Test func siriAcceptsAtMostThreeAlternativeNames() {
        // Apple: "no more than three dictionaries" in INAlternativeAppNames.
        #expect(AppBranding.alternativeNames.count <= 3)
        #expect(Set(AppBranding.alternativeNames) == ["Home Assistant", "HASS", "Fenton Home"])
    }

    @Test func theSearchTermsCoverTheNamesTheOwnerAskedFor() {
        for term in ["Home", "Home Assistant", "HASS", "Fenton", "Fenton Home", "Smart Home"] {
            #expect(AppBranding.searchTerms.contains(term), "\(term) is missing")
        }
    }

    private let catalog = RouteCatalog(sessionID: String(repeating: "a", count: 64), revision: 1, routes: [
        RouteCatalogEntry(id: "kitchen-page", path: "kitchen", title: "Kitchen", summary: "Kitchen lights", icon: "fork.knife",
                          aliases: ["cooking"], keywords: ["stove"], siri: true),
        RouteCatalogEntry(id: "security-page", path: "security", title: "Security", summary: "Doors and cameras", icon: "shield.fill"),
    ])

    @Test func theCatalogHasOneEntryPerOfferedRouteAndNoCompiledPages() {
        let entries = SpotlightCatalog.entries(for: catalog)
        #expect(entries.map(\.id) == ["route.kitchen-page", "route.security-page"])
        #expect(entries.map(\.request) == [RouteRequest(path: "kitchen"), RouteRequest(path: "security")])
        #expect(SpotlightCatalog.entries(for: RouteCatalog(sessionID: catalog.sessionID, revision: 1, routes: [])).isEmpty)
    }

    @Test func everyEntryCarriesTheSearchTermsTheTitleAndAThumbnailSymbol() {
        for entry in SpotlightCatalog.entries(for: catalog) {
            #expect(Set(AppBranding.searchTerms).isSubset(of: Set(entry.keywords)), "\(entry.id)")
            #expect(entry.keywords.contains(entry.title), "\(entry.id)")
            #expect(!entry.symbol.isEmpty && !entry.summary.isEmpty, "\(entry.id)")
        }
        let kitchen = SpotlightCatalog.entry(for: catalog.routes[0])
        #expect(kitchen.keywords.contains("stove"))
        #expect(kitchen.symbol == "fork.knife")
    }

    @Test func aTappedIdentifierNamesItsRouteID() {
        #expect(SpotlightCatalog.routeID(forIdentifier: "route.kitchen-page") == "kitchen-page")
        #expect(SpotlightCatalog.routeID(forIdentifier: "route.a.b-c") == "a.b-c")
    }

    @Test func identifiersFromOlderBuildsOpenNothing() {
        for old in ["section.climate", "room.living-room", "authored.kitchen", "route.", "route", ""] {
            #expect(SpotlightCatalog.routeID(forIdentifier: old) == nil, "\(old)")
        }
    }

    @Test func theTappedIdentifierIsReadFromTheActivityUserInfo() {
        #expect(SpotlightLink.identifier(in: [SpotlightLink.userInfoKey: "route.chores"]) == "route.chores")
        #expect(SpotlightLink.identifier(in: [SpotlightLink.userInfoKey: 3]) == nil)
        #expect(SpotlightLink.identifier(in: ["other": "x"]) == nil)
        #expect(SpotlightLink.identifier(in: nil) == nil)
    }
}
