#if os(iOS)
import AVFoundation
import HassCore
import HassDesign
import UIKit

/// Add Item (``ScanItemSheet``; web `ScanItemCameraSheet`; direction G mockups n6-scan-item and n6-scan-review): scan or type the
/// product, read or pick the expiration date, review, then add through `evershelf.add_scanned_item`. `onAdded` runs once after a
/// successful add.
///
/// A multi-step create sheet (direction G, Sheets): circle x Cancel on the first step, a Back circle on later steps, and on the review
/// step the filled check adds the item. The step's subtitle ("Scan Barcode · Step 1 of 3") sits under the title on iOS 26 and heads the
/// form before. The camera is AVFoundation behind ``ScanCameraController``: a live back camera, the simulated viewfinder
/// (`FENTON_SCAN_CAMERA=simulated`), or none.
@MainActor
enum UKScanItemSheet {
    static func present(model: ScanItemModel, from presenter: UIViewController, context: UKContext, camera: ScanCameraController = ScanCameraController(),
                        onAdded: @escaping () -> Void, onDismissed: @escaping () -> Void) {
        let page = UKScanItemViewController(model: model, camera: camera, context: context.with { $0.surface = .sheet }, onAdded: onAdded)
        var options = UKHassModalOptions(title: "Add Item")
        options.showsClose = false
        options.width = .form
        // Live camera scanner.
        options.height = .full
        options.onDismissed = onDismissed
        UKHassModalController(root: page, options: options).present(from: presenter)
    }
}

final class UKScanItemViewController: UKFormViewController {
    private let model: ScanItemModel
    private let camera: ScanCameraController
    private let onAdded: () -> Void
    private var reportedAdd = false
    private var cameraTask: Task<Void, Never>?
    private var cameraKey = ""
    private var lastLookup: ScanItemModel.LookupStatus = .idle
    private var lastExpiry: ScanItemModel.ExpiryStatus = .idle
    private var confirmItem: UKSheetConfirmItem?
    private var confirmTitle = ""

    // Rows made once and kept (a form reload would replace a control in use).
    private let barcodeFinder: UKScanViewfinder
    private let expiryFinder: UKScanViewfinder
    private let nameRow = UKFormFieldRow(title: "Name", placeholder: "Product Name", identifier: "scan.name", accessibilityLabel: "Product name")
    private let quantityRow = UKScanQuantityRow()
    private let hasExpiryRow = UKFormSwitchRow(title: "Expiration Date", identifier: "scan.hasExpiry")
    private let expiryDateRow = UKFormDateRow(title: "Expires", identifier: "scan.expiry", accessibilityLabel: "Expiration date")
    private let preparedRow = UKFormSwitchRow(title: "Prepared Food", identifier: "scan.prepared", actionOnly: true)
    private let scanAgain = UKFormActionRow(title: "Scan Barcode", ink: UKDesignInk.action, identifier: "scan.scanAgain")
    private let readAgain = UKFormActionRow(title: "Read Expiration Date", ink: UKDesignInk.action, identifier: "scan.readAgain")
    private let productHeader = UKScanProductHeaderView()
    private let footer = UKScanFooterView()
    private let footerHost = UIView()
    private var footerBar: UKPagePinnedBar!

