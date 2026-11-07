#if os(iOS)
import HassCore
import HassDesign
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Form rows

/// The placeholder ink of the todo fields: opaque (a translucent grey measured 2.9:1 on the sheet's cell), 4.5:1 or better in both
/// appearances.
enum UKTodoPlaceholder {
    static let ink = UIColor.ukDynamic(light: UIColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1), dark: UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1))
}

/// A single-line text field row of a todo form: body type, 44 pt tall at least, the field's own accessibility identifier.
@MainActor
final class UKTodoTextField: UITextField {
    private let placeholderLabel = UILabel.uk(.body, ink: UKTodoPlaceholder.ink, lines: 1)

    init(placeholder: String, identifier: String) {
        super.init(frame: .zero)
        font = .ukFont(.body)
        adjustsFontForContentSizeCategory = true
        textColor = UKDesignInk.primary
        accessibilityIdentifier = identifier
        accessibilityLabel = placeholder
        // The system placeholder is drawn lighter than any ink set for it and measured 2.9:1: a label stands in for it.
        placeholderLabel.text = placeholder
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addAction(UIAction { [weak self] _ in self?.updatePlaceholder() }, for: .editingChanged)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var text: String? {
        didSet { updatePlaceholder() }
    }

    /// The view to use as the form row: the field with its placeholder label laid over it as a sibling, so the accessibility audit
    /// sees an empty field and not the label's pixels as the field's text.
    lazy var rowView: UIView = {
        let container = UIView()
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        container.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor), bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor), trailingAnchor.constraint(equalTo: container.trailingAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()

    private func updatePlaceholder() { placeholderLabel.isHidden = !(text ?? "").isEmpty }
}

/// A growing text field row (`TextField(axis: .vertical).lineLimit(a...b)`): one line tall at first, growing with the text to
/// `maxLines`, then scrolling. The placeholder shows while it is empty.
@MainActor
final class UKTodoTextView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let placeholderLabel = UILabel.uk(.body, ink: UKTodoPlaceholder.ink)
    private let minLines: Int
    private let maxLines: Int
    /// Runs after every edit, with the new text.
    var onChange: ((String) -> Void)?
    /// Runs when the row's height changed, so the list can measure the cell again.
    var onHeightChange: (() -> Void)?
    private var lastHeight: CGFloat = 0
    /// A grouped `Form` row's padding above and below its text (a one-line row is 52 pt, a three-line one about 94 pt).
    private static let verticalInset: CGFloat = 15.5

    init(placeholder: String, identifier: String, lines: ClosedRange<Int>) {
        minLines = lines.lowerBound
        maxLines = lines.upperBound
        super.init(frame: .zero)
        textView.font = .ukFont(.body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UKDesignInk.primary
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: Self.verticalInset, left: 0, bottom: Self.verticalInset, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.accessibilityIdentifier = identifier
        textView.accessibilityLabel = placeholder
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = placeholder
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor), textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor), textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor), placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKTodoTextView, _) in view.invalidateIntrinsicContentSize() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        let line = textView.font?.lineHeight ?? 20
        let minimum = max(52, ceil(line * CGFloat(minLines)) + 2 * Self.verticalInset)
        let maximum = ceil(line * CGFloat(maxLines)) + 2 * Self.verticalInset
        let width = bounds.width > 0 ? bounds.width : 300
        let fitted = ceil(textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        return CGSize(width: UIView.noIntrinsicMetric, height: min(max(fitted, minimum), maximum))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = intrinsicContentSize.height
        textView.isScrollEnabled = textView.contentSize.height > height + 1
        if abs(height - lastHeight) > 0.5 {
            lastHeight = height
            invalidateIntrinsicContentSize()
            onHeightChange?()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        invalidateIntrinsicContentSize()
        onChange?(textView.text)
        onHeightChange?()
    }
}

