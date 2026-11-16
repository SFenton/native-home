#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Content base

/// What one page of the Vacation feature draws: a scroll view of sections, bound to its controller through a bag. A page host
/// (the entry screen, or a page the chooser pushes) puts `scrollView` on screen and tells the content when it appeared.
@MainActor
class UKVacationContent {
    let context: UKContext
    let bag = UKObservationBag()
    let container = UKColumnContainer(spacing: 0, padding: HassTokens.Spacing.l, maxWidth: nil)
    /// The controller that presents this content's sheets and alerts.
    weak var host: UIViewController?

    init(context: UKContext) { self.context = context }

    var scrollView: UIScrollView { container.scrollView }
    var surface: TileSurface { context.surface }
    var environment: UKTileEnvironment { UKTileEnvironment(context: context) }
    var title: String { "" }

    /// The host is on screen: present anything that was waiting for a window.
    func hostDidAppear() {}
    /// The host left the screen.
    func hostDidDisappear() {}

    /// A window to present from, or nil while the host is not on screen yet.
    var presenter: UIViewController? {
        guard let host, host.view.window != nil else { return nil }
        return host.ukTopPresented
    }

    /// Two sections side by side when the page is wide enough, else stacked (`AwaySectionGrid`). The minimum column width scales
    /// with Dynamic Type, so at accessibility sizes the sections stack.
    func makeSectionGrid() -> UKFlexGridView {
        UKFlexGridView(minWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, scaleStyle: .body)
    }
}

// MARK: - Error slot

/// A place for an inline error whose words change: empty (and hidden) until there is a message.
@MainActor
final class UKErrorSlot: UIView {
    private let stack = UIStackView.ukColumn(spacing: 0)
    private var message: String?

    init() {
        super.init(frame: .zero)
        addSubview(stack)
        stack.ukPin(to: self)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ message: String?, severity: UKInlineAlertView.Severity = .error, identifier: String? = nil) {
        guard message != self.message else { return }
        self.message = message
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let message {
            let alert = UKInlineAlertView(message, severity: severity)
            alert.accessibilityIdentifier = identifier
            stack.addArrangedSubview(alert)
        }
        isHidden = message == nil
    }
}

// MARK: - Announcing notice

/// A notice that is spoken when it appears (`announcesWhenShown`): a confirmed state arrives with its section after an action.
@MainActor
final class UKAnnouncingView: UIView {
    private let text: String
    private var announced = false

    init(child: UIView, announcement: String) {
        text = announcement
        super.init(frame: .zero)
        addSubview(child)
        child.ukPin(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !announced else { return }
        announced = true
        Announcer.announce(text)
    }
}

/// The "<Traveler> Away" notice as an info box (`SoloTripNoticeBox`).
@MainActor
func ukSoloTripNoticeBox(_ notice: SoloTripNotice) -> UIView {
    let box = UKInfoBoxView(title: notice.title, message: notice.description, tone: notice.isSuccess ? .success : .neutral)
    box.accessibilityIdentifier = "soloTrip.notice"
    return UKAnnouncingView(child: box, announcement: [notice.title, notice.description].compactMap { $0 }.joined(separator: ". "))
}

/// The Solo Trip status block (`SoloTripStatusView`, web `SoloTripStatusSection`).
@MainActor
func ukSoloTripStatusView(status: SoloTripStatus, notice: SoloTripNotice?, actionsDisabled: Bool, surface: TileSurface,
                          perform: @escaping (SoloTripStatus.Action) -> Void) -> UIView {
    var content: [UIView] = []
    if let error = status.error { content.append(UKInlineAlertView(error, severity: .error)) }
    if status.showsActiveNotice, let notice { content.append(ukSoloTripNoticeBox(notice)) }
    for action in status.actions {
        let button = UKAwayButtons.bordered(title: action.title, destructive: action == .endNow, identifier: "soloTrip.status.\(action.rawValue)") { perform(action) }
        button.isEnabled = !actionsDisabled
        content.append(button)
    }
    let section = UKAwaySectionView(title: status.title, description: status.description, surface: surface, content: content)
    // A container keeps the action buttons' own identifiers.
    section.accessibilityContainerType = .semanticGroup
    section.accessibilityIdentifier = "soloTrip.status"
    return section
}

// MARK: - Chooser

/// Vacation Mode (`VacationModeScreen`, web `VacationModePage`): the mode card, then the pre-vacation checklist or, once enabled,
/// the vacation dates. Enabling opens the confirmation sheet. While a Solo Trip owns the household plan, the page shows its
/// status instead.
@MainActor
final class UKVacationModeContent: UKVacationContent {
    let controller: VacationModeController
    private let modeTile: UKGlassTileView
    private let preChecklistError = UKInlineAlertView(Vacation.Copy.preChecklistError, severity: .error)
    private let commandError = UKErrorSlot()
    private var checklistSection: UKAwaySectionView!
    private var checklistRows: [UKVacationChecklistRow] = []
    private let datesSection: UKAwaySectionView
    private let dateFields: UKVacationDateFieldsView
    private let grid: UKFlexGridView
    private let statusSlot = UIStackView.ukColumn(spacing: 0)
    private var layoutKey = ""
    private var statusKey: SoloTripStatus?
    private weak var confirmation: UKHassModalController?
    private var confirmDates: UKVacationDateFieldsView?
    private var confirmButton: UKPrimaryButton?

