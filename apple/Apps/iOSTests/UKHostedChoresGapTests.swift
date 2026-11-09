import HassCore
import HassDesign
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HassUI

/// Chores paths the first hosted tests skipped: the admin to-do's image picks, the form's close/discard decision, and the page in a
/// window wide enough to open its forms beside the list.
@MainActor
final class UKHostedChoresGapTests: DemoHouseTestCase {
    private struct Rig {
        let service: RecordingChoresService
        let model: ChoresModel
        let host: UIViewController
        let window: UIWindow
    }

    private func rig(refuses: Bool = false) -> Rig {
        let store = EntityStore()
        let inner = ChoresFixtureService(store: store, lists: ChoresFixtures.lists())
        store.replaceAll(inner.entityStates())
        let service = RecordingChoresService(inner: inner)
        service.refuses = refuses
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: ChoresConfig.Resident.resident1.haUserId, accessToken: { "token" })
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2400))
        return Rig(service: service, model: model, host: host, window: window)
    }

    private func present(_ form: UKTodoFormController, on rig: Rig) async {
        rig.host.present(UKHassModalController(root: form, options: UKHassModalOptions(title: form.title)), animated: false)
        await FeatureHost.settleAsync(0.8)
    }

    /// An item provider that hands over `bytes` as `type`.
    private func provider(_ type: UTType, bytes: Int = 64) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(repeating: 7, count: bytes)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { done in
            done(data, nil)
            return nil
        }
        return provider
    }

    // MARK: Admin to-do images

    func testPickedImagesAreListedRemovedAndSentWithTheTask() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        await present(form, on: r)
        XCTAssertNotNil(FeatureHost.view("adminTodo.images", in: form.view), "the form offers Add Images")
        await form.readImages([provider(.png), provider(.jpeg)])
        await FeatureHost.settleAsync(0.5)
        XCTAssertTrue(form.hasEdits, "chosen images are edits that closing would drop")
        XCTAssertNil(FeatureHost.view("todoSheet.error", in: form.view), "valid images raise no error")
        XCTAssertTrue(HostedPage.labels(in: form.view).contains("Choose Different Images"), "the pick row now offers a different choice")
        type(form, "Fix the gate")
        form.confirmTapped()
        await FeatureHost.settleAsync(1.0)
        XCTAssertEqual(r.service.names.last, "upload", "a task with images goes up as an upload")
        XCTAssertEqual(r.service.calls.last?.data["images"] as? Int, 2)
    }

    func testTooManyImagesOrTheWrongKindExplainAndKeepNone() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        await present(form, on: r)
        await form.readImages(Array(repeating: provider(.png), count: 5))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(form.error, "Select no more than four images.")
        XCTAssertFalse(form.hasEdits)
        await form.readImages([provider(.gif)])
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(form.error, "Select PNG, JPEG, or WebP images.")
    }

    func testEmptyPickerResultsChangeNothingAndPickingOpensThePicker() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        await present(form, on: r)
        let picker = PHPickerViewController(configuration: PHPickerConfiguration())
        form.picker(picker, didFinishPicking: [])
        await FeatureHost.settleAsync(0.3)
        XCTAssertFalse(form.hasEdits)
        FeatureHost.press("adminTodo.images", in: form.view)
        await FeatureHost.settleAsync(0.8)
        FeatureHost.expectSystemPresentation(form.shownSheet as? PHPickerViewController, "Add Images opens the photo picker")
    }

    func testAnImagePickedBeforeClosingIsKeptAsADraftForTheNextOpening() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        await present(form, on: r)
        type(form, "Replace the filter")
        XCTAssertEqual(form.columnPopDecision, .confirmDiscard, "closing a form with typed text asks first")
        let empty = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        await present(empty, on: r)
        XCTAssertEqual(empty.columnPopDecision, .allow, "an untouched form closes without asking")
    }

    // MARK: Wide window

    private struct WideScreen {
        let page: UKTodoPageViewController
        let service: ChoresFixtureService
        let window: UIWindow
    }

    private func wideScreen(_ choresPage: ChoresConfig.Page) async -> WideScreen {
        let store = EntityStore()
        let service = ChoresFixtureService(store: store, lists: ChoresFixtures.lists())
        store.replaceAll(service.entityStates())
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: ChoresConfig.Resident.resident1.haUserId)
        let context = UKGalleryChrome.context(store: store)
        let page = UKChoresPages.page(choresPage, context: context, model: model)
        let host = UKGalleryChrome.wrap(page, context: context)
        let root = UIViewController()
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        root.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: host)
        // The page reads the window's own size class (as the shell does), not a child override: set it before the first layout.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 800))
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        await FeatureHost.settleAsync(1.0)
        return WideScreen(page: page, service: service, window: window)
    }

    func testOnAWideWindowAddOpensTheFormBesideTheListAndAddsTheItem() async throws {
        let s = await wideScreen(try demoChoresPage("groceries"))
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("todo.pane.placeholder", in: s.page.view), "the empty pane invites an Add")
        XCTAssertTrue(FeatureHost.press("fab.add", in: s.page.view))
        await FeatureHost.settleAsync(1.0)
        s.page.view.setNeedsLayout()
        s.window.rootViewController?.view.layoutIfNeeded()
        await FeatureHost.settleAsync(0.4)
        XCTAssertNil(s.page.shownSheet, "the form is a column, not a sheet")
        let field = try XCTUnwrap(HostedPage.descendants(of: s.page.view).compactMap { $0 as? UITextField }.first { $0.accessibilityIdentifier == "grocery.item" }, "the form sits beside the list: \(FeatureHost.identifiers(in: s.page.view).sorted()) shownSheet \(String(describing: s.page.shownSheet))")
        field.text = "Pears"
        field.sendActions(for: .editingChanged)
        _ = field.delegate?.textFieldShouldReturn?(field)
        await FeatureHost.settleAsync(1.0)
        XCTAssertEqual(s.service.lastCall, "todo.add_item Pears")
        XCTAssertNil(FeatureHost.view("grocery.item", in: s.page.view), "the pane goes back to its prompt once the item is added")
    }

    private func type(_ form: UKAddAdminTodoController, _ text: String) {
        guard let view = HostedPage.descendants(of: form.view).compactMap({ $0 as? UITextView }).first else { return XCTFail("no text view") }
        view.text = text
        view.delegate?.textViewDidChange?(view)
    }
}