/// A pop-up picker row (`Picker` in a `Form`): the title leading, the chosen option trailing with the pop-up chevrons, the whole row
/// opening the menu. One button to VoiceOver: label = title, value = the chosen option. The canonical row (form metrics) with a menu
/// button as its tap target.
@MainActor
final class UKTodoPickerRow: UKRowView {
    private let button = UIButton(type: .system)
    private let chevrons = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down",
                                                      withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small)))

    init(title: String, identifier: String) {
        super.init(.init(title, value: " ", style: .form))
        chevrons.tintColor = UKDesignInk.secondary
        chevrons.setContentHuggingPriority(.required, for: .horizontal)
        setAccessory(chevrons)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        installTapTarget(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the chosen option and the menu of all of them.
    func update(options: [DonetickTaskForm.Option], selected: String, choose: @escaping (String) -> Void) {
        let chosen = options.first { $0.value == selected }
        var content = rowContent
        content.value = chosen?.label ?? ""
        update(content, accessory: accessory)
        button.menu = UIMenu(children: options.map { option in
            UIAction(title: option.label, state: option.value == selected ? .on : .off) { _ in choose(option.value) }
        })
        button.accessibilityValue = chosen?.label
    }
}

/// A row with a leading label and a trailing control (`LabeledContent`, `DatePicker`): the canonical row (form metrics) with the
/// control as its accessory. Build a new one each time a row is needed; a row owns its control.
@MainActor
final class UKTodoLabeledRow: UKRowView {
    init(title: String, trailing: UIView) {
        super.init(.init(title, style: .form))
        trailing.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setAccessory(trailing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A full-row text button (a destructive Delete, a Choose Images row): the label in `ink`, an optional leading glyph. A ``UKRowButton``
/// around the canonical row.
@MainActor
final class UKTodoButtonRow: UKRowButton {
    /// The control itself, for a popover source.
    var button: UIControl { self }

    init(title: String, symbol: String? = nil, ink: UIColor, identifier: String, action: @escaping () -> Void) {
        var content = UKRowContent(title, symbol: symbol, glyph: ink, style: .form)
        content.titleInk = ink
        super.init(UKRowView(content), onTap: action)
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Base

/// What the todo forms share (`HassModal` + `SheetCancelItem` + `SheetConfirmItem` + `discardGuard` + ``TodoSheetErrorSection``):
/// an inset grouped form on the sheet ground, a circle-x Cancel leading, a filled check trailing, an error line on top, the draft
/// kept in the page's ``TodoDraftStore`` and the edits reported up so a pane form can be replaced only after "Discard changes?".
///
/// A subclass sets ``title``, builds ``sections()`` and says ``hasEdits`` and ``canConfirm``; it calls ``reload(animated:)`` when its
/// state changes. A form shows as a sheet (`UKHassModalController`) or in the trailing pane of a split todo page: the presenter sets
/// ``closeForm`` and ``onEditsChange``, and the form only calls ``close()``.
@MainActor
class UKTodoFormController: UKPageViewController, UKSheetFitting, UKColumnPopGuarding {
    let model: ChoresModel
    let form = UKFormViewController()
    /// This form's entry in the page's drafts (empty outside a todo page).
    var drafts = TodoDraftHandle()
    /// Closes the form: the pane's close in a split, else the sheet's.
    var closeForm: (() -> Void)?
    /// The form's `hasEdits`, reported whenever it changes.
    var onEditsChange: ((Bool) -> Void)?

    private var confirm: UKSheetConfirmItem?
    private(set) var isBusy = false
    private var lastEdits: Bool?
    private var lastAnnounced: String?
    var error: String? {
        didSet {
            guard error != oldValue else { return }
            if let error, error != lastAnnounced { Announcer.announce(error) }
            lastAnnounced = error
            reload()
        }
    }

    // MARK: Subclass surface

    /// The subtitle under the title (iOS 26): "Groceries", "Admin To-Do".
    var formSubtitle: String? { nil }
    var cancelIdentifier: String { "sheet.cancel" }
    var confirmTitle: String { "Save" }
    var busyTitle: String { "Saving" }
    var confirmIdentifier: String { "sheet.confirm" }
    /// Cancel and a swipe down ask before dropping this form.
    var guardsEdits: Bool { true }
    var hasEdits: Bool { false }
    var canConfirm: Bool { false }
    /// The form's sections below the error line.
    func sections() -> [UKFormSection] { [] }
    func confirmTapped() {}
    func formDidLoad() {}
    /// The view pinned in the page: the form's own, or a wrapper that contains it (the task form's content gate).
    func formHostView() -> UIView { form.view }

    init(model: ChoresModel) {
        self.model = model
        super.init(sheetTitle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var sheetFitScrollView: UIScrollView? { form.collectionView }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(form)
        let host = formHostView()
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: contentView.topAnchor), host.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), host.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        form.didMove(toParent: self)
        // The form's list is this page's scroller (the form is a page of its own, so the rules are already on it).
        setPageScrollView(form.collectionView)
        UKSheetSubtitle.apply(formSubtitle, to: navigationItem)
        confirm = UKSheetConfirmItem(confirmTitle, isEnabled: canConfirm, busyTitle: busyTitle, identifier: confirmIdentifier) { [weak self] in
            self?.confirmTapped()
        }
        navigationItem.rightBarButtonItem = confirm?.barButtonItem
        formDidLoad()
        reload(animated: false)
    }

    /// Closes the form (the pane's close, or the sheet's).
    func close() {
        if let closeForm { closeForm() } else if let modal = navigationController as? UKHassModalController { modal.close() } else { dismiss(animated: true) }
    }

    /// Marks a save in flight: the form dims, Cancel and the check are off, the swipe down is blocked.
    func setBusy(_ busy: Bool) {
        guard busy != isBusy else { return }
        isBusy = busy
        form.view.isUserInteractionEnabled = !busy
        form.view.alpha = busy ? CGFloat(HassTokens.ControlState.disabledOpacity) : 1
        updateChrome()
    }

    /// Rebuilds the sections (diffed by row id) and the bar items.
    func reload(animated: Bool = true) {
        guard isViewLoaded else { return }
        var all: [UKFormSection] = []
        if let error {
            // A failed save appears under the keyboard's focus: say it, since nothing moves VoiceOver there.
            all.append(UKFormSection(id: "error", headerStyle: .system, rows: [
                UKFormRow(id: "error-\(error)", identifier: "todoSheet.error", .custom {
                    let alert = UKInlineAlertView(error, severity: .error)
                    alert.accessibilityIdentifier = "todoSheet.error"
                    return alert
                }),
            ]))
        }
        all += sections()
        form.setSections(all, animated: animated && view.window != nil)
        updateChrome()
    }

    /// The leading bar item: Cancel, or a guarded Back on a page pushed into another sheet.
    func makeLeadingItem() -> UIBarButtonItem {
        UKSheetItems.cancel(identifier: cancelIdentifier, isEnabled: !isBusy, hasChanges: guardsEdits && hasEdits, presenter: self) { [weak self] in
            self?.close()
        }
    }

    /// Close and Back of the column the form sits in: wait for a save, ask before dropping edits (a sheet does the same through Cancel).
    var columnPopDecision: UKColumnPopDecision {
        if isBusy { return .block }
        return guardsEdits && hasEdits ? .confirmDiscard : .allow
    }

    private var columns: UKColumnsViewController? { parent as? UKColumnsViewController }

    func updateChrome() {
        guard isViewLoaded else { return }
        // In a column the section bar's Close is the cancel, with the same confirmation: no Cancel item beside it.
        navigationItem.leftBarButtonItem = columns == nil ? makeLeadingItem() : nil
        columns?.pageStateChanged()
        confirm?.update(isEnabled: canConfirm, isBusy: isBusy)
        UKDiscardGuard.apply(to: self, hasChanges: guardsEdits && hasEdits, isBusy: isBusy)
        let edits = hasEdits
        if edits != lastEdits {
            lastEdits = edits
            onEditsChange?(edits)
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        updateChrome()
    }

    /// Lets the list measure its cells again after a row grew (a text view with a second line).
    func remeasureRows() {
        UIView.performWithoutAnimation { form.collectionView?.performBatchUpdates(nil) }
    }
}

// MARK: - Add grocery item

/// Adds an item to the grocery list with `todo.add_item` (``AddGroceryItemSheet``).
@MainActor
final class UKAddGroceryItemController: UKTodoFormController, UITextFieldDelegate {
    private let entityId: String
    private let field = UKTodoTextField(placeholder: "Item", identifier: "grocery.item")
    private var item = ""

    private var trimmed: String { item.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(model: ChoresModel, entityId: String) {
        self.entityId = entityId
        super.init(model: model)
        title = "Add Grocery Item"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var formSubtitle: String? { "Groceries" }
    override var cancelIdentifier: String { "sheet.cancel" }
    override var confirmTitle: String { "Add" }
    override var busyTitle: String { "Adding" }
    override var confirmIdentifier: String { "grocery.add" }
    override var guardsEdits: Bool { false }
    override var hasEdits: Bool { !trimmed.isEmpty }
    override var canConfirm: Bool { !trimmed.isEmpty && !isBusy }

    override func formDidLoad() {
        if case let .text(saved)? = drafts.draft { item = saved }
        field.text = item
        field.returnKeyType = .done
        field.delegate = self
        field.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.item = self.field.text ?? ""
            self.drafts.save(.text(self.item))
            self.updateChrome()
        }, for: .editingChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        Task { await add() }
        return false
    }

    override func sections() -> [UKFormSection] {
        [UKFormSection(id: "item", header: "Item", footer: "Added to the Groceries list.", headerStyle: .system, footerIdentifier: "grocery.footer", rows: [
            // A label that stays visible once typing hides the placeholder (HIG Text fields; owner, 2026-10-16).
            UKFormRow(id: "field", identifier: "grocery.item", .custom { [field] in field.rowView }),
        ])]
    }

    override func confirmTapped() { Task { await add() } }

    private func add() async {
        guard !trimmed.isEmpty, !isBusy else { return }
        setBusy(true)
        error = nil
        defer { setBusy(false) }
        do {
            try await model.service.callService("todo", "add_item", data: ["entity_id": entityId, "item": trimmed])
            close()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to add grocery item")
        }
    }
}

// MARK: - Add admin to-do

/// Adds an admin to-do, with up to four images (``AddAdminTodoSheet``). Without images it is a plain `todo.add_item`; with images it
/// posts to the dashboard integration, which files them on the GitHub issue.
@MainActor
final class UKAddAdminTodoController: UKTodoFormController, PHPickerViewControllerDelegate {
    private let entityId: String
    private let taskView = UKTodoTextView(placeholder: "Task", identifier: "adminTodo.task", lines: 1...4)
    private var task = ""
    private var images: [UploadImage] = []

    /// An image read from the picker.
    struct UploadImage: Identifiable {
        let id = UUID()
        var upload: AdminTodoUpload.Image
    }

    private var trimmed: String { task.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(model: ChoresModel, entityId: String) {
        self.entityId = entityId
        super.init(model: model)
        title = "Add Task"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var formSubtitle: String? { "Admin To-Do" }
    override var confirmTitle: String { "Add" }
    override var busyTitle: String { "Adding" }
    override var confirmIdentifier: String { "adminTodo.add" }
    /// Typed text or chosen images that closing would drop.
    override var hasEdits: Bool { !task.isEmpty || !images.isEmpty }
    override var canConfirm: Bool { !trimmed.isEmpty && !isBusy }

    override func formDidLoad() {
        if case let .admin(saved, uploads)? = drafts.draft {
            task = saved
            images = uploads.map { UploadImage(upload: $0) }
        }
        taskView.text = task
        taskView.onChange = { [weak self] value in
            guard let self else { return }
            var value = value
            if value.count > 1000 {
                value = String(value.prefix(1000))
                self.taskView.text = value
            }
            self.task = value
            self.saveDraft()
            self.updateChrome()
        }
        taskView.onHeightChange = { [weak self] in self?.remeasureRows() }
    }

    private func saveDraft() { drafts.save(.admin(task: task, images: images.map(\.upload))) }

    override func sections() -> [UKFormSection] {
        var imageRows: [UKFormRow] = images.map { image in
            UKFormRow(id: "image-\(image.id)", .custom { [weak self] in
                UKAdminTodoImageRowView(image: image.upload) { self?.removeImage(image.id) }
            })
        }
        // The id follows the title: a custom row is only redrawn when its id changes, so "Add Images" became "Choose Different Images" never.
        imageRows.append(UKFormRow(id: images.isEmpty ? "pick" : "pick-change", identifier: "adminTodo.images", .custom { [weak self] in
            // The app accent measured 3.3:1 on the modal background (iPad audit, 2026-10-13).
            UKTodoButtonRow(title: (self?.images.isEmpty ?? true) ? "Add Images" : "Choose Different Images", symbol: "photo.on.rectangle.angled",
                            ink: UKDesignInk.action, identifier: "adminTodo.images") { self?.pickImages() }
        }))
        return [
            UKFormSection(id: "task", header: "Task",
                          footer: "This issue is synchronized from the dashboard Admin To-Do list. The repository is public.", headerStyle: .system, rows: [
                UKFormRow(id: "task-field", identifier: "adminTodo.task", .custom { [taskView] in taskView }),
            ]),
            UKFormSection(id: "images", header: "Images", footer: "Add up to four PNG, JPEG, or WebP images, 10 MB each.", headerStyle: .system, rows: imageRows),
        ]
    }

    private func removeImage(_ id: UUID) {
        images.removeAll { $0.id == id }
        saveDraft()
        reload()
    }

    private func pickImages() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = AdminTodoUpload.maxImages
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let providers = results.map(\.itemProvider)
        Task { await readImages(providers) }
    }

    /// Reads the picked items into the form (internal so a test can hand it item providers; ``PHPickerResult`` cannot be built).
    func readImages(_ providers: [NSItemProvider]) async {
        var read: [AdminTodoUpload.Image] = []
        for (index, provider) in providers.enumerated() {
            let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
            let type = types.first { AdminTodoUpload.mimeTypes.contains($0.preferredMIMEType ?? "") } ?? types.first
            guard let identifier = type?.identifier, let data = try? await Self.loadData(provider, identifier) else { continue }
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let ext = type?.preferredFilenameExtension ?? "img"
            read.append(AdminTodoUpload.Image(data: data, filename: "image-\(index + 1).\(ext)", mimeType: mime))
        }
        if let problem = AdminTodoUpload.validationError(count: read.count, sizes: read.map(\.data.count), mimeTypes: read.map(\.mimeType)) {
            images = []
            error = problem
        } else {
            images = read.map { UploadImage(upload: $0) }
            error = nil
        }
        saveDraft()
        reload()
    }

    private static func loadData(_ provider: NSItemProvider, _ identifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    override func confirmTapped() { Task { await add() } }

    private func add() async {
        guard !trimmed.isEmpty, !isBusy else { return }
        setBusy(true)
        error = nil
        defer { setBusy(false) }
        do {
            if images.isEmpty {
                try await model.service.callService("todo", "add_item", data: ["entity_id": entityId, "item": trimmed])
            } else {
                let upload = AdminTodoUpload(entityId: entityId, item: trimmed, images: images.map(\.upload))
                try await model.service.uploadAdminTodo(upload, accessToken: try await model.accessToken())
            }
            close()
        } catch {
            self.error = "Unable to add this task. Try again."
        }
    }
}

/// A picked image: thumbnail, name and a remove button (``AdminTodoImageRow``).
@MainActor
final class UKAdminTodoImageRowView: UIView {
    init(image: AdminTodoUpload.Image, onRemove: @escaping () -> Void) {
        super.init(frame: .zero)
        let thumbnail = UIImageView(image: UIImage(data: image.data) ?? UIImage(systemName: "photo"))
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.layer.cornerRadius = 8
        thumbnail.layer.cornerCurve = .continuous
        thumbnail.isAccessibilityElement = false
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        let name = UILabel.uk(.body, ink: UKDesignInk.primary)
        name.text = image.filename
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3)), for: .normal)
        remove.tintColor = UKDesignInk.danger
        remove.accessibilityLabel = "Remove \(image.filename)"
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [thumbnail, name, UIView(), remove])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            thumbnail.widthAnchor.constraint(equalToConstant: 44), thumbnail.heightAnchor.constraint(equalToConstant: 44),
            remove.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            remove.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Rename admin to-do

/// Renames an admin to-do with `todo.update_item` `rename` (``RenameTodoItemSheet``).
@MainActor
final class UKRenameTodoItemController: UKTodoFormController {
    private let target: AdminTodoEditTarget
    private let onSaved: () -> Void
    /// A single-line field: XCUITest finds the SwiftUI page's name field among the text fields, and a text view is not one.
    private let nameField = UKTodoTextField(placeholder: "Task Name", identifier: "renameTodo.name")
    private var draft: String

    init(model: ChoresModel, target: AdminTodoEditTarget, onSaved: @escaping () -> Void = {}) {
        self.target = target
        self.onSaved = onSaved
        draft = target.originalTitle
        super.init(model: model)
        title = "Edit Task"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var formSubtitle: String? { "Admin To-Do" }
    override var confirmIdentifier: String { "renameTodo.save" }
    /// The name differs from the one the sheet opened with.
    override var hasEdits: Bool { draft != target.originalTitle }
    override var canConfirm: Bool { RenameTodoItemSheet.canSave(target: target, draft: draft) && !isBusy }

    override func formDidLoad() {
        if case let .text(saved)? = drafts.draft { draft = saved }
        nameField.text = draft
        nameField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.draft = self.nameField.text ?? ""
            self.drafts.save(.text(self.draft))
            self.reload()
        }, for: .editingChanged)
    }

    override func sections() -> [UKFormSection] {
        var sections: [UKFormSection] = []
        if target.itemUid == nil {
            sections.append(UKFormSection(id: "identity", headerStyle: .system, rows: [
                UKFormRow(id: "identity-error", .custom {
                    UKInlineAlertView("This task cannot be edited because its Home Assistant identity is unavailable.", severity: .error)
                }),
            ]))
        }
        sections.append(UKFormSection(id: "name", footer: "This issue is synchronized from the dashboard Admin To-Do list. The repository is public.",
                                      headerStyle: .system, rows: [UKFormRow(id: "name-field", identifier: "renameTodo.name", .custom { [nameField] in nameField.rowView })]))
        // Reset is a list row in the action tint, shown only when there is something to reset: a disabled row fails the contrast audit.
        if draft != target.originalTitle || error != nil {
            sections.append(UKFormSection(id: "reset", headerStyle: .system, rows: [
                UKFormRow(id: "reset", identifier: "renameTodo.reset", .button(title: "Reset to Original") { [weak self] in
                    guard let self else { return }
                    self.draft = self.target.originalTitle
                    self.nameField.text = self.draft
                    self.drafts.save(.text(self.draft))
                    self.error = nil
                    self.reload()
                }),
            ]))
        }
        return sections
    }

    override func confirmTapped() { Task { await save() } }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = target.itemUid, RenameTodoItemSheet.canSave(target: target, draft: draft), !isBusy else { return }
        setBusy(true)
        error = nil
        defer { setBusy(false) }
        do {
            try await model.service.callService("todo", "update_item", data: ["entity_id": target.todoEntityId, "item": uid, "rename": trimmed])
            onSaved()
            close()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to update task.")
        }
    }
}
#endif
