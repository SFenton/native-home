import Foundation

/// A short, local trace of what the notification extensions did, for debugging pushes on a device.
///
/// Extensions can't be attached to or easily logged from on a phone, so debug builds append one line per step to
/// `Library/Caches/push-trace.log` in the app group container, which `xcrun devicectl device copy from --domain-type
/// appGroupDataContainer --domain-identifier group.com.sfenton.home` reads. Lines never carry tokens or message
/// text, only step names, entity ids and HTTP statuses. Release builds record nothing.
public struct PushTrace: Sendable {
    /// Lines kept; older ones are dropped.
    public static let limit = 200
    /// The trace file's name.
    public static let fileName = "push-trace.log"

    private let file: URL?

    /// Creates a trace.
    /// - Parameter directory: Where the file lives; nil records nothing.
    public init(directory: URL?) {
        file = directory?.appendingPathComponent(Self.fileName)
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    /// The app group's trace in debug builds; a no-op trace otherwise.
    public static var shared: PushTrace {
        #if DEBUG
        // Under Library: devicectl copies only from Library, Documents and tmp.
        PushTrace(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeychainTokenStore.sharedAccessGroup)?
            .appendingPathComponent("Library/Caches"))
        #else
        PushTrace(directory: nil)
        #endif
    }

    /// Appends a line, stamped with the time and the process.
    public func record(_ line: String, now: Date = Date()) {
        guard let file else { return }
        let stamp = ISO8601DateFormatter().string(from: now)
        let entry = "\(stamp) \(ProcessInfo.processInfo.processName): \(line)"
        let existing = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        let kept = (existing + [entry]).suffix(Self.limit)
        try? kept.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// The recorded lines, oldest first.
    public func lines() -> [String] {
        guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}
