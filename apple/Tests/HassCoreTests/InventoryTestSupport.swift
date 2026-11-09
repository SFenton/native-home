import Foundation
@testable import HassCore

/// Shared fixtures for the inventory tests: a pinned calendar and a scriptable service stub.
enum InventoryFixtures {
    /// Gregorian, UTC.
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// An inventory calendar whose "now" is noon UTC on `year-month-day` (default 2026-10-11).
    static func calendar(year: Int = 2026, month: Int = 10, day: Int = 11) -> InventoryCalendar {
        let calendar = utcCalendar
        let now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return InventoryCalendar(calendar: calendar, now: { now })
    }

    /// Midnight UTC of a date.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A plain row for catalog tests.
    static func item(
        _ id: Int?, _ name: String, quantity: Double = 1, location: StorageLocation? = .fridge,
        expiry: String? = nil, prepared: Bool = false, productId: Int? = nil
    ) -> InventoryItem {
        InventoryItem(inventoryId: id, name: name, quantity: quantity, location: location, expiryDate: expiry, preparedFood: prepared, productId: productId)
    }
}

/// Error the stub throws.
struct InventoryStubError: Error, Equatable {
    var message = "stub failure"
}

/// A scriptable `EverShelfCalling`: per-service queued answers, a fallback answer, and recorded calls.
@MainActor
final class InventoryStubCaller: EverShelfCalling {
    /// `domain.service` and the data converted to JSON.
    private(set) var calls: [(name: String, data: [String: JSONValue])] = []
    /// Answers consumed in order, keyed by service name (e.g. `list_inventory`).
    var queued: [String: [Result<JSONValue, InventoryStubError>]] = [:]
    /// Answer once the queue for a service is empty.
    var responses: [String: JSONValue] = [:]
    /// Services that always throw.
    var errors: [String: InventoryStubError] = [:]

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        _ = try await callServiceForResponse(domain, service, data: data)
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append(("\(domain).\(service)", data.mapValues { JSONValue(any: $0) }))
        if let error = errors[service] { throw error }
        if var queue = queued[service], !queue.isEmpty {
            let next = queue.removeFirst()
            queued[service] = queue
            return try next.get()
        }
        return responses[service] ?? .null
    }
}

/// Polls `condition` every 5 ms until it holds or `timeout` passes, and returns whether it held. Use it instead
/// of a fixed sleep before checking an in-flight or debounced state, so a loaded host can't race the check.
@MainActor
@discardableResult
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
