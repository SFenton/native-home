@testable import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Poses

/// One pose's window.
private struct SheetPose {
    let name: String
    let window: CGSize
}

/// The poses both classes run: iPhone, folded and unfolded iPhone Duo, iPad in both orientations.
private let sheetPoses = [
    SheetPose(name: "iPhone", window: CGSize(width: 393, height: 852)),
    SheetPose(name: "Duo folded", window: CGSize(width: 466, height: 678)),
    SheetPose(name: "iPad portrait", window: CGSize(width: 834, height: 1194)),
    SheetPose(name: "iPad landscape", window: CGSize(width: 1194, height: 834)),
    SheetPose(name: "Duo unfolded landscape", window: CGSize(width: 1338, height: 669)),
]

// MARK: - No configuration refuses a swipe down; the portrait refusal is the system's

/// Hosted UX and accessibility checks for the `sheet-portrait` finding. The app configures no sheet to refuse a drag down; on the iPad in
/// portrait the system keeps the centred full-height form sheet from following one, and Close is its exit
/// (`.agents/decisions/2026-11-16-ipad-full-form-sheet.md`). Written for the iPhone, the folded and unfolded iPhone Duo and the iPad in both orientations.
@MainActor
final class UKHostedSheetDismissTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A sheet over a window of the pose, with a short page: the shape the server-UI sheets have.
    private func present(_ pose: SheetPose, width: HassSheetWidth = .form)
        -> (modal: UKHassModalController, window: UIWindow) {
        let host = UIViewController()
        let window = HostedPage.show(host, size: pose.window)
        window.traitOverrides.horizontalSizeClass = pose.window.width >= 600 ? .regular : .compact
        host.view.layoutIfNeeded()
        HostedPage.wait(0.2)
        let page = UIViewController()
        page.title = "Palette"
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 540, height: 400))
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentSize = CGSize(width: 540, height: 900)
        page.view.addSubview(scroll)
        page.preferredContentSize = CGSize(width: 540, height: 400)
        var options = UKHassModalOptions(title: "Palette", fitKey: "test.sheet.dismiss.\(pose.name).\(width)")
        options.width = width
        let modal = UKHassModalController(root: page, options: options)
        modal.present(from: host, animated: false)
        HostedPage.wait(0.6)
        return (modal, window)
    }

    /// What the system reads to decide whether a drag down dismisses the sheet, as text for a failure message.
    private func state(of modal: UKHassModalController) -> String {
        let sheet = modal.sheetPresentationController
        let presentation = modal.presentationController
        let detents = sheet?.detents.map { String(describing: $0.identifier.rawValue) } ?? []
        let shouldDismiss = presentation.flatMap { $0.delegate?.presentationControllerShouldDismiss?($0) } ?? true
        return "style=\(modal.modalPresentationStyle.rawValue) modal=\(modal.isModalInPresentation) detents=\(detents) "
            + "selected=\(String(describing: sheet?.selectedDetentIdentifier?.rawValue)) grabber=\(sheet?.prefersGrabberVisible ?? false) "
            + "pageSizing=\(sheet?.prefersPageSizing ?? false) shouldDismiss=\(shouldDismiss) "
            + "class=\(presentation.map { String(describing: type(of: $0)) } ?? "none") machinery=\(machinery(of: modal))"
    }

    /// Every recogniser from the sheet's view and its container up to the window, by view and class.
    private func machinery(of modal: UKHassModalController) -> [String] {
        var names: [String] = []
        for root in [modal.view, modal.presentationController?.containerView, modal.presentationController?.presentedView] {
            var current: UIView? = root
            while let view = current, !(view is UIWindow) {
                for recognizer in view.gestureRecognizers ?? [] { names.append("\(type(of: view)).\(type(of: recognizer))") }
                current = view.superview
            }
        }
        return Array(Set(names)).sorted()
    }

    // MARK: Dismissal

    /// Nothing in the sheet's own configuration refuses a swipe down, in any pose or width: it is not modal in presentation, no delegate
    /// refuses it, and the system's dismissal recognisers are on its container. (`sheet-portrait`: the refusal on the iPad in portrait was
    /// the system's, for a lone-detent centred form sheet; `ModalSizingJourneyTests` drags it on a device.)
    func testNoConfigurationRefusesASwipeDownInAnyPose() throws {
        for pose in sheetPoses {
            for width in [HassSheetWidth.form, .page] {
                let shown = present(pose, width: width)
                defer { shown.window.isHidden = true }
                let modal = shown.modal
                let presentation = try XCTUnwrap(modal.presentationController, "\(pose.name) \(width)")
                XCTAssertFalse(modal.isModalInPresentation, "\(pose.name) \(width): \(state(of: modal))")
                XCTAssertTrue(presentation.delegate?.presentationControllerShouldDismiss?(presentation) ?? true, "\(pose.name) \(width)")
                XCTAssertFalse(machinery(of: modal).isEmpty, "\(pose.name) \(width): the container carries the system's recognisers")
                let regular = pose.window.width >= 600
                let expected: UIModalPresentationStyle = regular && width == .form ? .formSheet : .pageSheet
                XCTAssertEqual(modal.modalPresentationStyle, expected, "\(pose.name) \(width): the style follows the width class and the sheet's width")
                shown.modal.dismiss(animated: false)
            }
        }
    }

    /// A sheet that guards unsaved input is the only one that refuses, and it says so: the attempt reaches `onAttemptToDismiss` so the
    /// presenter can ask, on every pose.
    func testAGuardedSheetRefusesAndAsksOnEveryPose() throws {
        for pose in sheetPoses {
            let shown = present(pose)
            defer { shown.window.isHidden = true }
            var asked = 0
            shown.modal.onAttemptToDismiss = { asked += 1 }
            shown.modal.isModalInPresentation = true
            let presentation = try XCTUnwrap(shown.modal.presentationController)
            shown.modal.presentationControllerDidAttemptToDismiss(presentation)
            XCTAssertEqual(asked, 1, pose.name)
            shown.modal.isModalInPresentation = false
            shown.modal.dismiss(animated: false)
        }
    }
}

