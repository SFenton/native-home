import Foundation
import HassTelemetry
import Observation
import os

// MARK: - Store

/// The last-good UI publication, followed from Home Assistant and kept on disk.
///
/// **Source.** Events come from ``ServerUIPublicationSubscription``; there is no poll and no fetch. Each `published` event is
/// ordered by the integration's `(epoch, revision)`: within one epoch an older revision is ignored; a new epoch starts ordering
/// over, which is how a reset integration store is followed (C19). Identical content under a new revision only updates the
/// stored ordering.
///
/// **Acceptance.** A candidate is prepared (assets staged, renderer built), validated, saved and committed in that order; any
/// failure leaves the visible last-good untouched and restores the prior cache record. A candidate refused only because an
/// interaction is open (``ServerUIDeferrableFailure``) is held by its digest and committed by ``retryDeferred()`` once the
/// interaction ends; nothing is fetched again.
///
/// **Cache.** One record per server origin carries the layout, the integration's epoch and revision (so ordering never
/// needs a decode) and the Home Assistant user it was delivered to. ``restoreSynchronously(prepare:)`` reads it on the main
/// thread for a cold launch; every other write and removal goes through one actor, so no disk I/O or decoding happens under a lock (C5).
/// ``bind(userID:)`` discards a record written for another user.
///
/// **Boundary.** ``remote`` says what the server last said. With no last-good, `unpublished` and `incompatible` select the
/// recovery boundaries; with a last-good both keep it on screen.
@MainActor
@Observable
public final class ServerUIPublicationStore<Prepared: Sendable> {
    /// Must verify capabilities, assets and initial rendering without changing the visible UI.
    /// A throwing preparation must clean up resources it has not returned to the store.
    public typealias Prepare = @Sendable (ServerUICompositionPublication, ServerUIPreparationContext<Prepared>) async throws -> Prepared
    /// Releases an abandoned or superseded preparation without removing protected resources.
    public typealias Discard = @Sendable (Prepared, [Prepared]) async throws -> Void
    /// Rechecks transient interaction eligibility without mutation, after asynchronous preparation.
    public typealias Validate = @MainActor @Sendable (ServerUICompositionPublication, Prepared) throws -> Void
    /// Final eligibility recheck and visible reconciliation, synchronously on the main actor.
    /// Must validate all consumers before mutating any; throwing leaves the visible last-good UI unchanged.
    public typealias Commit = @MainActor @Sendable (ServerUICompositionPublication, Prepared) throws -> Void

    private struct Ordering: Equatable {
        var epoch: String
        var revision: Int
        var envelopeSha256: String
        var bytes: Data
    }

    /// The last-good publication, or `nil` before the first acceptance.
    public private(set) var current: ServerUICompositionPublication?
    /// Changes only when the document itself changes, not when its publication metadata changes.
    public private(set) var document: ServerUICompositionDocument?
    /// Promoted only after preparation and the durable write both succeed.
    public private(set) var prepared: Prepared?
    /// Protects the preceding scene while the renderer finishes its publication transition.
    public private(set) var previousPrepared: Prepared?
    /// The latest acceptance outcome.
    public private(set) var status: ServerUIPublicationStatus = .idle
    /// What the server last said.
    public private(set) var remote: ServerUIPublicationRemoteState = .waiting
    /// The Home Assistant user the cache is bound to: the record's user after a restore, the verified user after ``bind(userID:)``.
    public private(set) var userID: String?

    /// Why the last acceptance failed: the error case and JSON pointer only, never a value. Cleared by a successful adoption.
    public private(set) var rejection: String?

    /// The integration's revision of the last-good publication.
    public var revision: Int? { ordering?.revision }
    /// The integration's epoch of the last-good publication.
    public var epoch: String? { ordering?.epoch }
    /// Whether a candidate is waiting for an open interaction to end.
    public var hasDeferredCandidate: Bool { pending != nil }

