#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Canonical away models

/// One shared plan and its real command/echo lifetimes. Models must use explicit validated targets.
@MainActor
@Observable
final class UKServerUIAwayProvider: UKServerUISettingsProvider {
    let definition: ServerUISettingsSource
    let vacation: VacationModeController
    let solo: SoloTripController
    private let current: () -> Bool
    private let residents: [String: HouseholdResident]
    private var running = false
    private var confirming = false
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { running || confirming || vacation.hasPendingInteraction || solo.hasPendingInteraction }
    var blocksExit: Bool { running || confirming || vacation.isConfirming || vacation.pendingBatches > 0
        || solo.editorOpen || solo.isScheduling || solo.returnDraftDirty || solo.household.pending }
    var canDiscard: Bool { !running && !confirming && vacation.pendingBatches == 0
        && solo.canDiscardDrafts }

    init(id: String, vacation: VacationModeController, solo: SoloTripController,
         residents: [String: HouseholdResident], isCurrentSession: @escaping () -> Bool) throws {
        guard vacation.household === solo.household, vacation.targets != nil else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        definition = .init(providerId: id, domain: .away)
        self.vacation = vacation
        self.solo = solo
        self.residents = residents
        current = isCurrentSession
    }

    /// Projections share the exact models used by the controls and their exit guards.
    func addPresentations(to records: inout UKServerUIRecords) throws {
        guard let targets = vacation.targets, records.tabScopes["away-route"] == nil,
              ["away-mode", "away-checklist", "away-dates", "away-travelers"].allSatisfy({ records.sections[$0] == nil }),
              ["modal-vacation-confirm-cancel", "modal-solo-editor-cancel"].allSatisfy({ records.actionStates[$0] == nil }) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        records.tabScopes["away-route"] = .init(allowedTabIDs: ["chooser", "vacation", "solo"], initialTabID: "chooser",
            automaticSelection: { [vacation] in
                switch Vacation.route(snapshot: vacation.household.snapshot,
                                      vacationModeOn: vacation.store.entity(targets.modeEntityId).state?.state == "on",
                                      invalidDatesPending: vacation.store.entity(targets.invalidDatesPendingEntityId).state?.state == "on") {
                case .chooser: "chooser"
                case .vacationMode: "vacation"
                case .soloTrip: "solo"
                }
            })
        records.sections["away-mode"] = { [vacation] in .init(visible: !vacation.soloTripEngaged) }
        records.sections["away-checklist"] = { [vacation] in
            let done = vacation.checklist.filter(vacation.isChecked).count
            return .init(header: "\(Vacation.Copy.checklistTitle) · \(done) of \(vacation.checklist.count)",
                         visible: !vacation.showsInlineDates && !vacation.soloTripEngaged)
        }
        records.sections["away-dates"] = { [vacation] in .init(visible: vacation.showsInlineDates && !vacation.soloTripEngaged) }
        records.sections["away-travelers"] = { .init() }
        records.actionStates["modal-vacation-confirm-cancel"] = { [weak self] in
            .init(enabled: self?.isCurrentSession == true && self?.canDiscard == true)
        }
        records.actionStates["modal-solo-editor-cancel"] = { [weak self] in
            .init(enabled: self?.isCurrentSession == true && self?.canDiscard == true)
        }
    }

