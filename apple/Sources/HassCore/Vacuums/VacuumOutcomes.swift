import Foundation

/// The Main Floor coordinator's automatic cleaning report (`while_away_outcomes`), web `vacuumOutcomes.ts`.
///
/// Only the parts the native sheet shows are kept: rooms with their status, latest attempt, outstanding work and
/// reasons. Validation follows the web so a malformed report is never shown as if it were trustworthy.
public struct VacuumOutcomeContract: Equatable, Sendable {
    public enum Status: String, Sendable { case completed, deferred, failed, interrupted, partial, uncertain }
    public enum AttemptMode: String, Sendable { case fallbackVacuum = "fallback_vacuum", vacuum, vacuumMop = "vacuum_mop" }
    public enum AttemptResult: String, Sendable { case completed, failed, interrupted, partial, uncertain }
    public enum Operation: String, Sendable { case mop, vacuum, vacuumMop = "vacuum_mop" }

    public struct Reason: Equatable, Sendable {
        public var category: String
        public var code: String
        public var data: [String: JSONValue]
        public var raw: String
    }

    public struct Attempt: Equatable, Sendable {
        public var eventId: String
        public var mode: AttemptMode
        public var reason: Reason?
        public var result: AttemptResult
    }

    public struct Outstanding: Equatable, Sendable {
        public var operation: Operation
        public var reason: Reason?
    }

    public struct Room: Equatable, Sendable, Identifiable {
        public var roomId: String
        public var roomName: String
        public var status: Status
        public var requiredOperation: Operation
        public var latestAttempt: Attempt?
        public var outstanding: Outstanding?
        public var eventIds: [String]
        /// Set when an explicit Home Assistant marker reconciled this room as done.
        public var reconciledEventId: String?
        public var id: String { roomId }

        var isReconciled: Bool { reconciledEventId != nil && latestAttempt?.eventId == reconciledEventId }
    }

    public var day: String
    public var version: Int
    public var rooms: [Room]
    /// Room names seen on events, for reasons that name another room.
    public var eventRoomNames: [String: String]
}

/// How the cleaning report shows on the sheet (`VacuumWhileAwayPresentation`).
public enum VacuumWhileAway: Equatable, Sendable {
    case empty
    case typed(VacuumOutcomeContract)
    case legacy(cleaned: [String], issues: [String])
    /// incomplete, malformed or incompatible, with any legacy lines.
    case protocolNotice(Kind, cleaned: [String], issues: [String])

    public enum Kind: String, Sendable { case incomplete, malformed, incompatible }

    /// Reads the session sensor's attributes (`vacuumWhileAwayPresentation`).
    /// - Parameter reconciled: Room id → reconciled attempt event id.
    public static func read(_ attributes: [String: JSONValue]?, reconciled: [String: String] = [:]) -> VacuumWhileAway {
        guard let attributes else { return .empty }
        func list(_ key: String) -> [String] {
            attributes[key]?.array?.compactMap(\.string).filter { !$0.trimmed.isEmpty } ?? []
        }
        let cleaned = list("while_away_cleaned"), issues = list("while_away_issues")
        switch VacuumOutcomeParser.parse(attributes["while_away_outcomes"]) {
        case let .valid(contract):
            let reconciledContract = VacuumOutcomeParser.reconcile(contract, reconciled)
            return reconciledContract.rooms.isEmpty ? .empty : .typed(reconciledContract)
        case .incomplete: return .protocolNotice(.incomplete, cleaned: cleaned, issues: issues)
        case .malformed: return .protocolNotice(.malformed, cleaned: cleaned, issues: issues)
        case .unsupported: return .protocolNotice(.incompatible, cleaned: cleaned, issues: issues)
        case .absent: return cleaned.isEmpty && issues.isEmpty ? .empty : .legacy(cleaned: cleaned, issues: issues)
        }
    }
}

// MARK: - Parsing

enum VacuumOutcomeParser {
    enum Result: Equatable { case absent, valid(VacuumOutcomeContract), incomplete, malformed, unsupported }

    static func parse(_ value: JSONValue?) -> Result {
        guard let value, value != .null else { return .absent }
        guard case let .object(object) = value else { return .malformed }
        guard let version = object["version"]?.number, version > 0, version == version.rounded() else { return .malformed }
        guard version == 1 || version == 2 else { return .unsupported }
        if object["complete"] == .bool(false) { return .incomplete }
        guard object["complete"] == .bool(true) else { return .malformed }
        return contract(object, version: Int(version)).map(Result.valid) ?? .malformed
    }

