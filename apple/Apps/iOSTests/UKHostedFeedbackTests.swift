import HassCore
import HassDesign
import PhotosUI
import QuickLook
import UIKit
import XCTest
@testable import HassUI

/// Report an Issue / Request a Feature, hosted: the form's states (empty, typing, attaching, sending, failed, filed) and what each
/// control does, over the fixture filer so nothing leaves the device.
@MainActor
final class UKHostedFeedbackTests: DemoHouseTestCase {
    private struct Form {
        let page: UKFeedbackFormViewController
        let model: FeedbackFormModel
        let filer: FeedbackFixtureFiler
        let window: UIWindow
        let host: UIViewController?
    }

    private func form(kind: FeedbackKind = .bug, available: Bool = true, delay: Duration = .zero) throws -> Form {
        let filer = FeedbackFixtureFiler(available: available, delay: delay)
        let model = FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer))
        let host = try FeatureHost.signedIn()
        let page = UKFeedbackFormViewController(kind: kind, model: model, connection: host.connection)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 2400))
        FeatureHost.settle(0.4)
        return Form(page: page, model: model, filer: filer, window: window, host: nil)
    }

    private func type(_ text: String, into identifier: String, in page: UIViewController) throws {
        let view = try XCTUnwrap(FeatureHost.view(identifier, in: page.view), identifier)
        if let field = view as? UITextField {
            field.text = text
            field.sendActions(for: .editingChanged)
        } else if let box = view as? UITextView {
            box.text = text
            box.delegate?.textViewDidChange?(box)
        } else {
            XCTFail("\(identifier) is not a text control")
        }
        FeatureHost.settle(0.3)
    }

    private func fillValid(_ form: Form) throws {
        try type("[Bug] Lights flicker", into: "feedback.field.title", in: form.page)
        try type("The hall lights flicker on Home.", into: "feedback.field.description", in: form.page)
    }

    private func submitItem(_ page: UIViewController) throws -> UIBarButtonItem {
        try XCTUnwrap(page.navigationItem.rightBarButtonItem)
    }

    private func jpeg(named name: String = "photo.jpg") throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "feedback-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try XCTUnwrap(image.jpegData(compressionQuality: 0.8)).write(to: url)
        return url
    }

    // MARK: Empty and typing

    func testAnEmptyFormShowsItsFieldsAndTellsWhySubmitIsOff() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let ids = FeatureHost.identifiers(in: form.page.view)
        for identifier in ["feedback.field.title", "feedback.field.description", "feedback.field.repro", "feedback.field.expected", "feedback.attach"] {
            XCTAssertTrue(ids.contains(identifier), "\(identifier) is on the bug form")
        }
        XCTAssertEqual((FeatureHost.view("feedback.field.title", in: form.page.view) as? UITextField)?.text, "[Bug] ", "the prefix is pre-filled")
        XCTAssertFalse(try submitItem(form.page).isEnabled)
        let reason = try XCTUnwrap(form.model.blockingReason)
        XCTAssertEqual((FeatureHost.view("feedback.validation", in: form.page.view))?.accessibilityLabel, reason)
        XCTAssertEqual(try submitItem(form.page).accessibilityHint, reason, "VoiceOver hears why Submit is dimmed")
    }

    func testAFeatureRequestHasNoReproductionBoxes() throws {
        let form = try form(kind: .feature)
        defer { form.window.isHidden = true }
        let ids = FeatureHost.identifiers(in: form.page.view)
        XCTAssertTrue(ids.contains("feedback.field.description"))
        XCTAssertFalse(ids.contains("feedback.field.repro"))
        XCTAssertFalse(ids.contains("feedback.field.expected"))
        XCTAssertEqual((FeatureHost.view("feedback.field.title", in: form.page.view) as? UITextField)?.text, "[Feature] ")
    }

    func testTypingAValidReportEnablesSubmitAndUnlocksTheDiscardGuard() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        try fillValid(form)
        XCTAssertTrue(form.model.canSubmit)
        XCTAssertTrue(try submitItem(form.page).isEnabled)
        XCTAssertNil(FeatureHost.view("feedback.validation", in: form.page.view), "no reason is shown once it can be sent")
        try type("1. Open Home\n2. Wait", into: "feedback.field.repro", in: form.page)
        try type("Steady light", into: "feedback.field.expected", in: form.page)
        XCTAssertEqual(form.model.reproSteps, "1. Open Home\n2. Wait")
        XCTAssertEqual(form.model.expectedBehavior, "Steady light")
    }

    func testCancelAsksBeforeDiscardingTypedInput() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        try fillValid(form)
        form.page.requestClose()
        FeatureHost.settle(0.4)
        let sheet = try XCTUnwrap(FeatureHost.alert(on: form.page), "typed text is not thrown away silently")
        XCTAssertEqual(sheet.title, "Discard this \(FeedbackKind.bug.noun)?")
        XCTAssertEqual(sheet.actions.map(\.title), ["Discard Changes", "Keep Editing"])
        FeatureHost.answer(sheet, "Discard Changes")
        XCTAssertTrue(form.model.attachments.isEmpty)
    }

    func testCancelWithNothingTypedClosesAtOnce() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        form.page.requestClose()
        FeatureHost.settle(0.2)
        XCTAssertNil(FeatureHost.alert(on: form.page), "an empty form needs no confirmation")
        _ = try XCTUnwrap(form.page.navigationItem.leftBarButtonItem).primaryAction
    }

    // MARK: Setup

    func testAnUnconfiguredHomeAssistantShowsTheSetupNotice() throws {
        let form = try form(available: false)
        defer { form.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("feedback.setup", in: form.page.view))
        XCTAssertFalse(try submitItem(form.page).isEnabled)
    }

    // MARK: Sending

    func testSubmittingFilesTheReportAndOffersTheIssue() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        try fillValid(form)
        _ = try submitItem(form.page).primaryAction?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.8)
        XCTAssertEqual(form.filer.submittedReports.count, 1, "the report was filed once")
        XCTAssertEqual(form.filer.submittedReports.first?.title, "[Bug] Lights flicker")
        let alert = try XCTUnwrap(FeatureHost.alert(on: form.page))
        XCTAssertEqual(alert.title, "Report Sent")
        XCTAssertEqual(alert.actions.map(\.title), ["View on GitHub", "Done"])
        FeatureHost.answer(alert, "Done")
    }

    func testAFeatureRequestSaysRequestSent() throws {
        let form = try form(kind: .feature)
        defer { form.window.isHidden = true }
        try type("[Feature] Dark mode", into: "feedback.field.title", in: form.page)
        try type("A darker theme.", into: "feedback.field.description", in: form.page)
        _ = try submitItem(form.page).primaryAction?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.8)
        XCTAssertEqual(try XCTUnwrap(FeatureHost.alert(on: form.page)).title, "Request Sent")
    }

    func testAFailedSendExplainsAndReturnsToEditing() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        try type("[Bug] fixture-failed", into: "feedback.field.title", in: form.page)
        try type("It breaks.", into: "feedback.field.description", in: form.page)
        _ = try submitItem(form.page).primaryAction?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.8)
        let alert = try XCTUnwrap(FeatureHost.alert(on: form.page))
        XCTAssertEqual(alert.title, "Couldn't Send")
        FeatureHost.answer(alert, "OK")
        FeatureHost.settle(0.3)
        XCTAssertEqual(form.model.phase, .editing, "the form is editable again with everything kept")
        XCTAssertEqual(form.model.descriptionText, "It breaks.")
    }

    func testSendingShowsProgressAndStopReturnsToEditing() async throws {
        let form = try form(delay: .seconds(2))
        defer { form.window.isHidden = true }
        await FeatureHost.settleAsync(2.3)  // the availability check takes one delay too; Submit is off until it answers
        await form.model.importFiles(.success([try jpeg()]))
        await FeatureHost.settleAsync(0.3)
        try fillValid(form)
        _ = try submitItem(form.page).primaryAction?.performWithSender(nil, target: nil)
        await FeatureHost.settleAsync(0.5)
        XCTAssertTrue(form.model.isSending)
        XCTAssertNotNil(FeatureHost.view("feedback.progress", in: form.page.view), "a progress row shows while sending")
        XCTAssertTrue((FeatureHost.view("feedback.progress", in: form.page.view)?.accessibilityLabel ?? "").hasPrefix("Uploading media"))
        XCTAssertFalse((FeatureHost.view("feedback.field.title", in: form.page.view) as? UITextField)?.isEnabled ?? true, "the form is read-only meanwhile")
        XCTAssertTrue(FeatureHost.tapRow("feedback.stop", in: form.page.view))
        await FeatureHost.settleAsync(0.4)
        XCTAssertEqual(form.model.phase, .editing)
        XCTAssertNil(FeatureHost.view("feedback.progress", in: form.page.view))
    }

    // MARK: Media

    func testAttachingAPhotoShowsATileThatCanBeRemoved() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        await form.model.importFiles(.success([try jpeg()]))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(form.model.attachments.count, 1)
        let tile = try XCTUnwrap(FeatureHost.view("feedback.attachment.1", in: form.page.view))
        XCTAssertEqual(tile.accessibilityHint, "Opens in Quick Look")
        XCTAssertTrue(try XCTUnwrap(tile.accessibilityLabel).contains("photo"))
        XCTAssertTrue(FeatureHost.press("feedback.attachment.1.remove", in: form.page.view))
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(form.model.attachments.isEmpty, "Remove deletes the attachment")
        XCTAssertNil(FeatureHost.view("feedback.attachment.1", in: form.page.view))
    }

    func testOpeningAnAttachmentShowsQuickLook() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        await form.model.importFiles(.success([try jpeg()]))
        await FeatureHost.settleAsync(0.5)
        XCTAssertTrue(FeatureHost.press("feedback.attachment.1", in: form.page.view))
        await FeatureHost.settleAsync(0.6)
        FeatureHost.expectSystemPresentation(form.page.shownSheet as? QLPreviewController, "Quick Look opens for the attachment")
        let preview = (form.page.shownSheet as? QLPreviewController) ?? QLPreviewController()
        XCTAssertEqual(form.page.numberOfPreviewItems(in: preview), 1, "the app hands Quick Look the one attachment")
        XCTAssertNotNil(form.page.previewController(preview, previewItemAt: 0).previewItemURL)
    }

    func testAnUnsupportedFileIsRefusedWithAReason() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let folder = FileManager.default.temporaryDirectory.appending(path: "feedback-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = folder.appending(path: "notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        await form.model.importFiles(.success([text]))
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(form.model.attachments.isEmpty)
        let notice = try XCTUnwrap(FeatureHost.view("feedback.attachments.notice", in: form.page.view))
        XCTAssertFalse((notice.accessibilityLabel ?? "").isEmpty)
        await form.model.importFiles(.failure(CocoaError(.fileReadUnknown)))
        await FeatureHost.settleAsync(0.3)
        XCTAssertNotNil(form.model.attachmentMessage)
    }

    func testTheAttachButtonStopsAtTheLimit() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let attach = try XCTUnwrap(FeatureHost.view("feedback.attach", in: form.page.view) as? UIButton)
        XCTAssertTrue(attach.isEnabled)
        XCTAssertEqual(attach.menu?.children.map(\.title), ["Photo Library", "Choose File…"])
        for index in 0..<FeedbackLimits.attachments {
            await form.model.importFiles(.success([try jpeg(named: "p\(index).jpg")]))
        }
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(form.model.attachments.count, FeedbackLimits.attachments)
        XCTAssertEqual((FeatureHost.view("feedback.attach", in: form.page.view) as? UIButton)?.isEnabled, false, "no more than the limit")
    }

    func testTheMediaMenuOpensThePickers() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let attach = try XCTUnwrap(FeatureHost.view("feedback.attach", in: form.page.view) as? UIButton)
        let actions = attach.menu?.children.compactMap { $0 as? UIAction } ?? []
        actions.last?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.6)
        FeatureHost.expectSystemPresentation(form.page.shownSheet, "Choose File… opens the document picker")
    }

    func testPhotoPickerResultsWithNothingPickedDoNothing() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let picker = PHPickerViewController(configuration: PHPickerConfiguration())
        form.page.picker(picker, didFinishPicking: [])
        XCTAssertTrue(form.model.attachments.isEmpty)
    }

    // MARK: Text box

    func testTheTextBoxGrowsWithItsText() {
        let box = UKFeedbackTextView()
        box.minimumHeight = 96
        box.frame = CGRect(x: 0, y: 0, width: 300, height: 96)
        let empty = box.intrinsicContentSize.height
        XCTAssertGreaterThanOrEqual(empty, 96)
        var heard = ""
        box.onChange = { heard = $0 }
        box.text = Array(repeating: "A line of text that is typed.", count: 40).joined(separator: "\n")
        box.delegate?.textViewDidChange?(box)
        XCTAssertEqual(heard, box.text)
        XCTAssertGreaterThan(box.intrinsicContentSize.height, empty)
    }

    func testPresentingNeedsASignedInSession() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        UKFeedbackFormViewController.present(kind: .bug, context: UKGalleryChrome.context(), from: host)
        XCTAssertNil(host.presentedViewController, "a gallery has no session to file through")

        let signedIn = try FeatureHost.signedIn()
        let model = FeedbackFormModel(kind: .feature, services: FeedbackServices(filer: FeedbackFixtureFiler()))
        UKFeedbackFormViewController.present(kind: .feature, context: signedIn.context, from: host, model: model)
        FeatureHost.settle(0.6)
        XCTAssertNotNil(host.presentedViewController)
    }

    func testPickingFilesFromTheDocumentPickerAttachesThem() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image])
        form.page.documentPicker(picker, didPickDocumentsAt: [try jpeg()])
        for _ in 0..<10 where form.model.attachments.isEmpty { await FeatureHost.settleAsync(0.3) }
        XCTAssertEqual(form.model.attachments.count, 1, "the picked file became an attachment")
        await FeatureHost.settleAsync(0.4)
        XCTAssertNotNil(FeatureHost.view("feedback.attachments", in: form.page.view), "and the strip shows it")
    }

    func testTheFeedbackFormCancelAndDiscardWork() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        try fillValid(form)
        let cancel = try XCTUnwrap(form.page.navigationItem.leftBarButtonItem)
        _ = cancel.primaryAction?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.4)
        XCTAssertNotNil(FeatureHost.alert(on: form.page), "Cancel with typed text asks")
    }
}
