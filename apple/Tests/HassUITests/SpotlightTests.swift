import CoreSpotlight
import Foundation
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

    private func session(_ indexer: RecordingIndexer) -> AppSession {
        AppSession(tokenStore: InMemoryTokenStore(),
                   snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "spotlight-\(UUID()).json")),
                   spotlight: indexer)
    }

    // MARK: Session

    @Test func signingInIndexesThePagesAndSigningOutRemovesThem() throws {
        let indexer = RecordingIndexer()
        let session = session(indexer)
        #expect(indexer.indexed.isEmpty && indexer.removals == 0)
        try session.didSignIn(server: Self.server, tokens: Self.tokens)
        #expect(indexer.indexed == [SpotlightCatalog.entries(in: .shared)])
        session.signOut()
        #expect(indexer.removals == 1)
    }

    @Test func theInertIndexerIgnoresEverything() {
        let inert = InertSpotlightIndexer()
        inert.indexPages(SpotlightCatalog.entries)
        inert.removeAll()
    }

    // MARK: Opening pages

    @Test func aTappedResultOpensItsPage() throws {
        let push = PushCoordinator.inert()
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "section.climate"]))
        let first = try #require(push.pendingRequest)
        #expect(first.destination == .section(.climate))
        #expect(push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "room.kitchen"]))
        let second = try #require(push.pendingRequest)
        #expect(second.destination == .homePage("kitchen") && second.id > first.id)
    }

    @Test func aResultFromAnOlderVersionOpensNothing() {
        let push = PushCoordinator.inert()
        #expect(!push.open(spotlightUserInfo: [CSSearchableItemActivityIdentifier: "section.removed"]))
        #expect(!push.open(spotlightUserInfo: nil))
        #expect(push.pendingRequest == nil)
    }

    @Test func theSystemsKeyMatchesTheOneTheAppReads() {
        #expect(CSSearchableItemActivityIdentifier == SpotlightLink.userInfoKey)
    }

    @Test func everyRoomResultLandsOnARoomPage() {
        for entry in SpotlightCatalog.entries {
            guard case let .homePage(path) = entry.destination else { continue }
            #expect(HomeRoute(pushPath: path) != nil, "\(entry.id) opens nothing")
        }
    }

    // MARK: App Shortcuts

    @Test func aShortcutOpensThePageAtOnceOnceTheAppIsReady() {
        AppShortcutRouter.reset()
        var opened: [PushDestination] = []
        AppShortcutRouter.install { opened.append($0) }
        AppShortcutRouter.route(to: .section(.security))
        #expect(opened == [.section(.security)])
        AppShortcutRouter.reset()
    }

    @Test func aShortcutThatRunsBeforeLaunchFinishesWaits() {
        AppShortcutRouter.reset()
        AppShortcutRouter.route(to: .section(.chores))
        var opened: [PushDestination] = []
        AppShortcutRouter.install { opened.append($0) }
        #expect(opened == [.section(.chores)])
        // Delivered once.
        AppShortcutRouter.install { opened.append($0) }
        #expect(opened.count == 1)
        AppShortcutRouter.reset()
    }

    // MARK: Core Spotlight

    @Test func anItemCarriesTheTitleKeywordsAndTheAppName() throws {
        let entry = try #require(SpotlightCatalog.entries.first { $0.id == "section.climate" })
        let item = CoreSpotlightIndexer.item(for: entry)
        #expect(item.uniqueIdentifier == "section.climate")
        #expect(item.domainIdentifier == SpotlightCatalog.domainIdentifier)
        #expect(item.attributeSet.title == "Climate")
        #expect(item.attributeSet.contentDescription?.hasPrefix("S+H") == true)
        let keywords = Set(item.attributeSet.keywords ?? [])
        #expect(["Home Assistant", "HASS", "Fenton Home", "Smart Home", "Home", "thermostat"].allSatisfy(keywords.contains))
    }

    @Test func theIndexerReplacesThenRemovesTheItems() async {
        let indexer = CoreSpotlightIndexer(index: CSSearchableIndex(name: "tests.\(UUID().uuidString)"))
        indexer.indexPages(SpotlightCatalog.entries)
        indexer.removeAll()
        // The calls finish on their own; give them a moment so the work is part of the run.
        try? await Task.sleep(for: .milliseconds(200))
    }
}
