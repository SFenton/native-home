import Foundation
import Observation

// MARK: - Typed collection bridge

/// Bedroom row values and intents for the shell-owned collection/router interface.
/// Mirrored wake alarms only edit links; their schedule remains owned by the originating bed.
@MainActor
@Observable
public final class ServerUIBedroomAlarms {
    /// The authored source choices.
    public enum Source {
        case bed(BedSideController)
        case wake(WakeLightController)
    }
    /// The authored alarm choices.
    public enum Alarm: Equatable, Sendable {
        case bed(BedAlarm)
        case wake(WakeLight.Alarm)
    }
    /// The authored row.
    public struct Row: Equatable, Sendable {
        public let id: String
        public let alarm: Alarm
        public let enabled: Bool
        public let linked: Bool?
        public let editable: Bool
        public let pending: Bool
    }
    /// The authored route choices.
    public enum Route: Equatable, Sendable {
        case bedDay(Weekday), bedAlarm(String), addBed(Weekday?)
        case wakeAlarm(String), addWake, linkedBed(BedSide)
    }
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case staleRow, readOnly, missingLinkedSource }

    @ObservationIgnored private let source: Source
    public private(set) var error: String?

    /// Creates a server uibedroom alarms.
    public init(source: Source) { self.source = source }

    public var available: Bool {
        switch source {
        case .bed(let bed): bed.alarmsAvailable
        case .wake(let wake): wake.live.available
        }
    }

    public var canAdd: Bool {
        switch source {
        case .bed(let bed): bed.alarmsEditable
        case .wake(let wake): wake.canEdit && wake.live.available && !wake.configurationPending
        }
    }

    /// Stable alarm IDs and complete values let the shell key rows without losing focus or optimistic state.
    public func rows(day: Weekday? = nil) -> [Row] {
        switch source {
        case .bed(let bed):
            return bed.alarms.filter { day == nil || $0.day == day }.map {
                Row(id: $0.id, alarm: .bed($0), enabled: $0.enabled, linked: nil,
                    editable: bed.alarmsEditable, pending: bed.hasPendingCommands)
            }
        case .wake(let wake):
            let snapshot = wake.snapshot
            return snapshot.alarms.filter { alarm in day.map { alarm.weekdays.contains($0) } ?? true }.map {
                let pending = $0.isNative ? wake.isPending(alarmId: $0.id) : wake.arePending(linkKeys: $0.linkKeys())
                return Row(id: $0.id, alarm: .wake($0), enabled: $0.enabled,
                           linked: $0.isNative ? nil : snapshot.isLinked($0),
                           editable: wake.canEdit && wake.live.available && !pending && ($0.isNative || !$0.linkKeys().isEmpty), pending: pending)
            }
        }
    }

    /// Revalidates the full row, including revisions and link state, before using a canonical intent.
    @discardableResult
    public func toggle(_ expected: Row, enabled: Bool) async throws -> Bool {
        guard rows().contains(expected) else { error = "This alarm changed. Review it before trying again."; throw Failure.staleRow }
        guard expected.editable else { error = "This alarm is read-only."; throw Failure.readOnly }
        error = nil
        let accepted: Bool
        switch (source, expected.alarm) {
        case (.bed(let bed), .bed(let alarm)): accepted = bed.setEnabled(alarm, enabled)
        case (.wake(let wake), .wake(var alarm)):
            if alarm.isNative {
                alarm.enabled = enabled
                accepted = await wake.save(alarm)
            } else {
                accepted = await wake.setLinks(alarm.linkKeys(), enabled: enabled)
            }
        default: error = "This alarm changed."; throw Failure.staleRow
        }
        if !accepted { error = "Home Assistant did not update the alarm." }
        return accepted
    }

    /// Domain routing only: the shell chooses the authored destination and owns its route arguments.
    public func route(for expected: Row) throws -> Route {
        guard rows().contains(expected) else { throw Failure.staleRow }
        switch (source, expected.alarm) {
        case (.bed, .bed(let alarm)): return .bedAlarm(alarm.id)
        case (.wake(let wake), .wake(let alarm)):
            if alarm.isNative { return .wakeAlarm(alarm.id) }
            guard let source = alarm.sourceRef.flatMap(wake.config.source(id:)) else { throw Failure.missingLinkedSource }
            return .linkedBed(source.side)
        default: throw Failure.staleRow
        }
    }
}