    private static func contract(_ object: [String: JSONValue], version: Int) -> VacuumOutcomeContract? {
        guard let day = object["day"]?.string, isValidDay(day),
              let roomValues = object["rooms"]?.array, let eventValues = object["events"]?.array else { return nil }
        let results: Set<String> = version == 1 ? ["completed", "failed", "interrupted"] : ["completed", "failed", "interrupted", "partial", "uncertain"]
        let statuses: Set<String> = version == 1 ? ["completed", "deferred", "failed", "interrupted", "partial"]
            : ["completed", "deferred", "failed", "interrupted", "partial", "uncertain"]

        struct Event { var id: String; var roomId: String; var attempt: (mode: String, result: String)? }
        var events: [String: Event] = [:]
        var roomNames: [String: String] = [:]
        for value in eventValues {
            guard let id = nonEmpty(value["id"]), nonEmpty(value["session_id"]) != nil,
                  isPositiveInteger(value["sequence"]), timestamp(value["occurred_at"]),
                  value["day"]?.string == day, let roomId = nonEmpty(value["room_id"]),
                  value["room_name"] == .null || value["room_name"]?.string != nil,
                  ["cleaned", "failed", "fallback", "skipped"].contains(value["kind"]?.string ?? ""),
                  let reasonValue = value["reason"], reasonValue == .null || reason(reasonValue) != nil,
                  events[id] == nil else { return nil }
            if let name = value["room_name"]?.string { roomNames[roomId] = name }
            switch value["type"]?.string {
            case "attempt":
                guard let mode = value["attempt_mode"]?.string, VacuumOutcomeContract.AttemptMode(rawValue: mode) != nil,
                      let result = value["attempt_result"]?.string, results.contains(result) else { return nil }
                events[id] = Event(id: id, roomId: roomId, attempt: (mode, result))
            case "deferral":
                guard let operation = value["outstanding_operation"]?.string, VacuumOutcomeContract.Operation(rawValue: operation) != nil,
                      reason(reasonValue) != nil else { return nil }
                events[id] = Event(id: id, roomId: roomId, attempt: nil)
            default: return nil
            }
        }

        var rooms: [VacuumOutcomeContract.Room] = []
        var referenced = Set<String>()
        for value in roomValues {
            guard let roomId = nonEmpty(value["room_id"]), let roomName = nonEmpty(value["room_name"]),
                  let required = value["required_operation"]?.string, required == "vacuum" || required == "vacuum_mop",
                  let statusText = value["status"]?.string, statuses.contains(statusText),
                  let status = VacuumOutcomeContract.Status(rawValue: statusText),
                  credit(value["credit"]), value["reasons_coincide"]?.bool != nil,
                  isNonNegativeInteger(value["occurrence_count"]),
                  timestamp(value["first_occurred_at"]), timestamp(value["last_occurred_at"]),
                  isPositiveInteger(value["last_sequence"]),
                  let eventIds = value["event_ids"]?.array?.compactMap({ nonEmpty($0) }),
                  !eventIds.isEmpty, eventIds.count == value["event_ids"]?.array?.count, Set(eventIds).count == eventIds.count,
                  !rooms.contains(where: { $0.roomId == roomId })
            else { return nil }
            var attempt: VacuumOutcomeContract.Attempt?
            if let attemptValue = value["latest_attempt"], attemptValue != .null {
                guard let eventId = nonEmpty(attemptValue["event_id"]),
                      let mode = attemptValue["mode"]?.string.flatMap(VacuumOutcomeContract.AttemptMode.init(rawValue:)),
                      let resultText = attemptValue["result"]?.string, results.contains(resultText),
                      let result = VacuumOutcomeContract.AttemptResult(rawValue: resultText),
                      let reasonValue = attemptValue["reason"], reasonValue == .null || reason(reasonValue) != nil
                else { return nil }
                attempt = .init(eventId: eventId, mode: mode, reason: reason(reasonValue).map(normalize), result: result)
            } else if value["latest_attempt"] == nil { return nil }
            var outstanding: VacuumOutcomeContract.Outstanding?
            if let outstandingValue = value["outstanding"], outstandingValue != .null {
                guard let operation = outstandingValue["operation"]?.string.flatMap(VacuumOutcomeContract.Operation.init(rawValue:)),
                      let reasonValue = outstandingValue["reason"], reasonValue == .null || reason(reasonValue) != nil
                else { return nil }
                outstanding = .init(operation: operation, reason: reason(reasonValue).map(normalize))
            } else if value["outstanding"] == nil { return nil }

            for eventId in eventIds {
                guard let event = events[eventId], event.roomId == roomId, !referenced.contains(eventId) else { return nil }
                referenced.insert(eventId)
            }
            if let attempt {
                guard eventIds.contains(attempt.eventId), let event = events[attempt.eventId], let facts = event.attempt,
                      facts.mode == attempt.mode.rawValue, facts.result == attempt.result.rawValue else { return nil }
            }
            rooms.append(.init(roomId: roomId, roomName: roomName, status: status,
                               requiredOperation: VacuumOutcomeContract.Operation(rawValue: required) ?? .vacuum,
                               latestAttempt: attempt, outstanding: outstanding, eventIds: eventIds))
        }
        guard referenced.count == events.count else { return nil }
        return VacuumOutcomeContract(day: day, version: version, rooms: rooms, eventRoomNames: roomNames)
    }