    override var title: String { Vacation.Copy.modeTitle }

    init(context: UKContext, household: HouseholdAwayController, caller: any HassServiceCalling, targets: Vacation.Targets? = nil) {
        let controller = VacationModeController(store: context.store, household: household, caller: caller, targets: targets)
        self.controller = controller
        let surface = context.surface
        modeTile = UKGlassTileView(model: Self.modeModel(controller), environment: UKTileEnvironment(context: context))
        dateFields = UKVacationDateFieldsView(range: controller.dateRange, invalid: controller.invalidDateRange, identifierPrefix: "vacation.dates",
                                              commitDelay: liveDateCommitDelay) { range, changedEnd in controller.updateSavedRange(range, changedEnd: changedEnd) }
        datesSection = UKAwaySectionView(title: Vacation.Copy.datesTitle, surface: surface, content: [dateFields])
        grid = UKFlexGridView(minWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, scaleStyle: .body)
        super.init(context: context)

        modeTile.onPerform = { _ in VacationModeTile.run(controller) }
        let modeSection = UKAwaySectionView(description: Vacation.Copy.modeDescription, surface: surface, content: [preChecklistError, commandError, modeTile])
        sections = [modeSection]

        // The checklist as one inset list on a module (a sheet cell in a sheet).
        checklistRows = controller.checklist.enumerated().map { index, item in
            let row = UKVacationChecklistRow(title: item.title) { controller.toggle(item) }
            row.accessibilityIdentifier = "vacation.checklist.\(index)"
            return row
        }
        let list = UKModuleListView(hasGlyphs: true, surface: surface, rows: checklistRows)
        checklistSection = UKAwaySectionView(title: "\(Vacation.Copy.checklistTitle) · 0 of \(controller.checklist.count)", surface: surface, content: [list])
        statusSlot.isHidden = true
        container.column.addArrangedSubview(statusSlot)
        container.column.addArrangedSubview(grid)
        bag.observe { [weak self] in self?.refresh() }
    }

    private var sections: [UIView] = []

    /// The Vacation Mode card as an action tile (rollout lane M, audit item 27; `VacationModeTile`): *text, disc* with the toggle-styled `power`
    /// disc. It keeps its gates: turning it on opens the dates sheet (or shows the unfinished-checklist error), and turning it off asks first
    /// with today's alert (`AlertCopy.turnOffVacation`) as the tile's confirmation, so a disc tap and a body tap take the same path and no
    /// service call fires before Turn Off. The question's buttons are `vacation.modeCard.confirm` and `.cancel`.
    static func modeModel(_ controller: VacationModeController) -> UKGlassTileModel {
        let specs = VacationModeTile.specs(for: controller)
        var model = UKGlassTileModel(
            title: Vacation.Copy.modeTitle, subtitle: controller.cardSubtitle, symbol: SymbolMap.symbol(for: "mdi:airplane"),
            tint: controller.isConfirming ? UKHouseholdTint.pending : UKHouseholdTint.vacation,
            isActive: controller.cardEnabled || controller.isConfirming, isUnavailable: controller.modeUnavailable,
            behavior: TileBehavior(AwayTileActions.classification, primary: AwayTileActions.actionId), actions: specs.items,
            identifier: VacationModeTile.identifier)
        model.bodyHint = controller.cardAccessibilityHint
        return model
    }

