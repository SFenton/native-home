#if os(iOS)
import HassCore
import HassDesign
import PhotosUI
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

// MARK: - Form

/// Report an Issue / Request a Feature (``FeedbackFormSheet``): a scoped task in a sheet with Cancel (leading) and Submit
/// (trailing) rather than a Done button, because closing can lose typed input (HIG Sheets, Modality). A grouped form of text
/// boxes, the attached media and the send's progress, over ``FeedbackFormModel``.
final class UKFeedbackFormViewController: UKPageViewController, UKSheetFitting, PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
    QLPreviewControllerDataSource {
    private let kind: FeedbackKind
    private let model: FeedbackFormModel
    private let connection: HassConnection
    private let driver = UKSettingsListDriver(style: .sheet)
    weak var modal: UKHassModalController?

    private let cancelItem = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
    private let submitItem = UIBarButtonItem(title: "Submit", style: .done, target: nil, action: nil)
    private var previewURLs: [URL] = []
    private var presentedFinish = false
    private var presentedFailure = false

    var sheetFitScrollView: UIScrollView? { driver.collectionView }

    init(kind: FeedbackKind, model: FeedbackFormModel, connection: HassConnection) {
        self.kind = kind
        self.model = model
        self.connection = connection
        super.init(sheetTitle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Presents the form for `kind` as a content-fitted sheet (a form sheet on iPad), deleting staged media however it closes.
    /// Nothing happens without a signed-in session (a gallery).
    static func present(kind: FeedbackKind, context: UKContext, from presenter: UIViewController, model: FeedbackFormModel? = nil) {
        guard let session = context.session, let connection = context.connection else { return }
        let model = model ?? FeedbackFormModel(kind: kind, services: .resolve(ProcessInfo.processInfo.environment, server: connection.server, tokens: session.tokens))
        #if DEBUG
        // UI tests that are not about typing start with the draft filled in (`FENTON_FEEDBACK_PREFILL_TITLE` follows the title's
        // prefix, `_DESCRIPTION` fills the description): every action on a focused field waits out XCUITest's 60 s animations-idle
        // timeout in the live house. Debug builds only, and only in a form this call creates.
        let environment = ProcessInfo.processInfo.environment
        if let text = environment["FENTON_FEEDBACK_PREFILL_TITLE"] { model.title += text }
        if let text = environment["FENTON_FEEDBACK_PREFILL_DESCRIPTION"] { model.descriptionText = text }
        #endif
        let form = UKFeedbackFormViewController(kind: kind, model: model, connection: connection)
        var options = UKHassModalOptions(title: kind.formTitle)
        options.showsClose = false
        options.onDismissed = { FeedbackFormModel.purgeStagedMedia() }
        let modal = UKHassModalController(root: form, options: options)
        form.modal = modal
        modal.onAttemptToDismiss = { [weak form] in form?.requestClose() }
        modal.present(from: presenter)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: driver.collectionView)

        cancelItem.primaryAction = UIAction(title: "Cancel") { [weak self] _ in self?.requestClose() }
        cancelItem.accessibilityIdentifier = "feedback.close"
        submitItem.primaryAction = UIAction(title: "Submit") { [weak self] _ in self?.submit() }
        submitItem.style = .done
        submitItem.accessibilityIdentifier = "feedback.submit"
        navigationItem.leftBarButtonItem = cancelItem
        navigationItem.rightBarButtonItem = submitItem

        bag.observe { [weak self] in self?.modelChanged() }
        Task { await model.checkAvailability() }
    }

    // MARK: Model

    private func modelChanged() {
        driver.setSections(sections())
        submitItem.isEnabled = model.canSubmit
        // Why it is dimmed, where VoiceOver lands on it (the text under the form also changes in place).
        submitItem.accessibilityHint = model.blockingReason ?? ""
        modal?.isModalInPresentation = model.isSending || model.hasUnsavedInput
        if case let .finished(issue) = model.phase, !presentedFinish, isViewLoaded, view.window != nil {
            presentedFinish = true
            presentFinished(issue)
        }
        if case let .failed(message) = model.phase, !presentedFailure, isViewLoaded, view.window != nil {
            presentedFailure = true
            presentFailed(message)
        }
    }

    // MARK: Actions

    /// Cancel, Escape or a swipe: confirm first when something would be lost.
    func requestClose() {
        guard model.hasUnsavedInput || model.isSending else { close(); return }
        let dialog = UIAlertController(title: "Discard this \(kind.noun)?", message: "Your text and attached media will be lost.", preferredStyle: .actionSheet)
        dialog.addAction(UIAlertAction(title: "Discard Changes", style: .destructive) { [weak self] _ in self?.close() })
        dialog.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        // Anchored to Cancel so the popover-style dialog points at it.
        UKPopoverSource.barButton(cancelItem).attach(to: dialog.popoverPresentationController, fallback: view)
        present(dialog, animated: true)
    }

    private func close() {
        model.discardMedia()
        modal?.close()
    }

    private func submit() {
        view.endEditing(true)
        let collector = FeedbackDiagnosticsCollector(platform: platform, traits: .init(
            dynamicTypeSize: WeatherCarouselPaging.dynamicTypeSize(traitCollection.preferredContentSizeCategory),
            colorScheme: traitCollection.userInterfaceStyle == .dark ? .dark : .light,
            regularWidth: traitCollection.horizontalSizeClass == .regular, voiceOver: UIAccessibility.isVoiceOverRunning,
            reduceMotion: UIAccessibility.isReduceMotionEnabled))
        let connection = connection
        model.submit(platform: platform) { collector.collect(connection: connection) }
    }

    private var platform: FeedbackPlatform {
        FeedbackPlatform.resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad, hasHinge: HingePresence.shared.hasHinge)
    }

    private func presentFinished(_ issue: FiledIssue) {
        let alert = UIAlertController(title: kind == .bug ? "Report Sent" : "Request Sent", message: AlertCopy.feedbackFiled(number: issue.number), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "View on GitHub", style: .default) { [weak self] _ in
            UIApplication.shared.open(issue.url)
            self?.close()
        })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in self?.close() })
        present(alert, animated: true)
    }

    private func presentFailed(_ message: String) {
        let alert = UIAlertController(title: "Couldn't Send", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
            self?.presentedFailure = false
            self?.model.acknowledgeFailure()
        })
        present(alert, animated: true)
    }

    // MARK: Sections

    private var titleDetail: String {
        "Keep the \(kind.titlePrefix.trimmingCharacters(in: .whitespaces)) prefix and "
            + (kind == .bug ? "sum up the problem in a few words." : "name the idea in a few words.")
    }

    private var descriptionDetail: String {
        kind == .bug ? "What went wrong? Say which page you were on and what you saw." : "Describe the feature and how it would help."
    }

    private func sections() -> [UKSettingsListSection] {
        let sending = model.isSending
        var result: [UKSettingsListSection] = []
        if model.availability == .unavailable { result.append(setupSection()) }

        result.append(UKSettingsListSection(id: "title", header: fieldHeader("Title", detail: titleDetail), rows: [
            UKSettingsListRow(id: "title.field", signature: "title|\(sending)") { [model, titleDetail] cell in
                let field = UITextField()
                field.placeholder = "Title"
                field.text = model.title
                field.font = UKFont.preferred(.body)
                field.adjustsFontForContentSizeCategory = true
                field.textColor = UKDesignInk.primary
                field.autocapitalizationType = .sentences
                field.isEnabled = !sending
                field.accessibilityLabel = "Title"
                field.accessibilityHint = titleDetail
                field.accessibilityIdentifier = "feedback.field.title"
                field.addAction(UIAction { action in model.title = (action.sender as? UITextField)?.text ?? "" }, for: .editingChanged)
                cell.show(field, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
                cell.accessibilityElements = [field]
            },
        ]))
        result.append(textBox(id: "description", label: "Description", detail: descriptionDetail, field: .description, sending: sending))
        if kind.includesReproduction {
            result.append(textBox(id: "repro", label: "Steps to Reproduce", detail: "List the steps that make it happen, one per line.", field: .repro, sending: sending))
            result.append(textBox(id: "expected", label: "Expected Behavior", detail: "What did you expect to happen instead?", field: .expected, sending: sending))
        }
        result.append(mediaSection(sending: sending))
        if sending {
            result.append(progressSection())
        } else if let reason = model.blockingReason {
            result.append(UKSettingsListSection(id: "validation", rows: [
                UKSettingsListRow(id: "validation.text", signature: "validation|\(reason)") { cell in
                    let label = UILabel.uk(.footnote, ink: UKDesignInk.primary)
                    label.text = reason
                    cell.show(label, insets: NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16), minHeight: HassTokens.minTarget)
                    cell.makeElement(label: reason, traits: .staticText, identifier: "feedback.validation")
                },
            ]))
        }
        return result
    }

    /// A box's name with a visible line explaining what to write (``FeedbackFieldHeader``).
    private func fieldHeader(_ title: String, detail: String) -> UKSettingsListSection.Header {
        .view(label: "\(title), \(detail)", signature: "\(title)|\(detail)") {
            let titleLabel = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.primary)
            titleLabel.text = title
            let detailLabel = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
            detailLabel.text = detail
            let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
            stack.axis = .vertical
            stack.spacing = 2
            stack.alignment = .fill
            return stack
        }
    }

    private func setupSection() -> UKSettingsListSection {
        UKSettingsListSection(id: "setup", rows: [
            UKSettingsListRow(id: "setup.box", signature: "setup") { cell in
                cell.isTransparent = true
                let box = UKInfoBoxView(
                    title: "Reporting isn't set up yet",
                    message: "Reports are filed through Home Assistant. Whoever manages it can add the Fenton Home Feedback integration in Settings → Devices & services.",
                    tone: .neutral)
                box.accessibilityIdentifier = "feedback.setup"
                cell.show(box, insets: .zero)
            },
        ])
    }

    private func textBox(id: String, label: String, detail: String, field: FeedbackFormField, sending: Bool) -> UKSettingsListSection {
        UKSettingsListSection(id: id, header: fieldHeader(label, detail: detail), rows: [
            UKSettingsListRow(id: "\(id).box", signature: "box|\(sending)") { [model] cell in
                let box = UKFeedbackTextView()
                box.font = UKFont.preferred(.body)
                box.adjustsFontForContentSizeCategory = true
                box.textColor = UKDesignInk.primary
                box.backgroundColor = .clear
                box.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
                box.textContainer.lineFragmentPadding = 0
                box.isScrollEnabled = false
                box.isEditable = !sending
                box.text = Self.text(of: field, in: model)
                box.accessibilityLabel = label
                box.accessibilityHint = detail
                box.accessibilityIdentifier = field.identifier
                box.onChange = { Self.set(field, in: model, to: $0) }
                box.minimumHeight = 96
                cell.show(box, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: 96)
                cell.accessibilityElements = [box]
            },
        ])
    }

    private static func text(of field: FeedbackFormField, in model: FeedbackFormModel) -> String {
        switch field {
        case .title: model.title
        case .description: model.descriptionText
        case .repro: model.reproSteps
        case .expected: model.expectedBehavior
        }
    }

    private static func set(_ field: FeedbackFormField, in model: FeedbackFormModel, to text: String) {
        switch field {
        case .title: model.title = text
        case .description: model.descriptionText = text
        case .repro: model.reproSteps = text
        case .expected: model.expectedBehavior = text
        }
    }

    private func mediaSection(sending: Bool) -> UKSettingsListSection {
        var rows: [UKSettingsListRow] = []
        let attachments = model.attachments
        if !attachments.isEmpty {
            rows.append(UKSettingsListRow(id: "media.strip", signature: "strip|\(attachments.map { $0.id.uuidString }.joined(separator: ","))|\(sending)") { [weak self, model] cell in
                let strip = UKFeedbackAttachmentStrip(attachments: attachments, onOpen: { index in self?.preview(attachments, at: index) },
                                                      onRemove: { model.remove($0) })
                strip.isUserInteractionEnabled = !sending
                cell.show(strip, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
                cell.accessibilityElements = [strip]
            })
        }
        let canAttach = attachments.count < FeedbackLimits.attachments && !sending
        rows.append(UKSettingsListRow(id: "media.attach", signature: "attach|\(canAttach)") { [weak self] cell in
            var configuration = UIButton.Configuration.plain()
            configuration.title = "Attach Media"
            configuration.image = UIImage(systemName: "paperclip")
            configuration.imagePadding = HassTokens.Spacing.s
            configuration.contentInsets = .zero
            configuration.baseForegroundColor = canAttach ? UKDesignInk.action : UIColor.tertiaryLabel
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UKFont.preferred(.body)
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.showsMenuAsPrimaryAction = true
            button.isEnabled = canAttach
            button.accessibilityIdentifier = "feedback.attach"
            button.menu = UIMenu(children: [
                UIAction(title: "Photo Library", image: UIImage(systemName: "photo.on.rectangle")) { _ in self?.pickPhotos() },
                UIAction(title: "Choose File…", image: UIImage(systemName: "folder")) { _ in self?.pickFiles() },
            ])
            cell.show(button, insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
            cell.accessibilityElements = [button]
        })
        if model.importing > 0 {
            rows.append(UKSettingsListRow(id: "media.progress", signature: "progress") { cell in
                let progress = UKArcProgressView(title: "Adding media…", size: .compact, surface: .sheet)
                progress.accessibilityIdentifier = "feedback.attach.progress"
                cell.show(progress, insets: NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16), minHeight: HassTokens.minTarget)
                cell.accessibilityElements = [progress]
            })
        }
        if let message = model.attachmentMessage {
            rows.append(UKSettingsListRow(id: "media.notice", signature: "notice|\(message)") { cell in
                let label = UILabel.uk(.footnote, ink: UKDesignInk.danger)
                label.text = message
                cell.show(label, insets: NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16), minHeight: HassTokens.minTarget)
                cell.makeElement(label: message, traits: .staticText, identifier: "feedback.attachments.notice")
            })
        }
        return UKSettingsListSection(
            id: "media",
            header: fieldHeader("Media", detail: "Optional screenshots or screen recordings: up to \(FeedbackLimits.attachments) photos or videos. Large videos are compressed, and location is removed."),
            rows: rows)
    }

    /// Progress of the send, with Stop while media uploads (``FeedbackProgressSection``).
    private func progressSection() -> UKSettingsListSection {
        guard case let .sending(step, total) = model.phase else { return UKSettingsListSection(id: "progress", rows: []) }
        let text = step < total ? "Uploading media \(step) of \(total - 1)…" : "Filing your \(kind.noun) on GitHub…"
        let fraction = total > 0 ? Double(step - 1) / Double(total) : 0
        var rows = [
            UKSettingsListRow(id: "progress.bar", signature: "bar|\(text)|\(fraction)") { cell in
                let label = UILabel.uk(.body, ink: UKDesignInk.primary)
                label.text = text
                let bar = UIProgressView(progressViewStyle: .default)
                bar.progress = Float(fraction)
                let stack = UIStackView(arrangedSubviews: [label, bar])
                stack.axis = .vertical
                stack.spacing = HassTokens.Spacing.s
                cell.show(stack, insets: NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16), minHeight: HassTokens.minTarget)
                cell.makeElement(label: text, value: "\(Int((fraction * 100).rounded())) percent", traits: .updatesFrequently, identifier: "feedback.progress")
            },
        ]
        // Stopping is offered only while media uploads: once the issue request is out, it may be filed.
        if step < total {
            rows.append(UKSettingsRows.button(id: "progress.stop", identifier: "feedback.stop", title: "Stop Sending", ink: UKDesignInk.danger) { [model] in
                model.cancelSubmit()
            })
        }
        return UKSettingsListSection(id: "progress", rows: rows)
    }

    // MARK: Attaching

    private func pickPhotos() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = max(1, FeedbackLimits.attachments - model.attachments.count)
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let providers = results.map { ProviderBox(provider: $0.itemProvider) }
        let loaders: [@MainActor () async throws -> FeedbackPickedMedia?] = providers.map { box in { try await FeedbackPickedMedia.load(box.provider) } }
        Task { await model.importPicked(loaders) }
    }

    private func pickFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie])
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Task { await model.importFiles(.success(urls)) }
    }

    // MARK: Quick Look

    /// Opens an attachment in the system viewer (HIG File management, Quick Look: use its viewer for attachments your app cannot open).
    private func preview(_ attachments: [FeedbackAttachment], at index: Int) {
        previewURLs = attachments.map(\.fileURL)
        let controller = QLPreviewController()
        controller.dataSource = self
        controller.currentPreviewItemIndex = index
        present(controller, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURLs.count }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { previewURLs[index] as NSURL }
}