    @ObservationIgnored private let partition: ServerUIPublicationPartition
    @ObservationIgnored private let prepare: Prepare
    @ObservationIgnored private let discard: Discard
    @ObservationIgnored private let validate: Validate
    @ObservationIgnored private let commit: Commit
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let cache: ServerUIPublicationDiskCache
    @ObservationIgnored private let session = UUID()
    @ObservationIgnored private let log = Logger(subsystem: "com.sfenton.home", category: "ServerUI")
    @ObservationIgnored private var ordering: Ordering?
    @ObservationIgnored private var pending: ServerUIPublicationEvent.Published?
    @ObservationIgnored private var incoming: ServerUIPublicationEvent.Published?
    @ObservationIgnored private var rejectedDigest: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var working = false
    @ObservationIgnored private var resetting = false
    @ObservationIgnored private var ending = false
    @ObservationIgnored private var claimed = false
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a store for one server origin.
    /// - Parameters:
    ///   - partition: The server whose cache this is.
    ///   - cacheDirectory: ``ServerUIPublicationPartition/storageDirectory(in:)``; the record, staged assets and renders share its 50 MiB budget.
    ///   - prepare: Stages assets and builds the plan.
    ///   - discard: Releases a plan.
    ///   - validate: Rechecks eligibility.
    ///   - commit: Applies visibly.
    public init(partition: ServerUIPublicationPartition, cacheDirectory: URL,
                prepare: @escaping Prepare, discard: @escaping Discard,
                validate: @escaping Validate = { _, _ in }, commit: @escaping Commit = { _, _ in }) {
        self.partition = partition
        self.prepare = prepare
        self.discard = discard
        self.validate = validate
        self.commit = commit
        file = ServerUIPublicationFile.url(in: cacheDirectory, partition: partition)
        cache = ServerUIPublicationDiskCache.cache(for: file, root: cacheDirectory, partition: partition)
    }

    // MARK: - Identity and restore

    /// Binds the cache to the verified Home Assistant user (`auth/current_user`).
    ///
    /// A cache restored for a different user is discarded first, so nothing of another account's layout stays.
    /// - Returns: Whether the cache already belonged to this user (or there was none); `false` after a discard, when the caller
    ///   should ask the server again.
    @discardableResult
    public func bind(userID verified: String) async -> Bool {
        guard ServerUIPublicationPartition.isUserID(verified), !ending else { return false }
        guard let existing = userID, existing != verified else {
            userID = verified
            return true
        }
        await reset()
        userID = verified
        return false
    }

    /// Reads the last-good record on the calling thread and adopts it, so a cold launch shows the saved layout before its first frame.
    ///
    /// Reads and compiles the envelope and calls `prepare` (which re-adopts staged assets without the network); nothing is
    /// committed here, because the windows adopt `current` and `prepared` themselves in their first layout pass. A bad record is
    /// reported through ``status`` and left for the next publication to replace.
    ///
    /// `prepare` receives the Home Assistant user the record was delivered to: providers that are scoped to the signed-in user
    /// (the household-away settings) cannot be built before the socket says who that is, so the cached id stands in for it.
    /// - Parameter prepare: Builds the plan from the decoded publication and the record's user id.
    /// - Returns: Whether a publication was restored.
    @discardableResult
    public func restoreSynchronously(prepare: (ServerUICompositionPublication, _ userID: String) throws -> Prepared) -> Bool {
        guard current == nil, !ending, !resetting, !working else { return false }
        let interval = Telemetry.begin(Telemetry.Name.houseConfigRead)
        defer { Telemetry.end(interval, detail: current == nil ? "serverui miss" : "serverui hit") }
        do {
            guard let record = try ServerUIPublicationFile.read(at: file, partition: partition) else { return false }
            let publication = try ServerUICompositionPublication.decode(record.bytes)
            let value = try prepare(publication, record.userID)
            adopt(publication, ordering: .init(epoch: record.epoch, revision: record.revision,
                                               envelopeSha256: record.envelopeSha256, bytes: record.bytes),
                  prepared: value, documentChanged: true)
            userID = record.userID
            return true
        } catch {
            // A saved layout whose inputs have not arrived yet (house configuration) is not rejected: nothing is adopted and the
            // first event from the server prepares it, deferring until the inputs are there.
            if (error as? any ServerUIDeferrableFailure)?.isDeferred != true { report(error, epoch: generation) }
            return false
        }
    }

    // MARK: - Events

