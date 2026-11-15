import Foundation
import Observation

/// The Vacation Mode page's state (web `DashboardViewPage.tsx` `VacationModePage`, `VacationModeCard`,
/// `VacationChecklistSection`, `VacationDateControls`).
///
/// Enabling needs every checklist task done, then asks for dates in a confirmation sheet. While enabled the
/// page shows the dates inline (each change saves at once); disabling resets the checklist. If Home
/// Assistant paused the vacation for invalid dates, fixing them re-enables it.
@MainActor
@Observable
public final class VacationModeController {
    // MARK: - Dependencies

    public let store: EntityStore
    /// Household Away, for a backend vacation plan and the Solo Trip conflict.
    public let household: HouseholdAwayController

    /// Explicit helper targets, or the legacy house configuration for existing feature callers.
    public let targets: Vacation.Targets?
    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let overlay: OptimisticOverlay
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// How long a tapped toggle or checkbox shows its new value without an echo (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public static let optimisticRevert: Duration = .seconds(2)

    // MARK: - Page state

    /// The enable was refused because the checklist isn't done.
    public private(set) var blockedEnableAttempted = false
    /// Dates being confirmed; non-nil while the confirmation sheet is open.
    public private(set) var pendingRange: Vacation.DateRange?
    /// Dates just confirmed, shown until both helpers echo them. Without it the inline dates showed the
    /// previous vacation's helpers (often an end before the new start) and flashed the range error.
    public private(set) var confirmedRange: Vacation.DateRange?
    /// The turn-off alert is showing.
    public private(set) var isConfirmingDisable = false
    /// At least one ordered helper batch has not finished.
    public private(set) var pendingBatches = 0
    /// A helper call failed; the remainder of that batch was not sent.
    public private(set) var commandFailed = false
    @ObservationIgnored private var confirmedRangeTimer: Task<Void, Never>?

    /// How long confirmed dates wait for the helpers' echo before the live values win again.
    public static let confirmedRangeRevert: Duration = .seconds(10)

    // MARK: - Init