    init(model: ScanItemModel, camera: ScanCameraController, context: UKContext, onAdded: @escaping () -> Void) {
        self.model = model
        self.camera = camera
        self.onAdded = onAdded
        barcodeFinder = UKScanViewfinder(symbol: "barcode.viewfinder", label: "Live item scan camera feed", step: .barcode)
        expiryFinder = UKScanViewfinder(symbol: "camera", label: "Live expiration date camera feed", step: .expiry)
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        // The step's buttons are the page's pinned bar: the form scrolls under it (soft bottom edge) and clears it, never clipping at it.
        footerHost.translatesAutoresizingMaskIntoConstraints = false
        footerBar = UKPagePinnedBar(bar: footerHost, scrollView: collectionView, barMaterial: true)
        footerBar.install(in: self)
        pinFooter()
        wireRows()
        bag.observe { [weak self] in self?.render() }
        bag.observe { [weak self] in self?.syncCamera() }
        #if DEBUG
        // FENTON_SCAN_AUTOSIMULATE=1 reads the simulated barcode a moment after the sheet opens (screenshots, crash repros).
        if ProcessInfo.processInfo.environment["FENTON_SCAN_AUTOSIMULATE"] == "1" {
            Task { [model, camera] in
                try? await Task.sleep(for: .seconds(2))
                await camera.simulate(on: model)
            }
        }
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true || view.window == nil { camera.stop() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        footerBar?.layoutChanged()
    }

    deinit { MainActor.assumeIsolated { camera.stop() } }

    /// The step's buttons in the bar under the form (they join the form's last row at accessibility sizes and come back after).
    private func pinFooter() {
        guard footer.superview !== footerHost else { return }
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerHost.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: footerHost.topAnchor, constant: HassTokens.Spacing.s),
            footer.bottomAnchor.constraint(equalTo: footerHost.bottomAnchor, constant: -HassTokens.Spacing.s),
            footer.leadingAnchor.constraint(equalTo: footerHost.leadingAnchor, constant: HassTokens.Spacing.l),
            footer.trailingAnchor.constraint(equalTo: footerHost.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
    }

    /// The rows' callbacks into the model.
    private func wireRows() {
        nameRow.onChange = { [model] text in model.setName(text) }
        quantityRow.onChange = { [model] text in model.setQuantityText(text) }
        quantityRow.onStep = { [model] value in model.setQuantityText(String(Int(value))) }
        quantityRow.onSubmit = { [model] in _ = model.validateQuantity() }
        hasExpiryRow.onToggle = { [model] on in
            model.setExpiryDate(on ? model.calendar.isoString(model.calendar.today) : "")
        }
        expiryDateRow.onChange = { [model] date in model.setExpiryDate(model.calendar.isoString(date)) }
        preparedRow.onToggle = { [model] _ in model.togglePreparedFood() }
        scanAgain.addAction(UIAction { [model] _ in model.scanBarcodeAgain() }, for: .touchUpInside)
        readAgain.addAction(UIAction { [model] _ in model.readExpiryAgain() }, for: .touchUpInside)
        barcodeFinder.onManual = { [model] in model.enterNameManually() }
        expiryFinder.onManual = { [model] in model.enterExpiryManually() }
        for finder in [barcodeFinder, expiryFinder] {
            finder.onSimulate = { [model, camera] in Task { await camera.simulate(on: model) } }
        }
        footer.onForward = { [model] in
            switch model.step {
            case .barcode: model.goToExpiryStep()
            case .expiry: model.goToReviewStep()
            default: break
            }
        }
        footer.onReadExpiry = { [model, camera] in Task { await camera.captureExpiry(for: model) } }
    }

    // MARK: Camera

    /// `.task(id: CameraKey(step:, wanted:))`: starts the camera the step wants, or stops it.
    private func syncCamera() {
        let key = "\(model.step.rawValue)|\(model.wantedCamera?.rawValue ?? "-")"
        guard key != cameraKey else { return }
        cameraKey = key
        cameraTask?.cancel()
        cameraTask = Task { [model, camera] in await camera.sync(with: model) }
    }

    // MARK: Render

    private var isAccessibilityLayout: Bool { traitCollection.ukIsAccessibilitySize }

    private func render() {
        let step = model.step
        collectionView?.accessibilityIdentifier = "scan.\(step.rawValue)"
        showHaptics()
        if model.addStatus == .added, !reportedAdd {
            reportedAdd = true
            onAdded()
        }

        // Row state.
        nameRow.show(model.name)
        quantityRow.show(text: model.quantityText)
        hasExpiryRow.show(isOn: !model.expiryDate.isEmpty)
        expiryDateRow.show(date: model.calendar.date(fromISO: model.expiryDate) ?? model.calendar.today,
                           note: model.hasSuccessfulExpiryRead ? "Read from the package" : nil)
        preparedRow.show(isOn: model.preparedFood)
        scanAgain.show(title: model.scanBarcodeTitle)
        readAgain.show(title: model.readExpiryTitle, isEnabled: camera.source != .unavailable)
        productHeader.show(name: model.name, barcode: model.detectedBarcode)
        barcodeFinder.update(model: model, camera: camera)
        expiryFinder.update(model: model, camera: camera)

        // The step's buttons: pinned below the form, or (accessibility sizes) at the end of it.
        let showsFooter = !model.isProcessing && (step == .barcode || step == .expiry)
        footer.update(model: model, camera: camera, step: step)
        let pinned = showsFooter && !isAccessibilityLayout
        if !isAccessibilityLayout { pinFooter() }
        footerHost.isHidden = !pinned
        view.setNeedsLayout()

        setSections(sections(showsFooterInForm: showsFooter && isAccessibilityLayout), animated: false)
        updateBar()
    }

    private func showHaptics() {
        // A read lands without a sound or a look at the screen, so it is felt (owner, 2026-10-24).
        if model.lookupStatus != lastLookup {
            lastLookup = model.lookupStatus
            switch lastLookup {
            case .found: UKTapFeedback.confirmation()
            case .failed: UKTapFeedback.failure()
            default: break
            }
        }
        if model.expiryStatus != lastExpiry {
            lastExpiry = model.expiryStatus
            switch lastExpiry {
            case .found: UKTapFeedback.confirmation()
            case .failed: UKTapFeedback.failure()
            default: break
            }
        }
    }

    // MARK: Sections

    private func sections(showsFooterInForm: Bool) -> [UKFormSection] {
        var sections: [UKFormSection] = [headerSection()].compactMap { $0 }
        if model.isProcessing {
            sections.append(UKFormSection(id: "processing", rows: [UKFormRow(id: "processing", .clear { Self.processingView() })]))
        } else {
            switch model.step {
            case .barcode: sections.append(contentsOf: barcodeSections())
            case .expiry: sections.append(contentsOf: expirySections())
            case .review: sections.append(contentsOf: reviewSections())
            case .adding: sections.append(addingSection())
            }
        }
        // At accessibility sizes the step's buttons scroll with the form: pinned, they took about 40% of the iPhone screen.
        if showsFooterInForm {
            sections.append(UKFormSection(id: "footer", rows: [UKFormRow(id: "footer", .clear { [footer] in footer })]))
        }
        return sections
    }

    /// The step's instructions, led by its subtitle where the system can't draw one under the title.
    private func headerSection() -> UKFormSection? {
        let subtitle = SheetSubtitle.isShown ? nil : model.subtitle
        let instructions = (!model.instructions.isEmpty && !model.isProcessing) ? model.instructions : nil
        let key = "\(subtitle ?? "")|\(instructions ?? "")"
        guard subtitle != nil || instructions != nil else { return nil }
        return UKFormSection(id: "header", rows: [UKFormRow(id: "header-\(key)", .clear {
            let column = UIStackView()
            column.axis = .vertical
            column.spacing = HassTokens.Spacing.xs
            if let subtitle {
                let label = UILabel.uk(.subheadline, weight: .semibold, ink: UKDesignInk.secondary)
                label.text = subtitle
                label.accessibilityIdentifier = "scan.subtitle"
                column.addArrangedSubview(label)
            }
            if let instructions {
                let label = UILabel.uk(.body, ink: UKDesignInk.secondary)
                label.text = instructions
                column.addArrangedSubview(label)
            }
            let inset = UKRecipeInset(column, horizontal: HassTokens.Spacing.l, vertical: HassTokens.Spacing.s)
            inset.isAccessibilityElement = true
            inset.accessibilityLabel = [subtitle, instructions].compactMap { $0 }.joined(separator: ", ")
            return inset
        })])
    }

    private static func processingView() -> UIView {
        let arc = UKArcSpinnerView(.compact, label: "Processing")
        arc.isAccessibilityElement = false
        let label = UILabel.uk(.headline, ink: UKDesignInk.primary)
        label.text = "Processing…"
        let row = UIStackView(arrangedSubviews: [arc, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        let holder = UKWrapHost()
        holder.labels = [label]
        holder.reserved = 2 * HassTokens.Spacing.l + 40
        row.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: holder.centerXAnchor), row.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            holder.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        holder.isAccessibilityElement = true
        holder.accessibilityLabel = "Processing…"
        holder.accessibilityIdentifier = "scan.processing"
        return holder
    }

    private func statusSection() -> UKFormSection? {
        guard let message = model.statusMessage else { return nil }
        let isError = model.statusIsError
        return UKFormSection(id: "status", rows: [UKFormRow(id: "status-\(message)-\(isError)", .clear {
            let alert = UKInlineAlertView(message, severity: isError ? .error : .warning)
            alert.accessibilityIdentifier = "scan.status"
            return UKRecipeInset(alert, horizontal: HassTokens.Spacing.l, vertical: HassTokens.Spacing.xs)
        })])
    }

    private func cameraSection(finder: UKScanViewfinder, manualTitle: String, manualID: String, manual: @escaping () -> Void) -> UKFormSection {
        let button = UKScanManualButton(title: manualTitle, identifier: manualID, action: manual)
        return UKFormSection(id: "camera", rows: [
            UKFormRow(id: "viewfinder-\(finder.step.rawValue)", .clear { [finder] in
                let column = UIStackView(arrangedSubviews: [finder.row, button])
                column.axis = .vertical
                column.spacing = 0
                return column
            }),
        ])
    }

    private func barcodeSections() -> [UKFormSection] {
        if !model.barcodeCameraHidden {
            return [cameraSection(finder: barcodeFinder, manualTitle: "Manually Enter Name", manualID: "scan.manualName") { [model] in model.enterNameManually() }]
        }
        return [statusSection()].compactMap { $0 } + [
            UKFormSection(id: "name", header: "What item are you adding?", headerStyle: .system, rows: [
                UKFormRow(id: "name", .custom { [nameRow] in nameRow }),
                UKFormRow(id: "scanAgain", .custom { [scanAgain] in scanAgain }),
            ]),
        ]
    }

    private func expirySections() -> [UKFormSection] {
        if !model.expiryCameraHidden {
            return [cameraSection(finder: expiryFinder, manualTitle: "Manually Enter Expiration Date", manualID: "scan.manualExpiry") { [model] in model.enterExpiryManually() }]
        }
        var result = [statusSection()].compactMap { $0 }
        result.append(UKFormSection(id: "when", header: "When does it expire?", headerStyle: .system, rows: expiryFieldRows()))
        result.append(UKFormSection(id: "quick", header: "Quick Expiration Dates", headerStyle: .system, rows: ScanItemModel.QuickExpiry.allCases.map { quick in
            UKFormRow(id: "quick-\(quick.rawValue)", identifier: "scan.quick.\(quick.rawValue)",
                      .option(title: quick.title, subtitle: nil, swatch: [], isSelected: model.selectedQuickExpiry == quick) { [model] in model.selectQuickExpiry(quick) })
        }))
        result.append(UKFormSection(id: "readAgain", rows: [UKFormRow(id: "readAgain", .custom { [readAgain] in readAgain })]))
        return result
    }

    /// Optional date: a toggle plus a picker, as the web's empty-able date input. "Read from the package" under Expires once the camera read it.
    private func expiryFieldRows() -> [UKFormRow] {
        var rows = [UKFormRow(id: "hasExpiry", .custom { [hasExpiryRow] in hasExpiryRow })]
        if !model.expiryDate.isEmpty { rows.append(UKFormRow(id: "expiryDate", .custom { [expiryDateRow] in expiryDateRow })) }
        return rows
    }

    /// Review (mockup n6-scan-review): the product, its details in one group, then where it goes.
    private func reviewSections() -> [UKFormSection] {
        var sections = [UKFormSection(id: "product", rows: [UKFormRow(id: "product", .custom { [productHeader] in productHeader })])]
        var details: [UKFormRow] = [
            UKFormRow(id: "name", .custom { [nameRow] in nameRow }),
            UKFormRow(id: "quantity", .custom { [quantityRow] in quantityRow }),
        ]
        details.append(contentsOf: expiryFieldRows())
        details.append(UKFormRow(id: "prepared", .custom { [preparedRow] in preparedRow }))
        let note = InventoryEditorModel.preparedFoodNote
        sections.append(UKFormSection(id: "details", header: "What item are you adding?", footer: model.quantityError.map { "\($0)\n\(note)" } ?? note,
                                      headerStyle: .system, rows: details))
        sections.append(UKFormSection(id: "where", header: "Where should it be stored?", footer: model.locationHint, headerStyle: .system,
                                      rows: StorageLocation.allCases.map { location in
                                          UKFormRow(id: "location-\(location.rawValue)", identifier: "scan.location.\(location.rawValue)",
                                                    .option(title: location.title, subtitle: nil, swatch: [], isSelected: model.location == location) { [model] in model.selectLocation(location) })
                                      }))
        if let error = model.addError {
            sections.append(UKFormSection(id: "addError", rows: [UKFormRow(id: "addError-\(error)", .custom {
                let alert = UKInlineAlertView(error, severity: .error)
                alert.accessibilityIdentifier = "scan.addError"
                return alert
            })]))
        }
        return sections
    }

    private func addingSection() -> UKFormSection {
        let added = model.addStatus == .added
        let location = model.location.title
        return UKFormSection(id: "adding", rows: [UKFormRow(id: "adding-\(added)", .clear {
            let column = UIStackView()
            column.axis = .vertical
            column.alignment = .center
            column.spacing = HassTokens.Spacing.m
            let text = UILabel.uk(.headline, ink: UKDesignInk.primary, alignment: .center)
            if added {
                let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)))
                check.tintColor = UKDesignInk.success
                check.isAccessibilityElement = false
                column.addArrangedSubview(check)
                text.text = "Added to \(location)"
            } else {
                let arc = UKArcSpinnerView(.compact, label: "Adding")
                arc.isAccessibilityElement = false
                column.addArrangedSubview(arc)
                text.text = "Adding to \(location)…"
            }
            column.addArrangedSubview(text)
            let holder = UKWrapHost()
            holder.labels = [text]
            holder.reserved = 2 * HassTokens.Spacing.l
            column.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(column)
            NSLayoutConstraint.activate([
                column.centerXAnchor.constraint(equalTo: holder.centerXAnchor), column.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                column.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor),
                holder.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            ])
            holder.isAccessibilityElement = true
            holder.accessibilityLabel = text.text
            holder.accessibilityIdentifier = "scan.result"
            return holder
        })])
    }

    // MARK: Bar

    /// Cancel on the first step, Back on the later ones (direction G, Sheets: "Multi-step flows put Back leading on later steps"), Add as
    /// the filled check on review, and Close once the item is added.
    private func updateBar() {
        UKSheetSubtitle.apply(model.subtitle, to: navigationItem)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil
        switch model.step {
        case .barcode:
            navigationItem.leftBarButtonItem = UKSheetItems.cancel(identifier: "scan.cancel", hasChanges: model.hasDraft, presenter: self) { [weak self] in self?.close() }
        case .expiry, .review:
            let back = UIBarButtonItem(image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { [model] _ in model.goBack() })
            back.title = "Back"
            back.accessibilityLabel = model.step == .expiry ? "Back to Barcode Scan" : "Back to Expiration Date"
            back.accessibilityIdentifier = "scan.back"
            navigationItem.leftBarButtonItem = back
        case .adding:
            break
        }
        if model.step == .review {
            let title = "Add to \(model.location.title)"
            if confirmItem == nil || confirmTitle != title {
                confirmTitle = title
                confirmItem = UKSheetConfirmItem(title, isEnabled: model.canAdd, identifier: "scan.add") { [model] in Task { await model.add() } }
            }
            confirmItem?.update(isEnabled: model.canAdd)
            navigationItem.rightBarButtonItem = confirmItem?.barButtonItem
        }
        if model.step == .adding, model.addStatus == .added {
            navigationItem.rightBarButtonItem = UKSheetItems.close(identifier: "scan.done") { [weak self] in self?.close() }
        }
        // A swipe down on the review step would drop the typed name, date and quantity (`sheet-discard-guard`).
        UKDiscardGuard.apply(to: self, hasChanges: model.hasDraft, isBusy: model.addStatus == .adding)
    }

    private func close() {
        if let modal = navigationController as? UKHassModalController { modal.close() } else { dismiss(animated: true) }
    }
}