    /// Marks rooms whose latest attempt Home Assistant reconciled as completed (`reconcileVacuumOutcomeContract`).
    static func reconcile(_ contract: VacuumOutcomeContract, _ reconciled: [String: String]) -> VacuumOutcomeContract {
        var result = contract
        result.rooms = contract.rooms.map { room in
            guard room.status != .completed, let eventId = reconciled[room.roomId], !eventId.isEmpty,
                  room.latestAttempt?.eventId == eventId else { return room }
            var updated = room
            updated.status = .completed
            updated.outstanding = nil
            updated.reconciledEventId = eventId
            return updated
        }
        return result
    }

    // MARK: Field checks

    private static func nonEmpty(_ value: JSONValue?) -> String? {
        guard let text = value?.string, !text.trimmed.isEmpty else { return nil }
        return text
    }

    private static func isPositiveInteger(_ value: JSONValue?) -> Bool {
        guard let number = value?.number else { return false }
        return number > 0 && number == number.rounded()
    }

    private static func isNonNegativeInteger(_ value: JSONValue?) -> Bool {
        guard let number = value?.number else { return false }
        return number >= 0 && number == number.rounded()
    }

    private static func timestamp(_ value: JSONValue?) -> Bool { nonEmpty(value).flatMap(VacuumDates.parse) != nil }

    private static func isValidDay(_ day: String) -> Bool {
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let date = Int(parts[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let parsed = calendar.date(from: DateComponents(year: year, month: month, day: date)) else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: parsed)
        return components.year == year && components.month == month && components.day == date
    }

    private static func reason(_ value: JSONValue) -> VacuumOutcomeContract.Reason? {
        guard let code = nonEmpty(value["code"]), let category = nonEmpty(value["category"]), let raw = nonEmpty(value["raw"]),
              case let .object(data)? = value["data"] else { return nil }
        return .init(category: category, code: code, data: data, raw: raw)
    }

    private static func credit(_ value: JSONValue?) -> Bool {
        guard let value, let status = value["status"]?.string, ["full", "none", "partial"].contains(status) else { return false }
        let operation = value["operation"]
        if operation != .null && !["vacuum", "vacuum_mop"].contains(operation?.string ?? "") { return false }
        return status == "none" ? operation == .null : operation != .null
    }

    /// Legacy aliases (`LEGACY_REASON_ALIASES`).
    private static func normalize(_ reason: VacuumOutcomeContract.Reason) -> VacuumOutcomeContract.Reason {
        guard reason.code == "unknown", reason.raw == "Lost mop pad" else { return reason }
        var updated = reason
        updated.category = "mop"
        updated.code = "mop.attachment_missing"
        return updated
    }
}

// MARK: - Presentation

/// Copy and counts for the report (web `vacuumOutcomePresentation.ts` and `VacuumOutcomes.tsx`).
public enum VacuumOutcomeText {
    public struct Counts: Equatable, Sendable {
        public var attention = 0, completed = 0, due = 0, interrupted = 0, needsAttention = 0, unverified = 0
    }

