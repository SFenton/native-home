#if os(iOS)
import HassCore
import HassTelemetry
import ImageIO
import Observation
import UIKit

// MARK: - Session-owned publication transaction

/// One account-scoped store and refresh loop. Windows keep their own renderer and navigation.
@MainActor
@Observable
final class UKServerUIProductionRuntime {
    @MainActor final class Prepared {
        let assets: ServerUIStagedAssets
        let directory: URL
        private let photo: CGImage?
        private let blurPercent: Int
        private var backdrops: [UUID: HouseBackdropStore] = [:]
        private var plans: [UUID: UKServerUIProductionHost.ApplyPlan] = [:]
        private var providerGeneration: Int?
        init(assets: ServerUIStagedAssets, photo: CGImage?, blurPercent: Int, directory: URL) {
            self.assets = assets
            self.photo = photo
            self.blurPercent = blurPercent
            self.directory = directory
        }

        /// Geometry and blur rendering belong to a window, never to the session's first window. The render files do not: they are
        /// named by everything that shaped them, so every window, and the next launch, shares the publication's one folder (a
        /// relaunch draws its stored render on the first frame instead of rendering again).
        func backdrop(for host: UKServerUIProductionHost) throws -> HouseBackdropStore {
            if let value = backdrops[host.sceneID] { return value }
            let blur = BackdropBlurSettings(initialPercent: host.preferredBlurPercent(fallback: blurPercent))
            let value = photo.map {
                HouseBackdropStore(verifiedPhoto: $0, directory: directory, blur: blur)
            } ?? HouseBackdropStore.empty(directory: directory, blur: blur)
            try Self.requireGeometry(host.view.bounds.size)
            value.setWindow(host.view.bounds.size, scale: Double(host.traitCollection.displayScale))
            if backdrops.isEmpty {
                let directory = directory
                Task.detached(priority: .background) { Self.removeWindowFolders(in: directory) }
            }
            backdrops[host.sceneID] = value
            return value
        }

        /// Removes the per-window render folders earlier builds made, one per launch, named by a fresh scene UUID.
        nonisolated static func removeWindowFolders(in directory: URL) {
            let fileManager = FileManager.default
            guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil
                && (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fileManager.removeItem(at: entry)
            }
        }

        /// A scene that has not laid out yet has no window to size the backdrop to: timing, not a rejection. The store keeps the
        /// candidate and the host's first layout retries it (``UKServerUIProductionRuntime/layoutChanged(id:)``).
        static func requireGeometry(_ size: CGSize) throws {
            guard size.width > 0, size.height > 0 else { throw Failure.preparationChanged }
        }

        func prepare(host: UKServerUIProductionHost) async throws {
            let value = try backdrop(for: host)
            if photo != nil {
                await value.refresh()
                try Task.checkCancellation()
                // In the background the render waits for the foreground: timing, so the candidate is kept and retried then.
                if value.image == nil, value.isSuspended { throw Failure.preparationChanged }
                guard value.image != nil else { throw Failure.backdrop }
            }
        }

        /// The cold-launch backdrop: the window's store exists at once and its render finishes after the first frame, so the saved
        /// layout never waits on the blur.
        func adoptionBackdrop(for host: UKServerUIProductionHost) throws -> HouseBackdropStore {
            let existing = backdrops[host.sceneID]
            let value = try backdrop(for: host)
            if existing == nil, photo != nil { Task { await value.refresh() } }
            return value
        }

        func readyBackdrop(for host: UKServerUIProductionHost) throws -> HouseBackdropStore {
            let value = try backdrop(for: host)
            guard photo == nil || value.image != nil,
                  value.blur.percent == host.preferredBlurPercent(fallback: blurPercent) else { throw Failure.backdrop }
            return value
        }

        /// No renderer or provider factory is deferred until after the durable write.
        func prepareRenderers(_ publication: ServerUICompositionPublication,
                              hosts: [UKServerUIProductionHost], generation: Int) throws {
            var next: [UUID: UKServerUIProductionHost.ApplyPlan] = [:]
            for host in hosts { next[host.sceneID] = try host.prepareApply(publication, prepared: self) }
            plans = next
            providerGeneration = generation
        }

        /// Scene membership, geometry, interactions and authority may change while disk I/O awaits.
        func validatedPlans(hosts: [UKServerUIProductionHost], generation: Int) throws -> [UKServerUIProductionHost.ApplyPlan] {
            guard providerGeneration == generation else { throw Failure.preparationChanged }
            let current = try hosts.map { host in
                guard let plan = plans[host.sceneID] else { throw Failure.preparationChanged }
                try plan.validate()
                return plan
            }
            return current
        }

