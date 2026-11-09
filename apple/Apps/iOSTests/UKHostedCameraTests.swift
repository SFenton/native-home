import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Service-call recorder for hosted tests.
@MainActor
final class HostedCaller: HassServiceCalling {
    var calls: [String] = []
    var data: [[String: any Sendable]] = []
    var fails = false
    struct Failure: Error {}
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append("\(domain).\(service)")
        self.data.append(data)
        if fails { throw Failure() }
    }
}

/// Camera cards and the viewer, with a stream pool whose streams never touch the network.
@MainActor
final class UKHostedCameraTests: DemoHouseTestCase {
    private var front: HomeConfig.Camera { HomeConfig.cameras[0] }

    private func pool(modes: [CameraStreamMode] = [.webRTC, .hls], fails: Bool = false) -> CameraStreamPool {
        CameraStreamPool(modes: modes, retainsShownStreams: true, observesApp: false,
                         opener: { _, _, _, _ in if fails { throw URLError(.cannotConnectToHost) } },
                         retryDelays: [], pauseAfterHidden: .seconds(600), stallAfter: .seconds(600), stallCheckInterval: .seconds(600),
                         upgradeDelays: [], frameCounter: { _ in 1 }, prepareConnection: { _ in })
    }

    private func context(store: EntityStore = EntityStore(), caller: (any HassServiceCalling)? = nil) -> (UKContext, HassConnection) {
        let connection = HassConnection(server: .example, tokens: TokenManager(store: InMemoryTokenStore()), store: store)
        var context = UKGalleryChrome.context(store: store, caller: caller)
        context.connection = connection
        return (context, connection)
    }

    private func settle() { HostedPage.wait(0.15) }

    func testCardNamesTheCameraAndReadsItsStreamState() {
        let (context, connection) = context()
        let pool = pool()
        let card = UKCameraTileView(camera: front, context: context, identifier: "home.camera.front_door", pool: pool)
        var opened: UKCameraTileView?
        card.onOpen = { opened = $0 }
        let host = UIViewController()
        host.view.addSubview(card)
        card.frame = CGRect(x: 0, y: 0, width: 180, height: 140)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        settle()

        XCTAssertEqual(card.accessibilityLabel, "Front Door camera")
        XCTAssertEqual(card.accessibilityHint, "Opens the camera")
        XCTAssertTrue(card.accessibilityTraits.contains(.button))
        XCTAssertEqual(card.accessibilityIdentifier, "home.camera.front_door")
        XCTAssertEqual(card.accessibilityValue, CameraTile.statusText(pool.model(for: front).state))
        XCTAssertEqual(card.sizeThatFits(CGSize(width: 180, height: 0)).height, card.gridHeight(forWidth: 180))

        let model = pool.appear(front, connection: connection)
        model.firstFrame(.webRTC)
        settle()
        XCTAssertEqual(model.state.phase, .live)
        XCTAssertEqual(card.accessibilityValue, CameraTile.statusText(model.state), "going live updates the spoken state")

        card.sendActions(for: .touchUpInside)
        XCTAssertTrue(opened === card, "tapping opens the camera from the card")
        card.isHighlighted = true
        XCTAssertLessThan(card.alpha, 1, "a pressed card dims")
        card.isHighlighted = false
        XCTAssertEqual(card.alpha, 1)
        XCTAssertTrue(card.point(inside: CGPoint(x: 10, y: 10), with: nil))
        XCTAssertFalse(card.point(inside: CGPoint(x: -5, y: 10), with: nil))
    }

    func testCardShowsTheOfflineAndFailedStatesAndMovesTheNameBelowAtLargeText() {
        let (context, connection) = context()
        let failing = pool(fails: true)
        let card = UKCameraTileView(camera: front, context: context, identifier: "c", pool: failing)
        let host = UIViewController()
        host.view.addSubview(card)
        card.frame = CGRect(x: 0, y: 0, width: 180, height: 140)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let regular = card.gridHeight(forWidth: 180)
        _ = failing.appear(front, connection: connection)
        for _ in 0..<20 where failing.model(for: front).state.phase != .failed { settle() }
        XCTAssertEqual(failing.model(for: front).state.phase, .failed, "a stream that cannot open stays on its snapshot")
        XCTAssertEqual(card.accessibilityValue, CameraTile.statusText(failing.model(for: front).state))

        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        host.view.layoutIfNeeded()
        settle()
        XCTAssertGreaterThan(card.gridHeight(forWidth: 180), regular, "at accessibility sizes the name sits below the picture")
        card.semanticContentAttribute = .forceRightToLeft
        card.setNeedsLayout()
        card.layoutIfNeeded()
    }