/// Carries a picker result's item provider (which the picker hands over for exactly this use) into the import task.
struct ProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

/// A multi-line text box (`TextEditor`) that reports its text and holds a minimum height.
final class UKFeedbackTextView: UITextView, UITextViewDelegate {
    var onChange: ((String) -> Void)?
    var minimumHeight: CGFloat = 0

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func textViewDidChange(_ textView: UITextView) {
        onChange?(textView.text)
        // The cell grows with the text: ask the list to measure it again.
        invalidateIntrinsicContentSize()
        if let list = superview(of: UICollectionView.self) {
            UIView.performWithoutAnimation {
                list.collectionViewLayout.invalidateLayout()
                list.layoutIfNeeded()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        let fitted = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 320, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(minimumHeight, ceil(fitted.height)))
    }
}

private extension UIView {
    func superview<T: UIView>(of type: T.Type) -> T? {
        var view = superview
        while let current = view {
            if let match = current as? T { return match }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Attachments

/// Attached media shown above Attach Media (``FeedbackAttachmentStrip``): a thumbnail per file that opens in the system viewer, with
/// a remove button. The app never plays or views media itself.
final class UKFeedbackAttachmentStrip: UIScrollView {
    init(attachments: [FeedbackAttachment], onOpen: @escaping (Int) -> Void, onRemove: @escaping (FeedbackAttachment) -> Void) {
        super.init(frame: .zero)
        showsHorizontalScrollIndicator = false
        accessibilityIdentifier = "feedback.attachments"
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = HassTokens.Spacing.m
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, attachment) in attachments.enumerated() {
            stack.addArrangedSubview(UKFeedbackAttachmentTile(attachment: attachment, position: index + 1,
                                                              onOpen: { onOpen(index) }, onRemove: { onRemove(attachment) }))
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.xs),
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            heightAnchor.constraint(equalTo: contentLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }
}

/// One thumbnail button plus its remove button, each at least 44 pt (``FeedbackAttachmentTile``).
final class UKFeedbackAttachmentTile: UIView {
    private let attachment: FeedbackAttachment
    private let thumbnail = UIImageView()
    private let placeholder = UIImageView()
    private var task: Task<Void, Never>?

    init(attachment: FeedbackAttachment, position: Int, onOpen: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.attachment = attachment
        super.init(frame: .zero)
        let side = FeedbackAttachmentMetrics.side
        let reach = FeedbackAttachmentMetrics.removeReach
        let inset = FeedbackAttachmentMetrics.thumbnailInset

        let open = UIButton(type: .custom)
        open.layer.cornerRadius = FeedbackAttachmentMetrics.cornerRadius
        open.layer.cornerCurve = .continuous
        open.clipsToBounds = true
        open.layer.borderWidth = 1 / UIScreen.main.scale
        open.layer.borderColor = UIColor.separator.cgColor
        open.backgroundColor = .quaternarySystemFill
        open.addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
        open.accessibilityLabel = attachment.accessibilityLabel(position: position)
        open.accessibilityHint = "Opens in Quick Look"
        open.accessibilityIdentifier = "feedback.attachment.\(position)"
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.isUserInteractionEnabled = false
        thumbnail.frame = CGRect(x: 0, y: 0, width: side, height: side)
        placeholder.image = UIImage(systemName: attachment.isVideo ? "film" : "photo", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title2)))
        placeholder.tintColor = UKDesignInk.secondary
        placeholder.contentMode = .center
        placeholder.frame = thumbnail.frame
        open.addSubview(placeholder)
        open.addSubview(thumbnail)
        if attachment.isVideo {
            let badge = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.footnote, bold: true))))
            badge.tintColor = .white
            badge.contentMode = .center
            badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            badge.layer.cornerRadius = 12
            badge.frame = CGRect(x: 10, y: side - 34, width: 24, height: 24)
            badge.isUserInteractionEnabled = false
            open.addSubview(badge)
        }
        open.frame = CGRect(x: 0, y: 2 + inset, width: side, height: side)
        addSubview(open)

        let remove = UIButton(type: .custom)
        var removeImage = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title3)))
        removeImage = removeImage?.applyingSymbolConfiguration(UIImage.SymbolConfiguration(paletteColors: [.white, UIColor.black.withAlphaComponent(0.7)]))
        remove.setImage(removeImage, for: .normal)
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.accessibilityLabel = "Remove \(attachment.filename)"
        remove.accessibilityIdentifier = "feedback.attachment.\(position).remove"
        // Centred on the thumbnail's top trailing corner, a 44 pt target.
        remove.frame = CGRect(x: side - HassTokens.minTarget / 2, y: 2 + inset - HassTokens.minTarget / 2, width: HassTokens.minTarget, height: HassTokens.minTarget)
        addSubview(remove)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side + inset + reach),
            heightAnchor.constraint(equalToConstant: side + 2 + inset),
        ])
        loadThumbnail()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { task?.cancel() }

    private func loadThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL, size: CGSize(width: FeedbackAttachmentMetrics.side, height: FeedbackAttachmentMetrics.side),
            scale: UIScreen.main.scale, representationTypes: .thumbnail)
        task = Task { [weak self] in
            let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
            guard !Task.isCancelled, let image else { return }
            self?.thumbnail.image = image
            self?.placeholder.isHidden = true
        }
    }
}
#endif
