import AVFoundation
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

    // MARK: - Presenting, menu and tiles

    func testPresentedFormStartsPrefilledInADebugRunAndAsksBeforeDiscardingTheDraft() throws {
        setenv("FENTON_FEEDBACK_PREFILL_TITLE", "Lights", 1)
        setenv("FENTON_FEEDBACK_PREFILL_DESCRIPTION", "They flicker.", 1)
        defer {
            unsetenv("FENTON_FEEDBACK_PREFILL_TITLE")
            unsetenv("FENTON_FEEDBACK_PREFILL_DESCRIPTION")
        }
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let signedIn = try FeatureHost.signedIn()
        UKFeedbackFormViewController.present(kind: .bug, context: signedIn.context, from: host)
        FeatureHost.settle(0.8)
        let modal = try XCTUnwrap(host.presentedViewController as? UKHassModalController)
        let page = try XCTUnwrap(modal.viewControllers.first as? UKFeedbackFormViewController)
        XCTAssertEqual((FeatureHost.view("feedback.field.title", in: page.view) as? UITextField)?.text, "[Bug] Lights", "the title prefill follows the prefix")
        XCTAssertEqual((FeatureHost.view("feedback.field.description", in: page.view) as? UITextView)?.text, "They flicker.")
        let attempt = try XCTUnwrap(modal.onAttemptToDismiss, "a swipe-down on a filled form asks first")
        attempt()
        FeatureHost.settle(0.4)
        XCTAssertNotNil(FeatureHost.alert(on: page), "the draft is not dropped silently")
        modal.dismiss(animated: false)
        FeatureHost.settle(0.4)
    }

    func testDismissingThePresentedFormDeletesTheStagedMediaFromTheModelAndTheDisk() async throws {
        FeedbackFormModel.purgeStagedMedia()
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        let signedIn = try FeatureHost.signedIn()
        let model = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: FeedbackFixtureFiler()))
        UKFeedbackFormViewController.present(kind: .bug, context: signedIn.context, from: host, model: model)
        FeatureHost.settle(0.8)
        let modal = try XCTUnwrap(host.presentedViewController as? UKHassModalController)
        await model.importFiles(.success([try jpeg()]))
        let staged = try XCTUnwrap(model.attachments.first).fileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "the photo is staged on disk while the form is open")
        modal.dismiss(animated: false)
        modal.presentationController.map { modal.presentationControllerDidDismiss($0) }
        XCTAssertTrue(model.attachments.isEmpty, "dismissing drops the attachments from the model")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "and deletes the staged file")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: FeedbackPickedMedia.stagingFolder.path)) ?? []
        XCTAssertTrue(left.isEmpty, "nothing is left in the staging folder: \(left)")
    }

    func testThePhotoLibraryMenuItemOpensThePhotoPicker() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        let attach = try XCTUnwrap(FeatureHost.view("feedback.attach", in: form.page.view) as? UIButton)
        let actions = attach.menu?.children.compactMap { $0 as? UIAction } ?? []
        let library = try XCTUnwrap(actions.first { $0.title == "Photo Library" })
        library.performWithSender(nil, target: nil)
        FeatureHost.settle(0.8)
        FeatureHost.expectSystemPresentation(form.page.shownSheet, "Photo Library opens the system picker")
        if let shown = form.page.shownSheet { XCTAssertTrue(shown is PHPickerViewController, "and it is the photo picker") }
    }

    func testTheTitleFieldWritesThroughToTheModelAndSubmitReportsTheDarkTheme() throws {
        let form = try form()
        defer { form.window.isHidden = true }
        form.page.overrideUserInterfaceStyle = .dark
        let field = try XCTUnwrap(FeatureHost.view("feedback.field.title", in: form.page.view) as? UITextField)
        field.text = "[Bug] Dark flicker"
        field.enumerateEventHandlers { action, _, event, _ in
            if event.contains(.editingChanged) { action?.performWithSender(field, target: nil) }
        }
        XCTAssertEqual(form.model.title, "[Bug] Dark flicker", "typing in the title reaches the model")
        try type("It flickers.", into: "feedback.field.description", in: form.page)
        _ = try submitItem(form.page).primaryAction?.performWithSender(nil, target: nil)
        FeatureHost.settle(0.8)
        let report = try XCTUnwrap(form.filer.submittedReports.first)
        XCTAssertEqual(form.filer.submittedReports.count, 1)
        XCTAssertEqual(report.title, "[Bug] Dark flicker")
        XCTAssertTrue(report.diagnostics.contains { $0.last?.hasSuffix("Dark") == true }, "the diagnostics say the appearance was Dark: \(report.diagnostics)")
        FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: form.page)), "Done")
    }

    func testAVideoAttachmentShowsAFilmPlaceholderAndPlayBadge() async throws {
        let form = try form()
        defer { form.window.isHidden = true }
        await form.model.importFiles(.success([try await blockMovie(seconds: 2)]))
        let shown = await FeatureHost.settleAsync(until: { FeatureHost.view("feedback.attachment.1", in: form.page.view) != nil })
        XCTAssertTrue(shown, "the tile appears")
        let attachment = try XCTUnwrap(form.model.attachments.first)
        XCTAssertTrue(attachment.isVideo)
        let tile = try XCTUnwrap(FeatureHost.view("feedback.attachment.1", in: form.page.view))
        XCTAssertTrue(tile.accessibilityLabel?.hasPrefix("Video") ?? false)
        let symbols = Self.imageViews(in: tile).compactMap(\.image)
        let film = try XCTUnwrap(UIImage(systemName: "film", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title2))))
        let play = try XCTUnwrap(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.footnote, bold: true))))
        XCTAssertTrue(symbols.contains { $0.pngData() == film.pngData() }, "the film placeholder is drawn")
        XCTAssertTrue(symbols.contains { $0.pngData() == play.pngData() }, "and the play badge")
        let strip = try XCTUnwrap(FeatureHost.view("feedback.attachments", in: form.page.view) as? UKFeedbackAttachmentStrip)
        XCTAssertFalse(strip.isAccessibilityElement, "the strip is a container; its tiles are the elements")
        strip.isAccessibilityElement = true
        XCTAssertFalse(strip.isAccessibilityElement, "and stays one")
        form.model.discardMedia()
    }

    private static func imageViews(in view: UIView) -> [UIImageView] {
        ((view as? UIImageView).map { [$0] } ?? []) + view.subviews.flatMap { imageViews(in: $0) }
    }

    // MARK: - Movie compression

    /// A short H.264 movie of panning colour blocks: large at the source bitrate, compressible by the encoder.
    private func blockMovie(seconds: Int = 8) async throws -> URL {
        let width = 640, height = 480, fps = 12
        let folder = FileManager.default.temporaryDirectory.appending(path: "feedback-movie-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt32.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels) / 4
            for y in 0..<height {
                for x in 0..<width {
                    let block = UInt64((x + frame * 3) / 8) &* 73_856_093 ^ UInt64((y + frame * 2) / 8) &* 19_349_663
                    base[y * stride + x] = UInt32(truncatingIfNeeded: (block &* 0x9E37_79B9_7F4A_7C15) >> 24)
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testAnOverLimitMovieIsCompressedThroughAdmit() async throws {
        FeedbackFormModel.purgeStagedMedia()
        let model = FeedbackFormModel(
            kind: .bug, services: FeedbackServices(filer: FeedbackFixtureFiler(available: true, delay: .zero)), attachmentLimit: 300_000)
        let movie = try await blockMovie()
        let original = try XCTUnwrap(try movie.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(original, 300_000, "the fixture must start over the injected limit")
        await model.importFiles(.success([movie]))
        XCTAssertNil(model.attachmentMessage, "a compressible movie is not refused")
        let attachment = try XCTUnwrap(model.attachments.first)
        XCTAssertTrue(attachment.wasCompressed)
        XCTAssertLessThanOrEqual(attachment.byteCount, 300_000)
        XCTAssertEqual(attachment.mimeType, "video/mp4")
        model.discardMedia()
        FeedbackFormModel.purgeStagedMedia()
    }

    func testDiscardingWhileAMovieImportsCancelsTheImport() async throws {
        FeedbackFormModel.purgeStagedMedia()
        let model = FeedbackFormModel(
            kind: .bug, services: FeedbackServices(filer: FeedbackFixtureFiler(available: true, delay: .zero)), attachmentLimit: 300_000)
        let movie = try await blockMovie()
        let task = model.startImportFiles(.success([movie]))
        XCTAssertTrue(model.hasRunningImports)
        await Task.yield()
        model.discardMedia()
        await task.value
        XCTAssertTrue(model.attachments.isEmpty, "a cancelled import attaches nothing")
        XCTAssertNil(model.attachmentMessage, "and says nothing")
        XCTAssertFalse(model.hasRunningImports)
        XCTAssertEqual(model.importing, 0)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: FeedbackPickedMedia.stagingFolder.path)) ?? []
        XCTAssertTrue(left.isEmpty, "the staging folder is empty: \(left)")
    }
}