// MARK: - Pieces

/// "How Many": the typed quantity (validated on Add, as on the web) with a stepper beside it.
final class UKScanQuantityRow: UKRowView {
    var onChange: (String) -> Void = { _ in }
    var onStep: (Double) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    private let field = UITextField()
    private let stepper = UIStepper()

    init() {
        super.init(UKRowContent("How Many", style: .form))
        field.placeholder = "Quantity"
        field.font = .ukFont(.body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UKDesignInk.primary
        field.textAlignment = .right
        field.keyboardType = .decimalPad
        field.ukAddKeyboardDone()
        field.accessibilityIdentifier = "scan.quantity"
        field.accessibilityLabel = "Quantity"
        field.addAction(UIAction { [weak self] _ in self?.onChange(self?.field.text ?? "") }, for: .editingChanged)
        field.addAction(UIAction { [weak self] _ in self?.onSubmit() }, for: .editingDidEnd)
        field.widthAnchor.constraint(lessThanOrEqualToConstant: 80).isActive = true
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        stepper.minimumValue = 1
        stepper.maximumValue = InventoryCatalog.maxQuantity
        stepper.stepValue = 1
        stepper.accessibilityLabel = "How Many"
        stepper.accessibilityIdentifier = "scan.quantity.stepper"
        stepper.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onStep(self.stepper.value)
        }, for: .valueChanged)
        stepper.setContentHuggingPriority(.required, for: .horizontal)
        let controls = UIStackView(arrangedSubviews: [field, stepper])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = HassTokens.Spacing.m
        setAccessory(controls)
        isTextAccessible = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the model's text unless the person is typing it; the stepper shows its whole number within its range (1 when it isn't one).
    func show(text: String) {
        if field.text != text, !field.isFirstResponder { field.text = text }
        let value = Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        let shown = value.map { Int(min(max($0, 1), InventoryCatalog.maxQuantity)) } ?? 1
        if stepper.value != Double(shown) { stepper.value = Double(shown) }
    }
}

