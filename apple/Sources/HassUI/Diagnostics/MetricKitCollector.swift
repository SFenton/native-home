import Foundation
import HassTelemetry
#if canImport(MetricKit) && os(iOS)
import MetricKit
#endif

/// Keeps MetricKit's daily metric and diagnostic payloads (scroll hitch ratio, hangs, launch times) on disk so the
/// Performance screen can show and export them (pattern: `.agents/patterns/telemetry.md`).
///
/// MetricKit only delivers on physical devices, about once a day; simulators never receive payloads.
@MainActor
public final class MetricKitCollector: NSObject {
    /// The app's collector.
    public static let shared = MetricKitCollector()

    /// Where payload JSON files are kept.
    public let directory: URL

    /// Creates a collector writing to `directory` (default `Caches/MetricKit`).
    public init(directory: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appendingPathComponent("MetricKit", isDirectory: true)
        super.init()
    }

    /// Subscribes to MetricKit. Safe to call more than once.
    public func start() {
        #if canImport(MetricKit) && os(iOS)
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        #endif
    }

    private var started = false

    /// Saves one payload's JSON.
    /// - Parameters:
    ///   - json: The payload's `jsonRepresentation()`.
    ///   - kind: `metrics` or `diagnostics`.
    ///   - date: Names the file.
    nonisolated func store(_ json: Data, kind: String, date: Date = .now) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(kind)-\(Int(date.timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json"
        try? json.write(to: directory.appendingPathComponent(name), options: .atomic)
        Telemetry.count("metrickit.\(kind)")
    }

    /// Saved payload files, newest first.
    public func payloads() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Every saved payload as parsed JSON, for the export file.
    public func payloadObjects() -> [Any] {
        payloads().compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        }
    }

    /// The newest scroll hitch ratio MetricKit reported (ms per s), if any.
    public func latestScrollHitchRatio() -> Double? {
        for url in payloads() where url.lastPathComponent.hasPrefix("metrics") {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let value = Self.findHitchRatio(in: object) else { continue }
            return value
        }
        return nil
    }

    /// Finds `scrollHitchTimeRatio` anywhere in a payload and returns it in ms per s.
    nonisolated static func findHitchRatio(in object: Any) -> Double? {
        if let dictionary = object as? [String: Any] {
            if let ratio = dictionary["scrollHitchTimeRatio"] {
                // MetricKit's JSON writes measurements as "3.2 ms per s" strings or {value, unit} objects.
                if let text = ratio as? String { return Double(text.split(separator: " ").first ?? "") }
                if let nested = ratio as? [String: Any], let value = nested["value"] as? Double { return value }
                if let value = ratio as? Double { return value }
            }
            for value in dictionary.values {
                if let found = findHitchRatio(in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findHitchRatio(in: value) { return found }
            }
        }
        return nil
    }

    /// Deletes saved payloads.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

#if canImport(MetricKit) && os(iOS)
extension MetricKitCollector: MXMetricManagerSubscriber {
    public nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { store(payload.jsonRepresentation(), kind: "metrics") }
    }

    public nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { store(payload.jsonRepresentation(), kind: "diagnostics") }
    }
}
#endif