    /// Handles one event from the subscription. Events arrive one at a time and every one is the full current state.
    public func apply(_ event: ServerUIPublicationEvent) async {
        guard !ending, !resetting else { return }
        switch event {
        case .unpublished:
            pending = nil
            remote = .unpublished
        case let .incompatible(_, _, missing):
            pending = nil
            remote = .incompatible(missing: missing)
        case let .invalid(error):
            rejection = ServerUIRejectionDiagnostic.describe(error)
            log.error("Publication invalid: \(self.rejection ?? "unknown", privacy: .public)")
            status = .failure(error)
        case let .published(candidate):
            remote = .published
            incoming = candidate
            await drain()
        }
    }

    /// Commits the candidate an open interaction deferred, if there is one. Call when an interaction ends, a window returns to the
    /// foreground or the house configuration changes; it does nothing while another acceptance runs.
    public func retryDeferred() async {
        guard !ending, !resetting, let candidate = pending else { return }
        incoming = candidate
        await drain()
    }

    private func drain() async {
        guard !working else { return }
        working = true
        defer {
            working = false
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume() }
        }
        while let next = incoming {
            incoming = nil
            await process(next)
        }
    }

    private func process(_ candidate: ServerUIPublicationEvent.Published) async {
        let epoch = generation
        guard valid(epoch) else { return }
        if let ordering {
            if ordering.epoch == candidate.epoch {
                // Same epoch: strictly newer wins; the same revision must be the same content.
                if candidate.revision < ordering.revision { return }
                if candidate.revision == ordering.revision {
                    if candidate.envelopeSha256 != ordering.envelopeSha256 { status = .failure(.revisionConflict) }
                    return
                }
            }
            if candidate.envelopeSha256 == ordering.envelopeSha256 {
                await refreshOrdering(candidate, epoch: epoch)
                return
            }
        }
        if candidate.envelopeSha256 == rejectedDigest { return }
        pending = nil
        status = .loading
        do {
            try await stageAndAdopt(candidate, epoch: epoch)
            rejectedDigest = nil
        } catch {
            guard valid(epoch) else { return }
            if (error as? any ServerUIDeferrableFailure)?.isDeferred == true {
                pending = candidate
                status = current == nil ? .loading : .ready
            } else {
                // Only a rejection of the content itself (decode, capabilities, hash) is keyed: the same bytes will be refused
                // again. A runtime or preparation failure (an asset fetch, a provider that is not ready, a closed session) says
                // nothing about the content, so the next resubscribe or Try Again prepares it afresh.
                if error is ServerUICompositionError { rejectedDigest = candidate.envelopeSha256 }
                report(error, epoch: epoch)
            }
        }
    }

    /// New ordering for content the store already holds: persisted, never re-staged.
    private func refreshOrdering(_ candidate: ServerUIPublicationEvent.Published, epoch: Int) async {
        let next = Ordering(epoch: candidate.epoch, revision: candidate.revision,
                            envelopeSha256: candidate.envelopeSha256, bytes: candidate.bytes)
        guard let record = record(for: next) else { return }
        do {
            try await ensureClaimed()
            try await cache.save(record, session: session)
            guard valid(epoch) else { return }
            ordering = next
            pending = nil
            status = .ready
        } catch {
            report(error, epoch: epoch)
        }
    }

    private func stageAndAdopt(_ candidate: ServerUIPublicationEvent.Published, epoch: Int) async throws {
        let next = Ordering(epoch: candidate.epoch, revision: candidate.revision,
                            envelopeSha256: candidate.envelopeSha256, bytes: candidate.bytes)
        guard let record = record(for: next) else { throw ServerUIStoreError.invalidPartition }
        try await ensureClaimed()
        let reservation = try await cache.encodedSize(record)
        guard valid(epoch) else { throw CancellationError() }
        let publication = candidate.publication
        let planned = try await prepare(publication, .init(protected: protectedPreparations, cacheWriteBytes: reservation))
        let prior = ordering.flatMap { self.record(for: $0) }
        var saved = false
        do {
            guard valid(epoch) else { throw CancellationError() }
            try validate(publication, planned)
            try await cache.save(record, session: session)
            saved = true
            guard valid(epoch) else { throw CancellationError() }
            // No suspension between this check, reconciliation and adoption. A command or modal started while
            // assets or disk were preparing must not be removed by this publication.
            try validate(publication, planned)
            try commit(publication, planned)
        } catch {
            if saved, valid(epoch) {
                do { try await cache.restore(prior, replacing: record, session: session) }
                catch {
                    try await discardCandidate(planned)
                    throw ServerUIStoreError.cacheWrite
                }
            }
            try await discardCandidate(planned)
            throw error
        }
        let oldDocument = current?.document
        let changed = await Task.detached(priority: .userInitiated) { publication.document != oldDocument }.value
        let expired = previousPrepared
        previousPrepared = prepared
        adopt(publication, ordering: next, prepared: planned, documentChanged: changed)
        if let expired { try await discardCandidate(expired) }
    }

    private func adopt(_ publication: ServerUICompositionPublication, ordering next: Ordering,
                       prepared value: Prepared, documentChanged: Bool) {
        if documentChanged { document = publication.document }
        current = publication
        prepared = value
        ordering = next
        pending = nil
        remote = .published
        status = .ready
        rejection = nil
    }

    private func record(for ordering: Ordering) -> ServerUIPublicationRecord? {
        guard let userID else { return nil }
        return .init(origin: partition.origin, userID: userID, epoch: ordering.epoch, revision: ordering.revision,
                     envelopeSha256: ordering.envelopeSha256, bytes: ordering.bytes)
    }

    private func ensureClaimed() async throws {
        guard !claimed else { return }
        await cache.claim(session)
        claimed = true
    }

    private var protectedPreparations: [Prepared] { [prepared, previousPrepared].compactMap { $0 } }

    private func discardCandidate(_ candidate: Prepared) async throws {
        // Reset cancels the caller's task; cleanup still has to run to completion.
        let discard = self.discard, protected = protectedPreparations
        let cleanup = Task.detached { try await discard(candidate, protected) }
        do { try await cleanup.value }
        catch {
            log.error("Publication resource cleanup failed; the candidate was not reused.")
            throw ServerUIStoreError.preparationCleanup
        }
    }

    private func valid(_ epoch: Int) -> Bool { epoch == generation && !Task.isCancelled && !resetting && !ending }

    private func report(_ error: any Error, epoch: Int) {
        guard valid(epoch) else { return }
        rejection = ServerUIRejectionDiagnostic.describe(error)
        log.error("Publication rejected: \(self.rejection ?? "unknown", privacy: .public)")
        switch error {
        case let error as ServerUIStoreError: status = .failure(error)
        case let error as ServerUICompositionError: status = .failure(.composition(error))
        case let error as ServerUIAssetError: status = .failure(.asset(error))
        default: status = .failure(.acceptanceRejected)
        }
    }

    // MARK: - Reset

    /// Drops the last-good publication and its cache record and lets the next event start over. Never touches another origin.
    /// - Parameter purge: Removes staged assets; runs after any acceptance in flight has cleaned up.
    public func reset(purge: @Sendable () async throws -> Void = {}) async {
        guard !resetting else { return }
        resetting = true
        generation += 1
        let resources = protectedPreparations
        current = nil
        document = nil
        prepared = nil
        previousPrepared = nil
        ordering = nil
        pending = nil
        incoming = nil
        rejectedDigest = nil
        remote = .waiting
        status = .idle
        if working { await withCheckedContinuation { idleWaiters.append($0) } }
        do { try await cache.clear() }
        catch { status = .failure(.cacheClear) }
        claimed = false
        let discard = self.discard
        for resource in resources {
            do { try await discard(resource, []) }
            catch {
                log.error("Publication resource cleanup failed during reset.")
                status = .failure(.preparationCleanup)
            }
        }
        do { try await purge() }
        catch {
            log.error("Publication partition cleanup failed during reset.")
            status = .failure(.cacheClear)
        }
        resetting = false
    }

    /// Cancels pending work at once and removes the cache record before any asynchronous teardown starts. Terminal.
    public func endSession() {
        guard !ending else { return }
        ending = true
        generation += 1
        incoming = nil
        pending = nil
        try? ServerUIPublicationFile.remove(at: file)
    }
}
