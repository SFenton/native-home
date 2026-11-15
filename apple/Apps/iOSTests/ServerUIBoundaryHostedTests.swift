import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - The layout recovery boundary: titles, VoiceOver, alerts and the hinge

/// The boundary the server-driven root shows while no layout is on screen (`.agents/design/server-ui-boundary.md`), drawn by the
/// production host on this run's device family: iPhone, the folded Duo's outer panel or iPad. The window is the family's own size
/// (clamped to the scene), so one run per family covers each.
@MainActor
final class ServerUIBoundaryHostedTests: XCTestCase {
    override func tearDown() async throws {
        unsetenv("FENTON_SIGNOUT_FAIL")
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A subscription that never answers (the waiting state) or answers with a failure (the failed state).
    private final class Transport: ServerUIPublicationTransport {
        let fails: Bool
        init(fails: Bool) { self.fails = fails }
        func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void {
            if fails { handler(.success(Data(#"{"state":"bogus"}"#.utf8))) }
            return {}
        }
    }

    @MainActor private struct Rig {
        let host: UKServerUIProductionHost
        let window: UIWindow
        let session: AppSession
        let runtime: UKServerUIProductionRuntime
        let directory: URL

        func close() {
            window.isHidden = true
            host.didMove(toParent: nil)
            runtime.endSession()
            session.signOut()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The family's own window: the iPad's portrait window on an iPad, else the phone window (the folded Duo's scene is 466 by 678).
    private var familySize: CGSize {
        UIDevice.current.userInterfaceIdiom == .pad
            ? HostedPage.inScene(CGSize(width: 1024, height: 1366)) : HostedPage.phoneSize
    }

    private func rig(fails: Bool = false, size: CGSize? = nil, free: Bool = false,
                     category: UIContentSizeCategory? = nil) throws -> Rig {
        let directory = URL.temporaryDirectory.appendingPathComponent("boundary-hosted-\(UUID().uuidString)")
        let session = AppSession(tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("entities")),
            houseConfigCache: HouseConfigCache(fileURL: directory.appendingPathComponent("house")),
            buildDefault: nil, launchArguments: [])
        let server = HassServer(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))
        try session.didSignIn(server: server, tokens: .init(accessToken: "synthetic", expiresAt: .distantFuture, refreshToken: "synthetic"))
        guard case .signedIn(let connection, _) = session.phase else { throw XCTSkip("Missing synthetic session") }
        let runtime = UKServerUIProductionRuntime(session: session, connection: connection, privateRoot: directory,
                                                  transport: Transport(fails: fails))
        let host = UKServerUIProductionHost(runtime: runtime, session: session, connection: connection, environment: UKShellEnvironment())
        if let category { host.traitOverrides.preferredContentSizeCategory = category }
        let window = HostedPage.show(host, size: size ?? familySize, inScene: !free)
        // With an injected transport the subscription starts when the signed-in user is known, which this rig never learns: a
        // retry starts it, and the failing transport answers at once.
        if fails { Task { await runtime.retry() } }
        HostedPage.wait(0.3)
        return Rig(host: host, window: window, session: session, runtime: runtime, directory: directory)
    }

    private func views(_ identifier: String, in root: UIView) -> [UIView] {
        HostedPage.descendants(of: root).filter { $0.accessibilityIdentifier == identifier }
    }

    private func button(_ identifier: String, in root: UIView) -> UIView? { views(identifier, in: root).first }

    private func label(_ text: String, in root: UIView) -> UILabel? {
        HostedPage.descendants(of: root).compactMap { $0 as? UILabel }.first { $0.text == text }
    }

    // MARK: Compiled copy

    func testEveryBoundaryStringKeepsItsBuiltWordsByteForByte() {
        typealias Copy = UKServerUIProductionHost.BoundaryCopy
        XCTAssertEqual(Copy.tryAgain, "Try Again")
        XCTAssertEqual(Copy.tryingAgain, "Trying Again\u{2026}")
        XCTAssertEqual(Copy.clear, "Clear Rejected Layout")
        XCTAssertEqual(Copy.signOut, "Sign Out")
        XCTAssertEqual(Copy.clearAlert.title, "Clear Rejected Layout?")
        XCTAssertEqual(Copy.clearAlert.message, "Only this account's downloaded layout will be cleared. Your Home Assistant sign-in is kept.")
        XCTAssertEqual(Copy.clearAlert.confirm, AlertCopy.Action(title: "Clear Layout", role: .destructive))
        XCTAssertEqual(Copy.clearAlert.cancel, .cancel)
        let waiting = UKServerUIProductionHost.Boundary(remote: .waiting, status: .idle, storeMissing: false, expired: false, adoptionFailed: false)
        XCTAssertEqual(waiting.title, "Getting Your Layout\u{2026}")
        XCTAssertEqual(waiting.title.unicodeScalars.last?.value, 0x2026, "One ellipsis character, not three dots")
    }

    // MARK: Titles and VoiceOver

    func testTheWaitingBoundaryReadsTitleThenMessageAndOffersOnlySignOut() throws {
        let rig = try rig()
        defer { rig.close() }
        let view = rig.host.view!
        let heading = try XCTUnwrap(label("Getting Your Layout\u{2026}", in: view), "The waiting title ends in the ellipsis character")
        XCTAssertTrue(heading.accessibilityTraits.contains(.header))
        XCTAssertNotNil(label("Waiting for your Home Assistant to send the layout.", in: view))
        XCTAssertNil(button("server-ui.production.retry", in: view), "Nothing to retry while waiting")
        XCTAssertNil(views("server-ui.production.clear", in: view).first(where: { !$0.isHidden }), "Clear is for the failed state")
        let signOut = try XCTUnwrap(button("server-ui.production.signOut", in: view) as? UIButton)
        XCTAssertEqual(signOut.currentTitle, "Sign Out")
        XCTAssertGreaterThanOrEqual(signOut.bounds.height, 44)
        let icons = HostedPage.descendants(of: try XCTUnwrap(button("server-ui.production.recovery", in: view))).compactMap { $0 as? UIImageView }
        XCTAssertFalse(icons.isEmpty)
        XCTAssertTrue(icons.allSatisfy { !$0.isAccessibilityElement }, "The glyph is hidden from VoiceOver")
        // Reading order: title, message, then the actions.
        let state = try XCTUnwrap(button("server-ui.production.recovery", in: view))
        let titleY = state.convert(heading.bounds, from: heading).minY
        XCTAssertLessThan(titleY, view.convert(signOut.bounds, from: signOut).minY)
    }

    func testTheFailedBoundaryOffersTryAgainClearAndSignOutAndShowsTheBusyTitleWhileRetrying() throws {
        let rig = try rig(fails: true)
        defer { rig.close() }
        let view = rig.host.view!
        XCTAssertTrue(HostedPage.until { self.label("Layout Unavailable", in: view) != nil }, "A failed subscription shows the failed state")
        let retry = try XCTUnwrap(button("server-ui.production.retry", in: view) as? UKPrimaryButton)
        XCTAssertEqual(retry.title, "Try Again")
        XCTAssertFalse(retry.isBusy)
        let clear = try XCTUnwrap(button("server-ui.production.clear", in: view) as? UIButton)
        XCTAssertEqual(clear.currentTitle, "Clear Rejected Layout")
        XCTAssertFalse(clear.isHidden)
        XCTAssertEqual((button("server-ui.production.signOut", in: view) as? UIButton)?.currentTitle, "Sign Out")
        retry.sendActions(for: .touchUpInside)
        let busy = try XCTUnwrap(button("server-ui.production.retry", in: view) as? UKPrimaryButton)
        XCTAssertTrue(busy.isBusy, "The button answers where it was pressed")
        XCTAssertEqual(busy.activeTitle, "Trying Again\u{2026}")
    }

    // MARK: Alert flow

    func testClearAsksFirstWithACancelAndADestructiveClearLayout() throws {
        let rig = try rig(fails: true)
        defer { rig.close() }
        let view = rig.host.view!
        XCTAssertTrue(HostedPage.until { self.label("Layout Unavailable", in: view) != nil })
        (try XCTUnwrap(button("server-ui.production.clear", in: view) as? UIButton)).sendActions(for: .touchUpInside)
        HostedPage.wait(0.4)
        let alert = try XCTUnwrap(FeatureHost.alert(on: rig.host))
        XCTAssertEqual(alert.title, "Clear Rejected Layout?")
        XCTAssertEqual(alert.message, "Only this account's downloaded layout will be cleared. Your Home Assistant sign-in is kept.")
        XCTAssertEqual(alert.actions.map(\.title), ["Cancel", "Clear Layout"])
        XCTAssertEqual(alert.actions.map(\.style), [.cancel, .destructive])
    }

    func testSignOutAsksWithTheSharedAlertAndItsFailureNamesThisDeviceWithTryAgainAndCancel() throws {
        let rig = try rig()
        defer { rig.close() }
        let view = rig.host.view!
        (try XCTUnwrap(button("server-ui.production.signOut", in: view) as? UIButton)).sendActions(for: .touchUpInside)
        HostedPage.wait(0.4)
        let ask = try XCTUnwrap(FeatureHost.alert(on: rig.host))
        let spec = AlertCopy.signOut
        XCTAssertEqual(ask.title, "Sign Out of Home Assistant?")
        XCTAssertEqual(ask.title, spec.title)
        XCTAssertEqual(ask.message, spec.message)
        XCTAssertEqual(ask.actions.map(\.title), ["Cancel", "Sign Out"])
        XCTAssertEqual(ask.actions.map(\.style), [.cancel, .destructive])
        // Cancel keeps the session.
        FeatureHost.answer(ask, "Cancel")
        HostedPage.wait(0.3)
        XCTAssertTrue(rig.session.isSignedIn)
        // A failed sign-out says why and offers Try Again.
        setenv("FENTON_SIGNOUT_FAIL", "1", 1)
        (try XCTUnwrap(button("server-ui.production.signOut", in: view) as? UIButton)).sendActions(for: .touchUpInside)
        HostedPage.wait(0.4)
        let again = try XCTUnwrap(FeatureHost.alert(on: rig.host))
        // A tap dismisses the alert before its handler runs; the failure alert needs the host free to present.
        again.presentingViewController?.dismiss(animated: false)
        HostedPage.wait(0.5)
        FeatureHost.answer(again, "Sign Out", dismissing: false)
        XCTAssertTrue(HostedPage.until { FeatureHost.alert(on: rig.host)?.title == "Couldn't Sign Out" }, "The failure is presented")
        let failure = try XCTUnwrap(FeatureHost.alert(on: rig.host))
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        XCTAssertEqual(failure.message, "Signing out needs a connection so this \(device) stops reporting its location. Connect and try again.")
        XCTAssertFalse(failure.message?.contains("phone") ?? true)
        XCTAssertEqual(failure.actions.map(\.title), ["Cancel", "Try Again"])
        XCTAssertEqual(failure.actions.map(\.style), [.cancel, .default])
        XCTAssertTrue(rig.session.isSignedIn, "The session is still signed in")
    }

    // MARK: Accessibility size

    func testTheBoundaryScrollsAndKeepsEveryActionReachableAtTheLargestTextSize() throws {
        let rig = try rig(fails: true, category: .accessibilityExtraExtraExtraLarge)
        defer { rig.close() }
        let view = rig.host.view!
        XCTAssertTrue(HostedPage.until { self.label("Layout Unavailable", in: view) != nil })
        HostedPage.wait(0.2)
        view.layoutIfNeeded()
        let scroll = try XCTUnwrap(HostedPage.descendants(of: view).compactMap { $0 as? UIScrollView }
            .first { $0.superview?.accessibilityIdentifier == "server-ui.production.recoveryRegion" })
        XCTAssertGreaterThanOrEqual(scroll.contentSize.height, scroll.bounds.height)
        for identifier in ["server-ui.production.retry", "server-ui.production.clear", "server-ui.production.signOut"] {
            let control = try XCTUnwrap(button(identifier, in: view), identifier)
            XCTAssertGreaterThanOrEqual(control.bounds.height, 44, identifier)
            XCTAssertLessThanOrEqual(control.convert(control.bounds, to: scroll).maxX, scroll.contentSize.width + 0.5, identifier)
        }
    }

    // MARK: Hinge

    /// A partly folded Duo: a vertical band down the middle of the inner display (455.3 to 495.7 pt, measured on the simulator).
    private let band = CGRect(x: 455.3, y: 0, width: 40.4, height: 682)
    private let duoInner = CGSize(width: 951, height: 682)

    private func columnFrames(_ rig: Rig) throws -> [CGRect] {
        let view = rig.host.view!
        view.layoutIfNeeded()
        let identifiers = ["server-ui.production.recovery", "server-ui.production.clear", "server-ui.production.signOut"]
        return try identifiers.compactMap { identifier in
            let found = try XCTUnwrap(button(identifier, in: view), identifier)
            return found.isHidden ? nil : found.convert(found.bounds, to: nil)
        }
    }

    func testPartlyFoldedTheWholeColumnSitsInTheLeadingRegionClearOfTheBand() throws {
        UKHinge.hasFold = true
        UKHinge.frame = band
        let rig = try rig(fails: true, size: duoInner, free: true)
        defer { rig.close() }
        let view = rig.host.view!
        XCTAssertTrue(HostedPage.until { self.label("Layout Unavailable", in: view) != nil })
        HostedPage.wait(0.2)
        let frames = try columnFrames(rig)
        XCTAssertEqual(frames.count, 3, "State, Clear and Sign Out are all in the column")
        for frame in frames {
            XCTAssertLessThanOrEqual(frame.maxX, band.minX + 0.5, "In the leading region, clear of the band")
            XCTAssertFalse(frame.insetBy(dx: 0.5, dy: 0).intersects(band))
        }
        let centre = frames.map(\.midX).reduce(0, +) / Double(frames.count)
        XCTAssertEqual(centre, band.minX / 2, accuracy: 2, "Centred in the leading region")
    }

    func testLyingFlatTheColumnStaysCentredAndAChangeOfPoseMovesItInPlace() throws {
        UKHinge.hasFold = true
        UKHinge.frame = nil
        let rig = try rig(fails: true, size: duoInner, free: true)
        defer { rig.close() }
        let view = rig.host.view!
        XCTAssertTrue(HostedPage.until { self.label("Layout Unavailable", in: view) != nil })
        let flat = try columnFrames(rig)
        for frame in flat { XCTAssertEqual(frame.midX, duoInner.width / 2, accuracy: 1, "Lying flat the column is centred") }
        UKHinge.frame = band
        view.layoutIfNeeded()
        HostedPage.wait(0.2)
        view.layoutIfNeeded()
        for frame in try columnFrames(rig) { XCTAssertLessThanOrEqual(frame.maxX, band.minX + 0.5) }
        UKHinge.frame = nil
        HostedPage.wait(0.2)
        view.layoutIfNeeded()
        for frame in try columnFrames(rig) { XCTAssertEqual(frame.midX, duoInner.width / 2, accuracy: 1) }
    }

    func testWithoutAHingeTheColumnIsCentredOnEveryFamily() throws {
        let rig = try rig()
        defer { rig.close() }
        let safe = rig.host.view.safeAreaLayoutGuide.layoutFrame
        for frame in try columnFrames(rig) {
            XCTAssertEqual(frame.midX, rig.host.view.convert(safe, to: nil).midX, accuracy: 1, "Centred in the safe area")
        }
    }
}