    private func refresh() {
        let controller = controller
        // The mode card.
        modeTile.configure(Self.modeModel(controller), environment: environment, perform: { _ in VacationModeTile.run(controller) })
        preChecklistError.isHidden = !controller.showsPreChecklistError
        commandError.show(controller.commandFailed ? "Couldn't update Vacation Mode. Check the current state and try again." : nil)

        // The checklist and its count.
        var done = 0
        for (item, row) in zip(controller.checklist, checklistRows) {
            let checked = controller.isChecked(item)
            if checked { done += 1 }
            row.update(isChecked: checked, isUnavailable: controller.isUnavailable(item))
        }
        checklistSection.setTitle("\(Vacation.Copy.checklistTitle) · \(done) of \(controller.checklist.count)")
        dateFields.update(range: controller.dateRange, invalid: controller.invalidDateRange)

        // Which block shows: the Solo Trip status, or the mode section beside the dates or the checklist.
        let solo = controller.soloTripEngaged
        let key = solo ? "solo" : controller.showsInlineDates ? "dates" : "checklist"
        if key != layoutKey {
            let animated = !layoutKey.isEmpty && !UIAccessibility.isReduceMotionEnabled && scrollView.window != nil
            layoutKey = key
            let apply = {
                self.statusSlot.isHidden = !solo
                self.grid.isHidden = solo
                if !solo { self.grid.setItems([self.sections[0], key == "dates" ? self.datesSection : self.checklistSection]) }
            }
            if animated { UIView.transition(with: scrollView, duration: MotionTokens.standardDuration, options: .transitionCrossDissolve, animations: apply) } else { apply() }
        }
        if solo { refreshStatus() }
        grid.setNeedsLayout()

        presentSheetsIfNeeded()
    }

    private func refreshStatus() {
        let household = controller.household
        let status = SoloTripStatus.make(snapshot: household.snapshot, errorCode: household.errorCode)
        let notice = SoloTripNotice.make(snapshot: household.snapshot, viewer: nil)
        let disabled = household.pending || !household.snapshot.canCommand
        let key = "\(status)|\(String(describing: notice))|\(disabled)"
        guard key != statusSignature else { return }
        statusSignature = key
        statusSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusSlot.addArrangedSubview(ukSoloTripStatusView(status: status, notice: notice, actionsDisabled: disabled, surface: surface) { [weak self] action in
            Task { await self?.perform(action) }
        })
    }

    private var statusSignature = ""

    private func perform(_ action: SoloTripStatus.Action) async {
        let household = controller.household
        household.clearError()
        switch action {
        case .keepCurrent: _ = await household.resolveRestore(.keepCurrent)
        case .restoreSaved: _ = await household.resolveRestore(.restoreSaved)
        case .endNow: _ = await household.endNow()
        }
    }

    override func hostDidAppear() { presentSheetsIfNeeded() }

    // MARK: Sheets and alerts

    private func presentSheetsIfNeeded() {
        if controller.isConfirming {
            if confirmation != nil {
                confirmDates?.update(range: controller.dateRange, invalid: controller.invalidDateRange)
                confirmButton?.isEnabled = !controller.invalidDateRange
                confirmButton?.accessibilityHint = controller.invalidDateRange ? Vacation.Copy.dateRangeError : ""
            } else if let presenter {
                presentConfirmation(from: presenter)
            }
        } else if let confirmation, confirmation.presentingViewController != nil, !confirmation.isBeingDismissed {
            confirmation.dismiss(animated: true)
            self.confirmation = nil
        }
    }

