@testable import HassCore
import HassDesign
import Observation
import UIKit
import XCTest
@testable import HassUI

// MARK: - A sheet closed by a swipe opens again

/// A server-drawn sheet that a swipe down closed opens again from the same control, even when the sheet re-configured itself under the
/// open sheet first (an unfold, a rotation or an app switch re-runs `configureSheet`). The renderer hears the swipe through
/// `UKHassModalController` (the sheet's delegate) and its token, so a stale token or a replaced delegate would leave the renderer
/// believing the sheet is still up and refuse the next `present`. The controls that present (a folded row) re-read their enabled state
/// on the close, whichever way it came, or they stay greyed out under a closed sheet. The window sizes are the four of the three families: iPhone,
/// iPhone Duo folded and unfolded, iPad.
@MainActor
final class ServerUISheetReopenHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 744, height: 1133), CGSize(width: 1024, height: 768)]

    private func rig(_ size: CGSize) throws -> (UKServerUIRenderer, UKServerUIPage, UIWindow, String) {
        let publication = try ServerUIRendererFixture.publication()
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.1)
        return (host, try ServerUIRendererFixture.root(host), window, publication.document.modals[0].id)
    }

    private func open(_ host: UKServerUIRenderer, _ page: UKServerUIPage, _ id: String) throws -> UKHassModalController {
        try host.perform(.present(modalId: id, arguments: .init(), ifPresented: .reject), from: page)
        XCTAssertTrue(HostedPage.until(4) { host.modal?.presentingViewController != nil }, "the sheet is up")
        return try XCTUnwrap(host.modal)
    }

    /// What a swipe down does: the sheet goes, then the presentation controller tells its delegate.
    private func swipeDown(_ modal: UKHassModalController) throws {
        let controller = try XCTUnwrap(modal.presentationController)
        let presenter = try XCTUnwrap(modal.presentingViewController)
        presenter.dismiss(animated: false)
        XCTAssertTrue(HostedPage.until(4) { modal.presentingViewController == nil }, "the sheet has gone")
        controller.delegate?.presentationControllerDidDismiss?(controller)
    }

    func testASwipeCloseThenTheSameControlOpensTheSheetAgainOnEveryFamily() throws {
        for size in Self.sizes {
            let (host, page, window, id) = try rig(size)
            defer { window.isHidden = true }
            for round in 1...3 {
                let modal = try open(host, page, id)
                if round == 2 { modal.configureSheet() }
                XCTAssertEqual(host.navigation.snapshot.presentations.count, 1, "width \(size.width), round \(round): one sheet is recorded")
                try swipeDown(modal)
                XCTAssertNil(host.modal, "width \(size.width), round \(round): the renderer let go of the closed sheet")
                XCTAssertTrue(host.navigation.snapshot.presentations.isEmpty, "the navigation state recorded the close")
                XCTAssertTrue(page.view.isUserInteractionEnabled, "the page takes touches again")
                XCTAssertNotEqual(page.view.accessibilityElementsHidden, true, "VoiceOver reads the page again")
            }
            HostedPage.hideTracked()
        }
    }

    func testASwipeCloseReEnablesTheControlsThatPresentOnEveryFamily() throws {
        for size in Self.sizes {
            let (host, page, window, id) = try rig(size)
            defer { window.isHidden = true }
            let present = ServerUICompositionDocument.Action.present(modalId: id, arguments: .init(), ifPresented: .reject)
            let modal = try open(host, page, id)
            XCTAssertFalse(host.isEnabled(present, from: page), "width \(size.width): disabled while the sheet is up")
            // A control (a folded row) re-reads its enabled state only when what it read last changes. Watch from a moment the
            // renderer is idle (a push is enabled) and stays quiet: past the present's flight and any column settling it causes.
            let push = ServerUICompositionDocument.Action.push(.init(pageId: id, arguments: .init(), origin: .sender, duplicate: .reuseNearest))
            var changed = Flag()
            let quietBy = Date().addingTimeInterval(8)
            repeat {
                XCTAssertTrue(HostedPage.until(8) { host.isEnabled(push, from: page) }, "width \(size.width): the present settles")
                changed = Flag()
                let flag = changed
                withObservationTracking { _ = host.isEnabled(present, from: page) } onChange: { flag.raise() }
                HostedPage.wait(0.3)
            } while changed.isRaised && Date() < quietBy
            XCTAssertFalse(changed.isRaised, "width \(size.width): nothing changes while the sheet stays up")
            XCTAssertFalse(host.isEnabled(present, from: page), "width \(size.width): still disabled while the sheet is up")
            try swipeDown(modal)
            XCTAssertTrue(changed.isRaised, "width \(size.width): a swipe close tells the controls that present to re-read")
            XCTAssertTrue(host.isEnabled(present, from: page), "width \(size.width): and they are enabled again")
            HostedPage.hideTracked()
        }
    }

    func testTheSheetOpenedAfterASwipeCloseIsTheSheetsOwnAndClosesByEscape() throws {
        for size in Self.sizes {
            let (host, page, window, id) = try rig(size)
            defer { window.isHidden = true }
            try swipeDown(try open(host, page, id))
            let reopened = try open(host, page, id)
            XCTAssertTrue(reopened.presentationController?.delegate === reopened, "width \(size.width): the sheet is its own delegate again")
            XCTAssertTrue(reopened.accessibilityPerformEscape(), "VoiceOver's escape closes the reopened sheet")
            XCTAssertTrue(HostedPage.until(6) { host.modal == nil && reopened.presentingViewController == nil },
                          "the escape closes it and the renderer lets go")
            XCTAssertNoThrow(_ = try open(host, page, id), "and the control still opens it")
            HostedPage.hideTracked()
        }
    }
}

// MARK: - Flag

/// A one-way flag an observation's change handler (which may run off the main actor) raises.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    /// Whether ``raise()`` has run.
    var isRaised: Bool { lock.withLock { raised } }
    /// Raises the flag.
    func raise() { lock.withLock { raised = true } }
}