    public static func counts(_ contract: VacuumOutcomeContract) -> Counts {
        var counts = Counts()
        for room in contract.rooms {
            if room.status == .completed { counts.completed += 1 }
            if room.outstanding != nil { counts.due += 1 }
            if room.status == .failed { counts.attention += 1 }
            if room.status == .interrupted { counts.interrupted += 1 }
            if room.status == .uncertain { counts.unverified += 1 }
            if room.outstanding != nil && room.status != .interrupted { counts.needsAttention += 1 }
        }
        return counts
    }

    /// The overview tile's icon and tone.
    public static func overviewVisual(_ counts: Counts) -> VacuumVisual {
        if counts.attention > 0 { return statusVisual(.failed) }
        if counts.unverified > 0 { return statusVisual(.uncertain) }
        if counts.interrupted > 0 { return statusVisual(.interrupted) }
        if counts.due > 0 { return statusVisual(.deferred) }
        return statusVisual(.completed)
    }

    /// The report page's short navigation title. The vacuum and the count go in ``reportSubtitle(vacuum:rooms:)``: the
    /// web's one-line "Main Floor · Automatic Cleaning Report (4)" truncated on iPhone (HIG, Navigation bars: keep titles
    /// short; departure recorded in `.agents/pages/vacuums/spec.md`).
    public static let reportTitle = "Cleaning Report"

    /// `Main Floor · Automatic · 4 rooms`, the line under the report's title.
    public static func reportSubtitle(vacuum: String, rooms: Int) -> String {
        "\(vacuum) · Automatic · \(rooms) \(rooms == 1 ? "room" : "rooms")"
    }

    /// The overview tile's subtitle: `3 Rooms Completed • 1 Error`.
    public static func overviewSubtitle(_ counts: Counts) -> String {
        func plural(_ count: Int, _ one: String, _ other: String) -> String? {
            count > 0 ? "\(count) \(count == 1 ? one : other)" : nil
        }
        return [
            plural(counts.completed, "Room Completed", "Rooms Completed"),
            plural(counts.unverified, "Room Unverified", "Rooms Unverified"),
            plural(counts.needsAttention, "Room Needs Attention", "Rooms Need Attention"),
            plural(counts.attention, "Error", "Errors"),
        ].compactMap { $0 }.joined(separator: " • ")
    }

    /// `11 Oct 2026` style day label.
    public static func day(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return day }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    public static func statusVisual(_ status: VacuumOutcomeContract.Status) -> VacuumVisual {
        switch status {
        case .failed: .init(icon: "mdi:alert-circle", tone: .danger)
        case .interrupted: .init(icon: "mdi:pause-circle", tone: .warning)
        case .partial: .init(icon: "mdi:progress-check", tone: .warning)
        case .deferred: .init(icon: "mdi:clock-outline", tone: .warning)
        case .completed: .init(icon: "mdi:check-circle", tone: .ok)
        case .uncertain: .init(icon: "mdi:help-circle-outline", tone: .warning)
        }
    }

    public static func statusTitle(_ status: VacuumOutcomeContract.Status) -> String {
        switch status {
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        case .partial: "Partially Complete"
        case .uncertain: "Completion Unverified"
        case .deferred: "Not Attempted"
        case .completed: "Completed"
        }
    }

    /// The sentence under a room (`roomOutcomeDetail`).
    public static func detail(_ room: VacuumOutcomeContract.Room, roomNames: [String: String]) -> String {
        let primary: String
        if let attempt = room.latestAttempt {
            primary = attemptSentence(attempt.mode, room.isReconciled ? .completed : attempt.result)
        } else {
            primary = deferredSentence(room.requiredOperation)
        }
        let context: ReasonContext = room.status == .uncertain ? .uncertain : .standard
        func known(_ reason: VacuumOutcomeContract.Reason?) -> String? {
            guard let reason, reason.code != "unknown", !room.isReconciled else { return nil }
            return text(for: reason, roomNames: roomNames, context: context)
        }
        let resultReason = known(room.latestAttempt?.reason)
        let outstandingReason = known(room.outstanding?.reason)
        switch room.status {
        case .failed, .interrupted, .uncertain: return resultReason ?? outstandingReason ?? primary
        case .partial: return room.outstanding.map { outstandingSentence($0.operation) } ?? resultReason ?? primary
        case .deferred: return outstandingReason ?? primary
        case .completed: return primary
        }
    }