    /// Dates for a new vacation (`VacationConfirmationSheet`, web `VacationConfirmationModal`).
    private func presentConfirmation(from presenter: UIViewController) {
        let controller = controller
        let dates = UKVacationDateFieldsView(range: controller.dateRange, invalid: controller.invalidDateRange, identifierPrefix: "vacation.confirm",
                                             commitDelay: nil) { range, _ in controller.updatePendingRange(range) }
        // Present but disabled while the range is invalid, so the sheet does not reflow when the error appears; the error above
        // is the reason (HIG, Buttons: say why a button is disabled).
        let button = UKAwayButtons.prominent(title: Vacation.Copy.confirmAction, identifier: "vacation.confirm.action",
                                             isEnabled: !controller.invalidDateRange, disabledReason: Vacation.Copy.dateRangeError) { controller.confirm() }
        let stack = UIStackView.ukColumn([dates, button], spacing: HassTokens.Spacing.l)
        let page = UKHouseholdSheetContentController(content: UKHouseholdPaddedView(stack, insets: .ukAll(HassTokens.Spacing.l)))
        page.title = Vacation.Copy.confirmTitle
        // A create sheet (direction G, Sheets): circle x Cancel leading drops the dates; the primary button confirms.
        page.navigationItem.leftBarButtonItem = UKSheetItems.cancel(identifier: "vacation.confirm.cancel") { controller.cancelConfirmation() }
        var options = UKHassModalOptions(title: Vacation.Copy.confirmTitle, fitKey: "vacation.confirm")
        options.showsClose = false
        options.width = .form
        options.onDismissed = { [weak self] in
            self?.confirmation = nil
            controller.cancelConfirmation()
        }
        let modal = UKHassModalController(root: page, options: options)
        confirmation = modal
        confirmDates = dates
        confirmButton = button
        modal.present(from: presenter)
    }
}

// MARK: - Solo Trip

/// Solo Trip (`SoloTripScreen`, web `SoloTripPage`): the Solo Trip toggle beside the traveler choice. Turning it on opens the
/// editor sheet; turning it off ends or cancels the trip. While a trip runs, the return time can be moved and the status
/// section shows anything that needs attention.
@MainActor
final class UKSoloTripContent: UKVacationContent {
    let controller: SoloTripController
    var viewer: HouseholdResident? { didSet { controller.viewer = viewer } }
    private let noticeSlot = UIStackView.ukColumn(spacing: 0)
    private let toggleTile: UKGlassTileView
    private let setupError = UKErrorSlot()
    private let travelerGrid: UKFlexGridView
    private var travelerTiles: [HouseholdResident: UKGlassTileView] = [:]
    private var travelerOrder: [HouseholdResident] = []
    private let returnFields: UKScheduleDateFields
    private let returnError = UKErrorSlot()
    private let statusSlot = UIStackView.ukColumn(spacing: 0)
    private let grid: UKFlexGridView
    private var noticeSignature = ""
    private var statusSignature = ""
    private weak var editor: UKHassModalController?
    private var editorRefresh: (() -> Void)?
    private var confirmsEnd = false

    override var title: String { SoloTripCopy.title }

    init(context: UKContext, household: HouseholdAwayController, viewer: HouseholdResident?) {
        let controller = SoloTripController(household: household)
        controller.viewer = viewer
        self.controller = controller
        self.viewer = viewer
        let environment = UKTileEnvironment(context: context)
        toggleTile = UKGlassTileView(model: Self.toggleModel(controller), environment: environment)
        travelerGrid = UKFlexGridView(minWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, spacing: HassTokens.Spacing.s, scaleStyle: .subheadline)
        returnFields = UKScheduleDateFields(fields: [
            ScheduleDateField(SoloTripCopy.returns, .dateAndTime, controller.returnDraft, id: "soloTrip.return") { end in
                Task { await controller.updateReturn(end) }
            },
        ], commitDelay: liveDateCommitDelay)
        grid = UKFlexGridView(minWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, scaleStyle: .body)
        super.init(context: context)

        let description = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
        description.text = SoloTripCopy.description
        toggleTile.onPerform = { [weak controller] _ in guard let controller else { return }; Task { await controller.toggle() } }
        // No section title: the navigation title already says Solo Trip (owner, 2026-10-13).
        let toggleSection = UKAwaySectionView(surface: surface, content: [noticeSlot, description, toggleTile, setupError])

        let travelerSection = UKAwaySectionView(title: SoloTripCopy.awayFromHomeTitle, description: SoloTripCopy.awayFromHomeDescription,
                                                surface: surface, content: [travelerGrid, returnFields, returnError, statusSlot])
        grid.setItems([toggleSection, travelerSection])
        container.column.addArrangedSubview(grid)
        bag.observe { [weak self] in self?.refresh() }
    }

    override func hostDidDisappear() {
        // Errors belong to this page: leaving drops them so the shared controller doesn't carry a Solo Trip error onto the Vacation Mode page.
        controller.household.clearError()
    }

    override func hostDidAppear() { refresh() }

