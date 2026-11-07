import Foundation
import Observation

/// The Solo Trip page's state (web `DashboardViewPage.tsx` `SoloTripPage`).
///
/// The page picks a traveler, schedules a trip in an editor sheet, ends or cancels it from a toggle and
/// moves the return time while it runs. Each command waits for the status sensor to echo the change
/// before the page lets go of it, and the toggle shows "off" optimistically after an end request.
@MainActor
@Observable
public final class SoloTripController {
    // MARK: - Types

    /// One traveler tile.
    public struct TravelerTile: Equatable, Sendable, Identifiable {
        public var resident: HouseholdResident
        public var title: String
        public var subtitle: String?
        /// `mdi:account-arrow-right-outline` (away), `mdi:home-account` (home) or `mdi:account`.
        public var icon: String
        public var isSelected: Bool
        /// Tapping selects or clears the traveler.
        public var isInteractive: Bool
        public var isDisabled: Bool
        public var isMuted: Bool
        public var id: HouseholdResident { resident }
    }

    // MARK: - Dependencies

    /// Sends commands and reads the status sensor.
    public let household: HouseholdAwayController
    /// The signed-in resident, for "You" and the notice's wording.
    public var viewer: HouseholdResident?

    @ObservationIgnored private let toggleOverlay: OptimisticOverlay
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// How long an accepted end keeps the toggle off before falling back to live state; covers the script's
    /// echo waits plus Home Assistant's ending → idle restore (web `SOLO_TRIP_END_OPTIMISTIC_REVERT_MS`).
    public static let endOptimisticRevert: Duration = .seconds(60)
    static let toggleKey = "solo_trip.engaged"

    // MARK: - Page state

    public private(set) var selectedTraveler: HouseholdResident?
    /// The schedule editor sheet is open.
    public var editorOpen = false

    /// The one presentation this page makes, for `sheet(item:)`.
    public enum Presentation: String, Identifiable, Sendable {
        /// The schedule editor.
        case editor
        public var id: String { rawValue }
    }

    /// ``editorOpen`` as an optional presentation: setting it to nil is the person dismissing the sheet, which goes through
    /// ``closeEditor()`` (it stays open while a schedule request is in flight).
    public var presentation: Presentation? {
        get { editorOpen ? .editor : nil }
        set { if newValue == nil { closeEditor() } }
    }
    /// The editor's dates.
    public var scheduleDraft: SoloTripDraft
    /// The return-time fields while a trip is engaged.
    public private(set) var returnDraft = WallClock(date: "", time: "")
    public private(set) var returnDraftDirty = false

    private var scheduleAwaiting: (traveler: HouseholdResident, draft: SoloTripDraft)?
    private var toggleAwaitingSnapshot = false
    private var returnAwaiting: WallClock?
    public private(set) var restoreAwaitingSnapshot = false
    private var previousMode: HouseholdAway.Mode

    // MARK: - Init

    /// Creates the page state.
    /// - Parameters:
    ///   - household: The Household Away controller.
    ///   - scheduler: Runs the toggle's revert timer.
    ///   - now: The clock (tests pin it).
    ///   - calendar: The house's calendar.
    public init(
        household: HouseholdAwayController,
        scheduler: any RevertScheduler = TaskRevertScheduler(),
        now: @escaping @MainActor () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.household = household
        self.now = now
        self.calendar = calendar
        toggleOverlay = OptimisticOverlay(rules: [Self.toggleKey: .confirmation], scheduler: scheduler)
        scheduleDraft = .makeDefault(now: now(), calendar: calendar)
        previousMode = household.snapshot.mode
        reconcile()
        observeLive()
    }

    // MARK: - Derived

    public var snapshot: HouseholdAway.Snapshot { household.snapshot }
    public var isEngaged: Bool { snapshot.isEngaged(.soloTrip) }
    public var isVacationEngaged: Bool { snapshot.isEngaged(.vacation) }

    /// Why scheduling can't happen (web `householdAwaySetupError`). "Setup required" waits out the brief
    /// unavailable status Home Assistant publishes mid-transition (``HouseholdAwayController/setupUnavailable``);
    /// the web showed it for that moment, which read as an error flicker after ending a trip.
    public var setupError: String? {
        if isVacationEngaged { return SoloTripCopy.vacationConflict }
        if household.setupUnavailable { return SoloTripCopy.setupRequired }
        return nil
    }

    /// The toggle's shown value.
    public var toggleChecked: Bool {
        toggleOverlay.displayed(Self.toggleKey, live: liveToggle) == "on"
    }

    private var liveToggle: String { isEngaged ? "on" : "off" }
    private var restoreRequired: Bool { snapshot.state == .restoreRequired }

