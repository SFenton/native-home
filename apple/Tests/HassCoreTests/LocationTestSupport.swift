import Foundation
@testable import HassCore
import HassTestSupport

/// A clock a test moves by hand, starting at the same instant as ``fixNorth(of:accuracy:at:)``'s time zero.
@MainActor
final class LocationTestClock {
    var date = Date(timeIntervalSince1970: 1_000_000)

    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

/// `get_zones` first, then `count` plain successes.
func okReplies(zones: String = zonesJSON, _ count: Int) -> [StubHTTPTransport.Reply] {
    [(200, zones)] + Array(repeating: (200, "{}"), count: count)
}

/// The `data` of every `update_location` the transport saw, in order.
func updateLocations(_ transport: StubHTTPTransport) throws -> [[String: Any]] {
    try transport.requests.compactMap { request in
        let body = try sentBody(request)
        return body["type"] as? String == "update_location" ? body["data"] as? [String: Any] : nil
    }
}

/// The `data` of every `fire_event` the transport saw, in order.
func firedEvents(_ transport: StubHTTPTransport) throws -> [[String: Any]] {
    try transport.requests.compactMap { request in
        let body = try sentBody(request)
        return body["type"] as? String == "fire_event" ? body["data"] as? [String: Any] : nil
    }
}

/// The distinct zones among `regions`, in order.
func zoneOrder(_ regions: [PlannedRegion]) -> [String] {
    regions.reduce(into: []) { if $0.last != $1.zoneID { $0.append($1.zoneID) } }
}
