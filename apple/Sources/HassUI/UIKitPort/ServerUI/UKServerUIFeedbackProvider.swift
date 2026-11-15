#if os(iOS)
import HassCore
import HassDesign
import Observation
import PhotosUI
import QuickLook
import UIKit

// MARK: - Authenticated feedback draft

/// Authenticated services and privacy-safe diagnostics are injected by the session owner.
/// The renderer never receives tokens, server URLs, or an unrestricted connection.
@MainActor @Observable
final class UKServerUIFeedbackProvider: NSObject, UKServerUISettingsProvider,
    PHPickerViewControllerDelegate, UIDocumentPickerDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    let definition: ServerUISettingsSource
    let model: FeedbackFormModel
    private let current: () -> Bool
    private let platform: FeedbackPlatform
    private let diagnostics: @MainActor (UITraitCollection) async -> FeedbackDiagnostics
    private var checking = false
    private var pickerOpen = false
    private var previews: [URL] = []
    private weak var presentingPage: UKServerUIPage?
    private var resultShown = false
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { blocksExit || pickerOpen }
    var blocksExit: Bool {
        if case .finished = model.phase { return false }
        return model.hasUnsavedInput || model.isSending || model.hasRunningImports
    }
    var canDiscard: Bool { !model.isSending && !pickerOpen }

    init(id: String, model: FeedbackFormModel, platform: FeedbackPlatform,
         isCurrentSession: @escaping () -> Bool, diagnostics: @escaping @MainActor (UITraitCollection) async -> FeedbackDiagnostics) {
        definition = .init(providerId: id, domain: .feedback)
        self.model = model
        self.platform = platform
        current = isCurrentSession
        self.diagnostics = diagnostics
    }

    func discard() {
        guard canDiscard else { return }
        model.resetDraft()
        resultShown = false
    }

    func didExit() {
        if case .finished = model.phase { discard() }
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        guard control.kind.domain == .feedback else { return false }
        if control.kind == .feedbackField {
            return ["title", "description"].contains(control.item)
                || (model.draft.kind == .bug && ["repro", "expected"].contains(control.item))
        }
        return true
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        guard accepts(control) else { throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources") }
        if !checking { checking = true; Task { [model] in await model.checkAvailability() } }
        switch control.kind {
        case .feedbackField: return field(control, host: host, page: page)
        case .feedbackMedia: return media(control, host: host, page: page)
        case .feedbackStatus:
            let label = UILabel.uk(.footnote, ink: UKDesignInk.primary)
            label.numberOfLines = 0
            host.bag.observe { [weak self, weak label, weak host, weak page] in
                guard let self else { return }
                switch self.model.phase {
                case .editing: label?.text = self.model.attachmentMessage ?? self.model.blockingReason
                case .sending(let step, let total):
                    label?.text = step < total ? "Uploading media \(step) of \(total - 1)" : "Filing your \(self.model.draft.kind.noun)"
                case .finished(let issue):
                    label?.text = AlertCopy.feedbackFiled(number: issue.number)
                case .failed(let message): label?.text = message
                }
                if let page { self.showResult(from: page) }
                page?.renderer?.updateSettingsExitGuard()
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return label
        default:
            let button = UKPrimaryButton(control.node.title) { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    if control.kind == .feedbackStop { self.model.cancelSubmit() }
                    else {
                        self.resultShown = false
                        let traits = page.traitCollection
                        self.model.submit(platform: self.platform) { await self.diagnostics(traits) }
                    }
                }
            }
            host.bag.observe { [weak self, weak button, weak page] in
                guard let self, let button else { return }
                if control.kind == .feedbackStop {
                    if case .sending(let step, let total) = self.model.phase { button.isHidden = step >= total }
                    else { button.isHidden = true }
                } else {
                    button.isEnabled = self.isCurrentSession && self.model.canSubmit
                    button.isBusy = self.model.isSending
                    button.accessibilityHint = self.model.blockingReason
                }
                page?.renderer?.updateSettingsExitGuard()
            }
            return button
        }
    }

    private func text(_ item: String) -> String {
        switch item {
        case "title": model.title
        case "description": model.descriptionText
        case "repro": model.reproSteps
        default: model.expectedBehavior
        }
    }

    private func set(_ text: String, item: String) throws {
        try requireCurrent()
        guard !model.isSending else { throw HouseholdSettingsTarget.Failure.stale }
        switch item {
        case "title": model.title = text
        case "description": model.descriptionText = text
        case "repro": model.reproSteps = text
        case "expected": model.expectedBehavior = text
        default: throw HouseholdSettingsTarget.Failure.invalidTarget
        }
    }

    private func field(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) -> UIView {
        let field = UKFeedbackTextView()
        field.text = text(control.item)
        field.font = UKFont.preferred(.body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UKDesignInk.primary
        field.backgroundColor = .clear
        field.isScrollEnabled = false
        field.minimumHeight = control.item == "title" ? 44 : 96
        field.accessibilityLabel = control.node.title
        field.accessibilityHint = control.subtitle
        field.onChange = { [weak self, weak host, weak page] value in
            guard let self, let host, let page else { return }
            host.perform(from: page) { try self.set(value, item: control.item) }
            host.ukRemeasureContainers(includingSelf: true)
            page.renderer?.updateSettingsExitGuard()
        }
        host.bag.observe { [weak self, weak field] in
            guard let self, let field else { return }
            field.isEditable = self.isCurrentSession && !self.model.isSending
            if !field.isFirstResponder, field.text != self.text(control.item) { field.text = self.text(control.item) }
        }
        return field
    }

    private func media(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) -> UIView {
        let stack = UIStackView.ukColumn(spacing: HassTokens.Spacing.m)
        let strip = UIStackView.ukColumn(spacing: 0)
        let button = UIButton(configuration: .plain())
        button.configuration?.title = control.node.title
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIAction(title: "Photo Library", image: UIImage(systemName: "photo.on.rectangle")) { [weak self, weak host, weak page] _ in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    var config = PHPickerConfiguration()
                    config.selectionLimit = max(1, FeedbackLimits.attachments - self.model.attachments.count)
                    config.filter = .any(of: [.images, .videos])
                    config.preferredAssetRepresentationMode = .current
                    let picker = PHPickerViewController(configuration: config)
                    picker.delegate = self
                    self.pickerOpen = true
                    self.presentingPage = page
                    page.present(picker, animated: true)
                }
            },
            UIAction(title: "Choose File", image: UIImage(systemName: "folder")) { [weak self, weak host, weak page] _ in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie])
                    picker.allowsMultipleSelection = true
                    picker.delegate = self
                    self.pickerOpen = true
                    page.present(picker, animated: true)
                }
            },
        ])
        stack.addArrangedSubview(strip)
        stack.addArrangedSubview(button)
        var ids: [UUID] = []
        host.bag.observe { [weak self, weak strip, weak button, weak host, weak page] in
            guard let self, let strip else { return }
            let attachments = self.model.attachments
            button?.isEnabled = self.isCurrentSession && !self.model.isSending && attachments.count < FeedbackLimits.attachments
            strip.isUserInteractionEnabled = !self.model.isSending
            if ids != attachments.map(\.id) {
                ids = attachments.map(\.id)
                strip.arrangedSubviews.forEach { $0.removeFromSuperview() }
                if !attachments.isEmpty {
                    strip.addArrangedSubview(UKFeedbackAttachmentStrip(attachments: attachments, onOpen: { [weak self, weak page] index in
                        guard let self, let page, self.isCurrentSession else { return }
                        self.previews = attachments.map(\.fileURL)
                        let preview = QLPreviewController()
                        preview.dataSource = self
                        preview.delegate = self
                        self.pickerOpen = true
                        preview.currentPreviewItemIndex = index
                        page.present(preview, animated: true)
                    }, onRemove: { [weak self] item in
                        guard let self, self.isCurrentSession, !self.model.isSending else { return }
                        self.model.remove(item)
                    }))
                }
            }
            host?.ukRemeasureContainers(includingSelf: true)
        }
        return stack
    }

    private func showResult(from page: UKServerUIPage) {
        guard !resultShown, page.viewIfLoaded?.window != nil, page.presentedViewController == nil else { return }
        let alert: UIAlertController
        switch model.phase {
        case .finished(let issue):
            alert = UIAlertController(title: model.draft.kind == .bug ? "Report Sent" : "Request Sent",
                                      message: AlertCopy.feedbackFiled(number: issue.number), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "View on GitHub", style: .default) { _ in UIApplication.shared.open(issue.url) })
            alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self, weak page] _ in
                self?.discard()
                if let page { page.renderer?.activate(.dismiss(scope: .currentModal), from: page) }
            })
        case .failed(let message):
            alert = UIAlertController(title: "Couldn't Send", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.model.acknowledgeFailure(); self?.resultShown = false
            })
        default: return
        }
        resultShown = true
        page.present(alert, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        pickerOpen = false
        picker.dismiss(animated: true)
        guard isCurrentSession else { return }
        let boxes = results.map { ProviderBox(provider: $0.itemProvider) }
        model.startImportPicked(boxes.map { box in { try await FeedbackPickedMedia.load(box.provider) } })
    }

    nonisolated func previewControllerDidDismiss(_ controller: QLPreviewController) {
        Task { @MainActor [weak self] in
            self?.pickerOpen = false
            self?.previews = []
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pickerOpen = false
        guard isCurrentSession else { return }
        model.startImportFiles(.success(urls))
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { pickerOpen = false }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previews.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { previews[index] as NSURL }
}
#endif