// MARK: - Close is the exit of a server-UI sheet

/// Hosted UX and accessibility checks for the Close exit of the centred full-height form sheet. The system keeps that sheet from following a
/// drag down on the iPad in portrait, so Close is its exit there and a sheet without it would trap the person
/// (`.agents/decisions/2026-11-16-ipad-full-form-sheet.md`). Written for the iPhone, the folded and unfolded iPhone Duo and the iPad in
/// both orientations.
@MainActor
final class UKHostedSheetCloseExitTests: XCTestCase {
    // MARK: Fixtures

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The server-UI sheet of the conformance document (width `form`, height `full`, no toolbar items declared), presented over a window of the pose.
    private func present(_ pose: SheetPose) async throws -> (host: UKServerUIRenderer, modal: UKHassModalController, window: UIWindow) {
        let publication = try ServerUIRendererFixture.publication()
        let definition = try XCTUnwrap(publication.document.modals.first)
        XCTAssertEqual(definition.presentation.width, .form, pose.name)
        XCTAssertEqual(definition.presentation.height, .full, pose.name)
        XCTAssertEqual(definition.surface.toolbar, .replace(groups: []), "\(pose.name): the sheet declares no toolbar items")
        let host = try UKServerUIRenderer(publication: publication, context: UKContext(store: EntityStore()), backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: pose.window)
        window.traitOverrides.horizontalSizeClass = pose.window.width >= 600 ? .regular : .compact
        await FeatureHost.settleAsync(0.2)
        let root = try ServerUIRendererFixture.root(host)
        try host.perform(.present(modalId: definition.id, arguments: .init(), ifPresented: .reject), from: root)
        let opened = await FeatureHost.settleAsync(until: { host.modal?.presentingViewController != nil && host.modal?.topViewController is UKServerUIPage })
        XCTAssertTrue(opened, "\(pose.name): the sheet opens")
        return (host, try XCTUnwrap(host.modal), window)
    }

    /// Every bar item of the sheet's root page, in the trailing, leading, left and right slots.
    private func barItems(of modal: UKHassModalController) throws -> [UIBarButtonItem] {
        ServerUIRendererFixture.barItems(try XCTUnwrap(modal.viewControllers.first as? UKServerUIPage))
    }

    /// The Close item of the sheet's root bar, found by its accessibility identifier, or nil when the sheet has none.
    private func closeItem(of modal: UKHassModalController) throws -> UIBarButtonItem? {
        try barItems(of: modal).first { $0.accessibilityIdentifier == "server-ui.sheet.close" }
    }

    /// A sheet of width `form` and height `full` with no toolbar items declared carries Close in the bar at its root, in every pose.
    func testAFullHeightFormSheetWithNoToolbarItemsCarriesCloseInEveryPose() async throws {
        for pose in sheetPoses {
            let shown = try await present(pose)
            defer { shown.window.isHidden = true }
            XCTAssertNotNil(try closeItem(of: shown.modal), "\(pose.name): Close is in the sheet's root bar, its only exit where a drag does not close it")
        }
    }

    /// The sheet answers VoiceOver's Escape by closing, and Close is spoken as "Close" and as a button, in every pose.
    func testCloseHasItsLabelAndButtonTraitAndEscapeClosesTheSheetInEveryPose() async throws {
        for pose in sheetPoses {
            let shown = try await present(pose)
            defer { shown.window.isHidden = true }
            let close = try XCTUnwrap(try closeItem(of: shown.modal), pose.name)
            XCTAssertEqual(close.accessibilityLabel, "Close", pose.name)
            XCTAssertTrue(close.accessibilityTraits.contains(.button) || close.primaryAction != nil, "\(pose.name): Close is a button")
            XCTAssertTrue(shown.modal.accessibilityPerformEscape(), "\(pose.name): Escape is handled")
            let closed = await FeatureHost.settleAsync(until: { shown.host.modal == nil && shown.host.navigation.snapshot.presentations.isEmpty })
            XCTAssertTrue(closed, "\(pose.name): Escape closes the sheet")
        }
    }
}
