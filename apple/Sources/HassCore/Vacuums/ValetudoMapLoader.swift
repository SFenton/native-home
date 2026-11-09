import Foundation
import Observation

/// Where a shown map came from (web `ValetudoMapCard` provenance).
public enum ValetudoMapProvenance: String, Sendable {
    /// Polled while the vacuum is available.
    case live
    /// The camera's last image while the vacuum is unavailable ("Last Reported Map").
    case reported
    /// Nothing to show.
    case none
}

/// Loads the Valetudo map from the `camera.<map>_map_data` picture and keeps the last good map on screen.
///
/// While the vacuum is available the map is re-read every ``pollInterval`` (web: 3.5 s); while it is unavailable
/// the camera's last picture is read once and shown as reported, with only the robot and dock (web
/// `reportedOnly`).
@MainActor
@Observable
public final class ValetudoMapLoader {
    /// Reads a URL's bytes. Injected so tests and the gallery never touch the network.
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// The web's live poll interval.
    public static let pollInterval: Duration = .milliseconds(3500)

    /// The last decoded map.
    public private(set) var map: ValetudoMap?
    /// Live or reported.
    public private(set) var provenance: ValetudoMapProvenance = .none
    /// The last load failed and no map is shown.
    public private(set) var failed = false

    @ObservationIgnored private let fetch: Fetch

    /// Creates a loader.
    /// - Parameter fetch: Reads a URL; defaults to an uncached `URLSession` request.
    public init(fetch: @escaping Fetch = ValetudoMapLoader.urlSessionFetch) {
        self.fetch = fetch
    }

    /// Shows a map directly (gallery and tests).
    public func show(_ map: ValetudoMap?, provenance: ValetudoMapProvenance) {
        self.map = provenance == .reported ? map?.reportedOnly() : map
        self.provenance = map == nil ? .none : provenance
        failed = false
    }

    /// Loads once from `url`.
    /// - Parameters:
    ///   - url: The camera's absolute `entity_picture` URL.
    ///   - live: Whether the vacuum is available.
    public func load(from url: URL, live: Bool) async {
        do {
            let data = try await fetch(url)
            let decoded = try ValetudoMapDecoder.map(fromPNG: data)
            show(decoded, provenance: live ? .live : .reported)
        } catch {
            // Keep the last good map; only an empty card reports the failure.
            if map == nil { failed = true }
        }
    }

    /// Loads now and, while `live`, again every ``pollInterval`` until the task is cancelled (`.task(id:)`).
    public func run(url: URL?, live: Bool) async {
        guard let url else {
            if map == nil { provenance = .none }
            return
        }
        await load(from: url, live: live)
        guard live else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            await load(from: url, live: true)
        }
    }

    /// The production fetch: no cache, HTTP 200 only.
    public static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// The camera picture as an absolute URL on `server`.
    public static func pictureURL(_ entity: EntityState?, server: HassServer) -> URL? {
        guard let picture = entity?.attributes["entity_picture"]?.string else { return nil }
        return URL(string: picture, relativeTo: server.baseURL)?.absoluteURL
    }
}
