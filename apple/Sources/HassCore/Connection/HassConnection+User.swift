import Foundation
@preconcurrency import HAKit

/// The Home Assistant user the app is signed in as (`auth/current_user`).
public struct HassUser: Equatable, Sendable {
    /// User id.
    public var id: String
    /// Display name, when the server has one.
    public var name: String?
    /// Whether the user owns the instance.
    public var isOwner: Bool
    /// Whether the user is an administrator (can open Home Assistant's own Settings pages).
    public var isAdmin: Bool

    /// Creates a user value.
    public init(id: String, name: String?, isOwner: Bool, isAdmin: Bool) {
        self.id = id
        self.name = name
        self.isOwner = isOwner
        self.isAdmin = isAdmin
    }

    /// The role shown in Settings: Owner, Administrator or User.
    public var roleTitle: String {
        if isOwner { return "Owner" }
        return isAdmin ? "Administrator" : "User"
    }
}

extension HassConnection {
    /// Fetches the signed-in user over the existing websocket.
    public func currentUser() async throws -> HassUser {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HassUser, Error>) in
            connection.send(.currentUser()) { @Sendable result in
                switch result {
                case let .success(user):
                    continuation.resume(returning: HassUser(id: user.id, name: user.name, isOwner: user.isOwner, isAdmin: user.isAdmin))
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension HassConnection: HassCommandSending {
    public func command(_ type: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await requestJSON(type, data: data)
    }
}