    /// The Solo Trip toggle as an action tile (rollout lane M, audit item 28; `SoloTripToggleTile`): *text, disc* with the toggle-styled
    /// `power` disc. Turning a trip **on** opens the editor sheet (the controller's own gate); turning it **off** asks first with today's alert
    /// (`AlertCopy.endSoloTrip`) as the tile's confirmation (`soloTrip.toggle.confirm` / `.cancel`), so a disc tap and a body tap take the same
    /// path. It dims while no traveler is chosen.
    static func toggleModel(_ controller: SoloTripController) -> UKGlassTileModel {
        UKGlassTileModel(
            title: SoloTripCopy.title, subtitle: controller.toggleSubtitle, symbol: SymbolMap.symbol(for: "mdi:bag-suitcase"),
            tint: UKHouseholdTint.soloTrip, isActive: controller.toggleChecked,
            behavior: TileBehavior(AwayTileActions.classification, primary: AwayTileActions.actionId),
            actions: SoloTripToggleTile.specs(for: controller).items, identifier: "soloTrip.toggle")
    }

    private func askToEnd() {
        guard !confirmsEnd, let presenter else { return }
        confirmsEnd = true
        UKAlerts.alert(AlertCopy.endSoloTrip, from: presenter, confirmID: "soloTrip.end.confirm", cancelID: "soloTrip.end.cancel",
                       onCancel: { [weak self] in self?.confirmsEnd = false },
                       onConfirm: { [weak self] in
                           self?.confirmsEnd = false
                           guard let self else { return }
                           Task { await self.controller.toggle() }
                       })
    }

    private func refresh() {
        let controller = controller
        // The notice.
        let notice = controller.notice
        let noticeKey = String(describing: notice)
        if noticeKey != noticeSignature {
            noticeSignature = noticeKey
            noticeSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if let notice { noticeSlot.addArrangedSubview(ukSoloTripNoticeBox(notice)) }
            noticeSlot.isHidden = notice == nil
        }
        // The toggle.
        toggleTile.configure(Self.toggleModel(controller), environment: environment, perform: { [weak controller] _ in
            guard let controller else { return }
            Task { await controller.toggle() }
        })
        setupError.show(controller.setupError)

        refreshTravelers()

        // The return time.
        returnFields.isHidden = !controller.showsReturnFields
        returnFields.update(fields: [
            ScheduleDateField(SoloTripCopy.returns, .dateAndTime, controller.returnDraft, id: "soloTrip.return") { end in
                Task { await controller.updateReturn(end) }
            },
        ])
        let disabled = controller.returnFieldsDisabled
        returnFields.isUserInteractionEnabled = !disabled
        returnFields.alpha = disabled ? CGFloat(HassTokens.ControlState.disabledOpacity) : 1
        returnError.show(controller.returnError)

        // The status block.
        if let status = controller.status {
            let key = "\(status)|\(controller.restoreDisabled)"
            if key != statusSignature {
                statusSignature = key
                statusSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
                statusSlot.addArrangedSubview(ukSoloTripStatusView(status: status, notice: nil, actionsDisabled: controller.restoreDisabled, surface: surface) { [weak self] action in
                    guard let self else { return }
                    switch action {
                    case .keepCurrent: Task { await self.controller.resolveRestore(.keepCurrent) }
                    case .restoreSaved: Task { await self.controller.resolveRestore(.restoreSaved) }
                    case .endNow: self.askToEnd()
                    }
                })
            }
            statusSlot.isHidden = false
        } else {
            statusSignature = ""
            statusSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
            statusSlot.isHidden = true
        }
        grid.setNeedsLayout()

        // The editor sheet follows `presentation`.
        if controller.editorOpen {
            if editor == nil, let presenter { presentEditor(from: presenter) }
            editorRefresh?()
        } else if let editor, editor.presentingViewController != nil, !editor.isBeingDismissed {
            editor.dismiss(animated: true)
            self.editor = nil
            editorRefresh = nil
        }
    }

    private func refreshTravelers() {
        let tiles = controller.travelerTiles
        let ids = tiles.map(\.resident)
        if ids != travelerOrder {
            travelerOrder = ids
            travelerTiles = [:]
            let views = tiles.map { tile -> UKGlassTileView in
                let view = UKGlassTileView(model: Self.travelerModel(tile), environment: environment)
                travelerTiles[tile.resident] = view
                return view
            }
            travelerGrid.setItems(views)
        }
        for tile in tiles {
            guard let view = travelerTiles[tile.resident] else { continue }
            view.configure(Self.travelerModel(tile), environment: environment, perform: { [weak self] _ in
                if tile.isInteractive { self?.controller.selectTraveler(tile.resident) }
            })
        }
        travelerGrid.setNeedsLayout()
    }