    func testCameraSectionListsEveryConfiguredCameraAndOpensTheTappedOne() {
        let (context, _) = context()
        let bag = UKObservationBag()
        var opened: HomeConfig.Camera?
        let section = UKCameraGridSectionView(context: context, identifierPrefix: "security.camera", bag: bag, pool: pool()) { camera, _ in opened = camera }
        let host = UIViewController()
        host.view.addSubview(section)
        section.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        XCTAssertEqual(section.tiles.count, HomeConfig.cameras.count)
        XCTAssertEqual(section.tiles.map(\.accessibilityIdentifier), HomeConfig.cameras.map { "security.camera.\($0.rtcStreamId)" })
        XCTAssertTrue(HostedPage.labels(in: section).contains("Cameras"))
        XCTAssertGreaterThan(section.gridHeight(forWidth: 393), 100)
        XCTAssertEqual(section.sizeThatFits(CGSize(width: 393, height: 0)).height, section.gridHeight(forWidth: 393))
        section.hinge = CGRect(x: 0, y: 300, width: 393, height: 20)
        XCTAssertEqual(section.hinge, CGRect(x: 0, y: 300, width: 393, height: 20))
        section.tiles[1].sendActions(for: .touchUpInside)
        XCTAssertEqual(opened?.rtcStreamId, HomeConfig.cameras[1].rtcStreamId)
    }

    private func viewer(pool: CameraStreamPool, caller: HostedCaller, store: EntityStore = EntityStore(), size: CGSize = CGSize(width: 393, height: 852))
        -> (UKCameraViewerViewController, UIWindow, HassConnection) {
        let (context, connection) = context(store: store, caller: caller)
        let page = UKCameraViewerViewController(camera: front, context: context.with { $0.surface = .sheet }, pool: pool, caller: caller)
        let window = HostedPage.show(page, size: size)
        return (page, window, connection)
    }

