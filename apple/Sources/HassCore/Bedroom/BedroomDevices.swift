import Foundation
import Observation

/// The Master Bedroom's wake light and both bed sides together, so a wake alarm can add bed alarms and a bed
/// alarm can turn its wake-light link on (web `WakeLightModalWithBedAlarms`, `useWakeLightBedProvisioning`).
@MainActor
@Observable
public final class BedroomDevices {
    public let wakeLight: WakeLightController
    public let beds: [BedSideController]

    /// Creates the room's controllers on one store and caller.
    public init(store: EntityStore, caller: any HassServiceResponding, canEdit: Bool = true,
                scheduler: any RevertScheduler = TaskRevertScheduler(),
                requestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }) {
        wakeLight = WakeLightController(config: MasterBedroom.wakeLight, store: store, caller: caller, canEdit: canEdit,
                                        scheduler: scheduler, requestId: requestId)
        beds = MasterBedroom.beds.map {
            BedSideController(config: $0, store: store, caller: caller, scheduler: scheduler, requestId: requestId)
        }
    }

    /// The controller for `side`.
    public func bed(_ side: BedSide) -> BedSideController { beds.first { $0.config.side == side }! }

    /// The bed a wake-light source mirrors (`sleepypod:left` → Alex's Bed).
    public func bed(source: String) -> BedSideController? {
        wakeLight.config.source(id: source).map { bed($0.side) }
    }

    // MARK: - "Add to <bed>"

    /// A bed the wake-light editor can add alarms to.
    public struct BedTarget: Identifiable, Equatable, Sendable {
        public var side: BedSide
        /// `Alex's Bed`, or `Alex's Bed · Whole Bed` during a Solo Trip.
        public var title: String
        /// The side has an alarm schedule and isn't the traveler's.
        public var available: Bool
        public var id: BedSide { side }
    }

    /// The "Add to <bed>" toggles, in source order.
    public var bedTargets: [BedTarget] {
        wakeLight.config.sources.map { source in
            let bed = bed(source.side)
            return BedTarget(side: source.side, title: bed.title, available: bed.alarmsAvailable && !bed.scope.readOnly)
        }
    }

    /// Saves a wake alarm, then, for a new weekly alarm, brings each bed in line with its toggle: creating missing
    /// bed alarms and turning links on, or turning existing links off (web `save` + `applyBedTargets`). A one-time
    /// alarm carries the chosen sides in `bed_sides` instead.
    @discardableResult
    public func saveWakeAlarm(_ draft: WakeLight.Alarm, isNew: Bool, addToBeds: Set<BedSide>) async -> Bool {
        var saved = draft
        saved.label = draft.label.trimmingCharacters(in: .whitespaces)
        saved.bedSides = draft.kind == .once && isNew ? bedTargets.map(\.side).filter(addToBeds.contains) : (isNew ? [] : draft.bedSides)
        guard await wakeLight.save(saved) else { return false }
        guard isNew, saved.kind == .weekly else { return true }
        for target in bedTargets where target.available {
            guard let source = wakeLight.config.source(for: target.side) else { continue }
            let bed = bed(target.side)
            guard let plan = BedAlarmProvisioning.plan(snapshot: wakeLight.snapshot, days: saved.weekdays, linked: addToBeds.contains(target.side),
                                                       alarms: bed.sourceAlarms, source: source.id, time: saved.localTime),
                  !plan.isEmpty else { continue }
            if !plan.createDays.isEmpty { bed.createAlarms(days: plan.createDays, time: saved.localTime) }
            if !plan.linkKeysOn.isEmpty { await wakeLight.setLinks(plan.linkKeysOn, enabled: true) }
            if !plan.linkKeysOff.isEmpty { await wakeLight.setLinks(plan.linkKeysOff, enabled: false) }
        }
        return true
    }
}
