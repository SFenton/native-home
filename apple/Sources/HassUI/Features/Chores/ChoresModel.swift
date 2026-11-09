import Foundation
import HassCore
import Observation
import SwiftUI

/// What the Chores, Groceries and To-Do pages share: the todo service, the list store and who is viewing.
///
/// Pages read it from the environment; ``ChoresModel/live(connection:session:)`` builds the app's, and the
/// debug gallery and tests build one over fixtures.
@MainActor
@Observable
final class ChoresModel {
    /// Calls services and lists items.
    let service: any TodoServicing
    /// One controller per list, shared across pages.
    let todos: TodoStore
    /// The signed-in Home Assistant user's id, once known (cached across launches).
    var viewerUserId: String?
    private let loadViewer: @MainActor () async -> String?
    let accessToken: @MainActor () async throws -> String

    /// The signed-in household member, if the user is one.
    var viewer: ChoresConfig.Resident? { ChoresConfig.Resident.forUserId(viewerUserId) }

    init(service: any TodoServicing, todos: TodoStore, viewerUserId: String?,
         loadViewer: @escaping @MainActor () async -> String? = { nil },
         accessToken: @escaping @MainActor () async throws -> String = { throw CancellationError() }) {
        self.service = service
        self.todos = todos
        self.viewerUserId = viewerUserId
        self.loadViewer = loadViewer
        self.accessToken = accessToken
    }

    /// Refreshes ``viewerUserId`` from the server, keeping the cached id when the lookup fails.
    func refreshViewer() async {
        guard let id = await loadViewer(), id != viewerUserId else { return }
        viewerUserId = id
    }

    /// Where the last viewer id is remembered, so a relaunch shows the right lists before the lookup.
    static let viewerDefaultsKey = "chores.viewerUserId"

    /// The app's model for a signed-in connection.
    static func live(connection: HassConnection, session: AppSession?, defaults: UserDefaults = .standard) -> ChoresModel {
        ChoresModel(
            service: connection,
            todos: TodoStore.shared(for: connection),
            viewerUserId: defaults.string(forKey: viewerDefaultsKey),
            loadViewer: {
                guard let id = try? await connection.currentUser().id else { return nil }
                defaults.set(id, forKey: viewerDefaultsKey)
                return id
            },
            accessToken: {
                guard let tokens = session?.tokens else { throw URLError(.userAuthenticationRequired) }
                return try await tokens.validAccessToken()
            }
        )
    }
}
