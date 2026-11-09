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

    @Test func theCatalogHasTheFiveSectionsThenEveryRoom() {
        let ids = SpotlightCatalog.entries.map(\.id)
        #expect(Array(ids.prefix(5)) == ["section.home", "section.security", "section.climate", "section.chores", "section.settings"])
        #expect(ids.count == 5 + RoomsConfig.pages.count)
        #expect(Set(ids).count == ids.count, "identifiers are unique")
    }

    @Test func everyEntryCarriesTheSearchTermsAndAThumbnailIcon() {
        for entry in SpotlightCatalog.entries {
            #expect(Set(AppBranding.searchTerms).isSubset(of: Set(entry.keywords)), "\(entry.id)")
            #expect(entry.mdiIcon.hasPrefix("mdi:"), "\(entry.id)")
            #expect(!entry.title.isEmpty && !entry.summary.isEmpty, "\(entry.id)")
        }
    }

    @Test func sectionsOpenTheirSections() {
        #expect(SpotlightCatalog.destination(forIdentifier: "section.climate") == .section(.climate))
        #expect(SpotlightCatalog.destination(forIdentifier: "section.settings") == .section(.settings))
    }

    @Test func roomsOpenTheirPagesUnderHome() {
        #expect(SpotlightCatalog.destination(forIdentifier: "room.living-room") == .homePage("living-room"))
        for page in RoomsConfig.pages {
            #expect(SpotlightCatalog.destination(forIdentifier: "room.\(page.id)") == .homePage(page.id))
        }
    }

    @Test func anUnknownIdentifierOpensNothing() {
        #expect(SpotlightCatalog.destination(forIdentifier: "section.removed") == nil)
    }

    @Test func theTappedIdentifierIsReadFromTheActivityUserInfo() {
        #expect(SpotlightLink.identifier(in: [SpotlightLink.userInfoKey: "section.chores"]) == "section.chores")
        #expect(SpotlightLink.identifier(in: [SpotlightLink.userInfoKey: 3]) == nil)
        #expect(SpotlightLink.identifier(in: ["other": "x"]) == nil)
        #expect(SpotlightLink.identifier(in: nil) == nil)
    }
}
