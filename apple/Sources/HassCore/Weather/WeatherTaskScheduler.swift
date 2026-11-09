import Foundation

/// The production scheduler, backed by a sleeping `Task`.
@MainActor
public final class WeatherTaskScheduler: WeatherRefreshScheduling {
    public init() {}

    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}
