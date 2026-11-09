import Foundation
@testable import HassCore

/// A hand-advanced clock for the weather store.
@MainActor
final class WeatherTestClock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_788_611_400)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Captures the store's refresh timer so tests fire it by hand.
@MainActor
final class ManualWeatherScheduler: WeatherRefreshScheduling {
    struct Entry {
        var interval: TimeInterval
        var action: @MainActor () -> Void
        var cancelled = false
    }

    private(set) var entries: [Entry] = []
    private(set) var cancelCount = 0

    /// The timer currently armed, if any.
    var armed: (index: Int, interval: TimeInterval)? {
        guard let index = entries.lastIndex(where: { !$0.cancelled }) else { return nil }
        return (index, entries[index].interval)
    }

    var armedCount: Int { entries.filter { !$0.cancelled }.count }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let index = entries.count
        entries.append(Entry(interval: interval, action: action))
        return { [unowned self] in
            if !entries[index].cancelled { cancelCount += 1 }
            entries[index].cancelled = true
        }
    }

    /// Fires the armed timer.
    func fire() {
        guard let armed else { return }
        entries[armed.index].cancelled = true
        entries[armed.index].action()
    }
}

/// A weather service double: answers immediately from `respond`, or holds requests for the test to resolve.
@MainActor
final class FakeWeatherCaller: WeatherForecastCalling {
    struct Held {
        var kind: WeatherForecastKind
        var continuation: CheckedContinuation<JSONValue, Error>
    }

    private(set) var calls: [WeatherForecastKind] = []
    private(set) var lastData: [String: any Sendable] = [:]
    private(set) var held: [Held] = []
    var holds = false
    var respond: (WeatherForecastKind) throws -> JSONValue = { _ in WeatherFixtures.response(temperature: 60) }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        lastData = data
        precondition(domain == "weather" && service == "get_forecasts")
        let kind = WeatherForecastKind(rawValue: data["type"] as? String ?? "") ?? .daily
        calls.append(kind)
        if holds {
            return try await withCheckedThrowingContinuation { held.append(Held(kind: kind, continuation: $0)) }
        }
        return try respond(kind)
    }

    func resolve(_ kind: WeatherForecastKind, with value: JSONValue) {
        guard let index = held.firstIndex(where: { $0.kind == kind }) else { return }
        held.remove(at: index).continuation.resume(returning: value)
    }

    func reject(_ kind: WeatherForecastKind, with error: Error) {
        guard let index = held.firstIndex(where: { $0.kind == kind }) else { return }
        held.remove(at: index).continuation.resume(throwing: error)
    }

    /// Lets queued tasks run until `count` calls were made.
    func waitForCalls(_ count: Int) async {
        for _ in 0..<200 where calls.count < count { await Task.yield() }
    }
}

enum WeatherFixtures {
    static let entityId = "weather.demo_weather_1"

    /// A `weather.get_forecasts` response object.
    static func response(temperature: Double = 60, datetime: String = "2026-09-05T12:00:00+00:00", entries: [[String: JSONValue]]? = nil, wrapped: Bool = false) -> JSONValue {
        let forecast = entries ?? [["temperature": .number(temperature), "datetime": .string(datetime)]]
        let payload: JSONValue = .object([entityId: .object(["forecast": .array(forecast.map(JSONValue.object))])])
        return wrapped ? .object(["service_response": payload]) : payload
    }

    static func entry(_ datetime: String, _ temperature: Double) -> [String: JSONValue] {
        ["datetime": .string(datetime), "temperature": .number(temperature)]
    }

    static func temporaryCache() -> WeatherForecastDiskCache {
        WeatherForecastDiskCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "weather-\(UUID()).json"))
    }
}
