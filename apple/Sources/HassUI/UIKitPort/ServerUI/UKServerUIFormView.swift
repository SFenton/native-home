#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Generic native form host

/// A canonical inset-grouped form, embedded without a second vertical scroll owner.
@MainActor
final class UKServerUIFormView: UIView, UKGridMeasuring {
    private(set) var session: (any ServerUIFormSession)?
    private(set) var opening = false
    private(set) var definition: ServerUICompositionDocument.Form?
    private weak var page: UKServerUIPage?
    private var form: UKFormViewController?
    private var controls: [String: UKServerUIFormControl] = [:]
    private var schedules: [String: UKServerUIScheduleFields] = [:]
    private let bag = UKObservationBag()
    private var openTask: Task<Void, Never>?
    private var failure: String?
    private var sizeObservation: NSKeyValueObservation?
    private var confirm: UKSheetConfirmItem?
    private var measuredWidth: CGFloat = 0
    private let forward = UKPrimaryButton("Next") {}
    private let forwardHost = UIView()
    private let scanFooter = UKScanFooterView()
    private var confirmTitle: String?
    /// Bar items are created once per kind and updated in place, so an observation tick never rebuilds the bar.
    private var leaveItem: UIBarButtonItem?
    private var leaveDepth: Bool?
    private var stepBackItem: UIBarButtonItem?
    private var doneItem: UIBarButtonItem?
    private var chromePending = false
    private var forwardBar: UKPagePinnedBar?
    private var factory: UKServerUIFormFactory?
    private var finishedNavigation = false
    private var ended = false
    private var commandPrompt = false
    private let scanProduct = UKScanProductHeaderView()
    private let scanReadAgain = UKFormActionRow(title: "Read Expiration Date", ink: UKDesignInk.action, identifier: "scan.readAgain")

    var blocksPublication: Bool { opening || commandPrompt || session?.hasChanges == true || session?.isBusy == true }
    var blocksExit: Bool { opening || commandPrompt || session?.isBusy == true }
    var needsDiscard: Bool { definition?.selectionOnly == false && session?.hasChanges == true }