        /// Plans own detached renderers only until acceptance; retaining them would retain the session.
        func releasePlans() { plans.removeAll(); providerGeneration = nil }
    }

    private struct Consumer {
        weak var host: UKServerUIProductionHost?
    }
    private enum Failure: Error, ServerUIDeferrableFailure {
        case image, backdrop, sessionEnded, preparationChanged
        /// A scene or geometry change while preparing is a matter of timing; the candidate is kept and committed later.
        var isDeferred: Bool { self == .preparationChanged }
    }
    private(set) var store: ServerUIPublicationStore<Prepared>?
    private(set) var providerFailure = false
    @ObservationIgnored private var appliedProviderGeneration = 0
    @ObservationIgnored private weak var session: AppSession?
    @ObservationIgnored private let connection: HassConnection
    @ObservationIgnored private let privateRoot: URL
    @ObservationIgnored private var consumers: [UUID: Consumer] = [:]
    @ObservationIgnored private var subscription: ServerUIPublicationSubscription?
    @ObservationIgnored private var identityTask: Task<Void, Never>?
    @ObservationIgnored private var identityVerified = false
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var stager: ServerUIAssetStager?
    @ObservationIgnored private var root: URL?
    #if DEBUG
    @ObservationIgnored private var stubbed = false
    #endif
    let providers: UKServerUIProductionProviders

    /// Creates the session's one runtime: opens the cache for this server, restores its last-good publication on the calling
    /// thread (so the first window already has it), and follows the server's publication over `connection`.
    /// - Parameters:
    ///   - transport: How the publication is followed; tests pass a fake.
    ///   - assets: Where staged assets come from; the default is the integration's authenticated asset route.
    init(session: AppSession, connection: HassConnection,
         privateRoot: URL = URL.applicationSupportDirectory.appendingPathComponent("ServerUIProduction", isDirectory: true),
         preferencesDefaults: UserDefaults = .standard,
         transport: (any ServerUIPublicationTransport)? = nil, assets: (any ServerUIAssetFetching)? = nil) {
        self.session = session
        self.connection = connection
        self.privateRoot = privateRoot
        providers = UKServerUIProductionProviders(session: session, connection: connection,
            recordCacheRoot: privateRoot.appendingPathComponent("records", isDirectory: true), preferencesDefaults: preferencesDefaults)
        var source: any ServerUIPublicationTransport = transport ?? HassServerUIPublicationTransport(connection: connection)
        #if DEBUG
        if transport == nil, let stub = UKServerUIPublicationStub(environment: LaunchEnvironment.current) {
            source = stub
            stubbed = true
        }
        #endif
        configure(transport: source, assets: assets)
        restoreCachedPublication()
        startFollowing()
    }

    func attach(_ host: UKServerUIProductionHost, id: UUID) {
        consumers[id] = Consumer(host: host)
    }

    func detach(id: UUID) {
        consumers[id] = nil
        providers.detachRecordWindow(id)
    }

    /// A window's layout is the moment a candidate that waited for geometry can commit. Cheap when nothing is deferred.
    func layoutChanged(id: UUID) {
        guard !ended, consumers[id]?.host?.hasGeometry == true else { return }
        interactionMayHaveEnded()
    }

    /// A window returning to the foreground is one moment an open interaction may have ended.
    func setForeground(_ active: Bool, id: UUID) {
        guard !ended, active else { return }
        interactionMayHaveEnded()
    }

    func reconnected() async {
        await providers.connected()
        refreshProviders()
        await verifyIdentity()
        await store?.retryDeferred()
    }

    /// The publication is pushed, so there is nothing to poll: this asks the server for its current state again.
    func retry() async {
        guard !ended else { return }
        refreshProviders()
        subscription?.restart()
        await store?.retryDeferred()
    }

    /// Commits a candidate an open interaction deferred, now that one may have ended. Cheap when nothing is deferred.
    func interactionMayHaveEnded() {
        guard !ended, let store, store.hasDeferredCandidate else { return }
        Task { await store.retryDeferred() }
    }

    /// A house-config update can rebind idle controllers without requiring a new Studio revision.
    func refreshProviders() {
        // A layout held back for house configuration or the signed-in user commits as soon as either arrives.
        if !ended, let store, store.hasDeferredCandidate { Task { await store.retryDeferred() } }
        guard !ended, let current = store?.current, let prepared = store?.prepared else { return }
        // Nothing to do unless the house configuration moved or a provider generation is not applied yet: the preflight is
        // main-thread work and does not run on a schedule.
        guard providers.hasPendingConfiguration || appliedProviderGeneration != providers.generation else { return }
        do {
            try providers.prepare(current)
            guard appliedProviderGeneration != providers.generation else { return }
            try validate(current)
            let applies = try hosts.map { try $0.prepareApply(current, prepared: prepared) }
            for plan in applies { try plan.validate() }
            for plan in applies { try plan.apply() }
            appliedProviderGeneration = providers.generation
            providerFailure = false
        } catch {
            providerFailure = true
            NSLog("ServerUI retained the previous house provider bindings.")
        }
    }