/// "Manually Enter Name" under the camera, in the action tint (mockup n6-scan-item).
final class UKScanManualButton: UIButton {
    init(title: String, identifier: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: "keyboard")
        configuration.imagePadding = HassTokens.Spacing.s
        configuration.baseForegroundColor = UKDesignInk.action
        self.configuration = configuration
        accessibilityIdentifier = identifier
        accessibilityLabel = title
        addAction(UIAction { _ in action() }, for: .touchUpInside)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The product at the top of Add Item's review step (``ScanProductHeader``; mockup n6-scan-review): a glyph tile, the name and the
/// scanned barcode.
final class UKScanProductHeaderView: UIView {
    private let tile = UIImageView()
    private let nameLabel = UILabel.uk(.headline, ink: UKDesignInk.primary)
    private let barcodeLabel = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
    private var tileSize: NSLayoutConstraint!
    private var tileHeight: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        tile.contentMode = .center
        tile.tintColor = UKDesignInk.secondary
        tile.backgroundColor = .tertiarySystemFill
        tile.layer.cornerRadius = HassTokens.Radius.chip
        tile.layer.cornerCurve = .continuous
        tile.clipsToBounds = true
        tile.isAccessibilityElement = false
        tile.translatesAutoresizingMaskIntoConstraints = false
        tileSize = tile.widthAnchor.constraint(equalToConstant: 56)
        tileHeight = tile.heightAnchor.constraint(equalToConstant: 56)
        tile.setContentHuggingPriority(.required, for: .horizontal)
        let texts = UIStackView(arrangedSubviews: [nameLabel, barcodeLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [tile, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            tileSize, tileHeight,
            row.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.xs), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.xs),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "scan.product"
        rescale()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKScanProductHeaderView, _) in self.rescale() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rescale() {
        let side = UIFontMetrics(forTextStyle: .headline).scaledValue(for: 56, compatibleWith: traitCollection)
        tileSize.constant = side
        tileHeight.constant = side
        tile.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
    }

