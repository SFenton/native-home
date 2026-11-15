import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Isolated forecast access

@MainActor @Suite
struct ServerUIWeatherReaderTests {
    @Test func readerScopesBothForecastKindsWithoutExposingCommands() async throws {
        let caller = Recorder()
        let reader = ServerUIWeatherReader(entityIds: ["weather.demo_forecast"], caller: caller)
        for kind in WeatherForecastKind.allCases {
            _ = try await reader.forecast(entityId: "weather.demo_forecast", kind: kind)
        }
        #expect(caller.calls == ["weather.get_forecasts:weather.demo_forecast:daily",
                                 "weather.get_forecasts:weather.demo_forecast:hourly"])
        await #expect(throws: ServerUIWeatherReader.Failure.unapprovedEntity) {
            _ = try await reader.forecast(entityId: "weather.demo_other", kind: .hourly)
        }
        let invalid = ServerUIWeatherReader(entityIds: ["light.demo_lamp"], caller: caller)
        await #expect(throws: ServerUIWeatherReader.Failure.unapprovedEntity) {
            _ = try await invalid.forecast(entityId: "light.demo_lamp", kind: .daily)
        }
        #expect(caller.calls.count == 2)
    }

    @Test func connectionReadinessRemainsLiveAndReadFailuresPropagate() async {
        let state = Readiness()
        let reader = ServerUIWeatherReader(entityIds: ["weather.demo_forecast"], connected: { state.ready }) { _, _ in
            throw Failure.offline
        }
        #expect(!reader.isConnected)
        state.ready = true
        #expect(reader.isConnected)
        await #expect(throws: Failure.offline) {
            _ = try await reader.forecast(entityId: "weather.demo_forecast", kind: .hourly)
        }
    }

    @Test func lateHouseEntityWaitsWithoutTimerThenStartsBothFeeds() async {
        let state = Readiness()
        let scheduler = ManualWeatherScheduler()
        let store = WeatherForecastStore(entityId: state.entity, scheduler: scheduler)
        let caller = Recorder()
        store.activate(caller: caller, revision: nil)
        await store.settle()
        store.update(revision: nil)
        store.setConnected(false)
        store.setConnected(true)
        await store.settle()
        #expect(caller.calls.isEmpty)
        #expect(scheduler.armedCount == 0)
        #expect(store.daily.showsPlaceholders && store.hourly.showsPlaceholders)
        state.entity = "weather.demo_forecast"
        store.update(revision: nil)
        await store.settle()
        #expect(caller.calls.count == 2)
        #expect(store.daily.phase == .empty && store.hourly.phase == .empty)
        store.deactivate()
    }

    @Test func rejectedForecastUsesDeckCopyInsteadOfRawServerText() async {
        let caller = Recorder()
        caller.fails = true
        let store = WeatherForecastStore(entityId: "weather.demo_forecast")
        store.activate(caller: caller, revision: nil)
        await store.settle()
        #expect(store.daily.error == WeatherCopy.forecastFailure(.daily))
        #expect(store.hourly.error == WeatherCopy.forecastFailure(.hourly))
        store.deactivate()
    }

    private enum Failure: Error { case offline }
    @MainActor private final class Readiness {
        var ready = false
        var entity = ""
    }
    @MainActor private final class Recorder: WeatherForecastCalling {
        var calls: [String] = []
        var fails = false
        func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
            let entity = data["entity_id"] as? String ?? ""
            calls.append("\(domain).\(service):\(entity):\(data["type"] as? String ?? "")")
            if fails { throw WeatherForecastError(message: "private schema text: entity_id") }
            return .object([entity: .object(["forecast": .array([])])])
        }
    }
}