    /// Creates the page state.
    public init(
        store: EntityStore,
        household: HouseholdAwayController,
        caller: any HassServiceCalling,
        targets: Vacation.Targets? = nil,
        scheduler: any RevertScheduler = TaskRevertScheduler(),
        now: @escaping @MainActor () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.household = household
        self.caller = caller
        self.targets = targets
        self.now = now
        self.calendar = calendar
        var rules: [String: OptimisticOverlay.ClearRule] = [targets?.modeEntityId ?? Vacation.modeEntityId: .liveChange]
        for item in targets?.checklist ?? Vacation.checklist { rules[item.entityId] = .liveChange }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading

    private func live(_ entityId: String) -> String? { store.entity(entityId).state?.state }
    private func displayed(_ entityId: String) -> String? { overlay.displayed(entityId, live: live(entityId)) }
    private var modeId: String { targets?.modeEntityId ?? Vacation.modeEntityId }
    private var invalidDatesId: String { targets?.invalidDatesPendingEntityId ?? Vacation.invalidDatesPendingEntityId }
    private var startId: String { targets?.startEntityId ?? Vacation.startEntityId }
    private var endId: String { targets?.endEntityId ?? Vacation.endEntityId }
    /// Checklist order and labels supplied by the source.
    public var checklist: [Vacation.ChecklistItem] { targets?.checklist ?? Vacation.checklist }
    /// Drafts, confirmations and running commands must survive a publication update.
    public var hasPendingInteraction: Bool {
        isConfirming || isConfirmingDisable || pendingBatches > 0 || household.pending
            || confirmedRange != nil || !overlay.pending.isEmpty
    }

    /// The mode entity is missing, unavailable or unknown.
    public var modeUnavailable: Bool {
        guard let state = live(modeId) else { return true }
        return state == "unavailable" || state == "unknown"
    }

    /// The mode shows on (optimistically).
    public var modeOn: Bool { displayed(modeId) == "on" }

    /// The confirmation sheet is open.
    public var isConfirming: Bool { pendingRange != nil }

    /// The helpers' saved range.
    public var savedRange: Vacation.DateRange {
        Vacation.DateRange(startState: live(startId), endState: live(endId), now: now(), calendar: calendar)
    }

    /// The range shown: the sheet's draft while confirming, the just-confirmed dates until they echo, else the saved one.
    public var dateRange: Vacation.DateRange { pendingRange ?? confirmedRange ?? savedRange }

    /// Start is not before end.
    public var invalidDateRange: Bool {
        dateRange.start.date(in: calendar) == nil || dateRange.end.date(in: calendar) == nil
            || dateRange.isInvalid(calendar: calendar)
    }

    /// Home Assistant paused the vacation for invalid dates (or they are invalid now).
    public var recoveringInvalidDates: Bool {
        !isConfirming && (invalidDateRange || live(invalidDatesId) == "on")
    }

    /// A backend Household Away vacation is engaged.
    public var backendVacationEngaged: Bool { household.snapshot.isEngaged(.vacation) }

    /// The card shows enabled.
    public var cardEnabled: Bool { modeOn || recoveringInvalidDates || backendVacationEngaged }

    /// Show the dates instead of the checklist.
    public var showsInlineDates: Bool { cardEnabled }

    /// A Solo Trip owns the plan; the page shows its status instead.
    public var soloTripEngaged: Bool { household.snapshot.mode == .soloTrip }

    /// A checklist task is done (optimistically).
    public func isChecked(_ item: Vacation.ChecklistItem) -> Bool { displayed(item.entityId) == "on" }

    /// A checklist task can't be changed.
    public func isUnavailable(_ item: Vacation.ChecklistItem) -> Bool {
        let state = displayed(item.entityId) ?? "unavailable"
        return state == "unavailable" || state == "unknown"
    }

    /// Every checklist task is done.
    public var checklistComplete: Bool { !checklist.isEmpty && checklist.allSatisfy(isChecked) }

    /// Show the "finish the checklist" error.
    public var showsPreChecklistError: Bool {
        blockedEnableAttempted && !checklistComplete && !showsInlineDates && !isConfirming
    }

    /// The card can't be tapped.
    public var cardDisabled: Bool {
        modeUnavailable || household.pending || (recoveringInvalidDates && invalidDateRange)
    }

    /// The card subtitle (web `formatCompactEntityState`).
    public var cardSubtitle: String {
        if isConfirming { return Vacation.Copy.pending }
        if modeUnavailable { return Vacation.Copy.unavailable }
        return cardEnabled ? Vacation.Copy.on : Vacation.Copy.off
    }

    /// What tapping the card does, for VoiceOver.
    public var cardAccessibilityHint: String {
        if cardOpensSheet { return "Asks for the vacation dates." }
        return cardEnabled && !cardDisabled ? "Asks before turning Vacation Mode off." : ""
    }

    /// The card leads to the confirmation sheet.
    public var cardOpensSheet: Bool { !cardDisabled && !cardEnabled && !isConfirming && checklistComplete }

    // MARK: - Actions

    /// Taps the Vacation Mode card (web `toggleVacationMode`). Turning an engaged vacation off asks first
    /// (owner, 2026-10-13; HIG Alerts: confirm a destructive action).
    public func tapCard() {
        guard !cardDisabled else { return }
        if cardEnabled {
            pendingRange = nil
            isConfirmingDisable = true
            return
        }
        if isConfirming {
            pendingRange = nil
            return
        }
        guard checklistComplete else {
            blockedEnableAttempted = true
            return
        }
        pendingRange = .makeDefault(now: now(), calendar: calendar)
        blockedEnableAttempted = false
    }

    /// Turns the vacation off after the alert's Turn Off. Doesn't depend on ``isConfirmingDisable``: SwiftUI may
    /// clear the alert's binding before or after it runs the button's action.
    public func confirmDisable() {
        isConfirmingDisable = false
        guard cardEnabled, !cardDisabled, !soloTripEngaged else { return }
        confirmedRange = nil
        overlay.commit(modeId, value: "off", live: live(modeId), revertAfter: Self.optimisticRevert)
        send(Vacation.disableCalls(targets: targets))
    }

    /// Dismisses the turn-off alert, leaving the vacation on.
    public func cancelDisable() { isConfirmingDisable = false }

    /// Checks or unchecks a task.
    public func toggle(_ item: Vacation.ChecklistItem) {
        guard checklist.contains(item), !isUnavailable(item) else { return }
        let checked = isChecked(item)
        overlay.commit(item.entityId, value: checked ? "off" : "on", live: live(item.entityId), revertAfter: Self.optimisticRevert)
        if checklistComplete { blockedEnableAttempted = false }
        send([Vacation.setBoolean(item.entityId, on: !checked)])
    }

    /// Changes the sheet's draft.
    public func updatePendingRange(_ range: Vacation.DateRange) {
        guard isConfirming else { return }
        pendingRange = range
    }

    /// Closes the confirmation sheet without enabling.
    public func cancelConfirmation() { pendingRange = nil }

    /// Saves the sheet's dates and enables the mode.
    public func confirm() {
        guard let range = pendingRange, range.start.date(in: calendar) != nil, range.end.date(in: calendar) != nil,
              !range.isInvalid(calendar: calendar),
              checklistComplete, !modeUnavailable, !household.pending, !soloTripEngaged, !cardEnabled else { return }
        send(Vacation.confirmCalls(range, targets: targets))
        confirmedRange = range
        scheduleConfirmedRangeRevert()
        pendingRange = nil
        blockedEnableAttempted = false
        overlay.commit(modeId, value: "on", live: live(modeId), revertAfter: Self.optimisticRevert)
    }

    /// Saves one inline date change; a fix to paused dates re-enables the vacation.
    /// - Parameters:
    ///   - range: The range after the change.
    ///   - changedEnd: The end changed (else the start).
    public func updateSavedRange(_ range: Vacation.DateRange, changedEnd: Bool) {
        guard range.start.date(in: calendar) != nil, range.end.date(in: calendar) != nil else { return }
        let recovering = recoveringInvalidDates
        // Show the edited range until it echoes, so the untouched side doesn't fall back to a stale helper.
        confirmedRange = range
        scheduleConfirmedRangeRevert()
        var calls = [changedEnd
            ? Vacation.setDateTime(endId, range.end)
            : Vacation.setDateTime(startId, range.start)]
        if recovering, !range.isInvalid(calendar: calendar), range.isFuture(now: now(), calendar: calendar) {
            calls += Vacation.recoveryCalls(targets: targets)
        }
        send(calls)
    }

    // MARK: - Private

    @ObservationIgnored private var lastSend: Task<Void, Never>?

    /// Clears the displayed transport failure after the user acknowledges it.
    public func clearCommandError() { commandFailed = false }

    /// Sends calls in order after any earlier batch; never enables after a failed date write.
    private func send(_ calls: [ServiceCall]) {
        let previous = lastSend
        let caller = caller
        if pendingBatches == 0 { commandFailed = false }
        pendingBatches += 1
        lastSend = Task { @MainActor [self] in
            await previous?.value
            defer { pendingBatches -= 1 }
            for call in calls {
                do { try await caller.call(call) }
                catch {
                    commandFailed = true
                    break
                }
            }
        }
    }

    /// Waits for every sent call (tests).
    func drain() async { await lastSend?.value }

    private func liveDidChange() {
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: live(key)) }
        if let confirmedRange, savedRange == confirmedRange { self.confirmedRange = nil }
    }

    private func scheduleConfirmedRangeRevert() {
        confirmedRangeTimer?.cancel()
        confirmedRangeTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.confirmedRangeRevert)
            guard !Task.isCancelled else { return }
            self?.confirmedRange = nil
        }
    }

    private func observeLive() {
        withObservationTracking {
            for id in targets?.pageEntityIds ?? Vacation.pageEntityIds { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}