    /// An accepted end shows the settled off page until Home Assistant confirms or the value reverts.
    public var endPending: Bool { isEngaged && !toggleChecked && !restoreRequired }
    public var presentedEngaged: Bool { isEngaged && !endPending }

    var awaitingCommand: Bool {
        scheduleAwaiting != nil || toggleAwaitingSnapshot || returnAwaiting != nil || restoreAwaitingSnapshot
    }

    var selectionLocked: Bool { editorOpen || scheduleAwaiting != nil || isEngaged || isVacationEngaged }
    /// A schedule request is waiting for the sensor.
    public var isScheduling: Bool { scheduleAwaiting != nil }

    private var knownTraveler: HouseholdResident? {
        endPending ? nil : snapshot.traveler ?? selectedTraveler
    }

    /// The return fields accept changes.
    public var canEditReturn: Bool {
        snapshot.mode == .soloTrip && snapshot.state != .idle && snapshot.state != .ending
            && snapshot.start != nil && snapshot.end != nil && snapshot.canCommand
    }

    /// Show the return-time fields.
    public var showsReturnFields: Bool { !endPending && snapshot.mode == .soloTrip && snapshot.end != nil }
    /// The return fields are disabled.
    public var returnFieldsDisabled: Bool { !canEditReturn || household.pending || returnAwaiting != nil }

    /// The return-time error to show under the fields.
    public var returnError: String? {
        guard returnDraftDirty else { return nil }
        let validation = SoloTripReturnValidation(end: returnDraft, start: snapshot.start, now: now(), calendar: calendar)
        if !validation.endInFuture { return SoloTripCopy.endInFuture }
        if !validation.endAfterStart { return SoloTripCopy.endAfterStart }
        return nil
    }

    public var toggleDisabled: Bool {
        household.pending || awaitingCommand || editorOpen || snapshot.state == .ending || restoreRequired
            || !snapshot.canCommand || isVacationEngaged || (!toggleChecked && selectedTraveler == nil)
    }

    public var toggleSubtitle: String {
        if toggleChecked { return SoloTripCopy.toggleOn }
        if setupError != nil { return household.setupUnavailable ? SoloTripCopy.setupRequiredSubtitle : SoloTripCopy.toggleOff }
        return selectedTraveler != nil ? SoloTripCopy.toggleOff : SoloTripCopy.toggleDisabled
    }

    /// Alex then Sam (web order).
    public var travelerTiles: [TravelerTile] {
        HouseholdResident.allCases.map { resident in
            let selected = knownTraveler == resident
            let home = !endPending && snapshot.homeResident == resident
            let subtitle: String? = if presentedEngaged {
                selected ? SoloTripCopy.travelerAway : home ? SoloTripCopy.travelerHome : nil
            } else {
                selectionLocked && selected ? SoloTripCopy.travelerSelected : nil
            }
            let interactive = !selectionLocked
            return TravelerTile(
                resident: resident,
                title: viewer == resident ? SoloTripCopy.you : resident.name,
                subtitle: subtitle,
                icon: selected ? "mdi:account-arrow-right-outline" : home ? "mdi:home-account" : "mdi:account",
                isSelected: selected,
                isInteractive: interactive,
                isDisabled: !interactive && !endPending,
                isMuted: isVacationEngaged || !selected
            )
        }
    }

    /// The "<Traveler> Away" notice under the page title.
    public var notice: SoloTripNotice? {
        endPending ? nil : SoloTripNotice.make(snapshot: snapshot, viewer: viewer)
    }

    /// The status section below the traveler tiles, while engaged.
    public var status: SoloTripStatus? {
        guard presentedEngaged else { return nil }
        let status = SoloTripStatus.make(snapshot: snapshot, errorCode: household.errorCode, options: .soloTripPage)
        return status.isEmpty ? nil : status
    }

    /// The restore buttons are disabled.
    public var restoreDisabled: Bool {
        restoreAwaitingSnapshot || household.pending || !snapshot.canCommand
    }

    // MARK: - Editor

    /// The editor's alerts, in web order.
    public var editorAlerts: [String] {
        var alerts: [String] = []
        if selectedTraveler == nil { alerts.append(SoloTripCopy.travelerRequired) }
        if !scheduleDraft.endAfterStart(calendar: calendar) { alerts.append(SoloTripCopy.endAfterStart) }
        if let setupError { alerts.append(setupError) }
        else if let error = SoloTripCopy.commandError(household.errorCode) { alerts.append(error) }
        return alerts
    }

    /// The editor's Schedule button is disabled.
    public var editorConfirmDisabled: Bool {
        scheduleAwaiting != nil || household.pending || !scheduleDraft.isValid(traveler: selectedTraveler, calendar: calendar)
    }

    // MARK: - Actions

    /// Selects a traveler, or clears the selection when tapped again.
    public func selectTraveler(_ resident: HouseholdResident) {
        guard !selectionLocked else { return }
        household.clearError()
        selectedTraveler = selectedTraveler == resident ? nil : resident
    }

