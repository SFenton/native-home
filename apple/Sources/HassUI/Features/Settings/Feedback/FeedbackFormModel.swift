import Foundation
import HassCore
import Observation
import SwiftUI

/// State behind a Report an Issue / Request a Feature sheet, ported from FestivalNativeApps'
/// `FeedbackFormModel`.
///
/// Owns the draft, the app's private copies of attached media, whether Home Assistant can file reports,
/// and the submit phase. Media is copied into app temporary storage so the original stays
/// untouched; ``discardMedia()`` deletes the copies.
@MainActor
@Observable
final class FeedbackFormModel {
    /// Where the submit is.
    enum Phase: Equatable {
        case editing
        /// Uploading media (`step` of `total`, the last step being the issue itself).
        case sending(step: Int, total: Int)
        case finished(FiledIssue)
        /// The message to show.
        case failed(String)
    }

    /// Whether Home Assistant's Fenton Home Feedback integration can file reports.
    enum Availability: Equatable {
        case checking
        case available
        /// The integration isn't installed or set up.
        case unavailable
    }

    private(set) var draft: FeedbackDraft
    private(set) var attachments: [FeedbackAttachment] = []
    private(set) var phase: Phase = .editing
    private(set) var availability: Availability = .checking
    /// Why the last picked file was refused, shown under Attach Media.
    private(set) var attachmentMessage: String?
    /// Picked items still being copied, so Submit waits for them.
    private(set) var importing = 0
    @ObservationIgnored let services: FeedbackServices
    @ObservationIgnored private var submitTask: Task<Void, Never>?

    /// Starts an empty form.
    /// - Parameters:
    ///   - kind: Bug report or feature request.
    ///   - services: Where reports are filed.
    init(kind: FeedbackKind, services: FeedbackServices) {
        draft = FeedbackDraft(kind: kind)
        self.services = services
    }

    // MARK: - Draft

    /// Prefix-preserving title binding target.
    var title: String {
        get { draft.title }
        set { draft.setTitle(newValue) }
    }

    var descriptionText: String {
        get { draft.description }
        set { draft.description = newValue }
    }

    var reproSteps: String {
        get { draft.reproSteps }
        set { draft.reproSteps = newValue }
    }

    var expectedBehavior: String {
        get { draft.expectedBehavior }
        set { draft.expectedBehavior = newValue }
    }

    /// Whether closing would lose typed text or attached media.
    var hasUnsavedInput: Bool { draft.hasTypedInput || !attachments.isEmpty }

    /// Uploading or filing: the form is read-only.
    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    /// The reason Submit is disabled, shown under the form; nil when it can be sent.
    var blockingReason: String? {
        if let issue = draft.validationIssue { return issue.message }
        if availability == .unavailable { return "Reporting isn't set up in Home Assistant yet." }
        if availability == .checking { return "Checking Home Assistant…" }
        if importing > 0 { return "Adding media…" }
        return nil
    }

    /// Submit is enabled only for a valid draft, with Home Assistant ready and every picked item copied.
    var canSubmit: Bool { blockingReason == nil && phase == .editing }

    // MARK: - Availability

    /// Asks Home Assistant whether it can file reports. A failed check counts as available, so Submit shows the
    /// real error rather than a guess.
    func checkAvailability() async {
        do {
            availability = try await services.filer.isAvailable() ? .available : .unavailable
        } catch {
            availability = .available
        }
    }

    // MARK: - Attachments

    /// Copies files chosen in the system file importer.
    /// - Parameter result: The importer's result; a failure is shown as a message.
    func importFiles(_ result: Result<[URL], any Error>) async {
        switch result {
        case let .success(urls):
            for url in urls { await importFile(at: url) }
        case .failure:
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
        }
    }

    /// Copies photos and videos from any picker: each loader returns the staged copy of one pick (`PHPickerViewController`'s item
    /// provider in the UIKit port).
    /// - Parameter loaders: One per picked item.
    func importPicked(_ loaders: [@MainActor () async throws -> FeedbackPickedMedia?]) async {
        for load in loaders {
            importing += 1
            defer { importing -= 1 }
            do {
                guard let picked = try await load() else {
                    attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
                    continue
                }
                await admit(picked.url, displayName: picked.url.lastPathComponent)
            } catch {
                attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            }
        }
    }

    /// Removes one attachment and its private copy.
    func remove(_ attachment: FeedbackAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        Self.deleteCopy(attachment.fileURL)
        attachmentMessage = nil
    }

    /// Stops any upload and deletes every private media copy (on dismiss).
    func discardMedia() {
        submitTask?.cancel()
        for attachment in attachments { Self.deleteCopy(attachment.fileURL) }
        attachments = []
    }

