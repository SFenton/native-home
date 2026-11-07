import HassCore

/// What a layout-driven page draws, given the house document and how the last attempt to get it went
/// (`.agents/design/house-config-states.md`, rules 10 to 12).
///
/// A saved layout always wins: whenever there is a document the answer is ``content``, whatever ``HouseConfigStore/Status``
/// says. Without one, a store that is still asking (or offline) shows the ``skeleton`` and a store that got a problem shows a
/// ``message``.
enum HouseLayoutState: Equatable {
    /// Which problem the message describes.
    enum Kind: Equatable, CaseIterable {
        case integrationMissing, notConfigured, invalid, newerSchema, timedOut
    }

    /// Who is looking: administrators and the owner get the actions that open Home Assistant's pages.
    enum Role: Equatable {
        case admin, member
        /// The user has not been loaded yet: the member copy with no action.
        case unknown

        /// The role of a Home Assistant user, or ``unknown`` before the user loaded.
        init(_ user: HassUser?) {
            guard let user else { self = .unknown; return }
            self = user.isAdmin || user.isOwner ? .admin : .member
        }
    }

    /// The document is there: draw the page.
    case content
    /// No document yet and the store is idle or loading (offline included): the page's own shape, pulsing.
    case skeleton
    /// No document and the server answered with a problem.
    case message(Kind, showsAction: Bool)

    /// - Parameters:
    ///   - document: The document the facades read (`HouseConfigSource.current`), or nil.
    ///   - status: ``HouseConfigStore/status``.
    ///   - role: Who is looking.
    /// - Returns: What the page draws.
    static func resolve(document: HouseConfig?, status: HouseConfigStore.Status, role: Role) -> HouseLayoutState {
        resolve(hasDocument: document != nil, status: status, role: role)
    }

    /// The same answer when the caller only knows whether a document exists, so it need not copy the whole document out of the
    /// source to ask.
    /// - Parameters:
    ///   - hasDocument: Whether the facades have a document.
    ///   - status: ``HouseConfigStore/status``.
    ///   - role: Who is looking.
    /// - Returns: What the page draws.
    static func resolve(hasDocument: Bool, status: HouseConfigStore.Status, role: Role) -> HouseLayoutState {
        if hasDocument { return .content }
        let admin = role == .admin
        switch status {
        case .idle, .loading, .ready: return .skeleton
        case .integrationMissing: return .message(.integrationMissing, showsAction: admin)
        case .notConfigured: return .message(.notConfigured, showsAction: admin)
        case .invalid: return .message(.invalid, showsAction: admin)
        case .newerSchema: return .message(.newerSchema, showsAction: false)
        case .timedOut: return .message(.timedOut, showsAction: true)
        }
    }
}