    /// Opens the schedule editor with fresh default dates.
    public func openEditor() {
        guard selectedTraveler != nil, setupError == nil, !household.pending, !awaitingCommand else { return }
        household.clearError()
        scheduleDraft = .makeDefault(now: now(), calendar: calendar)
        editorOpen = true
    }

    /// Closes the editor unless a schedule request is in flight.
    public func closeEditor() {
        guard !household.pending, scheduleAwaiting == nil else { return }
        household.clearError()
        scheduleDraft = .makeDefault(now: now(), calendar: calendar)
        editorOpen = false
    }

    /// The toggle: off opens the editor; on cancels a scheduled trip or ends a running one.
    public func toggle() async {
        guard !household.pending, !awaitingCommand else { return }
        household.clearError()
        guard toggleChecked else {
            openEditor()
            return
        }
        guard snapshot.canCommand, [.scheduled, .activating, .active, .degraded].contains(snapshot.state) else { return }
        toggleOverlay.commit(Self.toggleKey, value: "off", live: liveToggle, revertAfter: Self.endOptimisticRevert)
        selectedTraveler = nil
        returnDraftDirty = false
        let result = snapshot.state == .scheduled ? await household.cancel() : await household.endNow()
        if case .rejected = result {} else { toggleAwaitingSnapshot = true }
        if case .accepted = result {} else { toggleOverlay.reset(Self.toggleKey) }
        reconcile()
    }

    /// Sends the editor's schedule.
    public func confirmSchedule() async {
        guard let traveler = selectedTraveler, setupError == nil, !household.pending, scheduleAwaiting == nil else { return }
        let draft = scheduleDraft
        guard draft.isValid(traveler: traveler, calendar: calendar) else { return }
        let result = await household.scheduleSoloTrip(traveler: traveler, draft: draft)
        if case .rejected = result {} else { scheduleAwaiting = (traveler, draft) }
        reconcile()
    }

    /// Changes the return date or time; a valid change is sent at once.
    public func updateReturn(_ end: WallClock) async {
        guard canEditReturn, !household.pending, returnAwaiting == nil else { return }
        household.clearError()
        returnDraft = end
        returnDraftDirty = true
        guard SoloTripReturnValidation(end: end, start: snapshot.start, now: now(), calendar: calendar).isValid else { return }
        if end == snapshot.end {
            returnDraftDirty = false
            return
        }
        let result = await household.updateEnd(end)
        if case .rejected = result {} else { returnAwaiting = end }
        reconcile()
    }

    /// Resolves a `restore_required` plan.
    public func resolveRestore(_ action: HouseholdAway.ResolveAction) async {
        guard !household.pending, !awaitingCommand, restoreRequired, snapshot.canCommand else { return }
        household.clearError()
        let result = await household.resolveRestore(action)
        if case .rejected = result {} else { restoreAwaitingSnapshot = true }
        reconcile()
    }

    // MARK: - Reconciling with live state

    /// Applies what the latest sensor value confirms (the web does this during render).
    func reconcile() {
        let snapshot = self.snapshot
        toggleOverlay.liveChanged(Self.toggleKey, to: liveToggle)
        if restoreRequired { toggleOverlay.reset(Self.toggleKey) }

        if previousMode != snapshot.mode {
            if previousMode == .soloTrip, !editorOpen, scheduleAwaiting == nil {
                selectedTraveler = nil
                returnDraftDirty = false
            }
            previousMode = snapshot.mode
        }

        if !endPending, snapshot.mode == .soloTrip, let traveler = snapshot.traveler, selectedTraveler != traveler {
            selectedTraveler = traveler
        }

        if let awaiting = scheduleAwaiting, snapshot.mode == .soloTrip, snapshot.traveler == awaiting.traveler,
           snapshot.start == awaiting.draft.start, snapshot.end == awaiting.draft.end {
            scheduleAwaiting = nil
            editorOpen = false
            scheduleDraft = .makeDefault(now: now(), calendar: calendar)
        }

        if toggleAwaitingSnapshot, snapshot.mode != .soloTrip || snapshot.state == .idle {
            toggleAwaitingSnapshot = false
        }

        if let awaiting = returnAwaiting, snapshot.end == awaiting {
            returnAwaiting = nil
            returnDraftDirty = false
        }

        if restoreAwaitingSnapshot, !restoreRequired { restoreAwaitingSnapshot = false }

        if !returnDraftDirty, returnAwaiting == nil, let end = snapshot.end, returnDraft != end {
            returnDraft = end
        }
    }

    private func observeLive() {
        withObservationTracking {
            _ = household.store.entity(HouseholdAway.statusEntityId).state
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.reconcile()
                self?.observeLive()
            }
        }
    }
}
