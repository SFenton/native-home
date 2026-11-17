#if os(iOS) && DEBUG
import HassCore
import Observation
import UIKit

// MARK: - Ephemeral read-only state

/// Owns the preview's only connection. Neither the connection nor its token is exposed to configured actions.
@MainActor
final class UKServerUIPreviewLiveData {
    struct Configuration: Decodable, Sendable {
        let server: String
        let accountID: String

        func validatedServer() throws -> HassServer {
            guard let url = URLComponents(string: server), url.scheme == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
                  let origin = url.url, !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  accountID.utf16.count <= 160 else { throw Failure.configuration }
            return HassServer(baseURL: origin)
        }
    }

    enum Failure: Error, LocalizedError {
        case configuration, credential, commandsDisabled

        var errorDescription: String? {
            switch self {
            case .configuration: "Live preview requires an HTTPS Home Assistant origin and an isolated account identity."
            case .credential: "A one-time preview credential (FENTON_PREVIEW_HA_TOKEN) is missing or invalid."
            case .commandsDisabled: "Live commands are disabled in this read-only design preview."
            }
        }
    }

    /// Keeps canonical controls visible without pretending a command succeeded or changing live entity values.
    @MainActor @Observable
    final class ReadOnlyCaller: HassServiceResponding {
        private(set) var blockedCommands = 0

        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            try reject()
        }

        func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
            try reject()
        }

        /// Counts, announces and throws; every write path of the preview ends here.
        func reject() throws -> Never {
            blockedCommands += 1
            NSLog("ServerUI preview: live device command blocked by read-only policy.")
            UIAccessibility.post(notification: .announcement, argument: Failure.commandsDisabled.errorDescription)
            throw Failure.commandsDisabled
        }
    }

    let connection: HassConnection
    let lifecycle: ConnectionLifecycle
    let caller = ReadOnlyCaller()

    init(configuration: Configuration, credential: String, directory: URL, store: EntityStore) throws {
        let server = try configuration.validatedServer()
        guard !credential.isEmpty, !credential.contains(where: \.isWhitespace) else { throw Failure.credential }
        let tokens = TokenManager(store: InMemoryTokenStore(),
                                  initial: AuthTokens(accessToken: credential, expiresAt: .distantFuture, refreshToken: ""))
        connection = HassConnection(server: server, tokens: tokens, store: store,
                                    snapshotCache: EntitySnapshotCache(fileURL: directory.appendingPathComponent("EntitySnapshot.json")),
                                    reachability: SystemNetworkReachability())
        lifecycle = ConnectionLifecycle(connection: connection)
    }

    /// Wraps a connection built elsewhere; a test passes one over a mock HAKit connection that records every request it is sent.
    init(connection: HassConnection) {
        self.connection = connection
        lifecycle = ConnectionLifecycle(connection: connection)
    }

    deinit {
        let lifecycle = lifecycle
        Task { @MainActor in lifecycle.stop() }
    }

    var context: UKContext {
        UKContext(store: connection.store, caller: caller).with { $0.valuesPending = true }
    }

    /// Only accepted weather sources can request forecasts through the existing websocket.
    func weatherReader(for document: ServerUICompositionDocument) -> ServerUIWeatherReader {
        let ids = document.dataSources.compactMap { source -> String? in
            guard case .homeWeather(_, let configuration) = source else { return nil }
            return configuration.weatherEntityId
        }
        let connection = connection
        return ServerUIWeatherReader(entityIds: Set(ids), caller: connection, connected: {
            if case .connected = connection.status { return true }
            return false
        })
    }

    /// The reader and renderer lease the same canonical pool; recording still uses the rejecting caller.
    func cameraReader(for document: ServerUICompositionDocument,
                      pool: CameraStreamPool = .shared) -> UKCameraReadProvider {
        let descriptors = document.dataSources.compactMap { source -> ServerUICameraDescriptor? in
            guard case .camera(_, let configuration) = source else { return nil }
            return configuration
        }
        return UKCameraReadProvider(descriptors: descriptors, connection: connection, store: connection.store, pool: pool)
    }

    /// Only connection-wide changes are observed; entity deltas still update their individual boxes.
    var receipt: [String: Any] {
        ["connectionStatus": "\(connection.status)", "freshness": "\(connection.store.freshness)",
         "reapplyGeneration": connection.store.reapplyGeneration,
         "blockedCommands": caller.blockedCommands]
    }
}
#endif