    func show(name: String, barcode: String?) {
        tile.image = UIImage(systemName: barcode == nil ? "square.and.pencil" : "barcode")
        let title = name.isEmpty ? "New Item" : name
        nameLabel.text = title
        barcodeLabel.text = barcode.map { "Barcode \($0)" }
        barcodeLabel.isHidden = barcode == nil
        accessibilityLabel = [title, barcode.map { "Barcode \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}

/// What the Add Item camera is doing, on a dark capsule over the feed with an inline arc (``CameraStatusPill``; mockup n6-scan-item:
/// "Looking for a Barcode"). Content over the camera, not navigation, so a material rather than glass.
final class UKCameraStatusPill: UIView {
    private let label = UILabel()
    private let arc = UKArcSpinnerView(.compact, label: "")
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        overrideUserInterfaceStyle = .dark
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        label.font = UKFont.rowTitle()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 0
        arc.color = .white
        arc.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [arc, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.s
        row.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor), blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor), blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: HassTokens.Spacing.s),
            row.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -HassTokens.Spacing.s),
            row.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: HassTokens.Spacing.m + 2),
            row.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -(HassTokens.Spacing.m + 2)),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .updatesFrequently
        accessibilityIdentifier = "scan.cameraActivity"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String) {
        label.text = text
        accessibilityLabel = text
    }

    /// The most the pill may take: the feed's width, which the card fixes. The title wraps within it (never at the pill's own width).
    func setMaxWidth(_ width: CGFloat) {
        UKWrapWidth.set(label, to: width - 2 * (HassTokens.Spacing.m + 2) - 24 - HassTokens.Spacing.s)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.layer.cornerRadius = bounds.height / 2
    }
}