    /// Explicit recovery for a corrupt/rejected disk cache. Never used while a last-good page exists.
    func resetRejectedCache() async {
        guard !ended, store?.current == nil else { return }
        await store?.reset()
        guard !ended else { return }
        subscription?.restart()
    }

    func endSession() {
        guard !ended else { return }
        ended = true
        identityTask?.cancel()
        providers.endSession()
        subscription?.stop()
        store?.endSession()
        let store = store, stager = stager
        Task { await store?.reset(purge: { try await stager?.purgePartition() }) }
        consumers.removeAll()
    }

    private var hosts: [UKServerUIProductionHost] { consumers.values.compactMap(\.host) }

    // MARK: - Following

    private func configure(transport: any ServerUIPublicationTransport, assets: (any ServerUIAssetFetching)?) {
        guard let partition = try? ServerUIPublicationPartition(server: connection.server) else {
            NSLog("ServerUI publication cache could not be keyed to this server.")
            return
        }
        let root = partition.storageDirectory(in: privateRoot)
        self.root = root
        let fetcher = assets ?? ServerUIAssetTransport(server: connection.server, tokenProvider: { [weak self] in
            guard let provider = await self?.activeToken() else { throw ServerUIAssetError.credentialUnavailable }
            return try await provider()
        })
        guard let stager = try? ServerUIAssetStager(partition: partition, partitionDirectory: root, transport: fetcher) else { return }
        self.stager = stager
        let store = ServerUIPublicationStore<Prepared>(
            partition: partition, cacheDirectory: root,
            prepare: { [weak self] publication, context in
                guard let self else { throw CancellationError() }
                return try await self.prepare(publication, context: context, stager: stager, root: root)
            }, discard: { candidate, protected in
                await candidate.releasePlans()
                try await stager.discard(candidate.assets, retaining: protected.map(\.assets))
                try await Self.removeRender(candidate.directory, retaining: protected)
            }, validate: { [weak self] publication, prepared in
                guard let self else { throw CancellationError() }
                try self.validate(publication)
                _ = try prepared.validatedPlans(hosts: self.hosts, generation: self.providers.generation)
            }, commit: { [weak self] publication, prepared in
                guard let self else { throw CancellationError() }
                defer { prepared.releasePlans() }
                try self.validate(publication)
                let applies = try prepared.validatedPlans(hosts: self.hosts, generation: self.providers.generation)
                // Validation and every visible apply share this main-actor turn.
                try self.session?.deliverExtensions(publication, applying: {
                    try self.session?.setup.configure(bootstrap: publication.document.bootstrap)
                    for plan in applies { try plan.apply() }
                })
                self.appliedProviderGeneration = self.providers.generation
                self.providerFailure = false
            })
        self.store = store
        subscription = ServerUIPublicationSubscription(transport: transport) { [weak self] event in
            await self?.store?.apply(event)
        }
    }

    /// Cold launch: the saved layout is read, staged assets re-adopted and the plan built before any window lays out.
    private func restoreCachedPublication() {
        guard let store, let stager, let root else { return }
        let restored = store.restoreSynchronously { publication, cachedUser in
            // The away settings are scoped to the signed-in user and the socket has not said who that is yet, so the saved
            // record's user stands in before any provider is built; without it every cold launch rejected the saved layout.
            session?.setPublicationUser(cachedUser, connection: connection)
            try providers.prepare(publication)
            let assets = try stager.restoreVerified(publication, documentDigest: publication.documentSha256)
            return Self.makePrepared(publication, assets: assets, root: root, photo: try Self.loadPhoto(for: publication, assets: assets))
        }
        guard restored, let publication = store.current else { return }
        if let user = store.userID { session?.setPublicationUser(user, connection: connection) }
        do {
            try session?.deliverExtensions(publication, applying: {
                try session?.setup.configure(bootstrap: publication.document.bootstrap)
            })
        } catch {
            Telemetry.event("serverui.restoredExtensionDeliveryFailed")
        }
        appliedProviderGeneration = providers.generation
    }

    /// With a restored cache the subscription starts at once; otherwise it starts when the user is known, because the cache
    /// record is keyed to that user.
    private func startFollowing() {
        guard let store else { return }
        #if DEBUG
        if stubbed {
            // A UI-test stub has no socket to say who is signed in.
            Task { await store.bind(userID: "ui-test"); subscription?.start() }
            return
        }
        #endif
        if store.userID != nil { subscription?.start() }
        identityTask = Task { [weak self] in await self?.verifyIdentity() }
    }

