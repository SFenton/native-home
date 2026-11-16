import Foundation

// MARK: - Store errors and status

/// A sanitized store failure. No account, document content, URL, or underlying error is exposed.
public enum ServerUIStoreError: Error, Equatable, Sendable {
    case invalidPartition
    case cacheRead
    case cacheWrite
    case cacheClear
    case corruptCache
    case wrongPartition
    case unsupportedCacheVersion
    case revisionConflict
    case staleGeneration
    case acceptanceRejected
    case preparationCleanup
    /// The server refused the subscription (the integration is missing or older than this build).
    case subscription
    /// An event was not the shape the integration documents.
    case malformedEvent
    case composition(ServerUICompositionError)
    case asset(ServerUIAssetError)
}

/// A failure the store keeps as a candidate to commit later instead of rejecting.
///
/// The UI layer conforms its "an interaction is open" error to this; the store then holds the publication by digest
/// and commits it when ``ServerUIPublicationStore/retryDeferred()`` runs after the interaction ends, instead of asking the server again.
public protocol ServerUIDeferrableFailure: Error {
    /// Whether the failure is only a matter of timing.
    var isDeferred: Bool { get }
}

/// Resources that preparation must protect, and space needed for the atomic cache write.
public struct ServerUIPreparationContext<Prepared: Sendable>: Sendable {
    /// Prepared plans whose resources must survive this preparation.
    public let protected: [Prepared]
    /// Bytes reserved for the atomic cache write.
    public let cacheWriteBytes: Int

    /// Creates a context.
    public init(protected: [Prepared], cacheWriteBytes: Int) {
        self.protected = protected
        self.cacheWriteBytes = cacheWriteBytes
    }
}

/// How accepting the newest publication is going, independent of the wire.
public enum ServerUIPublicationStatus: Equatable, Sendable {
    case idle, loading, ready
    case failure(ServerUIStoreError)
}

/// What the server last said, used only when there is no last-good publication to show.
public enum ServerUIPublicationRemoteState: Equatable, Sendable {
    /// Nothing heard yet.
    case waiting
    /// A publication reached the store.
    case published
    /// Nothing is published; the recovery boundary applies without a last-good.
    case unpublished
    /// The newest publications need capabilities this build lacks; the "update the app" boundary applies without a last-good.
    case incompatible(missing: [String])
}