/// The camera card (26 pt corners, on the sheet ground) with its status pill: the live feed, the simulated viewfinder, or the camera's
/// status.
final class UKScanViewfinder: UIView {
    var onManual: () -> Void = {}
    var onSimulate: () -> Void = {}
    let step: ScanItemModel.Step
    /// The row the form holds: the card, capped at 400 pt and centred.
    let row = UIView()

    private let symbol: String
    private let feedLabel: String
    private let preview = CameraPreview.PreviewView()
    private let simulated = UIStackView()
    private let simulatedIcon = UIImageView()
    private let simulateButton = UIButton(type: .system)
    private let statusStack = UIStackView()
    private let statusIcon = UIImageView()
    private let statusArc = UKArcSpinnerView(.page, label: "Starting camera")
    private let statusText = UILabel()
    private let settings = UIButton(type: .system)
    private let pill = UKCameraStatusPill()

    init(symbol: String, label: String, step: ScanItemModel.Step) {
        self.symbol = symbol
        feedLabel = label
        self.step = step
        super.init(frame: .zero)
        backgroundColor = .black
        layer.cornerRadius = HassTokens.Radius.module
        layer.cornerCurve = .continuous
        clipsToBounds = true
        accessibilityIdentifier = "scan.camera"

        preview.previewLayer.videoGravity = .resizeAspectFill
        preview.isHidden = true
        preview.isAccessibilityElement = true
        preview.accessibilityLabel = label
        addSubview(preview)

        simulatedIcon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 56))
        simulatedIcon.tintColor = UIColor.white.withAlphaComponent(0.8)
        simulatedIcon.isAccessibilityElement = false
        var prominent = UIButton.Configuration.borderedProminent()
        prominent.title = step == .barcode ? "Simulate Scan" : "Simulate Photo"
        prominent.baseBackgroundColor = UKDesignInk.actionFill
        simulateButton.configuration = prominent
        simulateButton.accessibilityIdentifier = "scan.simulate"
        simulateButton.addAction(UIAction { [weak self] _ in self?.onSimulate() }, for: .touchUpInside)
        simulated.axis = .vertical
        simulated.alignment = .center
        simulated.spacing = HassTokens.Spacing.m
        simulated.addArrangedSubview(simulatedIcon)
        simulated.addArrangedSubview(simulateButton)
        simulated.isHidden = true
        simulated.accessibilityContainerType = .semanticGroup
        simulated.accessibilityLabel = label
        addSubview(simulated)

        statusIcon.image = UIImage(systemName: "exclamationmark.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 42))
        statusIcon.tintColor = .white
        statusIcon.isAccessibilityElement = false
        statusArc.color = .white
        statusArc.isAccessibilityElement = false
        statusText.font = .ukFont(.body)
        statusText.adjustsFontForContentSizeCategory = true
        statusText.textColor = .white
        statusText.numberOfLines = 0
        statusText.textAlignment = .center
        var bordered = UIButton.Configuration.bordered()
        bordered.title = "Open Settings"
        bordered.baseForegroundColor = .white
        settings.configuration = bordered
        settings.accessibilityIdentifier = "scan.openSettings"
        settings.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        settings.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        let status = UIStackView(arrangedSubviews: [statusIcon, statusArc, statusText])
        status.axis = .vertical
        status.alignment = .center
        status.spacing = HassTokens.Spacing.s
        status.isAccessibilityElement = true
        status.accessibilityIdentifier = "scan.cameraStatus"
        statusStack.axis = .vertical
        statusStack.alignment = .center
        statusStack.spacing = HassTokens.Spacing.s
        statusStack.addArrangedSubview(status)
        statusStack.addArrangedSubview(settings)
        statusStack.isHidden = true
        self.statusSummary = status
        addSubview(statusStack)
        addSubview(pill)
        pill.isHidden = true

        // The card's row: portrait like the mockup's 4:5, capped on wide sheets, where a full-width feed pushed the manual-entry button
        // under the pinned footer.
        translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(self)
        let fill = widthAnchor.constraint(equalTo: row.widthAnchor)
        fill.priority = UILayoutPriority(750)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: row.topAnchor), bottomAnchor.constraint(equalTo: row.bottomAnchor),
            centerXAnchor.constraint(equalTo: row.centerXAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 400), fill,
            leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor), trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: 5.0 / 4.0),
        ])
    }

    private var statusSummary: UIStackView?

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
        let fit = CGSize(width: bounds.width - 2 * HassTokens.Spacing.l, height: bounds.height)
        UKWrapWidth.set(statusText, to: fit.width)
        pill.setMaxWidth(bounds.width - 2 * HassTokens.Spacing.m)
        for stack in [simulated, statusStack] {
            let size = stack.systemLayoutSizeFitting(CGSize(width: fit.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            stack.frame = CGRect(x: (bounds.width - min(size.width, fit.width)) / 2, y: (bounds.height - size.height) / 2, width: min(size.width, fit.width), height: size.height)
        }
        let pillSize = pill.systemLayoutSizeFitting(CGSize(width: bounds.width - 2 * HassTokens.Spacing.m, height: 0), withHorizontalFittingPriority: .fittingSizeLevel,
                                                    verticalFittingPriority: .fittingSizeLevel)
        pill.frame = CGRect(x: (bounds.width - pillSize.width) / 2, y: bounds.height - HassTokens.Spacing.l - pillSize.height, width: pillSize.width, height: pillSize.height)
    }

    /// What the running camera is doing, for the pill over the feed: "Looking for a Barcode" while scanning, "Looking Up Product" while a
    /// barcode resolves, "Reading Expiration Date" while a photo is read.
    private func activity(_ model: ScanItemModel) -> String? {
        guard model.cameraStatus == .ready else { return nil }
        switch model.step {
        case .barcode:
            switch model.lookupStatus {
            case .resolving: return "Looking Up Product"
            case .idle, .scanning: return "Looking for a Barcode"
            default: return nil
            }
        case .expiry:
            return model.expiryStatus == .reading ? "Reading Expiration Date" : nil
        case .review, .adding:
            return nil
        }
    }

    func update(model: ScanItemModel, camera: ScanCameraController) {
        switch camera.source {
        case .live:
            preview.isHidden = false
            if preview.previewLayer.session !== camera.box.session { preview.previewLayer.session = camera.box.session }
            simulated.isHidden = true
        case .simulated:
            preview.isHidden = true
            simulated.isHidden = false
        case .unavailable:
            preview.isHidden = true
            simulated.isHidden = true
        }
        let status = model.cameraStatus
        statusStack.isHidden = status == .ready
        if status != .ready {
            if case let .failed(message) = status {
                statusIcon.isHidden = false
                statusArc.isHidden = true
                statusText.text = message
            } else {
                statusIcon.isHidden = true
                statusArc.isHidden = false
                statusText.text = "Starting camera…"
            }
            statusSummary?.accessibilityLabel = statusText.text
            settings.isHidden = !ScanCameraController.offersSettings(status)
        }
        if let text = activity(model) {
            pill.show(text)
            pill.isHidden = false
        } else {
            pill.isHidden = true
        }
        setNeedsLayout()
    }
}