    static func attemptSentence(_ mode: VacuumOutcomeContract.AttemptMode, _ result: VacuumOutcomeContract.AttemptResult) -> String {
        switch (result, mode) {
        case (.completed, .vacuum): "Vacuuming completed for the room."
        case (.completed, .vacuumMop): "Vacuuming and mopping completed for the room."
        case (.completed, .fallbackVacuum): "Fallback vacuuming completed for the room; mopping was not confirmed."
        case (.failed, .vacuum): "Vacuuming the room without mopping failed."
        case (.failed, .vacuumMop): "Vacuuming and mopping the room failed."
        case (.failed, .fallbackVacuum): "The fallback attempt to vacuum the room without mopping failed."
        case (.interrupted, .vacuum): "The vacuum-only attempt was interrupted before completion."
        case (.interrupted, .vacuumMop): "The vacuuming and mopping attempt was interrupted before completion."
        case (.interrupted, .fallbackVacuum): "The fallback vacuum-only attempt was interrupted before completion."
        case (.partial, .vacuum): "The vacuum-only attempt was partially completed."
        case (.partial, .vacuumMop): "The vacuuming and mopping attempt was partially completed."
        case (.partial, .fallbackVacuum): "The fallback vacuum-only attempt was partially completed."
        case (.uncertain, .vacuum): "Vacuuming completion could not be verified."
        case (.uncertain, .vacuumMop): "Vacuuming and mopping completion could not be verified."
        case (.uncertain, .fallbackVacuum): "Fallback vacuuming completion could not be verified."
        }
    }

    static func deferredSentence(_ operation: VacuumOutcomeContract.Operation) -> String {
        switch operation {
        case .vacuum: "Vacuuming was deferred before any attempt."
        case .vacuumMop: "Vacuuming and mopping were deferred before any attempt."
        case .mop: "Only mopping was deferred without being attempted."
        }
    }

    static func outstandingSentence(_ operation: VacuumOutcomeContract.Operation) -> String {
        switch operation {
        case .vacuum: "Vacuuming remains due."
        case .vacuumMop: "Combined vacuuming and mopping remain due."
        case .mop: "Mopping remains due."
        }
    }

    enum ReasonContext { case standard, uncertain }

