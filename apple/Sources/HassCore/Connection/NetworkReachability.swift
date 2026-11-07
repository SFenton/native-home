import Foundation
import Network
import os

/// Whether the device has any network path at all (Airplane mode, no Wi-Fi and no cellular).
///
/// ``HassConnection`` uses it to stop HAKit's reconnect backoff while there is nothing to reconnect over, to report
/// ``HassConnection/isOffline``, and to reconnect the moment a path returns.
public protocol NetworkReachability: Sendable {
    /// A usable network path exists right now.
    var isOnline: Bool { get }
    /// Starts watching; `onChange` runs on an arbitrary queue with the new state on every path update.
    func start(_ onChange: @escaping @Sendable (_ isOnline: Bool) -> Void)
}

/// Watches the system path with `NWPathMonitor`.
public final class SystemNetworkReachability: NetworkReachability, @unchecked Sendable {
    // Unchecked: `monitor` is configured once in `start` (guarded by `started`) and only touched again by `deinit`.
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sfenton.home.reachability")
    private let online = OSAllocatedUnfairLock(initialState: true)
    private let started = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    deinit { monitor.cancel() }

    public var isOnline: Bool { online.withLock { $0 } }

    public func start(_ onChange: @escaping @Sendable (Bool) -> Void) {
        let first = started.withLock { started in
            defer { started = true }
            return !started
        }
        guard first else { return }
        monitor.pathUpdateHandler = { [online] path in
            let value = path.status == .satisfied
            online.withLock { $0 = value }
            onChange(value)
        }
        monitor.start(queue: queue)
    }
}