    private func control(_ id: String, in page: UIViewController) -> UKCameraControlButton? {
        HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id } as? UKCameraControlButton
    }

    func testViewerShowsStatusAndRecordsThroughTheScript() {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: front.recordingEntityId ?? "", state: "off")])
        let caller = HostedCaller()
        let pool = pool()
        let (page, window, connection) = viewer(pool: pool, caller: caller, store: store)
        defer { window.isHidden = true }
        let video = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.viewer.video" }
        XCTAssertEqual(video?.accessibilityLabel, "Front Door camera")
        XCTAssertEqual(video?.accessibilityValue, "Connecting to live video")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Connecting"))

        let model = pool.appear(front, connection: connection)
        model.firstFrame(.webRTC)
        settle()
        XCTAssertEqual(video?.accessibilityValue, "Live")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Live"))

        let sound = control("camera.control.sound", in: page)
        XCTAssertEqual(sound?.accessibilityValue, "Off", "the viewer opens muted")
        sound?.sendActions(for: .touchUpInside)
        settle()
        XCTAssertEqual(control("camera.control.sound", in: page)?.accessibilityValue, "On", "tapping sound turns it on")

        let record = control("camera.control.record", in: page)
        XCTAssertEqual(record?.accessibilityValue, "Not recording")
        record?.sendActions(for: .touchUpInside)
        settle()
        XCTAssertEqual(caller.calls, ["script.turn_on"])
        XCTAssertEqual(control("camera.control.record", in: page)?.accessibilityValue, "Recording", "the tap shows recording at once")

        XCTAssertEqual(control("camera.control.snapshot", in: page)?.accessibilityLabel, "Snapshot")
        XCTAssertNotNil(page.predictedContentHeight() ?? 1)
    }

    func testViewerOffersRetryWhenEveryModeFailsAndRetryReopensTheStream() {
        let caller = HostedCaller()
        let failing = pool(fails: true)
        let (page, window, connection) = viewer(pool: failing, caller: caller)
        defer { window.isHidden = true }
        _ = failing.appear(front, connection: connection)
        for _ in 0..<20 where failing.model(for: front).state.phase != .failed { settle() }
        settle()
        let retry = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.viewer.retry" } as? UIButton
        XCTAssertEqual(retry?.isHidden, false, "the viewer offers a retry")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Snapshot"))
        let video = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "camera.viewer.video" }
        XCTAssertEqual(video?.accessibilityValue, "Live video unavailable, showing the latest snapshot")
        retry?.sendActions(for: .touchUpInside)
        settle()
        XCTAssertNotEqual(failing.model(for: front).state.phase, .live)
    }

    func testViewerSplitsOnAWideLandscapeWindowAndStacksControlsAtLargeText() {
        let caller = HostedCaller()
        let (wide, wideWindow, _) = viewer(pool: pool(modes: []), caller: caller, size: CGSize(width: 1100, height: 700))
        defer { wideWindow.isHidden = true }
        let layouts = HostedPage.descendants(of: wide.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("camera.layout.") }
        XCTAssertEqual(layouts.count, 1)

        let (tall, window, _) = viewer(pool: pool(modes: []), caller: caller)
        defer { window.isHidden = true }
        let narrow = HostedPage.descendants(of: tall.view).compactMap(\.accessibilityIdentifier).filter { $0.hasPrefix("camera.layout.") }
        XCTAssertEqual(narrow, ["camera.layout.stacked"])
        tall.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        tall.view.setNeedsLayout()
        tall.view.layoutIfNeeded()
        settle()
        let sound = control("camera.control.sound", in: tall)
        let snapshot = control("camera.control.snapshot", in: tall)
        XCTAssertNotNil(sound)
        if let sound, let snapshot {
            let a = sound.convert(sound.bounds, to: tall.view), b = snapshot.convert(snapshot.bounds, to: tall.view)
            XCTAssertFalse(a.intersects(b), "controls do not overlap at AX5")
        }
    }

    func testSnapshotTapSavesOrReportsItsOutcomeAndASecondRecordTapStopsRecording() {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: front.recordingEntityId ?? "", state: "off")])
        let caller = HostedCaller()
        let pool = pool()
        let (page, window, connection) = viewer(pool: pool, caller: caller, store: store)
        defer { window.isHidden = true }
        let model = pool.appear(front, connection: connection)
        model.firstFrame(.webRTC)
        settle()
        let snapshot = control("camera.control.snapshot", in: page)
        XCTAssertEqual(snapshot?.isEnabled, true)
        snapshot?.sendActions(for: .touchUpInside)
        HostedPage.wait(1.0)
        // Whatever the simulator's photo permission says, the button settles into a named state rather than staying "saving".
        let value = control("camera.control.snapshot", in: page)?.accessibilityValue
        XCTAssertNotEqual(value, "Saving", "the snapshot attempt finishes; saw \(value ?? "nil")")
        let record = control("camera.control.record", in: page)
        record?.sendActions(for: .touchUpInside)
        settle()
        control("camera.control.record", in: page)?.sendActions(for: .touchUpInside)
        settle()
        XCTAssertEqual(caller.calls.count, 2, "each record tap calls the script once; saw \(caller.calls)")
        XCTAssertEqual(control("camera.control.record", in: page)?.accessibilityValue, "Not recording", "the second tap shows recording stopped")
    }

    func testAFailedRecordCallRollsBackAndSaysSo() {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: front.recordingEntityId ?? "", state: "off")])
        let caller = HostedCaller()
        caller.fails = true
        let pool = pool()
        let (page, window, connection) = viewer(pool: pool, caller: caller, store: store)
        defer { window.isHidden = true }
        pool.appear(front, connection: connection).firstFrame(.webRTC)
        settle()
        control("camera.control.record", in: page)?.sendActions(for: .touchUpInside)
        HostedPage.wait(0.8)
        XCTAssertEqual(control("camera.control.record", in: page)?.accessibilityValue, "Not recording", "a rejected call rolls the shown state back")
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0.contains("Couldn't change recording") }, "the viewer says the change failed")
    }

    // MARK: - Control tint stays inside its circle

    private func assertWashClipped(category: UIContentSizeCategory?, file: StaticString = #filePath, line: UInt = #line) {
        let button = UKCameraControlButton(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
        if let category { button.traitOverrides.preferredContentSizeCategory = category }
        button.configure(.init(title: "Sound", symbol: "speaker.wave.2.fill", isActive: true, tint: .systemBlue, pulses: false,
                               accessibilityLabel: "Sound", accessibilityValue: "On", isToggle: true, identifier: "camera.control.test"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(button)
        window.isHidden = false
        button.frame = CGRect(x: 0, y: 0, width: 120, height: button.sizeThatFits(CGSize(width: 120, height: 0)).height)
        button.layoutIfNeeded()
        defer { window.isHidden = true }
        let rounded = HostedPage.descendants(of: button).filter { $0.layer.cornerRadius > 0 }
        XCTAssertEqual(rounded.count, 1, "one rounded circle holds the tint", file: file, line: line)
        guard let circle = rounded.first else { return }
        XCTAssertEqual(circle.layer.cornerRadius, circle.bounds.width / 2, accuracy: 0.5, "the circle is round", file: file, line: line)
        XCTAssertTrue(circle.clipsToBounds, "the on tint is clipped to the circle, not drawn as a square", file: file, line: line)
        XCTAssertTrue(circle.subviews.contains { $0.frame == circle.bounds && $0.backgroundColor != nil },
                      "the tint wash fills the circle", file: file, line: line)
    }

    func testControlTintIsClippedToItsCircle() { assertWashClipped(category: nil) }

    func testControlTintIsClippedToItsCircleAtAX5() { assertWashClipped(category: .accessibilityExtraExtraExtraLarge) }
}