    init() { super.init(frame: .zero) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ definition: ServerUICompositionDocument.Form, factory: UKServerUIFormFactory, page: UKServerUIPage) {
        self.page = page
        self.factory = factory
        if form == nil {
            let controller = UKFormViewController(context: page.context)
            page.addChild(controller)
            controller.loadViewIfNeeded()
            addSubview(controller.view)
            controller.didMove(toParent: page)
            controller.collectionView.isScrollEnabled = false
            controller.collectionView.contentInsetAdjustmentBehavior = .never
            form = controller
            sizeObservation = controller.collectionView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    self?.ukRemeasureContainers(includingSelf: true)
                } }
            }
        }
        let changed = self.definition != definition
        self.definition = definition
        if confirm == nil || changed {
            confirm = UKSheetConfirmItem(definition.saveLabel, isEnabled: false, busyTitle: "Saving",
                identifier: definition.node.id + ".save") { [weak self] in self?.save() }
            confirmTitle = definition.saveLabel
        }
        if session == nil, !opening {
            opening = true
            failure = nil
            render()
            openTask = Task { [weak self] in
                do {
                    let session = try await factory.open()
                    guard !Task.isCancelled else { try session.discard(); return }
                    guard let self else { try session.discard(); return }
                    let groups = session.groups
                    guard Set(groups.map(\.id)).count == groups.count,
                          groups.allSatisfy({ Set($0.fields.map(\.key)).count == $0.fields.count }),
                          groups.flatMap(\.fields).allSatisfy({ factory.fields[$0.key] == $0.control && $0.isValidDescriptor }),
                          (!factory.fields.values.contains(.attachment) || session is any ServerUIAttachmentFormSession),
                          (!factory.fields.values.contains(.scanCamera) || session is UKServerUIScanForm) else {
                        try session.discard()
                        throw ServerUIRecordFailure.invalidField
                    }
                    self.session = session
                    self.opening = false
                    self.bag.observe { [weak self] in self?.render(tracked: true) }
                } catch {
                    self?.opening = false
                    self?.failure = error.localizedDescription
                    self?.render()
                    page.renderer?.onError(.init(code: .unavailableSource, pointer: "/document/form"))
                }
            }
        } else { render() }
    }

    func applyChrome() {
        guard let page, let definition else { return }
        let title = (session as? UKServerUIScanForm)?.needsRefresh == true ? "Retry Refresh" : definition.saveLabel
        if confirmTitle != title {
            confirmTitle = title
            confirm = UKSheetConfirmItem(title, isEnabled: false, busyTitle: "Saving",
                identifier: definition.node.id + ".save") { [weak self] in self?.save() }
        }
        page.navigationItem.hidesBackButton = true
        page.navigationController?.interactivePopGestureRecognizer?.isEnabled = !blocksPublication
        let leave = { [weak self, weak page] in
            guard let self, let page else { return }
            page.renderer?.activate(page.depth > 0 ? .back : .dismiss(scope: .currentModal), from: page)
            _ = self
        }
        let pushed = page.depth > 0
        if leaveItem == nil || leaveDepth != pushed {
            leaveDepth = pushed
            leaveItem = pushed
                ? UKSheetItems.back(hasChanges: false, isEnabled: !blocksExit, presenter: page, action: leave)
                : UKSheetItems.cancel(isEnabled: !blocksExit, action: leave)
        }
        leaveItem?.isEnabled = !blocksExit
        var left: [UIBarButtonItem] = leaveItem.map { [$0] } ?? []
        confirm?.update(isEnabled: session?.canSave == true && !blocksExit, isBusy: session?.isBusy == true)
        page.navigationItem.rightBarButtonItems = confirm.map { [$0.barButtonItem] } ?? []
        UKDiscardGuard.apply(to: page, hasChanges: !definition.selectionOnly && session?.hasChanges == true, isBusy: blocksExit)
        if let stepped = session as? any ServerUISteppedFormSession {
            let progress = stepped.progress
            UKSheetSubtitle.apply(progress.subtitle, to: page.navigationItem)
            if progress.hasPrevious {
                if stepBackItem == nil {
                    stepBackItem = UKSheetItems.back(hasChanges: false, isEnabled: !blocksExit, presenter: page) { [weak self] in
                        guard let self else { return }
                        do { try (session as? any ServerUISteppedFormSession)?.retreat() } catch { failure = error.localizedDescription }
                        render()
                    }
                }
                stepBackItem?.isEnabled = !blocksExit
                left = stepBackItem.map { [$0] } ?? []
            }
            if !progress.canSubmit { page.navigationItem.rightBarButtonItems = [] }
            if let title = progress.forwardTitle {
                forward.title = title
                forward.isEnabled = progress.forwardEnabled
                forward.action = { [weak self] in
                    do { try stepped.advance() } catch { self?.failure = error.localizedDescription }
                    self?.render()
                }
                if let scan = session as? UKServerUIScanForm {
                    scanFooter.update(model: scan.model, camera: scan.camera, step: scan.model.step)
                    scanFooter.onForward = forward.action
                    scanFooter.onReadExpiry = { Task { await scan.camera.captureExpiry(for: scan.model) } }
                }
                let footer = session is UKServerUIScanForm ? scanFooter : forward
                if !traitCollection.ukIsAccessibilitySize {
                    if footer.superview !== forwardHost {
                        forwardHost.addSubview(footer); footer.ukPin(to: forwardHost)
                    }
                    if forwardBar == nil {
                        let bar = UKPagePinnedBar(bar: forwardHost, edge: .bottom, spacing: HassTokens.Spacing.l, scrollView: page.pageScroll)
                        forwardBar = bar
                        bar.install(in: page)
                    }
                }
                forwardHost.isHidden = traitCollection.ukIsAccessibilitySize
                forwardBar?.layoutChanged()
            } else {
                forwardHost.isHidden = true
                forwardBar?.layoutChanged()
            }
        }
        if let scan = session as? UKServerUIScanForm, scan.model.addStatus == .added, scan.error == nil, !scan.isBusy {
            left = []
            if doneItem == nil {
                doneItem = UKSheetItems.close(identifier: definition.node.id + ".done") { [weak page] in
                    guard let page else { return }
                    page.renderer?.activate(definition.success ?? .dismiss(scope: .currentModal), from: page)
                }
            }
            page.navigationItem.rightBarButtonItems = doneItem.map { [$0] } ?? []
        }
        let columns = page.parent as? UKColumnsViewController
        if columns != nil { left = [] }
        setLeft(left, on: page.navigationItem)
        columns?.pageStateChanged()
    }

    /// Assigns the leading items only when the set changed, so UIKit keeps the same item instances between ticks.
    private func setLeft(_ items: [UIBarButtonItem], on item: UINavigationItem) {
        guard (item.leftBarButtonItems ?? []) != items else { return }
        item.leftBarButtonItems = items
    }

    /// Chrome is refreshed one turn after an observation tick, outside the tracked closure, so what chrome reads is not tracked.
    private func scheduleChrome() {
        guard !chromePending else { return }
        chromePending = true
        DispatchQueue.main.async { [weak self] in
            self?.chromePending = false
            self?.page?.refreshChrome()
        }
    }

    func discard() throws {
        guard !blocksExit else { throw ServerUIRecordFailure.busy }
        try session?.discard()
        ended = true
    }

    func reopenIfNeeded() {
        guard ended, !opening, let definition, let factory, let page else { return }
        ended = false
        finishedNavigation = false
        session = nil
        controls = [:]
        bag.removeAll()
        bind(definition, factory: factory, page: page)
    }

    private func render(tracked: Bool = false) {
        guard let definition, let form else { return }
        var sections: [UKFormSection] = []
        if let message = failure ?? session?.error {
            sections.append(.init(id: "error", rows: [.init(id: "error." + message, .custom { UKInlineAlertView(message, severity: .error) })]))
        }
        if session == nil, !opening, let factory, let page {
            sections.append(.init(id: "retry", rows: [.init(id: "retry", .button(title: AlertCopy.tryAgain) { [weak self] in
                self?.bind(definition, factory: factory, page: page)
            })]))
        }
        if opening {
            sections.append(.init(id: "loading", rows: [.init(id: "loading", .custom { UKTodoSpinnerRow(label: "Loading") })]))
        }
        if let session {
            if let inventory = session as? ServerUIInventoryForm { page?.title = inventory.model.title }
            if let scan = session as? UKServerUIScanForm {
                if let header = UKScanItemViewController.headerSection(model: scan.model) { sections.append(header) }
                scanReadAgain.show(title: scan.model.readExpiryTitle, isEnabled: !scan.isBusy && scan.camera.source != .unavailable)
                scanReadAgain.onTap = { [weak self] in
                    guard !scan.isBusy, scan.camera.source != .unavailable else { return }
                    scan.model.readExpiryAgain(); self?.render()
                }
                if scan.model.isProcessing {
                    sections.append(.init(id: "processing", rows: [.init(id: "processing", .clear { UKScanItemViewController.processingView() })]))
                } else if scan.model.step == .review {
                    scanProduct.show(name: scan.model.name, barcode: scan.model.detectedBarcode)
                    sections.append(.init(id: "product", rows: [.init(id: "product", .custom { [scanProduct] in scanProduct })]))
                } else if scan.model.step == .adding {
                    sections.append(UKScanItemViewController.addingSection(model: scan.model))
                }
            }
            for group in session.groups {
                var rows: [UKFormRow] = []
                let visible = group.fields.filter(\.visible)
                if !visible.isEmpty, visible.allSatisfy({ $0.control == .scheduleDateTime }) {
                    let schedule = schedules[group.id] ?? UKServerUIScheduleFields()
                    schedules[group.id] = schedule
                    do {
                        try schedule.apply(visible.map { value in
                            var value = value
                            value.label = definition.fields.first { $0.key == value.key }?.label ?? value.label
                            return value
                        }, enabled: !session.isBusy) { [weak self] key, seconds in
                            do { try session.set(.number(seconds), group: group.id, field: key) }
                            catch { self?.failure = error.localizedDescription }
                            self?.render()
                        }
                    } catch {
                        let message = error.localizedDescription
                        failure = message
                        sections.append(.init(id: group.id + ".error",
                            rows: [.init(id: group.id + ".error", .custom { UKInlineAlertView(message, severity: .error) })]))
                        continue
                    }
                    sections.append(.init(id: group.id, header: group.title.isEmpty ? nil : group.title,
                        footer: group.footer.isEmpty ? nil : group.footer, rows: [.init(id: group.id, .clear { schedule })]))
                    continue
                }
                for field in definition.fields {
                    guard var value = group.fields.first(where: { $0.key == field.key }), value.visible else { continue }
                    value.label = field.label
                    let key = "\(group.id.utf8.count):\(group.id).\(field.key)"
                    if value.control == .weekdays, case .string(let csv) = value.value {
                        let selected = Set(csv.split(separator: ",").map(String.init))
                        for day in DonetickTaskForm.weekdays {
                            rows.append(.init(id: key + "." + day.value,
                                .option(title: day.label, subtitle: nil, swatch: [], isSelected: selected.contains(day.value)) { [weak self] in
                                    guard !session.isBusy, value.enabled else { return }
                                    var next = selected
                                    if !next.insert(day.value).inserted { next.remove(day.value) }
                                    do { try session.set(.string(DonetickTaskForm.weekdays.map(\.value).filter(next.contains).joined(separator: ",")),
                                                         group: group.id, field: field.key) }
                                    catch { self?.failure = error.localizedDescription }
                                    self?.render()
                                }))
                        }
                        continue
                    }
                    if value.control == .options, case .choice(let options) = value.rule {
                        for option in options {
                            rows.append(.init(id: key + "." + option.id, identifier: definition.node.id + "." + key + "." + option.id,
                                .option(title: option.label, subtitle: value.optionDetails[option.id], swatch: [],
                                        isSelected: value.value == .string(option.id)) { [weak self] in
                                    guard !session.isBusy, value.enabled else { return }
                                    do { try session.set(.string(option.id), group: group.id, field: field.key) }
                                    catch { self?.failure = error.localizedDescription }
                                    self?.render()
                                }))
                        }
                        continue
                    }
                    let control = controls[key] ?? UKServerUIFormControl(value, identifier: definition.node.id + "." + key,
                        session: session, page: page, report: { [weak self] in self?.failure = $0.localizedDescription; self?.render() }) { [weak self] next in
                        do {
                            if field.key == "prepared", let inventory = session as? ServerUIInventoryForm, let page = self?.page {
                                try inventory.prepared(group: group.id, from: page) { [weak self] in self?.failure = $0.localizedDescription }
                            } else { try session.set(next, group: group.id, field: field.key) }
                            self?.failure = nil
                        } catch { self?.failure = error.localizedDescription }
                        self?.render()
                    }
                    controls[key] = control
                    control.update(value, !session.isBusy && value.enabled)
                    if value.control == .scanCamera { rows.append(.init(id: key, .clear { control.view })) }
                    else { rows.append(.init(id: key, .custom { control.view })) }
                }
                if group.id == "details", let scan = session as? UKServerUIScanForm {
                    if scan.model.step == .barcode {
                        rows.append(.init(id: "scan-again", .button(title: scan.model.scanBarcodeTitle) { [weak self] in
                            guard !scan.isBusy else { return }
                            scan.model.scanBarcodeAgain(); self?.render()
                        }))
                    }
                }
                sections.append(.init(id: group.id, header: group.title.isEmpty ? nil : group.title,
                    footer: group.footer.isEmpty ? nil : group.footer, headerStyle: .system, rows: rows))
                if group.id == "quick", session is UKServerUIScanForm {
                    sections.append(.init(id: "read-again", rows: [.init(id: "read-again", .custom { [scanReadAgain] in scanReadAgain })]))
                }
                if let inventory = session as? ServerUIInventoryForm,
                   inventory.model.batches.first(where: { $0.key == group.id })?.addressable == true {
                    sections.append(.init(id: "delete." + group.id,
                        footer: "Deleting asks first and applies at once. It is not part of Save.",
                        rows: [.init(id: "delete." + group.id, .button(title: "Delete") { [weak self] in
                            guard let self, let page else { return }
                            do { try inventory.delete(group: group.id, from: page, source: self) { [weak self] in self?.failure = $0.localizedDescription } }
                            catch { failure = error.localizedDescription; render() }
                        })]))
                }
            }
            if session.canReset {
                sections.append(.init(id: "reset", rows: [.init(id: "reset", .button(title: session.resetLabel) { [weak self] in
                    do { try session.reset() } catch { self?.failure = error.localizedDescription }
                    self?.render()
                })]))
            }
            if !finishedNavigation, let deletable = session as? any ServerUIDeletableFormSession, let deletion = deletable.deletion {
                sections.append(.init(id: "delete-record", rows: [.init(id: "delete-record", .custom { [weak self] in
                    let row = UKTodoButtonRow(title: deletion.title, ink: UKDesignInk.danger, identifier: definition.node.id + ".delete") {
                        self?.delete(deletable, deletion: deletion)
                    }
                    row.isEnabled = !session.isBusy && self?.commandPrompt != true
                    return row
                })]))
            }
            if traitCollection.ukIsAccessibilitySize,
               let stepped = session as? any ServerUISteppedFormSession, stepped.progress.forwardTitle != nil {
                let footer: UIView = session is UKServerUIScanForm ? scanFooter : forward
                sections.append(.init(id: "step-footer", rows: [.init(id: "step-footer", .clear { footer })]))
            }
        }
        form.setSections(sections, animated: false)
        if let inventory = session as? ServerUIInventoryForm, inventory.model.isFinished, !finishedNavigation {
            finishedNavigation = true
            Task { [weak self] in
                guard let self, let page else { return }
                page.renderer?.activate(definition.success ?? .dismiss(scope: .currentModal), from: page)
            }
        }
        if tracked { scheduleChrome() } else { page?.refreshChrome() }
        ukRemeasureContainers(includingSelf: true)
    }

    private func save() {
        guard let session, session.canSave, let page else { return }
        page.view.endEditing(true)
        Task { [self] in
            do {
                try await session.save()
                failure = nil
                if !(session is UKServerUIScanForm), let action = definition?.success {
                    finishedNavigation = true
                    page.renderer?.activate(action, from: page)
                }
            } catch {
                failure = session.error ?? error.localizedDescription
                page.renderer?.onError(.init(code: .unavailableSource, pointer: "/document/form"))
            }
            render()
        }
    }

    private func delete(_ session: any ServerUIDeletableFormSession, deletion: ServerUIFormDeletion) {
        guard !blocksExit, let page else { return }
        commandPrompt = true
        render()
        UKServerUIRecordPrompts.confirm(AlertCopy.delete(deletion.noun, named: deletion.name), from: page, source: self,
            cancel: { [weak self] in self?.commandPrompt = false; self?.render() },
            submit: { [self] in
                commandPrompt = false
                try await session.delete()
                finishedNavigation = true
                if let action = definition?.success { page.renderer?.activate(action, from: page) }
                render()
            }, report: { [weak self] in self?.commandPrompt = false; self?.failure = $0.localizedDescription; self?.render() })
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let form, width > 0 else { return 1 }
        if measuredWidth != width {
            measuredWidth = width
            form.view.frame = CGRect(x: 0, y: 0, width: width, height: max(1, form.collectionView.contentSize.height))
            form.collectionView.collectionViewLayout.invalidateLayout()
        }
        form.view.layoutIfNeeded()
        return max(1, ceil(form.collectionView.collectionViewLayout.collectionViewContentSize.height))
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); form?.view.frame = bounds; forwardBar?.layoutChanged() }

    func detach() {
        openTask?.cancel()
        bag.removeAll()
        do { try session?.discard() }
        catch { page?.renderer?.onError(.init(code: .interactionBlocked, pointer: "/document/form")) }
        forwardBar?.follow(nil)
        forwardHost.removeFromSuperview()
        if forwardBar != nil { page?.additionalSafeAreaInsets.bottom = 0 }
        forwardBar = nil
        form?.willMove(toParent: nil)
        form?.view.removeFromSuperview()
        form?.removeFromParent()
        form = nil
    }

    deinit {
        MainActor.assumeIsolated {
            do { try session?.discard() }
            catch { NSLog("ServerUI form release failed: %@", String(describing: type(of: error))) }
        }
    }
}

