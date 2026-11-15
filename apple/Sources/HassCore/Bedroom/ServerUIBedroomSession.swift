import Foundation
import Observation
import os

// MARK: - Bedroom collection and editor ownership

/// One authored bedroom owns its controllers, live keyed rows and alarm drafts across publications.
@MainActor @Observable
public final class ServerUIBedroomSession {
    /// Why an editor request or release was refused.
    public enum Failure: Error, Equatable { case missingProvider, staleAlarm, notEditorRoute, editorBusy }
    /// The validated authored room this session was built from.
    public let descriptor: ServerUIBedroomDescriptor
    /// The wake light and bed controllers the session owns.
    public let devices: BedroomDevices
    /// Row sources keyed by provider id.
    public let alarms: [String: ServerUIBedroomAlarms]
    /// Live keyed rows by collection id: `<provider>.alarms` and `<provider>.day.<weekday>`.
    public let collections: [String: ServerUIRowCollection]
    /// Open alarm drafts keyed by route identity.
    public private(set) var editors: [String: ServerUIBedroomDraft] = [:]
    /// Fixed copy shown when a collection could not be refreshed, or `nil`.
    public private(set) var collectionError: String?
    private var retiringEditors: Set<String> = []
    private static let log = Logger(subsystem: "com.sfenton.home", category: "ServerUI")

    /// Builds the controllers, row sources and collections for one authored room.
    ///
    /// Scripts and the schedule topic come from the house document, never from `descriptor`.
    public init(descriptor: ServerUIBedroomDescriptor, store: EntityStore, caller: any HassServiceResponding, canEdit: Bool) {
        self.descriptor = descriptor
        devices = BedroomDevices(descriptor: descriptor, store: store, caller: caller, canEdit: canEdit)
        var alarms = [descriptor.wakeProviderId: ServerUIBedroomAlarms(source: .wake(devices.wakeLight))]
        var collections = [descriptor.wakeProviderId + ".alarms": ServerUIRowCollection()]
        for (index, bed) in descriptor.beds.enumerated() {
            alarms[bed.providerId] = ServerUIBedroomAlarms(source: .bed(devices.beds[index]))
            collections[bed.providerId + ".alarms"] = ServerUIRowCollection()
            for day in Weekday.allCases { collections[bed.providerId + ".day." + day.rawValue] = ServerUIRowCollection() }
        }
        self.alarms = alarms
        self.collections = collections
        observe()
    }

    /// Whether a pending command or an open draft forbids replacing this session.
    public var protectsPublication: Bool {
        devices.wakeLight.hasPendingCommands || devices.beds.contains { $0.hasPendingCommands }
            || editors.values.contains { $0.protectsPublication }
    }

    // MARK: - Alarm editors

    /// Reuses an existing editor by route identity. New-alarm identity is supplied by the shell visit.
    public func editor(providerId: String, route: ServerUIBedroomAlarms.Route, visitId: String,
                       now: Date = .now) throws -> ServerUIBedroomDraft {
        guard let rows = alarms[providerId] else { throw Failure.missingProvider }
        let key: String
        switch route {
        case .bedAlarm(let id), .wakeAlarm(let id): key = providerId + "/" + id
        case .addBed, .addWake: key = providerId + "/new/" + visitId
        default: throw Failure.notEditorRoute
        }
        if let current = editors[key], !current.completed { return current }
        guard rows.canAdd else { throw Failure.staleAlarm }
        let draft: ServerUIBedroomDraft
        if providerId == descriptor.wakeProviderId {
            let alarm: WakeLight.Alarm
            let isNew: Bool
            switch route {
            case .wakeAlarm(let id):
                guard let row = rows.rows().first(where: { $0.id == id }), case .wake(let value) = row.alarm,
                      value.isNative else { throw Failure.staleAlarm }
                alarm = value
                isNew = false
            case .addWake:
                alarm = .new(id: visitId, kind: .weekly, now: now, defaults: devices.wakeLight.snapshot.defaults)
                isNew = true
            default: throw Failure.notEditorRoute
            }
            let devices = devices
            draft = .wake(controller: devices.wakeLight, alarm: alarm, isNew: isNew,
                          bedTargets: { isNew ? devices.bedTargets : [] }) {
                await devices.saveWakeAlarm($0, isNew: isNew, addToBeds: Set($0.bedSides))
            }
        } else {
            guard let index = descriptor.beds.firstIndex(where: { $0.providerId == providerId }) else { throw Failure.missingProvider }
            let bed = devices.beds[index]
            let value: BedSideController.AlarmDraft
            switch route {
            case .bedAlarm(let id):
                guard let alarm = bed.alarms.first(where: { $0.id == id }) else { throw Failure.staleAlarm }
                value = bed.editDraft(alarm, wakeLight: devices.wakeLight.snapshot)
            case .addBed(let day): value = bed.newAlarmDraft(lockedDay: day)
            default: throw Failure.notEditorRoute
            }
            draft = .bed(controller: bed, wake: devices.wakeLight, draft: value)
        }
        editors[key] = draft
        return draft
    }