    /// Binds the cache to the verified Home Assistant user (`auth/current_user`, over the one socket) and follows the publication.
    private func verifyIdentity() async {
        guard !ended, !identityVerified, let store, session?.isCurrentConnection(connection) == true else { return }
        do {
            let user = try await connection.currentUser()
            guard !ended, !identityVerified, session?.isCurrentConnection(connection) == true else { return }
            identityVerified = true
            let matched = await store.bind(userID: user.id)
            guard !ended else { return }
            session?.setPublicationUser(user.id, connection: connection)
            session?.setRouteViewer(userID: user.id, isAdmin: user.isAdmin)
            await store.retryDeferred()
            if matched, subscription?.isStarted == true { return }
            subscription?.restart()
        } catch {
            // Offline or not yet authenticated: the next reconnect asks again.
            NSLog("ServerUI could not verify the signed-in user yet.")
        }
    }

    private func activeToken() async -> (@Sendable () async throws -> String)? {
        guard !ended, let tokens = session?.tokens else { return nil }
        return { try await tokens.validAccessToken() }
    }

    private func validate(_ publication: ServerUICompositionPublication) throws {
        guard !ended, let session, session.isCurrentConnection(connection) else { throw Failure.sessionEnded }
        try providers.prepare(publication)
        // A permission explanation and its system alert are a pinned interaction, not page decoration.
        guard !session.setup.blocksPublication else {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/bootstrap/setup")
        }
        for host in hosts { try host.validate(publication) }
    }

    private func prepare(_ publication: ServerUICompositionPublication,
                         context: ServerUIPreparationContext<Prepared>,
                         stager: ServerUIAssetStager, root: URL) async throws -> Prepared {
        try validate(publication)
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256,
                                           reservingBytes: context.cacheWriteBytes)
        let directory = Self.renderDirectory(publication, root: root)
        do {
            let photo = try await Task.detached(priority: .userInitiated) { try Self.loadPhoto(for: publication, assets: assets) }.value
            let prepared = Self.makePreparedValue(publication, assets: assets, directory: directory, photo: photo)
            for host in hosts { try await prepared.prepare(host: host) }
            try validate(publication)
            try prepared.prepareRenderers(publication, hosts: hosts, generation: providers.generation)
            return prepared
        } catch {
            try await stager.discard(assets, retaining: context.protected.map(\.assets))
            try Self.removeRender(directory, retaining: context.protected)
            throw error
        }
    }

    private nonisolated static func renderDirectory(_ publication: ServerUICompositionPublication, root: URL) -> URL {
        root.appendingPathComponent("renders", isDirectory: true)
            .appendingPathComponent(publication.documentSha256, isDirectory: true)
    }

    /// The decoded backdrop photo, or `nil` for a solid background.
    private nonisolated static func loadPhoto(for publication: ServerUICompositionPublication, assets: ServerUIStagedAssets) throws -> CGImage? {
        guard case let .downloaded(assetID, _, _, _, _, _) = publication.document.theme.background else { return nil }
        guard let file = assets.assets.first(where: { $0.id == assetID })?.fileURL,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.image }
        return image
    }

    private static func makePrepared(_ publication: ServerUICompositionPublication, assets: ServerUIStagedAssets,
                                     root: URL, photo: CGImage?) -> Prepared {
        makePreparedValue(publication, assets: assets, directory: renderDirectory(publication, root: root), photo: photo)
    }

    private static func makePreparedValue(_ publication: ServerUICompositionPublication, assets: ServerUIStagedAssets,
                                          directory: URL, photo: CGImage?) -> Prepared {
        let percent: Int
        switch publication.document.theme.background {
        case .solid: percent = 0
        case let .downloaded(_, _, blur, _, _, _):
            switch blur {
            case .fixed(let value): percent = value
            case .preference(_, let initial): percent = initial
            }
        }
        return Prepared(assets: assets, photo: photo, blurPercent: percent, directory: directory)
    }

    private static func removeRender(_ directory: URL, retaining protected: [Prepared]) throws {
        guard !protected.contains(where: { $0.directory == directory }),
              FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Deferred acceptance

/// An open interaction refuses a publication only for now; the store keeps the candidate and commits it later.
extension UKServerUIRendererError: ServerUIDeferrableFailure {
    public var isDeferred: Bool { code == .interactionBlocked || code == .inputsPending }
}

extension SetupCoordinator.ConfigurationError: ServerUIDeferrableFailure {
    public var isDeferred: Bool { true }
}
#endif