    /// A resident tile: selectable before a trip, then showing Away or Home. One of several, so the **selected face** (rollout lane M, audit
    /// item 29; `SelectionActions.single`): the chosen traveler fills in the Vents family blue (Solo Trip's own blue is not a family) with a
    /// white check disc, the other stays dark with an empty ring, and VoiceOver reads "selected", never "switch". While a trip runs the tiles
    /// lock (the disc dims) and say Away or Home.
    static func travelerModel(_ tile: SoloTripController.TravelerTile) -> UKGlassTileModel {
        let specs = [TravelerTileView.spec(for: tile)]
        return UKGlassTileModel(title: tile.title, subtitle: tile.subtitle, symbol: SymbolMap.symbol(for: tile.icon),
                                family: TravelerTileView.family, isActive: false, behavior: .perform(SelectionActions.actionId), actions: specs.items,
                                identifier: "soloTrip.traveler.\(tile.resident.key)")
    }

    // MARK: Editor

    /// Departure and return for a new Solo Trip (`SoloTripEditorSheet`, web `SoloTripEditorModal`).
    private func presentEditor(from presenter: UIViewController) {
        let controller = controller
        func makeFields() -> [ScheduleDateField] {
            [
                ScheduleDateField(SoloTripCopy.departs, .dateAndTime, controller.scheduleDraft.start, id: "soloTrip.editor.start") {
                    controller.scheduleDraft.start = $0
                }.limited(to: controller.scheduleDraft.end.date()),
                ScheduleDateField(SoloTripCopy.returns, .dateAndTime, controller.scheduleDraft.end, id: "soloTrip.editor.end") {
                    controller.scheduleDraft.end = $0
                }.limited(from: controller.scheduleDraft.start.date()),
            ]
        }
        let description = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
        description.text = SoloTripCopy.editorDescription
        let fields = UKScheduleDateFields(fields: makeFields())
        let alerts = UIStackView.ukColumn(spacing: HassTokens.Spacing.l)
        let confirm = UKAwayButtons.prominent(title: SoloTripCopy.editorConfirm, identifier: "soloTrip.editor.confirm",
                                              isEnabled: !controller.editorConfirmDisabled || controller.isScheduling, isBusy: controller.isScheduling,
                                              busyTitle: SoloTripCopy.editorConfirmBusy) { Task { await controller.confirmSchedule() } }
        let stack = UIStackView.ukColumn([description, fields, alerts, confirm], spacing: HassTokens.Spacing.l)
        let page = UKHouseholdSheetContentController(content: UKHouseholdPaddedView(stack, insets: .ukAll(HassTokens.Spacing.l)))
        page.title = SoloTripCopy.editorTitle
        // A create sheet (direction G, Sheets): circle x Cancel leading drops the draft; the primary button schedules.
        let cancel = UKSheetItems.cancel(identifier: "soloTrip.editor.cancel", isEnabled: !(controller.isScheduling || controller.household.pending)) {
            controller.closeEditor()
        }
        page.navigationItem.leftBarButtonItem = cancel
        var options = UKHassModalOptions(title: SoloTripCopy.editorTitle, fitKey: "soloTrip.editor")
        options.showsClose = false
        options.width = .form
        options.onDismissed = { [weak self] in
            self?.editor = nil
            self?.editorRefresh = nil
            controller.closeEditor()
        }
        let modal = UKHassModalController(root: page, options: options)
        var alertSignature = ""
        editorRefresh = { [weak modal] in
            fields.update(fields: makeFields())
            let scheduling = controller.isScheduling
            fields.isUserInteractionEnabled = !scheduling
            fields.alpha = scheduling ? CGFloat(HassTokens.ControlState.disabledOpacity) : 1
            let messages = controller.editorAlerts
            if messages.joined(separator: "|") != alertSignature {
                alertSignature = messages.joined(separator: "|")
                alerts.arrangedSubviews.forEach { $0.removeFromSuperview() }
                messages.forEach { alerts.addArrangedSubview(UKInlineAlertView($0, severity: .error)) }
                alerts.isHidden = messages.isEmpty
            }
            confirm.isEnabled = !controller.editorConfirmDisabled || scheduling
            confirm.isBusy = scheduling
            cancel.isEnabled = !(scheduling || controller.household.pending)
            modal?.isModalInPresentation = scheduling
        }
        editor = modal
        editorRefresh?()
        modal.present(from: presenter)
    }
}

// MARK: - Screens

#endif