    /// A reason as a sentence (`vacuumOutcomeReasonValue`).
    static func text(for reason: VacuumOutcomeContract.Reason, roomNames: [String: String], context: ReasonContext) -> String {
        func number(_ key: String) -> String? {
            guard let value = reason.data[key]?.number, value.isFinite else { return nil }
            return value.formatted(.number)
        }
        let measurement = reason.data["measurement"]?.string
        switch reason.code {
        case "mop.fresh_water_unavailable":
            switch reason.data["state"]?.string {
            case "missing": return "Fresh-water status is missing."
            case "unknown": return "Fresh-water status is unknown."
            case "unavailable": return "Fresh-water status is unavailable."
            default: return "The vacuum outcome reason was not recognized."
            }
        case "mop.clean_water_empty": return "The mop dock's clean-water tank was empty; refill it."
        case "dock.dustbag_full_or_duct_blocked": return "The auto-empty dock dust bag was full or its dust duct was blocked."
        case "occupancy.person_arrived": return "Cleaning was interrupted because someone returned home."
        case "power.low_battery": return "The vacuum battery was too low to continue cleaning the room."
        case "dispatch.failed": return "Home Assistant could not dispatch the room-cleaning request; try again."
        case "navigation.stuck": return "The vacuum became stuck while trying to clean the room."
        case "navigation.room_unreachable": return "The vacuum could not reach the requested room."
        case "navigation.dock_unreachable": return "The vacuum could not reach its dock."
        case "execution.cleaning_not_observed": return "The vacuum never entered a cleaning state for the attempted room run; try again."
        case "execution.segment_not_observed": return "The vacuum never reported cleaning the requested room segment; try again."
        case "operation.cancelled": return "The room run was cancelled."
        case "mop.attachment_missing": return "The vacuum's mop attachment was missing; attach it before mopping."
        case "mop.dirty_water_unavailable": return "The dirty-water tank was unavailable; check it before mopping."
        case "mop.detergent_unavailable": return "Mop cleaning liquid was unavailable; check it before mopping."
        case "mop.hardware_unavailable": return "The mop hardware was unavailable; check it before mopping."
        case "telemetry.counter_attribution_ambiguous":
            return measurement == "time" ? "Floor completion time became ambiguous during a telemetry outage."
                : measurement == "area" ? "Floor completion area became ambiguous during a telemetry outage."
                : "A floor completion measurement became ambiguous during a telemetry outage."
        case "telemetry.task_identity_conflict": return "Telemetry recovered with conflicting room evidence."
        case "verification.iterations_uncertain":
            return "Floor thresholds were met, but the requested iterations did not reach a coherent completed task state."
        case "verification.measurement_unavailable":
            return measurement == "time" ? "Floor completion time was unavailable during dock servicing."
                : measurement == "area" ? "Floor completion area was unavailable during dock servicing."
                : "A floor completion measurement was unavailable during dock servicing."
        case "telemetry.source_outage_unresolved":
            return number("timeout_seconds").map { "Telemetry recovery was not coherent within \($0) seconds." }
                ?? "Telemetry recovery was not coherent."
        case "verification.iterations_incomplete":
            if let observed = number("observed_iterations"), let requested = number("requested_iterations") {
                return "Observed \(observed) of \(requested) requested iterations."
            }
            return "Requested iterations could not all be verified."
        case "dispatch.timeout":
            return number("timeout_seconds").map { "The room-cleaning request did not start within \($0) seconds; try again." }
                ?? "The room-cleaning request timed out without a verified duration; try again."
        case "recovery.native_resume_timeout":
            return number("timeout_seconds").map { "The vacuum did not resume within \($0) seconds; try again." }
                ?? "The vacuum resume request timed out without a verified duration; try again."
        case "verification.duration_below_minimum":
            if let observed = number("observed_seconds"), let minimum = number("minimum_seconds") {
                return "Room cleaning lasted \(observed) seconds, below the required minimum of \(minimum) seconds."
            }
            return "Room-cleaning duration fell below the required minimum without verified values; retry."
        case "verification.estimated_dwell_below_minimum":
            if let observed = number("observed_seconds"), let minimum = number("minimum_seconds") {
                return "Estimated time in the requested room was \(observed) seconds, below the required minimum of \(minimum) seconds."
            }
            return "Estimated time in the requested room was below the required minimum; reliable values were unavailable."
        case "verification.area_below_minimum": return "The cleaned area of the room was below the required minimum."
        case "verification.wrong_room":
            guard let dominant = number("dominant_seconds"), let commanded = number("commanded_seconds") else {
                return "The vacuum outcome reason was not recognized."
            }
            if let dominantRoom = reason.data["dominant_room_id"]?.string.flatMap({ roomNames[$0] }),
               let commandedRoom = reason.data["commanded_room_id"]?.string.flatMap({ roomNames[$0] }) {
                return "Observed cleaning was dominated by \(dominantRoom) for \(dominant) seconds instead of the requested \(commandedRoom) for \(commanded) seconds."
            }
            return "Observed cleaning time was dominated elsewhere, with \(dominant) seconds versus \(commanded) seconds in the requested room."
        default:
            return context == .uncertain ? "Completion could not be verified from the available vacuum data."
                : "The vacuum outcome reason was not recognized."
        }
    }

    /// Room names for reasons: event names, then room names, then the vacuum's configured names (`reasonRoomNames`).
    public static func roomNames(_ contract: VacuumOutcomeContract, vacuum: VacuumConfig) -> [String: String] {
        var names = contract.eventRoomNames
        for room in contract.rooms { names[room.roomId] = room.roomName }
        names.merge(vacuum.outcomeRoomNames) { _, configured in configured }
        return names
    }

    /// Protocol notice copy.
    public static func protocolTitle(_ kind: VacuumWhileAway.Kind) -> (title: String, description: String) {
        switch kind {
        case .incomplete: ("Report Still Being Prepared", "Final counts are not available.")
        case .malformed: ("Report Could Not Be Read", "Structured cleaning results are unavailable.")
        case .incompatible: ("Dashboard Update Required", "This cleaning report uses an unsupported version.")
        }
    }
}