    /// Completed/discarded sessions may be released, but never a draft still owning a command.
    public func release(_ draft: ServerUIBedroomDraft) throws {
        guard !draft.protectsPublication else { throw Failure.editorBusy }
        for key in editors.keys.filter({ editors[$0] === draft }) {
            editors.removeValue(forKey: key)
            retiringEditors.remove(key)
        }
    }

    /// A departed page relinquishes its editor only after owned commands settle. Repeated retirement is harmless.
    public func retire(_ draft: ServerUIBedroomDraft) {
        let owned = editors.keys.filter { editors[$0] === draft }
        retiringEditors.formUnion(owned)
        if !owned.isEmpty && !draft.completed && !draft.blocksExit { draft.discard() }
        releaseSettledEditors()
    }

    private func releaseSettledEditors() {
        for (key, draft) in editors where (draft.completed || retiringEditors.contains(key)) && !draft.protectsPublication {
            editors.removeValue(forKey: key)
            retiringEditors.remove(key)
        }
    }

    // MARK: - Row collections

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    /// Reads each provider's rows once and derives its seven weekday collections from them, so one alarm change
    /// re-reads three sources rather than every collection, and a collection whose rows did not change is not written.
    private func refresh() {
        releaseSettledEditors()
        for (providerId, alarms) in alarms {
            let rows = alarms.available ? alarms.rows() : nil
            update(collections[providerId + ".alarms"], rows: rows)
            for day in Weekday.allCases {
                update(collections[providerId + ".day." + day.rawValue], rows: rows?.filter { Self.occurs($0, on: day) })
            }
        }
    }

    private static func occurs(_ row: ServerUIBedroomAlarms.Row, on day: Weekday) -> Bool {
        switch row.alarm {
        case .bed(let alarm): alarm.day == day
        case .wake(let alarm): alarm.weekdays.contains(day)
        }
    }

    /// `rows == nil` marks the source unavailable.
    private func update(_ collection: ServerUIRowCollection?, rows: [ServerUIBedroomAlarms.Row]?) {
        guard let collection else { return }
        do {
            guard let rows else { try collection.apply(nil, phase: .unavailable); return }
            let values = rows.map { row in
                switch row.alarm {
                case .bed(let alarm):
                    ServerUIRowItem(id: row.id, title: alarm.time, subtitle: alarm.day.label, value: row.enabled ? "On" : "Off")
                case .wake(let alarm):
                    ServerUIRowItem(id: row.id, title: alarm.label.isEmpty ? alarm.localTime : alarm.label,
                                    subtitle: alarm.localTime, value: row.linked.map { $0 ? "Linked" : "Unlinked" } ?? (row.enabled ? "On" : "Off"))
                }
            }
            try collection.apply(values, phase: .ready)
        } catch {
            let message = "Alarm rows could not be loaded."
            if collectionError != message { collectionError = message }
            do { try collection.apply(nil, phase: .failed) }
            catch { Self.log.error("Bedroom collection rejected its failure state.") }
        }
    }
}