// MARK: - Retained canonical controls

@MainActor
private final class UKServerUIFormControl {
    let view: UIView
    let update: (ServerUIFormValue, Bool) -> Void

    init(_ field: ServerUIFormValue, identifier: String, session: any ServerUIFormSession,
         page: UIViewController?, report: @escaping (any Error) -> Void,
         change: @escaping (ServerUICompositionDocument.LocalValue) -> Void) {
        switch field.control {
        case .scheduleDateTime:
            let control = UKServerUIScheduleFields()
            view = control
            update = { field, enabled in
                do { try control.apply([field], enabled: enabled) { _, seconds in change(.number(seconds)) } }
                catch { report(error) }
            }
        case .text:
            let control = UKTodoTextField(placeholder: field.label, identifier: identifier)
            control.addAction(UIAction { _ in change(.string(control.text ?? "")) }, for: .editingChanged)
            view = control.rowView
            update = { field, enabled in
                if case .string(let value) = field.value, !control.isFirstResponder { control.text = value }
                control.isEnabled = enabled
            }
        case .multiline:
            let control = UKTodoTextView(placeholder: field.label, identifier: identifier, lines: 3...8)
            control.onChange = { change(.string($0)) }
            control.onHeightChange = { [weak control] in control?.ukRemeasureContainers() }
            view = control
            update = { field, enabled in
                if case .string(let value) = field.value, !control.textView.isFirstResponder { control.text = value }
                control.textView.isEditable = enabled
            }
        case .toggle:
            let control = UKFormSwitchRow(title: field.label, identifier: identifier)
            control.onToggle = { change(.boolean($0)) }
            view = control
            update = { field, enabled in
                if case .boolean(let value) = field.value { control.show(isOn: value, isEnabled: enabled) }
            }
        case .number:
            if let scan = session as? UKServerUIScanForm, field.key == "quantity" {
                let control = UKScanQuantityRow()
                control.onChange = { if !scan.isBusy { scan.model.setQuantityText($0) } }
                control.onStep = { if !scan.isBusy { scan.model.setQuantityText(String(Int($0))) } }
                control.onSubmit = { _ = scan.model.validateQuantity() }
                view = control
                update = { _, enabled in control.show(text: scan.model.quantityText); control.isUserInteractionEnabled = enabled }
                break
            }
            let control = UKFormStepperRow(title: field.label, identifier: identifier)
            control.onChange = { change(.number($0)) }
            view = control
            update = { field, enabled in
                if case .number(let value) = field.value, case .number(let min, let max, let step) = field.rule {
                    control.stepper.stepValue = step
                    control.show(current: value, minimum: min, maximum: max, display: InventoryFormat.quantity(value),
                                 isEnabled: enabled, label: field.label)
                }
            }
        case .choice, .options:
            let control = UKTodoPickerRow(title: field.label, identifier: identifier)
            view = control
            update = { field, enabled in
                if case .string(let value) = field.value, case .choice(let options) = field.rule {
                    control.update(options: options.map { .init($0.label, $0.id) }, selected: value) { change(.string($0)) }
                }
                control.isUserInteractionEnabled = enabled
            }
        case .percent:
            let control = UKPercentSliderRow(field.label, value: 0, identifier: identifier) { change(.number($0)) }
            view = control
            update = { field, enabled in
                if case .number(let value) = field.value { control.value = value }
                control.isEnabled = enabled
            }
        case .segmented:
            let options: [ServerUICompositionDocument.LocalField.Option]
            if case .choice(let values) = field.rule { options = values } else { options = [] }
            let selected: String
            if case .string(let value) = field.value { selected = value } else { selected = "" }
            let control = UKSegmentedChoice(label: field.label, options: options.map(\.id),
                title: { id in options.first(where: { $0.id == id })?.label ?? id },
                selection: selected, identifier: identifier) { change(.string($0)) }
            view = control
            update = { field, enabled in
                if case .string(let value) = field.value { control.selection = value }
                control.isEnabled = enabled
            }
        case .date, .time:
            let control = UIDatePicker()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = field.control == .date ? "yyyy-MM-dd" : "HH:mm"
            control.datePickerMode = field.control == .date ? .date : .time
            control.preferredDatePickerStyle = .compact
            control.accessibilityLabel = field.label; control.accessibilityIdentifier = identifier
            control.addAction(UIAction { _ in change(.string(formatter.string(from: control.date))) }, for: .valueChanged)
            view = UKTodoLabeledRow(title: field.label, trailing: control)
            update = { field, enabled in
                if case .string(let value) = field.value, let date = formatter.date(from: value), control.date != date { control.date = date }
                control.isEnabled = enabled
            }
        case .weekdays:
            view = UKServerUIRejected.view("weekdays control")
            update = { _, _ in }
        case .attachment:
            if let session = session as? any ServerUIAttachmentFormSession, let page {
                let control = UKServerUIAttachments(session: session, page: page, report: report)
                view = control
                update = { _, _ in control.update() }
            } else {
                view = UKServerUIRejected.view("attachment session")
                update = { _, _ in }
                report(UKServerUIRendererError(code: .unavailableSource, pointer: "/document/forms"))
            }
        case .scanCamera:
            guard let session = session as? UKServerUIScanForm else {
                view = UKServerUIRejected.view("scan session")
                update = { _, _ in }
                report(UKServerUIRendererError(code: .unavailableSource, pointer: "/document/forms"))
                break
            }
            let control = UKServerUIScanCamera(session)
            view = control
            update = { _, enabled in control.isUserInteractionEnabled = enabled }
        }
    }
}
#endif