/// The step's buttons: one filled button at most (direction G, Controls: Primary buttons): the step's forward action once there is
/// something to carry forward, else Read Expiration Date; the other is a grey capsule. Made once; each is shown or hidden.
final class UKScanFooterView: UIView {
    var onForward: () -> Void = {}
    var onReadExpiry: () -> Void = {}
    private let column = UIStackView()
    private lazy var forwardPrimary = UKPrimaryButton("Next") { [weak self] in self?.onForward() }
    private lazy var forwardSecondary = UKScanFooterView.secondary("Next") { [weak self] in self?.onForward() }
    private lazy var readPrimary = UKPrimaryButton("Read Expiration Date") { [weak self] in self?.onReadExpiry() }
    private lazy var readSecondary = UKScanFooterView.secondary("Read Expiration Date") { [weak self] in self?.onReadExpiry() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        forwardPrimary.accessibilityIdentifier = "scan.forward"
        forwardSecondary.accessibilityIdentifier = "scan.forward"
        readPrimary.accessibilityIdentifier = "scan.readExpiry"
        readSecondary.accessibilityIdentifier = "scan.readExpiry"
        [readPrimary, readSecondary, forwardPrimary, forwardSecondary].forEach(column.addArrangedSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A grey capsule (mockup `.n6-btn.sec`), tinted with ink.
    private static func secondary(_ title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.title = title
        configuration.baseForegroundColor = UKDesignInk.primary
        configuration.background.backgroundColor = UKDesignInk.primary.withAlphaComponent(0.2)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.preferred(.headline)
            return attributes
        }
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    func update(model: ScanItemModel, camera: ScanCameraController, step: ScanItemModel.Step) {
        let atBarcode = step == .barcode
        let atExpiry = step == .expiry
        let forwardTitle = atBarcode ? model.barcodeForwardTitle : model.expiryForwardTitle
        let forwardProminent = atBarcode ? model.hasBarcodeValue : model.hasExpiryValue
        let forwardDisabled = atBarcode ? model.barcodeForwardDisabled : model.expiryForwardDisabled
        let showsRead = atExpiry && model.canReadExpiry
        forwardPrimary.title = forwardTitle
        forwardPrimary.isEnabled = !forwardDisabled
        forwardSecondary.configuration?.title = forwardTitle
        forwardSecondary.isEnabled = !forwardDisabled
        forwardPrimary.isHidden = !forwardProminent
        forwardSecondary.isHidden = forwardProminent
        // Read Expiration Date is the filled button until there is a date to carry forward.
        let readProminent = !model.hasExpiryValue
        readPrimary.title = model.readExpiryTitle
        readSecondary.configuration?.title = model.readExpiryTitle
        readPrimary.isHidden = !(showsRead && readProminent)
        readSecondary.isHidden = !(showsRead && !readProminent)
    }
}
#endif