    func discard() {
        guard canDiscard else { return }
        vacation.cancelConfirmation()
        solo.discardDrafts()
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        guard control.kind.domain == .away else { return false }
        switch control.kind {
        case .vacationCheck: return vacation.checklist.contains { $0.entityId == control.item }
        case .soloTraveler: return residents[control.item] != nil
        case .awayRestore: return HouseholdAway.ResolveAction(rawValue: control.item) != nil
        default: return true
        }
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        guard accepts(control) else { throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources") }
        switch control.kind {
        case .vacationDates, .soloDates, .soloReturn: return dateFields(control, host: host, page: page)
        case .vacationCheck:
            guard let item = vacation.checklist.first(where: { $0.entityId == control.item }) else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            let row = UKVacationChecklistRow(title: control.node.title) { [weak self, weak host, weak page] in
                guard let self, let host, let page else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    guard !self.vacation.showsInlineDates, !self.solo.isVacationEngaged else {
                        throw HouseholdSettingsTarget.Failure.stale
                    }
                    self.vacation.toggle(item)
                }
            }
            host.bag.observe { [weak self, weak row, weak host] in
                guard let self else { return }
                row?.update(isChecked: self.vacation.isChecked(item), isUnavailable: !self.isCurrentSession
                            || self.vacation.isUnavailable(item) || self.vacation.showsInlineDates)
                host?.isHidden = self.vacation.showsInlineDates || self.vacation.soloTripEngaged
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return row
        case .vacationStatus, .awayStatus:
            if control.kind == .awayStatus { return status(host: host, page: page) }
            let label = UILabel.uk(.body, ink: UKDesignInk.primary)
            label.numberOfLines = 0
            host.bag.observe { [weak self, weak label, weak host] in
                guard let self else { return }
                let message: String
                if control.kind == .vacationStatus {
                    message = self.vacation.commandFailed ? "Couldn't save the vacation. Try again."
                        : self.vacation.showsPreChecklistError ? Vacation.Copy.preChecklistError
                        : self.vacation.soloTripEngaged ? SoloTripCopy.vacationConflict : self.vacation.cardSubtitle
                } else {
                    message = self.solo.setupError ?? SoloTripCopy.commandError(self.solo.household.errorCode)
                        ?? self.solo.toggleSubtitle
                }
                label?.text = [control.node.title, control.subtitle, message].filter { !$0.isEmpty }.joined(separator: "\n")
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return label
        default: return action(control, host: host, page: page)
        }
    }

    private func status(host: UKServerUISettingsAtom, page: UKServerUIPage) -> UIView {
        let slot = UIStackView.ukColumn(spacing: HassTokens.Spacing.m)
        var signature = ""
        host.bag.observe { [weak self, weak slot, weak host, weak page] in
            guard let self, let slot, let host, let page else { return }
            let status = self.solo.status
            let notice = self.solo.notice
            let disabled = self.running || self.solo.restoreDisabled || !self.isCurrentSession
            let errors = ([self.solo.setupError, self.solo.returnError].compactMap { $0 }
                          + (self.solo.editorOpen ? self.solo.editorAlerts : [])).reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
            let key = "\(String(describing: status))|\(String(describing: notice))|\(disabled)|\(errors)"
            guard key != signature else { return }
            signature = key
            slot.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for error in errors { slot.addArrangedSubview(UKInlineAlertView(error, severity: .error)) }
            if let notice { slot.addArrangedSubview(ukSoloTripNoticeBox(notice)) }
            if let status {
                let expected = self.solo.snapshot
                slot.addArrangedSubview(ukSoloTripStatusView(status: status, notice: nil, actionsDisabled: disabled,
                                                            surface: page.context.surface) { [weak self, weak host, weak page] action in
                    guard let self, let host, let page else { return }
                    host.perform(from: page) {
                        try self.requireCurrent()
                        guard self.solo.snapshot == expected else { throw HouseholdSettingsTarget.Failure.stale }
                        switch action {
                        case .keepCurrent: self.run(from: page) { await self.solo.resolveRestore(.keepCurrent) }
                        case .restoreSaved: self.run(from: page) { await self.solo.resolveRestore(.restoreSaved) }
                        case .endNow:
                            self.confirming = true
                            UKAlerts.alert(AlertCopy.endSoloTrip, from: page, onCancel: { [weak self] in self?.confirming = false }) { [weak self] in
                                guard let self else { return }
                                defer { self.confirming = false }
                                host.perform(from: page) {
                                    try self.requireCurrent()
                                    guard self.solo.snapshot == expected else { throw HouseholdSettingsTarget.Failure.stale }
                                    self.run(from: page) { await self.solo.toggle() }
                                }
                            }
                        }
                    }
                })
            }
            host.isHidden = slot.arrangedSubviews.isEmpty
            host.ukRemeasureContainers(includingSelf: true)
        }
        return slot
    }

    private func action(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) -> UIView {
        let row = UKGroupedRowButton(title: control.node.title, symbol: control.icon.drawn, identifier: control.node.id)
        var submitted = false
        var wasEditorOpen = solo.editorOpen
        row.hint = control.subtitle
        row.onTap = { [weak self, weak host, weak page] in
            guard let self, let host, let page else { return }
            host.perform(from: page) {
                try self.requireCurrent()
                switch control.kind {
                case .soloTraveler:
                    guard let resident = self.residents[control.item] else { throw HouseholdSettingsTarget.Failure.invalidTarget }
                    self.solo.selectTraveler(resident)
                case .vacationToggle:
                    self.vacation.tapCard()
                    if self.vacation.isConfirming, let destination = control.destination {
                        do { try page.renderer?.perform(destination, from: page, source: host) }
                        catch { self.vacation.cancelConfirmation(); throw error }
                    } else if self.vacation.isConfirmingDisable {
                        self.confirming = true
                        let spec = AlertCopy.turnOffVacation
                        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .default) { [weak self] _ in
                            guard let self else { return }
                            defer { self.confirming = false }
                            host.perform(from: page) { try self.requireCurrent(); self.vacation.confirmDisable() }
                        })
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                            self?.confirming = false; self?.vacation.cancelDisable()
                        })
                        page.present(alert, animated: true)
                    }
                case .vacationConfirm:
                    guard self.vacation.isConfirming, !self.vacation.invalidDateRange,
                          self.vacation.checklistComplete, !self.solo.household.pending else {
                        throw HouseholdSettingsTarget.Failure.stale
                    }
                    submitted = true
                    self.vacation.confirm()
                case .soloToggle:
                    if !self.solo.toggleChecked {
                        self.solo.openEditor()
                        if self.solo.editorOpen, let destination = control.destination {
                            do { try page.renderer?.perform(destination, from: page, source: host) }
                            catch { self.solo.closeEditor(); throw error }
                        }
                    } else {
                        let expected = self.solo.snapshot
                        let spec = AlertCopy.endSoloTrip
                        self.confirming = true
                        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: spec.confirm.title, style: .destructive) { [weak self] _ in
                            guard let self else { return }
                            defer { self.confirming = false }
                            host.perform(from: page) {
                                try self.requireCurrent()
                                guard self.solo.snapshot == expected else { throw HouseholdSettingsTarget.Failure.stale }
                                self.run(from: page) { await self.solo.toggle() }
                            }
                        })
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.confirming = false })
                        page.present(alert, animated: true)
                    }
                case .soloConfirm: self.run(from: page) { await self.solo.confirmSchedule() }
                case .awayRestore:
                    guard let action = HouseholdAway.ResolveAction(rawValue: control.item) else { throw HouseholdSettingsTarget.Failure.invalidTarget }
                    self.run(from: page) { await self.solo.resolveRestore(action) }
                default: throw HouseholdSettingsTarget.Failure.invalidTarget
                }
            }
        }
        host.bag.observe { [weak self, weak row, weak host, weak page] in
            guard let self, let row else { return }
            var enabled = !self.running && self.isCurrentSession
            switch control.kind {
            case .vacationToggle:
                row.value = self.vacation.cardSubtitle
                enabled = enabled && !self.vacation.cardDisabled && !self.vacation.soloTripEngaged
                host?.isHidden = self.vacation.soloTripEngaged
            case .vacationConfirm:
                enabled = enabled && self.vacation.isConfirming && !self.vacation.invalidDateRange
                    && self.vacation.checklistComplete && !self.solo.household.pending
            case .soloToggle:
                row.value = self.solo.toggleSubtitle
                enabled = enabled && !self.solo.toggleDisabled
            case .soloConfirm: enabled = enabled && !self.solo.editorConfirmDisabled
            case .soloTraveler:
                if let tile = self.solo.travelerTiles.first(where: { $0.resident == self.residents[control.item] }) {
                    row.value = tile.subtitle ?? ""
                    row.accessibilityTraits = tile.isSelected ? [.button, .selected] : .button
                    enabled = enabled && tile.isInteractive && !tile.isDisabled
                } else { enabled = false }
            case .awayRestore:
                enabled = enabled && self.solo.snapshot.state == .restoreRequired && !self.solo.restoreDisabled
                host?.isHidden = self.solo.snapshot.state != .restoreRequired
            default: break
            }
            row.isEnabled = enabled
            host?.ukRemeasureContainers(includingSelf: true)
            page?.renderer?.updateSettingsExitGuard()
            if control.kind == .vacationConfirm {
                if self.vacation.pendingBatches > 0 { submitted = true }
                if submitted, self.vacation.pendingBatches == 0, !self.vacation.commandFailed {
                    submitted = false
                    if let page { page.renderer?.activate(.dismiss(scope: .currentModal), from: page) }
                }
            }
            if control.kind == .soloConfirm, wasEditorOpen, !self.solo.editorOpen {
                wasEditorOpen = false
                if let page { page.renderer?.activate(.dismiss(scope: .currentModal), from: page) }
            }
        }
        func tileModel() -> UKGlassTileModel? {
            var model: UKGlassTileModel
            switch control.kind {
            case .vacationToggle: model = UKVacationModeContent.modeModel(vacation)
            case .soloToggle: model = UKSoloTripContent.toggleModel(solo)
            case .soloTraveler:
                guard let tile = solo.travelerTiles.first(where: { $0.resident == residents[control.item] }) else { return nil }
                model = UKSoloTripContent.travelerModel(tile)
            default: return nil
            }
            model.title = control.node.title
            model.identifier = control.node.id
            return model
        }
        if let model = tileModel() {
            let tap = row.onTap
            let tile = UKGlassTileView(model: model, environment: UKTileEnvironment(context: page.context))
            host.bag.observe { [weak tile, weak host, weak page] in
                guard let tile, let page, let model = tileModel() else { return }
                tile.configure(model, environment: UKTileEnvironment(context: page.context), perform: { _ in tap?() })
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return tile
        }
        return row
    }

    private func run(from page: UKServerUIPage, _ operation: @escaping @MainActor () async -> Void) {
        guard !running else { return }
        running = true
        Task { [self, weak page] in
            defer { running = false }
            guard isCurrentSession else {
                page?.renderer?.onError(.init(code: .interactionBlocked, pointer: "/document/dataSources"))
                return
            }
            await operation()
        }
    }

    private func dateFields(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) -> UIView {
        if control.kind == .soloReturn {
            func value() -> [ScheduleDateField] {
                [ScheduleDateField(control.node.title, .dateAndTime, solo.returnDraft, id: control.node.id) { [weak self, weak host, weak page] end in
                    guard let self, let host, let page else { return }
                    host.perform(from: page) {
                        try self.requireCurrent()
                        self.run(from: page) { await self.solo.updateReturn(end) }
                    }
                }.limited(from: solo.snapshot.start?.date())]
            }
            let fields = UKScheduleDateFields(fields: value(), commitDelay: .milliseconds(900))
            host.bag.observe { [weak self, weak fields, weak host] in
                guard let self else { return }
                fields?.update(fields: value())
                fields?.isUserInteractionEnabled = self.isCurrentSession && !self.running && !self.solo.returnFieldsDisabled
                host?.isHidden = !self.solo.showsReturnFields
                host?.ukRemeasureContainers(includingSelf: true)
            }
            return fields
        }
        func range() -> Vacation.DateRange {
            control.kind == .vacationDates ? vacation.dateRange
                : .init(start: solo.scheduleDraft.start, end: control.kind == .soloReturn ? solo.returnDraft : solo.scheduleDraft.end)
        }
        let fields = UKVacationDateFieldsView(range: range(), invalid: false, identifierPrefix: control.node.id,
                                              commitDelay: control.kind == .vacationDates && !page.isSheet ? .milliseconds(900) : nil,
                                              description: control.subtitle) { [weak self, weak host, weak page] range, end in
            guard let self, let host, let page else { return }
            host.perform(from: page) {
                try self.requireCurrent()
                switch control.kind {
                case .vacationDates:
                    if self.vacation.isConfirming { self.vacation.updatePendingRange(range) }
                    else if self.vacation.showsInlineDates { self.vacation.updateSavedRange(range, changedEnd: end) }
                    else { throw HouseholdSettingsTarget.Failure.stale }
                case .soloDates:
                    guard self.solo.editorOpen, !self.solo.isScheduling, !self.solo.household.pending else { throw HouseholdSettingsTarget.Failure.stale }
                    self.solo.scheduleDraft = .init(start: range.start, end: range.end)
                case .soloReturn:
                    guard end else { throw HouseholdSettingsTarget.Failure.invalidTarget }
                    self.run(from: page) { await self.solo.updateReturn(range.end) }
                default: throw HouseholdSettingsTarget.Failure.invalidTarget
                }
            }
        }
        host.bag.observe { [weak self, weak fields, weak host, weak page] in
            guard let self else { return }
            fields?.update(range: range(), invalid: control.kind == .vacationDates ? self.vacation.invalidDateRange
                           : control.kind == .soloReturn ? self.solo.returnError != nil : !self.solo.scheduleDraft.endAfterStart())
            fields?.isUserInteractionEnabled = self.isCurrentSession && !self.running && !self.solo.household.pending
                && (control.kind == .vacationDates ? self.vacation.isConfirming || self.vacation.showsInlineDates
                    : control.kind == .soloReturn ? !self.solo.returnFieldsDisabled : self.solo.editorOpen && !self.solo.isScheduling)
            host?.isHidden = control.kind == .vacationDates
                ? !self.vacation.isConfirming && !self.vacation.showsInlineDates : !self.solo.editorOpen
            host?.ukRemeasureContainers(includingSelf: true)
            page?.renderer?.updateSettingsExitGuard()
        }
        return fields
    }
}
#endif
