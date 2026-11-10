import CoreGraphics
import Foundation
import ImageIO
import HassCore
@testable import HassUI
import Testing
import UniformTypeIdentifiers

/// A filer that answers from closures, so each test sets up the exact Home Assistant behaviour it needs.
private final class StubFiler: FeedbackFiling, @unchecked Sendable {
    var available: () async throws -> Bool = { true }
    var onUpload: (FeedbackAttachment) async throws -> URL = { _ in URL(string: "https://github.com/user-attachments/assets/1")! }
    var onSubmit: (FeedbackReport) async throws -> FiledIssue = { _ in
        FiledIssue(number: 7, url: URL(string: "https://github.com/x/y/issues/7")!)
    }
    func isAvailable() async throws -> Bool { try await available() }
    func upload(_ attachment: FeedbackAttachment) async throws -> URL { try await onUpload(attachment) }
    func submit(_ report: FeedbackReport) async throws -> FiledIssue { try await onSubmit(report) }
}

private let diagnostics = FeedbackDiagnostics(
    app: "1.0 (1)", system: "iOS 27", device: "iPhone", window: "402 x 874", homeAssistant: "2026.11",
    accessibility: "default", locale: "en_GB"
)

@MainActor
@Suite(.serialized, .hosted) // The staging folder is process-wide.
struct FeedbackFormModelTests {
    private func model(_ filer: StubFiler = StubFiler(), kind: FeedbackKind = .bug) -> FeedbackFormModel {
        FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer))
    }

    private func fill(_ model: FeedbackFormModel) {
        model.title = "Lights flicker"
        model.descriptionText = "They flicker at night."
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Draft and gating

    @Test func draftBindingsWriteThroughAndTitleKeepsItsPrefix() {
        let m = model()
        m.title = "Broken"
        m.descriptionText = "d"
        m.reproSteps = "r"
        m.expectedBehavior = "e"
        #expect(m.title == "[Bug] Broken")
        #expect(m.descriptionText == "d" && m.reproSteps == "r" && m.expectedBehavior == "e")
        #expect(m.hasUnsavedInput)
        #expect(!model().hasUnsavedInput)
    }

    @Test func submitStaysBlockedUntilAvailabilityIsKnownAndTheDraftIsValid() async {
        let m = model()
        #expect(m.blockingReason == FeedbackDraft(kind: .bug).validationIssue?.message)
        fill(m)
        #expect(m.blockingReason == "Checking Home Assistant…" && !m.canSubmit)
        await m.checkAvailability()
        #expect(m.availability == .available && m.blockingReason == nil && m.canSubmit)
    }

    @Test func unavailableIntegrationBlocksSubmit() async {
        let filer = StubFiler()
        filer.available = { false }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        #expect(m.availability == .unavailable)
        #expect(m.blockingReason == "Reporting isn't set up in Home Assistant yet." && !m.canSubmit)
    }

    @Test func aFailedAvailabilityCheckCountsAsAvailable() async {
        let filer = StubFiler()
        filer.available = { throw FeedbackFilingError.network }
        let m = model(filer)
        await m.checkAvailability()
        #expect(m.availability == .available)
    }

    // MARK: Attachments

    @Test func aPhotoIsAttachedWithItsLocationRemovedAndCanBeRemoved() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let url = try FeedbackUITestMedia.image(in: folder, name: "shot.png", type: .png, gps: true)
        let m = model()
        await m.importFiles(.success([url]))
        let attachment = try #require(m.attachments.first)
        #expect(attachment.filename == "shot.png" && attachment.mimeType == "image/png" && !attachment.isVideo)
        #expect(m.attachmentMessage == nil && m.importing == 0 && m.hasUnsavedInput)
        #expect(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        m.remove(attachment)
        #expect(m.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachment.fileURL.path))
        FeedbackFormModel.purgeStagedMedia()
    }

    @Test func importFailuresAndUnsupportedFilesShowAMessage() async throws {
        let m = model()
        await m.importFiles(.failure(FeedbackFilingError.network))
        #expect(m.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)

        await m.importFiles(.success([URL(fileURLWithPath: "/nonexistent/file.png")]))
        #expect(m.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription)

        let folder = try FeedbackUITestMedia.folder()
        let text = folder.appendingPathComponent("notes.txt")
        try "hi".write(to: text, atomically: true, encoding: .utf8)
        await m.importFiles(.success([text]))
        #expect(m.attachmentMessage == FeedbackAttachmentRejection.unsupportedType("notes.txt").errorDescription)
        #expect(m.attachments.isEmpty)
        FeedbackFormModel.purgeStagedMedia()
    }

    @Test func aFifthPhotoIsRefusedAndItsCopyDeleted() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let m = model()
        for index in 0..<FeedbackLimits.attachments {
            await m.importFiles(.success([try FeedbackUITestMedia.image(in: folder, name: "p\(index).png", type: .png, gps: false)]))
        }
        #expect(m.attachments.count == FeedbackLimits.attachments)
        await m.importFiles(.success([try FeedbackUITestMedia.image(in: folder, name: "extra.png", type: .png, gps: false)]))
        #expect(m.attachments.count == FeedbackLimits.attachments)
        #expect(m.attachmentMessage == FeedbackAttachmentRejection.tooMany.errorDescription)
        m.discardMedia()
        #expect(m.attachments.isEmpty)
        FeedbackFormModel.purgeStagedMedia()
    }

    @Test func pickedItemsThatFailOrAreEmptyAreReportedAndCounted() async throws {
        let m = model()
        await m.importPicked([
            { nil },
            { throw FeedbackFilingError.network },
        ])
        #expect(m.attachmentMessage == FeedbackAttachmentRejection.unreadable.errorDescription && m.importing == 0)

        let folder = try FeedbackUITestMedia.folder()
        let url = try FeedbackUITestMedia.image(in: folder, name: "picked.jpg", type: .jpeg, gps: true)
        let staged = try FeedbackPickedMedia.stage(url)
        await m.importPicked([{ staged }])
        #expect(m.attachments.map(\.filename) == ["picked.jpg"] && m.attachmentMessage == nil)
        FeedbackFormModel.purgeStagedMedia()
    }

    @Test func aCopyOutsideTheStagingFolderIsDeletedByItself() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let url = try FeedbackUITestMedia.image(in: folder, name: "loose.png", type: .png, gps: false)
        let m = model()
        await m.admit(url, displayName: "loose.png")
        let attachment = try #require(m.attachments.first)
        m.remove(attachment)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: folder.path), "Only the file goes, not its folder")
    }

    @Test func aCorruptPhotoIsRefusedAsUnreadableAndLeavesNothingBehind() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let bad = folder.appendingPathComponent("broken.png")
        try Data("not a png".utf8).write(to: bad)
        let m = model()
        await m.importFiles(.success([bad]))
        #expect(m.attachments.isEmpty)
        #expect(m.attachmentMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: FeedbackPickedMedia.stagingFolder.path)
            || ((try? FileManager.default.contentsOfDirectory(atPath: FeedbackPickedMedia.stagingFolder.path))?.isEmpty ?? true))
    }

    @Test func aPhotoTooBigEvenAfterCompressionIsRefusedWithItsName() async throws {
        // A noisy image far over the limit that cannot shrink below it is not attached.
        let folder = try FeedbackUITestMedia.folder()
        let url = folder.appendingPathComponent("huge.png")
        try Data(count: Int(FeedbackLimits.attachmentBytes) + 1).write(to: url)
        let m = model()
        await m.admit(url, displayName: "huge.png")
        #expect(m.attachments.isEmpty)
        #expect(m.attachmentMessage != nil)
    }

    // MARK: Import tasks

    private func stagedFolderIsEmpty() -> Bool {
        !FileManager.default.fileExists(atPath: FeedbackPickedMedia.stagingFolder.path)
            || ((try? FileManager.default.contentsOfDirectory(atPath: FeedbackPickedMedia.stagingFolder.path))?.isEmpty ?? true)
    }

    @Test(arguments: [0, 1, 4, 15])
    func discardingCancelsAFileImportQuietly(delay: Int) async throws {
        FeedbackFormModel.purgeStagedMedia()
        let folder = try FeedbackUITestMedia.folder()
        let url = try FeedbackUITestMedia.image(in: folder, name: "p.jpg", type: .jpeg, gps: true)
        let m = model()
        let task = m.startImportFiles(.success([url]))
        #expect(m.hasRunningImports)
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        m.discardMedia()
        await task.value
        #expect(m.attachments.isEmpty && m.attachmentMessage == nil && m.importing == 0 && !m.hasRunningImports)
        #expect(stagedFolderIsEmpty())
    }

    @Test func discardingCancelsPickedImportsWhereverTheyAre() async throws {
        FeedbackFormModel.purgeStagedMedia()
        let folder = try FeedbackUITestMedia.folder()
        let url = try FeedbackUITestMedia.image(in: folder, name: "picked.jpg", type: .jpeg, gps: false)
        let m = model()
        // One loader is still loading when the sheet closes, the other had already finished.
        let slow = try FeedbackPickedMedia.stage(url)
        let ready = try FeedbackPickedMedia.stage(url)
        let task = m.startImportPicked([
            { try await Task.sleep(for: .seconds(5)); return slow },
            { ready },
        ])
        await waitUntil { m.importing > 0 }
        m.discardMedia()
        await task.value
        #expect(m.attachments.isEmpty && m.attachmentMessage == nil && !m.hasRunningImports)
        FeedbackFormModel.purgeStagedMedia()
        let again = model()
        let finished = try FeedbackPickedMedia.stage(url)
        let second = again.startImportPicked([{ finished }])
        again.discardMedia()
        await second.value
        #expect(again.attachments.isEmpty && again.attachmentMessage == nil)
        #expect(stagedFolderIsEmpty())
    }

    @Test func submitWaitsWhileAnImportRuns() async throws {
        let m = model()
        fill(m)
        await m.checkAvailability()
        let task = m.startImportPicked([{ try await Task.sleep(for: .milliseconds(200)); return nil }])
        await waitUntil { m.importing > 0 }
        #expect(m.blockingReason == "Adding media…" && !m.canSubmit)
        await task.value
        #expect(m.blockingReason == nil)
    }

    @Test func aPhotoOverTheLimitIsCompressedAndRenamed() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let url = folder.appendingPathComponent("noise.png")
        let side = 1200
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in pixels.indices where index % 4 != 3 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 33)
        }
        let context = try #require(pixels.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        })
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, context, nil)
        #expect(CGImageDestinationFinalize(destination))
        let m = FeedbackFormModel(kind: .bug, services: FeedbackServices(filer: StubFiler()), attachmentLimit: 1_000_000)
        await m.importFiles(.success([url]))
        let attachment = try #require(m.attachments.first)
        #expect(attachment.wasCompressed && attachment.byteCount <= 1_000_000)
        #expect(attachment.filename.hasSuffix(".jpg"))
        m.discardMedia()
        FeedbackFormModel.purgeStagedMedia()
    }

    // MARK: Submit

    @Test func submitUploadsMediaThenFilesTheReportAndFinishes() async throws {
        let folder = try FeedbackUITestMedia.folder()
        let filer = StubFiler()
        var uploaded: [String] = []
        filer.onUpload = { uploaded.append($0.filename); return URL(string: "https://github.com/a/\(uploaded.count)")! }
        var filed: FeedbackReport?
        filer.onSubmit = { filed = $0; return FiledIssue(number: 12, url: URL(string: "https://github.com/x/y/issues/12")!) }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        await m.importFiles(.success([try FeedbackUITestMedia.image(in: folder, name: "a.png", type: .png, gps: false)]))
        m.submit(platform: .ios) { diagnostics }
        #expect(m.isSending && !m.canSubmit)
        await waitUntil { if case .finished = m.phase { true } else { false } }
        #expect(m.phase == .finished(FiledIssue(number: 12, url: URL(string: "https://github.com/x/y/issues/12")!)))
        #expect(uploaded == ["a.png"])
        #expect(filed?.title == "[Bug] Lights flicker" && filed?.media.count == 1 && filed?.platform == FeedbackPlatform.ios.rawValue)
        m.discardMedia()
        FeedbackFormModel.purgeStagedMedia()
    }

    @Test func submitDoesNothingWhileBlocked() {
        let m = model()
        m.submit(platform: .ios) { diagnostics }
        #expect(m.phase == .editing)
    }

    @Test func aFilingErrorShowsItsMessageAndCanBeAcknowledged() async {
        let filer = StubFiler()
        filer.onSubmit = { _ in throw FeedbackFilingError.rateLimited }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        m.submit(platform: .ipados) { diagnostics }
        await waitUntil { if case .failed = m.phase { true } else { false } }
        #expect(m.phase == .failed(FeedbackFilingError.rateLimited.errorDescription ?? ""))
        m.acknowledgeFailure()
        #expect(m.phase == .editing && m.title == "[Bug] Lights flicker")
        m.acknowledgeFailure() // Harmless when not failed.
        #expect(m.phase == .editing)
    }

    @Test func notConfiguredFlipsAvailabilityAndOtherErrorsReadAsNetwork() async {
        let filer = StubFiler()
        filer.onSubmit = { _ in throw FeedbackFilingError.notConfigured }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        m.submit(platform: .ios) { diagnostics }
        await waitUntil { m.availability == .unavailable }
        #expect(m.availability == .unavailable)

        struct Odd: Error {}
        let other = StubFiler()
        other.onSubmit = { _ in throw Odd() }
        let n = model(other)
        fill(n)
        await n.checkAvailability()
        n.submit(platform: .ios) { diagnostics }
        await waitUntil { if case .failed = n.phase { true } else { false } }
        #expect(n.phase == .failed(FeedbackFilingError.network.errorDescription ?? ""))
    }

    @Test func cancellingASendGoesBackToEditingWithEverythingKept() async {
        let filer = StubFiler()
        filer.onSubmit = { _ in try await Task.sleep(for: .seconds(30)); throw FeedbackFilingError.network }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        m.cancelSubmit() // Not sending: nothing happens.
        #expect(m.phase == .editing)
        m.submit(platform: .ios) { diagnostics }
        #expect(m.isSending)
        m.cancelSubmit()
        #expect(m.phase == .editing && m.title == "[Bug] Lights flicker")
    }

    @Test func discardingWhileSendingCancelsTheUpload() async {
        let filer = StubFiler()
        filer.onSubmit = { _ in try await Task.sleep(for: .seconds(30)); throw FeedbackFilingError.network }
        let m = model(filer)
        fill(m)
        await m.checkAvailability()
        m.submit(platform: .ios) { diagnostics }
        m.discardMedia()
        await waitUntil { m.phase == .editing }
        #expect(m.phase == .editing)
    }
}
