import Foundation

/// A synthetic coordinator report for the gallery, hosted tests and screenshots, never the real house.
public enum VacuumOutcomeFixtures {
    /// A small typed report: two rooms completed, one interrupted, one deferred.
    public static let sample: JSONValue = {
        let day = "2026-10-10", session = "fixture-session"
        func reason(_ code: String, _ category: String, _ raw: String) -> [String: Any] {
            ["code": code, "category": category, "raw": raw, "data": [String: Any]()]
        }
        func attempt(_ id: String, _ room: String, _ name: String, _ sequence: Int, _ mode: String, _ result: String, reason: Any = NSNull()) -> [String: Any] {
            ["id": id, "session_id": session, "sequence": sequence, "occurred_at": "2026-10-10T1\(sequence):00:00Z", "day": day,
             "room_id": room, "room_name": name, "kind": result == "completed" ? "cleaned" : "failed", "reason": reason,
             "type": "attempt", "attempt_mode": mode, "attempt_result": result]
        }
        func room(_ id: String, _ name: String, _ status: String, events: [String], latest: [String: Any]?, outstanding: Any = NSNull(),
                  credit: [String: Any] = ["status": "full", "operation": "vacuum_mop"]) -> [String: Any] {
            ["room_id": id, "room_name": name, "required_operation": "vacuum_mop", "status": status, "credit": credit,
             "reasons_coincide": false, "occurrence_count": events.count, "first_occurred_at": "2026-10-10T11:00:00Z",
             "last_occurred_at": "2026-10-10T14:00:00Z", "last_sequence": 4, "event_ids": events,
             "latest_attempt": latest.map { $0 as Any } ?? NSNull(), "outstanding": outstanding]
        }
        let interrupted = reason("occupancy.person_arrived", "occupancy", "Person arrived")
        let deferredReason = reason("mop.clean_water_empty", "mop", "Clean water empty")
        let deferral: [String: Any] = ["id": "e4", "session_id": session, "sequence": 4, "occurred_at": "2026-10-10T14:00:00Z", "day": day,
                                       "room_id": "dining_room", "room_name": "Dining Room", "kind": "skipped", "reason": deferredReason,
                                       "type": "deferral", "outstanding_operation": "vacuum_mop"]
        let object: [String: Any] = [
            "version": 2, "complete": true, "day": day,
            "events": [attempt("e1", "kitchen", "Kitchen", 1, "vacuum_mop", "completed"),
                       attempt("e2", "office", "Office", 2, "vacuum_mop", "completed"),
                       attempt("e3", "living_room", "Living Room", 3, "vacuum_mop", "interrupted", reason: interrupted),
                       deferral],
            "rooms": [
                room("kitchen", "Kitchen", "completed", events: ["e1"], latest: ["event_id": "e1", "mode": "vacuum_mop", "result": "completed", "reason": NSNull()]),
                room("office", "Office", "completed", events: ["e2"], latest: ["event_id": "e2", "mode": "vacuum_mop", "result": "completed", "reason": NSNull()]),
                room("living_room", "Living Room", "interrupted", events: ["e3"],
                     latest: ["event_id": "e3", "mode": "vacuum_mop", "result": "interrupted", "reason": interrupted],
                     outstanding: ["operation": "vacuum_mop", "reason": interrupted], credit: ["status": "none", "operation": NSNull()]),
                room("dining_room", "Dining Room", "deferred", events: ["e4"], latest: nil,
                     outstanding: ["operation": "vacuum_mop", "reason": deferredReason], credit: ["status": "none", "operation": NSNull()]),
            ],
        ]
        return JSONValue(any: object)
    }()

}
