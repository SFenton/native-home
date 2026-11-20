import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Preview state flags on the three families

/// Each DEBUG state flag of the `--server-ui-preview` route puts the page in the state it names, on the iPhone, the folded iPhone Duo
/// and the iPad, and what a person using VoiceOver hears follows (``UKServerUIPreviewFlags``).
///
/// The page is the one the preview renders: ``UKServerUIPreview/Prepared`` over the isolated gallery fixtures, with the flags the
/// preview would have passed in. Every test runs one flagged page against the unflagged one, so a state that was already there cannot pass.
@MainActor
final class ServerUIPreviewFlagsHostedTests: DemoHouseTestCase {
    /// The windows of the three families: iPhone, folded Duo and iPad.
    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678), CGSize(width: 820, height: 1180)]
    private var directory: URL!
    private var restore: (() -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        directory = URL.temporaryDirectory.appendingPathComponent("ServerUIPreviewFlagsHostedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        restore?()
        restore = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        UKDesign.animationsPaused = false
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    // MARK: Fixture

    /// The renderer the preview would mount for `flags`, shown in a window of `size`.
    private func page(flags: UKServerUIPreviewFlags, size: CGSize,
                      store: EntityStore = EntityStore()) async throws -> (UKServerUIRenderer, UKServerUIPreviewFixtures) {
        restore?()
        restore = flags.isDefault ? nil : flags.applyProcessSwitches()
        store.replaceAll([
            EntityState(entityId: "person.demo_alex", state: "home", attributes: ["friendly_name": .string("Alex Demo")]),
            EntityState(entityId: "person.demo_sam", state: "not_home", attributes: ["friendly_name": .string("Sam Demo")]),
            EntityState(entityId: "person.demo_guest", state: "home", attributes: ["friendly_name": .string("Guest")]),
        ])
        let publication = try ServerUIPreviewGalleryFixture.publication(header: true)
        let partition = try ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "https://preview.invalid")!))
        let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: partition.storageDirectory(in: directory),
            transport: ServerUIAssetTransport(server: HassServer(baseURL: URL(string: "https://preview.invalid")!),
                                              tokenProvider: { throw URLError(.notConnectedToInternet) }))
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256)
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        let fixtures = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId, administrator: true),
                                                     store: store, flags: flags)
        let prepared = try UKServerUIPreview.Prepared(publication: publication, context: fixtures.context, assets: assets,
            backdrop: ServerUIRendererFixture.backdrop(), renderDirectory: directory, fixtures: fixtures)
        _ = HostedPage.show(prepared.renderer, size: HostedPage.inScene(size))
        HostedPage.wait(0.15)
        return (prepared.renderer, fixtures)
    }

    private func trailingItems(_ renderer: UKServerUIRenderer) throws -> [UIBarButtonItem] {
        let page = try ServerUIRendererFixture.root(renderer)
        let grouped = page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
        return grouped.isEmpty ? page.navigationItem.rightBarButtonItems ?? [] : grouped
    }

    private func profile(_ renderer: UKServerUIRenderer) throws -> UIBarButtonItem {
        try XCTUnwrap(trailingItems(renderer).first { $0.customView is UKProfileButtonView || $0.accessibilityIdentifier == "nav.profile" },
                      "The shell header has a Profile button")
    }

    /// What VoiceOver reads for the Profile button (the value sits on the view's element, as in the shell tests).
    private func spokenValue(_ item: UIBarButtonItem) -> String? {
        (item.customView?.accessibilityElements?.first as? UIView)?.accessibilityValue
            ?? item.customView?.accessibilityValue ?? item.accessibilityValue
    }

    private func arcViews(_ renderer: UKServerUIRenderer) throws -> [UIView] {
        try trailingItems(renderer).compactMap(\.customView).filter { $0 is UKReconnectingArcView }
    }

    private func layers(in layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers(in:)) }

    private func spinAnimation(in view: UIView) -> CABasicAnimation? {
        layers(in: view.layer).compactMap { $0.animation(forKey: "spin") as? CABasicAnimation }.first
    }

    // MARK: connection

    func testOfflineDrawsTheProfileBadgeAndSpeaksOfflineOnEveryFamily() async throws {
        for size in Self.sizes {
            let (live, _) = try await page(flags: .init(), size: size)
            XCTAssertFalse(try spokenValue(profile(live))?.contains("Offline") ?? false, "Connected at \(size)")
            HostedPage.hideTracked()
            let (offline, _) = try await page(flags: .init(connection: .offline), size: size)
            let button = try profile(offline)
            XCTAssertTrue(try XCTUnwrap(spokenValue(button), "\(size)").contains("Offline"), "VoiceOver hears the offline state at \(size)")
            if let drawn = button.customView as? UKProfileButtonView {
                XCTAssertTrue(drawn.isOffline, "The offline badge is drawn at \(size)")
            } else {
                // The Duo's vertical bar folds Profile into a rail item that has no view of its own; its value carries the state.
                XCTAssertTrue(button.accessibilityValue?.contains("Offline") == true, "The rail item says offline at \(size)")
            }
            XCTAssertTrue(try arcViews(offline).isEmpty, "Offline shows no reconnecting arc at \(size)")
            HostedPage.hideTracked()
        }
    }

    func testReconnectingLightsTheArcAndNamesItOnEveryFamily() async throws {
        for size in Self.sizes {
            let (live, _) = try await page(flags: .init(), size: size)
            XCTAssertTrue(try arcViews(live).isEmpty, "No arc while connected at \(size)")
            let before = try trailingItems(live).count
            HostedPage.hideTracked()
            let (retrying, _) = try await page(flags: .init(connection: .reconnecting), size: size)
            let arcs = try arcViews(retrying)
            XCTAssertEqual(arcs.count, 1, "One arc beside Quick Links at \(size)")
            XCTAssertGreaterThan(try trailingItems(retrying).count, before)
            let named = HostedPage.descendants(of: try XCTUnwrap(arcs.first)).contains { $0.accessibilityLabel == ReconnectingArc.label }
            XCTAssertTrue(named, "VoiceOver hears the arc named \"\(ReconnectingArc.label)\" at \(size)")
            XCTAssertFalse(try spokenValue(profile(retrying))?.contains("Offline") ?? false, "Retrying is not offline at \(size)")
            HostedPage.hideTracked()
        }
    }

    // MARK: failCalls

    func testFailedCallsDrawTheFailedFaceWhereTheUnflaggedCallSucceeds() async throws {
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        for size in Self.sizes {
            for failing in [false, true] {
                let flags = UKServerUIPreviewFlags(failCalls: failing)
                let fixtures = try UKServerUIPreviewFixtures(configuration: .init(viewerUserID: viewer.haUserId, administrator: true),
                                                             store: EntityStore(), flags: flags)
                let store = EntityStore()
                store.replaceAll([EntityState(entityId: "input_boolean.demo_auto_clean", state: "off")])
                let host = try UKServerUIRenderer(publication: autoCleanPublication(),
                    context: UKContext(store: store, caller: fixtures.caller), backdrop: ServerUIRendererFixture.backdrop())
                _ = HostedPage.show(host, size: HostedPage.inScene(size))
                HostedPage.wait(0.1)
                let root = try ServerUIRendererFixture.root(host)
                root.view.layoutIfNeeded()
                let node = try XCTUnwrap(root.nodes["auto-clean-row"]?.view as? UKServerUILocalControl)
                let row = try XCTUnwrap(node.drawnControl as? UKModuleToggleRow)
                row.sendActions(for: .touchUpInside)
                await host.callRunner.waitForCalls()
                let words = "Automatic cleaning did not respond."
                let showsFailure = await HostedPage.settle { self.spoken(node).contains(words) }
                XCTAssertEqual(showsFailure, failing, "failCalls \(failing) at \(size): \(spoken(node))")
                XCTAssertEqual(host.callRunner.isFailed(node: "auto-clean-row"), failing)
                let captions = labels(in: node).compactMap(\.text)
                XCTAssertEqual(captions.contains(words), failing, "The caption is drawn under the row only when the call failed")
                HostedPage.hideTracked()
            }
        }
    }

    private func autoCleanPublication() throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/parts-row-auto-clean-row.json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func spoken(_ view: UIView) -> [String] {
        var result = [view.accessibilityLabel].compactMap { $0 }
        for element in view.accessibilityElements ?? [] {
            if let child = element as? UIView { result += spoken(child) } else if let label = (element as? NSObject)?.accessibilityLabel { result.append(label) }
        }
        for child in view.subviews { result += spoken(child) }
        return result
    }

    private func stateMessage(in view: UIView) -> UIView? {
        HostedPage.descendants(of: view).first { $0 is UKStateMessageView }
    }

    private func labels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap(labels(in:))
    }

    // MARK: empty

    func testEmptyLeavesTheListWithItsEmptyTextOnEveryFamily() async throws {
        for size in Self.sizes {
            for empty in [false, true] {
                let (renderer, fixtures) = try await page(flags: .init(empty: empty), size: size)
                let collection = try XCTUnwrap(renderer.recordCollection("records-groceries"))
                try await collection.load()
                XCTAssertEqual(collection.records.isEmpty, empty, "empty \(empty) at \(size): \(collection.error ?? "no error")")
                let root = try ServerUIRendererFixture.root(renderer)
                let view = try XCTUnwrap(root.nodes[ServerUIPreviewGalleryFixture.collectionID]?.view as? UKServerUICollectionView)
                let drawn = await HostedPage.settle {
                    empty ? view.rows.isEmpty && self.stateMessage(in: view) != nil
                          : !view.rows.isEmpty
                }
                XCTAssertTrue(drawn, "The list draws \(empty ? "no rows" : "its rows") at \(size)")
                let message = stateMessage(in: view)
                XCTAssertEqual(message != nil, empty, "The empty state is drawn only when the list is empty at \(size)")
                if let message {
                    let words = labels(in: message).compactMap(\.text).filter { !$0.isEmpty }
                    XCTAssertFalse(words.isEmpty, "The empty state says something a person can read at \(size)")
                    XCTAssertTrue(spoken(message).contains { !$0.isEmpty } || !words.isEmpty, "VoiceOver reaches the empty state at \(size)")
                }
                XCTAssertTrue(fixtures.recordService.inventory.rows.isEmpty == empty)
                HostedPage.hideTracked()
            }
        }
    }

    // MARK: gateDelayMs

    func testTheGateDelayShowsTheLoadingLineBeforeTheFirstLayoutOnEveryFamily() async throws {
        for size in Self.sizes {
            try Data(#"{"entities":{},"flags":{"gateDelayMs":500}}"#.utf8).write(to: directory.appendingPathComponent("bootstrap.json"))
            let preview = UKServerUIPreview(directory: directory, environmentName: "FENTON_FLAGS_HOSTED_\(UUID().uuidString.prefix(6))",
                                            launchEnvironment: [:])
            _ = HostedPage.show(preview, size: HostedPage.inScene(size))
            let started = ContinuousClock.now
            let load = Task { await preview.loadPublication() }
            HostedPage.wait(0.15)
            let status = try XCTUnwrap(HostedPage.descendants(of: preview.view)
                .first { $0.accessibilityIdentifier == "server-ui.preview.status" } as? UILabel)
            XCTAssertEqual(status.text, "Downloading configuration...", "The gate shows the loading line at \(size)")
            XCTAssertNil(preview.renderer, "Nothing is laid out yet at \(size)")
            XCTAssertTrue(status.frame.width > 0 && !status.isHidden, "The line is on screen at \(size)")
            XCTAssertTrue(status.adjustsFontForContentSizeCategory, "The line follows the person's text size")
            await load.value
            XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(500), "The load waited at \(size)")
            HostedPage.hideTracked()
        }
    }

    // MARK: animationsPaused

    func testPausedAnimationsHoldTheReconnectingArcStillOnEveryFamily() async throws {
        for size in Self.sizes {
            let (moving, _) = try await page(flags: .init(connection: .reconnecting), size: size)
            let movingArc = try XCTUnwrap(arcViews(moving).first)
            XCTAssertNotNil(spinAnimation(in: movingArc), "The arc turns when nothing is paused at \(size)")
            HostedPage.hideTracked()
            let (paused, _) = try await page(flags: .init(connection: .reconnecting, animationsPaused: true), size: size)
            let pausedArc = try XCTUnwrap(arcViews(paused).first)
            XCTAssertNil(spinAnimation(in: pausedArc), "The arc is held still when animations are paused at \(size)")
            XCTAssertTrue(HostedPage.descendants(of: pausedArc).contains { $0.accessibilityLabel == ReconnectingArc.label },
                          "A still arc is still named for VoiceOver at \(size)")
            HostedPage.hideTracked()
        }
    }

    // MARK: reduceMotion

    func testReduceMotionIsForcedThroughUKMotionAndSlowsTheArcOnEveryFamily() async throws {
        for size in Self.sizes {
            let (normal, _) = try await page(flags: .init(connection: .reconnecting), size: size)
            let normalSpin = try XCTUnwrap(spinAnimation(in: XCTUnwrap(arcViews(normal).first)), "\(size)")
            XCTAssertEqual(UKMotion.reduceMotion, UIAccessibility.isReduceMotionEnabled, "Unflagged, the system setting rules")
            HostedPage.hideTracked()
            let (reduced, _) = try await page(flags: .init(connection: .reconnecting, reduceMotion: true), size: size)
            XCTAssertTrue(UKMotion.reduceMotion, "The one reader says Reduce Motion is on at \(size)")
            XCTAssertTrue(UKDesign.reduceMotion)
            let reducedSpin = try XCTUnwrap(spinAnimation(in: XCTUnwrap(arcViews(reduced).first)), "\(size)")
            XCTAssertEqual(reducedSpin.duration, normalSpin.duration * 2, accuracy: 0.001, "The arc turns at half speed under Reduce Motion at \(size)")
            XCTAssertTrue(reduced.environment.reduceMotion,
                          "The shell's mirror follows the forced setting at \(size)")
            HostedPage.hideTracked()
        }
    }
}
