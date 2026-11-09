import Foundation

/// Saves the last good forecasts (and the frozen day briefing) so a cold launch draws the hourly carousel at once.
///
/// Lives in the Caches directory: it is a convenience copy that Home Assistant replaces within seconds of the
/// connection coming up, so the system may purge it. A snapshot from another server is ignored.
public struct WeatherForecastDiskCache: Sendable {
    /// On-disk format.
    public struct Snapshot: Codable, Sendable, Equatable {
        /// Format version; bump when ``WeatherForecast`` or the briefing change incompatibly.
        public var version: Int
        /// The server these forecasts came from.
        public var server: URL
        /// When the snapshot was last written.
        public var savedAt: Date
        public var daily: [WeatherForecast]
        public var dailyUpdatedAt: Date?
        public var hourly: [WeatherForecast]
        public var hourlyUpdatedAt: Date?
        public var briefing: WeatherDayBriefing?
    }

    static let currentVersion = 1

    private let fileURL: URL

    /// Creates a cache at a file location.
    /// - Parameter fileURL: Defaults to `Caches/WeatherForecasts.json`.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appending(path: "WeatherForecasts.json")
        }
    }

    /// Loads the snapshot for a server, or `nil` if missing, in an old format or for another server.
    public func load(for server: HassServer) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.version == Self.currentVersion,
              snapshot.server == server.baseURL else { return nil }
        return snapshot
    }

    /// Writes a snapshot atomically.
    public func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Deletes the cache (sign out).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Builds a snapshot for a server from the store's current feeds.
    static func snapshot(
        server: HassServer, savedAt: Date, daily: WeatherForecastFeed, hourly: WeatherForecastFeed, briefing: WeatherDayBriefing?
    ) -> Snapshot {
        Snapshot(
            version: currentVersion, server: server.baseURL, savedAt: savedAt,
            daily: daily.forecasts, dailyUpdatedAt: daily.updatedAt,
            hourly: hourly.forecasts, hourlyUpdatedAt: hourly.updatedAt, briefing: briefing
        )
    }
}
