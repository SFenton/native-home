import CoreSpotlight
import Foundation
import FentonActivityModel
import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// Records what the session asks of system search.
@MainActor
private final class RecordingIndexer: SpotlightIndexing {
    var indexed: [[SpotlightEntry]] = []
    var removals = 0
    func indexPages(_ entries: [SpotlightEntry]) { indexed.append(entries) }
    func removeAll() { removals += 1 }
}

/// Spotlight results and App Shortcuts: what is indexed, when, and how a tap reaches a page.
@MainActor
@Suite(.serialized, .hosted, .demoHouse)
struct SpotlightTests {
    private static let server = HassServer(baseURL: URL(string: "http://127.0.0.1:1")!)
    private static let tokens = AuthTokens(accessToken: "access", expiresAt: .distantFuture, refreshToken: "refresh")
    private static let catalog = RouteCatalog(sessionID: String(repeating: "a", count: 64), revision: 1, routes: [
        RouteCatalogEntry(id: "climate-page", path: "climate", title: "Climate", summary: "Thermostat and air", icon: "thermometer.medium",
                          aliases: ["thermostat"], keywords: ["heat", "cooling"], siri: true),
        RouteCatalogEntry(id: "kitchen-page", path: "kitchen", title: "Kitchen", summary: "Kitchen lights", icon: "fork.knife"),
    ])

    private func session(_ indexer: RecordingIndexer) -> AppSession {
        AppSession(tokenStore: InMemoryTokenStore(),
                   snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "spotlight-\(UUID()).json")),
                   spotlight: indexer)
    }

    // MARK: Session

    @Test func signingInIndexesNothingUntilAPublicationIsAcceptedAndSigningOutRemovesIt() throws {
        let indexer = RecordingIndexer()
        let session = session(indexer)
        #expect(indexer.indexed.isEmpty && indexer.removals == 0)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(indexer.indexed.isEmpty, "the app compiles no pages of its own: the index waits for the routes")
        #expect(session.routeCatalog == nil)
        session.signOut()
        #expect(indexer.removals == 1)
    }

    @Test func theInertIndexerIgnoresEverything() {
        let inert = InertSpotlightIndexer()
        inert.indexPages(SpotlightCatalog.entries(for: Self.catalog))
        inert.removeAll()
    }

    // MARK: Opening pages

    @Test func aTappedResultOpensItsRoute() throws {
        let push = PushCoordinator.inert()
        push.routeCatalog = { Self.catalog }
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "route.climate-page"]))
        let first = try #require(push.pendingRequest)
        #expect(first.route == RouteRequest(path: "climate"))
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "route.kitchen-page"]))
        let second = try #require(push.pendingRequest)
        #expect(second.route == RouteRequest(path: "kitchen") && second.id > first.id)
    }

    @Test func aResultForARouteThePublicationNoLongerListsOpensTheAppOnly() {
        let push = PushCoordinator.inert()
        push.routeCatalog = { Self.catalog }
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "route.removed"]), "it was one of ours")
        #expect(push.pendingRequest == nil, "and navigates nowhere")
        let none = PushCoordinator.inert()
        #expect(none.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "route.climate-page"]))
        #expect(none.pendingRequest == nil, "no catalog yet: the app opens, the tap is not queued")
    }

    @Test func aResultFromAnOlderVersionIsNotOurs() {
        let push = PushCoordinator.inert()
        push.routeCatalog = { Self.catalog }
        for old in ["section.climate", "room.kitchen", "authored.kitchen-page"] {
            #expect(!push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: old]), "\(old)")
        }
        #expect(!push.open(spotlightUserInfo: nil))
        #expect(push.pendingRequest == nil)
    }

    @Test func theSystemsKeyMatchesTheOneTheAppReads() {
        #expect(CSSearchableItemActivityIdentifier == SpotlightLink.userInfoKey)
    }

    // MARK: App Shortcuts

    @Test func aShortcutOpensTheRouteAtOnceOnceTheAppIsReady() {
        AppShortcutRouter.reset()
        var opened: [RouteRequest] = []
        AppShortcutRouter.install { opened.append($0) }
        AppShortcutRouter.route(RouteRequest(path: "security"))
        #expect(opened == [RouteRequest(path: "security")])
        AppShortcutRouter.reset()
    }

    @Test func aShortcutThatRunsBeforeLaunchFinishesWaits() {
        AppShortcutRouter.reset()
        AppShortcutRouter.route(RouteRequest(path: "chores"))
        var opened: [RouteRequest] = []
        AppShortcutRouter.install { opened.append($0) }
        #expect(opened == [RouteRequest(path: "chores")])
        // Delivered once.
        AppShortcutRouter.install { opened.append($0) }
        #expect(opened.count == 1)
        AppShortcutRouter.reset()
    }

    // MARK: Core Spotlight

    @Test func anItemCarriesTheTitleKeywordsAndTheAppName() throws {
        let entry = try #require(SpotlightCatalog.entries(for: Self.catalog).first { $0.id == "route.climate-page" })
        let item = CoreSpotlightIndexer.item(for: entry)
        #expect(item.uniqueIdentifier == "route.climate-page")
        #expect(item.domainIdentifier == SpotlightCatalog.domainIdentifier)
        #expect(item.attributeSet.title == "Climate")
        #expect(item.attributeSet.contentDescription?.hasPrefix("S+H") == true)
        let keywords = Set(item.attributeSet.keywords ?? [])
        #expect(["Home Assistant", "HASS", "Fenton Home", "Smart Home", "Home", "heat", "cooling"].allSatisfy(keywords.contains))
    }

    @Test func theAppDecoratesEachItemSoItCanAssociateTheEntity() throws {
        let entry = try #require(SpotlightCatalog.entries(for: Self.catalog).first)
        final class Seen: @unchecked Sendable { var ids: [String] = [] }
        let seen = Seen()
        _ = CoreSpotlightIndexer.item(for: entry) { _, entry in seen.ids.append(entry.routeID) }
        #expect(seen.ids == ["climate-page"])
    }

    @Test func theFirstLaunchOfThisBuildClearsAnOlderBuildsItemsOnce() throws {
        let suite = "spotlight-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!defaults.bool(forKey: CoreSpotlightIndexer.routesMigratedKey))
        _ = CoreSpotlightIndexer(index: CSSearchableIndex(name: "tests.\(UUID().uuidString)"), defaults: defaults)
        #expect(defaults.bool(forKey: CoreSpotlightIndexer.routesMigratedKey))
    }

    @Test func theIndexerReplacesThenRemovesTheItems() async {
        let defaults = UserDefaults(suiteName: "spotlight-replace-\(UUID().uuidString)") ?? .standard
        let indexer = CoreSpotlightIndexer(index: CSSearchableIndex(name: "tests.\(UUID().uuidString)"), defaults: defaults)
        indexer.indexPages(SpotlightCatalog.entries(for: Self.catalog))
        indexer.removeAll()
        // The calls finish on their own; give them a moment so the work is part of the run.
        try? await Task.sleep(for: .milliseconds(200))
    }
}