    private func importFile(at url: URL) async {
        importing += 1
        defer { importing -= 1 }
        let staged: FeedbackPickedMedia
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            staged = try FeedbackPickedMedia.stage(url)
        } catch {
            attachmentMessage = FeedbackAttachmentRejection.unreadable.errorDescription
            return
        }
        await admit(staged.url, displayName: url.lastPathComponent)
    }

    /// Accepts or refuses a staged copy: type check, location removal, compression to GitHub's limit,
    /// then the count limit.
    func admit(_ url: URL, displayName: String) async {
        guard let media = FeedbackAttachmentPolicy.media(forFilename: url.lastPathComponent) else {
            refuse(url, .unsupportedType(displayName))
            return
        }
        if attachments.count >= FeedbackLimits.attachments {
            refuse(url, .tooMany)
            return
        }
        do {
            try await FeedbackLocationScrubber.scrub(url, isVideo: media.isVideo)
        } catch {
            let unreadable = error as? FeedbackLocationScrubber.Failure == .unreadable
            refuse(url, unreadable ? .unreadable : .locationNotRemoved(displayName))
            return
        }
        let fitted: FeedbackMediaFitter.Fitted
        do {
            fitted = try await FeedbackMediaFitter.fit(url, isVideo: media.isVideo)
        } catch {
            let tooLarge = error as? FeedbackMediaFitter.Failure == .tooLarge
            refuse(url, tooLarge ? .fileTooLarge(displayName) : .unreadable)
            return
        }
        if let rejection = FeedbackAttachmentPolicy.rejection(byteCount: fitted.byteCount, filename: displayName, existing: attachments) {
            refuse(fitted.url, rejection)
            return
        }
        let type = fitted.compressed ? FeedbackAttachmentPolicy.media(forFilename: fitted.url.lastPathComponent) ?? media : media
        attachmentMessage = nil
        attachments.append(FeedbackAttachment(
            fileURL: fitted.url, filename: fitted.compressed ? fitted.url.lastPathComponent : displayName,
            mimeType: type.mimeType, byteCount: fitted.byteCount, isVideo: media.isVideo, wasCompressed: fitted.compressed
        ))
    }

    private func refuse(_ url: URL, _ rejection: FeedbackAttachmentRejection) {
        attachmentMessage = rejection.errorDescription
        Self.deleteCopy(url)
    }

    /// Deletes every staged media copy, whichever way a feedback sheet went away.
    static func purgeStagedMedia() {
        try? FileManager.default.removeItem(at: FeedbackPickedMedia.stagingFolder)
    }

    /// Each copy lives alone in a UUID folder inside the staging folder; delete the folder.
    private static func deleteCopy(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == FeedbackPickedMedia.stagingFolder.standardizedFileURL else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Submit

    /// Uploads the media through Home Assistant, then files the report; progress, success and failure land
    /// in ``phase``.
    ///
    /// - Parameters:
    ///   - platform: Platform label for the issue.
    ///   - diagnostics: Collects the diagnostics table when sending starts.
    func submit(platform: FeedbackPlatform, diagnostics: @escaping @MainActor () async -> FeedbackDiagnostics) {
        guard canSubmit else { return }
        let draft = draft
        let attachments = attachments
        let filer = services.filer
        phase = .sending(step: 1, total: attachments.count + 1)
        submitTask = Task { [weak self] in
            do {
                var media: [(attachment: FeedbackAttachment, url: URL)] = []
                for (index, attachment) in attachments.enumerated() {
                    self?.phase = .sending(step: index + 1, total: attachments.count + 1)
                    media.append((attachment, try await filer.upload(attachment)))
                }
                try Task.checkCancellation()
                self?.phase = .sending(step: attachments.count + 1, total: attachments.count + 1)
                let report = FeedbackReport(draft: draft, platform: platform, diagnostics: await diagnostics(), media: media)
                self?.phase = .finished(try await filer.submit(report))
            } catch is CancellationError {
                self?.phase = .editing
            } catch let error as FeedbackFilingError {
                if error == .notConfigured { self?.availability = .unavailable }
                self?.phase = .failed(error.errorDescription ?? "")
            } catch {
                self?.phase = .failed(FeedbackFilingError.network.errorDescription ?? "")
            }
        }
    }

    /// Stops sending and goes back to editing with everything kept.
    func cancelSubmit() {
        guard isSending else { return }
        submitTask?.cancel()
        submitTask = nil
        phase = .editing
    }

    /// Returns from an error to the editable form.
    func acknowledgeFailure() {
        if case .failed = phase { phase = .editing }
    }
}
