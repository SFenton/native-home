import Foundation
import Testing
@testable import HassCore

// MARK: - Controlled preparation

private actor PreparationLog {
    struct Plan: Equatable, Sendable {
        let revision: Int
        let instance: Int
    }
    var prepares: [Int] = []
    var cleanups: [Int] = []
    var reservations: [Int] = []
    func prepare(_ publication: ServerUICompositionPublication, _ context: ServerUIPreparationContext<Plan>) -> Plan {
        prepares.append(publication.revision)
        reservations.append(context.cacheWriteBytes)
        return Plan(revision: publication.revision, instance: prepares.count)
    }
    func discard(_ plan: Plan) { cleanups.append(plan.instance) }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func set() { lock.withLock { raised = true } }
    var value: Bool { lock.withLock { raised } }
}

private struct Open: Error, ServerUIDeferrableFailure { var isDeferred: Bool { true } }
private struct Broken: Error {}
private struct Located: Error, ServerUIDiagnosable { var diagnostic: String { "unavailable_source at /synthetic/pointer" } }

private actor Gate {
    var entered = false
    var waiting: CheckedContinuation<Void, Never>?
    var observer: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { waiting = $0 }
    }
    func untilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
}

// MARK: - Store

@Suite @MainActor struct ServerUIPublicationStoreTests {
    private typealias F = ServerUIPublicationFixtures
    private typealias Plan = PreparationLog.Plan
    private typealias Store = ServerUIPublicationStore<Plan>

    private func store(_ dir: URL, _ log: PreparationLog, server: HassServer = F.server,
                       prepare: Store.Prepare? = nil, validate: @escaping Store.Validate = { _, _ in },
                       commit: @escaping Store.Commit = { _, _ in }) throws -> Store {
        Store(partition: try .init(server: server), cacheDirectory: dir,
              prepare: prepare ?? { await log.prepare($0, $1) },
              discard: { plan, _ in await log.discard(plan) }, validate: validate, commit: commit)
    }

    private func bound(_ dir: URL, _ log: PreparationLog, user: String = "user-1", server: HassServer = F.server,
                       prepare: Store.Prepare? = nil, validate: @escaping Store.Validate = { _, _ in },
                       commit: @escaping Store.Commit = { _, _ in }) async throws -> Store {
        let instance = try store(dir, log, server: server, prepare: prepare, validate: validate, commit: commit)
        await instance.bind(userID: user)
        return instance
    }

    // MARK: Acceptance and ordering

    @Test func aPublishedEventIsPreparedCommittedAndSavedWithItsOrdering() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var commits: [Int] = []
        let instance = try await bound(dir, log, commit: { publication, _ in commits.append(publication.revision) })
        await instance.apply(try F.event(revision: 5))
        #expect(instance.status == .ready)
        #expect(instance.remote == .published)
        #expect(instance.epoch == "epoch-1" && instance.revision == 5)
        #expect(instance.current != nil && instance.document != nil)
        #expect(instance.prepared?.instance == 1)
        #expect(commits.count == 1)
        #expect(await log.reservations.first ?? 0 > 0)
        #expect(FileManager.default.fileExists(atPath: ServerUIPublicationFile.url(in: dir, partition: try .init(server: F.server)).path))
    }

    @Test func anOlderRevisionInTheSameEpochIsIgnoredAndTheSameRevisionMustBeTheSameContent() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let instance = try await bound(dir, log)
        await instance.apply(try F.event(revision: 5, name: "Five"))
        await instance.apply(try F.event(revision: 4, name: "Four"))
        #expect(instance.revision == 5)
        #expect(instance.document?.name == "Five")
        await instance.apply(try F.event(revision: 5, name: "Five"))
        #expect(await log.prepares.count == 1)
        await instance.apply(try F.event(revision: 5, name: "Other"))
        #expect(instance.status == .failure(.revisionConflict))
        #expect(instance.document?.name == "Five")
        await instance.apply(try F.event(revision: 6, name: "Six"))
        #expect(instance.revision == 6)
        #expect(instance.document?.name == "Six")
    }

    @Test func aNewEpochStartsOrderingOverEvenAtALowerRevision() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let instance = try await bound(dir, log)
        await instance.apply(try F.event(epoch: "old", revision: 9, name: "Old"))
        await instance.apply(try F.event(epoch: "new", revision: 1, name: "New"))
        #expect(instance.epoch == "new" && instance.revision == 1)
        #expect(instance.document?.name == "New")
        #expect(await log.prepares.count == 2)
    }

    @Test func identicalContentUnderANewRevisionOnlyUpdatesAndPersistsTheOrdering() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let instance = try await bound(dir, log)
        await instance.apply(try F.event(revision: 3, hash: F.sha))
        await instance.apply(try F.event(revision: 4, hash: F.sha))
        await instance.apply(try F.event(epoch: "reset", revision: 1, hash: F.sha))
        #expect(await log.prepares.count == 1)
        #expect(instance.epoch == "reset" && instance.revision == 1)
        let restored = try await bound(dir, log)
        #expect(restored.restoreSynchronously { _, _ in Plan(revision: 0, instance: 0) })
        #expect(restored.epoch == "reset" && restored.revision == 1)
    }

    // MARK: Server states

    @Test func incompatibleAndUnpublishedKeepALastGoodAndSelectTheBoundariesWithout() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let empty = try await bound(dir, log)
        await empty.apply(.incompatible(epoch: "e", revision: 2, missing: ["sh.future@1"]))
        #expect(empty.remote == .incompatible(missing: ["sh.future@1"]) && empty.current == nil)
        await empty.apply(.unpublished)
        #expect(empty.remote == .unpublished && empty.current == nil)

        await empty.apply(try F.event(revision: 1))
        #expect(empty.remote == .published)
        await empty.apply(.incompatible(epoch: "epoch-1", revision: 2, missing: ["x"]))
        await empty.apply(.unpublished)
        #expect(empty.current != nil && empty.prepared != nil)
        #expect(empty.remote == .unpublished)
        await empty.apply(try F.event(revision: 2, name: "Back"))
        #expect(empty.document?.name == "Back")
    }

    @Test func invalidEventsKeepTheLastGood() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let instance = try await bound(dir, log)
        await instance.apply(try F.event(revision: 1))
        await instance.apply(.invalid(.subscription))
        #expect(instance.status == .failure(.subscription))
        #expect(instance.current != nil)
    }

    // MARK: Deferral

    @Test func aCandidateBlockedByAnOpenInteractionIsCommittedLaterWithoutAskingTheServerAgain() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var blocked = false
        var commits: [Int] = []
        let instance = try await bound(dir, log, validate: { _, _ in if blocked { throw Open() } },
                                       commit: { publication, _ in commits.append(publication.revision) })
        await instance.apply(try F.event(revision: 1, name: "One"))
        blocked = true
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(instance.hasDeferredCandidate)
        #expect(instance.document?.name == "One")
        #expect(instance.status == .ready)
        #expect(await log.cleanups.count == 1)
        await instance.retryDeferred()
        #expect(instance.hasDeferredCandidate)
        blocked = false
        await instance.retryDeferred()
        #expect(!instance.hasDeferredCandidate)
        #expect(instance.document?.name == "Two")
        #expect(instance.revision == 2)
        // The candidate was kept, never fetched again: two events in, and each was prepared when it was tried.
        #expect(commits.count == 2)
    }

    @Test func aNewerEventReplacesTheDeferredCandidateAndUnpublishingDropsIt() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var blocked = true
        let instance = try await bound(dir, log, validate: { _, _ in if blocked { throw Open() } })
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(instance.hasDeferredCandidate && instance.status == .loading)
        await instance.apply(try F.event(revision: 2, name: "Two"))
        await instance.apply(.unpublished)
        #expect(!instance.hasDeferredCandidate)
        await instance.retryDeferred()
        blocked = false
        #expect(instance.current == nil)
    }

    @Test func aRuntimeFailureKeepsTheLastGoodAndTheSameContentIsPreparedAgainOnRetry() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var refusing = false
        let instance = try await bound(dir, log, validate: { _, _ in if refusing { throw Broken() } })
        await instance.apply(try F.event(revision: 1, name: "One"))
        refusing = true
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(instance.status == .failure(.acceptanceRejected))
        #expect(!instance.hasDeferredCandidate)
        #expect(instance.document?.name == "One")
        refusing = false
        // Try Again resubscribes and the server sends the same content: a runtime failure said nothing about it, so it is tried afresh.
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(await log.prepares.count == 3)
        #expect(instance.document?.name == "Two")
        #expect(instance.status == .ready)
    }

    @Test func aRejectionOfTheContentItselfIsKeyedAndNotPreparedAgain() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var refusing = true
        let instance = try await bound(dir, log, validate: { _, _ in
            if refusing { throw ServerUICompositionError(.unsupportedCapability, "/capabilities/0") }
        })
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(instance.status == .failure(.composition(.init(.unsupportedCapability, "/capabilities/0"))))
        refusing = false
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(await log.prepares.count == 1)
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(instance.document?.name == "Two")
    }

    /// A provider whose inputs (house configuration, the user) have not arrived defers the layout; it is neither rejected nor reloaded.
    @Test func aLayoutWaitingForItsInputsIsHeldLoadingAndCommitsWhenTheyArrive() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var ready = false
        let instance = try await bound(dir, log, validate: { _, _ in if !ready { throw Open() } })
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(instance.status == .loading && instance.hasDeferredCandidate && instance.current == nil)
        ready = true
        await instance.retryDeferred()
        #expect(instance.document?.name == "One" && instance.status == .ready && !instance.hasDeferredCandidate)
    }

    @Test func aSavedLayoutWhoseInputsAreNotThereYetIsNotRejectedByTheColdRestore() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let first = try await bound(dir, log)
        await first.apply(try F.event(revision: 1))
        let second = try store(dir, log)
        #expect(!second.restoreSynchronously { _, _ in throw Open() })
        #expect(second.status == .idle && second.current == nil)
    }

    @Test func aRejectionRecordsItsCaseAndPointerAndAdoptionClearsThem() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        var refusing = true
        let instance = try await bound(dir, log, validate: { _, _ in if refusing { throw Located() } })
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(instance.status == .failure(.acceptanceRejected))
        #expect(instance.rejection == "unavailable_source at /synthetic/pointer")
        refusing = false
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(instance.status == .ready)
        #expect(instance.rejection == nil)
        #expect(ServerUIRejectionDiagnostic.describe(Broken()).hasPrefix("unclassified: "))
        #expect(ServerUIRejectionDiagnostic.describe(ServerUIStoreError.cacheRead) == "store: cacheRead")
        #expect(ServerUIRejectionDiagnostic.describe(ServerUIAssetError.missing) == "asset: missing")
    }

    @Test func aFailedFinalCommitRestoresTheDurableLastGood() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let instance = try await bound(dir, log, commit: { publication, _ in
            if publication.document.name == "Two" { throw Broken() }
        })
        await instance.apply(try F.event(revision: 1, name: "One"))
        await instance.apply(try F.event(revision: 2, name: "Two"))
        #expect(instance.status == .failure(.acceptanceRejected))
        #expect(instance.revision == 1)
        let restored = try await bound(dir, log)
        #expect(restored.restoreSynchronously { _, _ in Plan(revision: 1, instance: 0) })
        #expect(restored.revision == 1)
        #expect(restored.document?.name == "One")
    }

    // MARK: Restore, keying, sign-out

    @Test func restoreAdoptsTheSavedLayoutSynchronouslyWithItsStoredOrdering() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let first = try await bound(dir, log)
        await first.apply(try F.event(epoch: "e", revision: 12, name: "Saved"))
        let second = try store(dir, log)
        var preparedFor: [String] = []
        #expect(second.restoreSynchronously { publication, _ in
            preparedFor.append(publication.document.name)
            return Plan(revision: publication.revision, instance: 99)
        })
        #expect(preparedFor == ["Saved"])
        #expect(second.current != nil && second.prepared?.instance == 99)
        #expect(second.epoch == "e" && second.revision == 12)
        #expect(second.userID == "user-1")
        #expect(second.status == .ready && second.remote == .published)
        #expect(!second.restoreSynchronously { _, _ in Plan(revision: 0, instance: 0) })
    }

    /// A cold launch builds user-scoped providers (the household-away settings) while the socket has not said who is signed in.
    /// The saved record's user id must reach the preparation, or every cold launch rejects the saved layout.
    @Test func restorePassesTheSavedUserToPreparationBeforeTheSocketKnowsWhoIsSignedIn() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let first = try await bound(dir, log, user: "user-7")
        await first.apply(try F.event(revision: 3))
        let second = try store(dir, log)
        #expect(second.userID == nil)
        var seen: [String] = []
        #expect(second.restoreSynchronously { _, user in
            seen.append(user)
            return Plan(revision: 3, instance: 0)
        })
        #expect(seen == ["user-7"])
        #expect(second.userID == "user-7")
    }

    @Test func aMissingOrUnpreparableCacheRestoresNothing() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let empty = try store(dir, log)
        #expect(!empty.restoreSynchronously { _, _ in Plan(revision: 0, instance: 0) })
        #expect(empty.status == .idle)
        let first = try await bound(dir, log)
        await first.apply(try F.event(revision: 1))
        let failing = try store(dir, log)
        #expect(!failing.restoreSynchronously { _, _ in throw ServerUIAssetError.assetIntegrity })
        #expect(failing.status == .failure(.asset(.assetIntegrity)))
        #expect(failing.current == nil)
    }

    @Test func aRecordForAnotherUserIsDiscardedWhenTheVerifiedUserDiffers() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let first = try await bound(dir, log, user: "user-1")
        await first.apply(try F.event(revision: 1))
        let second = try store(dir, log)
        #expect(second.restoreSynchronously { _, _ in Plan(revision: 1, instance: 1) })
        #expect(await second.bind(userID: "user-1"))
        #expect(second.current != nil)
        #expect(await second.bind(userID: "user-2") == false)
        #expect(second.current == nil && second.userID == "user-2")
        let third = try store(dir, log)
        #expect(!third.restoreSynchronously { _, _ in Plan(revision: 1, instance: 1) })
    }

    @Test func anInvalidUserIdIsNotBound() async throws {
        let log = PreparationLog()
        let instance = try store(F.directory(), log)
        #expect(await instance.bind(userID: "") == false)
        #expect(await instance.bind(userID: "has space") == false)
        #expect(instance.userID == nil)
        // With no user the record cannot be written, so a publication is refused rather than saved without an owner.
        await instance.apply(try F.event(revision: 1))
        #expect(instance.status == .failure(.invalidPartition))
    }

    @Test func eachServerOriginHasItsOwnCache() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let home = try await bound(dir, log)
        await home.apply(try F.event(revision: 1))
        let other = HassServer(baseURL: URL(string: "https://elsewhere.example:8123")!)
        let elsewhere = try store(dir, log, server: other)
        #expect(!elsewhere.restoreSynchronously { _, _ in Plan(revision: 0, instance: 0) })
        #expect(try ServerUIPublicationPartition(server: F.server).origin == "https://home.example")
        #expect(try ServerUIPublicationPartition(server: other).origin == "https://elsewhere.example:8123")
        let root = URL(fileURLWithPath: "/tmp/x")
        #expect(try ServerUIPublicationPartition(server: F.server).storageDirectory(in: root)
            != ServerUIPublicationPartition(server: other).storageDirectory(in: root))
        #expect(throws: ServerUIStoreError.invalidPartition) {
            try ServerUIPublicationPartition(server: HassServer(baseURL: URL(string: "ftp://nope.example")!))
        }
    }

    @Test func signOutClearsTheCacheAtOnceAndLateWritesLose() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let gate = Gate()
        let instance = try await bound(dir, log, prepare: { publication, context in
            if publication.document.name == "Two" { await gate.pause() }
            return await log.prepare(publication, context)
        })
        await instance.apply(try F.event(revision: 1, name: "One"))
        let file = ServerUIPublicationFile.url(in: dir, partition: try .init(server: F.server))
        #expect(FileManager.default.fileExists(atPath: file.path))
        let second = try F.event(revision: 2, name: "Two")
        let pending = Task { await instance.apply(second) }
        await gate.untilEntered()
        instance.endSession()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await gate.release()
        await pending.value
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await log.cleanups.count == 1)
        await instance.apply(try F.event(revision: 3))
        #expect(instance.revision == 1)
        #expect(await instance.bind(userID: "user-9") == false)
    }

    @Test func resetDropsTheLayoutAndTheNextEventStartsOver() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = PreparationLog()
        let purged = Flag()
        let instance = try await bound(dir, log)
        await instance.apply(try F.event(revision: 4, name: "Four"))
        await instance.reset(purge: { purged.set() })
        #expect(purged.value)
        #expect(instance.current == nil && instance.prepared == nil && instance.remote == .waiting)
        #expect(await log.cleanups.count == 1)
        let restored = try store(dir, log)
        #expect(!restored.restoreSynchronously { _, _ in Plan(revision: 0, instance: 0) })
        // A reset with the same epoch must not make the next, lower revision look stale.
        await instance.apply(try F.event(revision: 1, name: "One"))
        #expect(instance.revision == 1 && instance.document?.name == "One")
    }

    @Test func cacheFilesAreValidatedAndNeverFollowedThroughLinks() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let partition = try ServerUIPublicationPartition(server: F.server)
        let file = ServerUIPublicationFile.url(in: dir, partition: partition)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: file)
        #expect(throws: ServerUIStoreError.corruptCache) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        func record(version: Int = 2, origin: String = "https://home.example", user: String = "u", epoch: String = "e",
                    revision: Int = 1) throws -> Data {
            try JSONEncoder().encode(ServerUIPublicationRecord(version: version, origin: origin, userID: user, epoch: epoch,
                revision: revision, envelopeSha256: F.sha, bytes: Data([1])))
        }
        try record(version: 1).write(to: file)
        #expect(throws: ServerUIStoreError.unsupportedCacheVersion) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try record(origin: "https://other.example").write(to: file)
        #expect(throws: ServerUIStoreError.wrongPartition) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try record(user: "bad user").write(to: file)
        #expect(throws: ServerUIStoreError.wrongPartition) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try record(epoch: "").write(to: file)
        #expect(throws: ServerUIStoreError.corruptCache) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try record(revision: -1).write(to: file)
        #expect(throws: ServerUIStoreError.corruptCache) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try Data(repeating: 0, count: ServerUIPublicationFile.maximumBytes + 1).write(to: file)
        #expect(throws: ServerUIStoreError.corruptCache) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: dir)
        #expect(throws: ServerUIStoreError.cacheRead) { try ServerUIPublicationFile.read(at: file, partition: partition) }
        try ServerUIPublicationFile.remove(at: file)
        #expect(try ServerUIPublicationFile.read(at: file, partition: partition) == nil)
        try ServerUIPublicationFile.remove(at: dir.appendingPathComponent("missing/none.json"))
    }

    @Test func aLaterRevisionOnDiskIsNeverOverwrittenByAnEarlierSave() async throws {
        let dir = F.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let partition = try ServerUIPublicationPartition(server: F.server)
        let file = ServerUIPublicationFile.url(in: dir, partition: partition)
        let cache = ServerUIPublicationDiskCache.cache(for: file, root: dir, partition: partition)
        let session = UUID()
        func record(_ revision: Int) -> ServerUIPublicationRecord {
            .init(origin: partition.origin, userID: "u", epoch: "e", revision: revision, envelopeSha256: F.sha, bytes: Data([1]))
        }
        await cache.claim(session)
        try await cache.save(record(5), session: session)
        await #expect(throws: ServerUIStoreError.staleGeneration) { try await cache.save(record(4), session: session) }
        await #expect(throws: CancellationError.self) { try await cache.save(record(6), session: UUID()) }
        await cache.release(session)
        await #expect(throws: CancellationError.self) { try await cache.save(record(6), session: session) }
        await #expect(throws: ServerUIStoreError.staleGeneration) { try await cache.restore(nil, replacing: record(5), session: session) }
        await cache.claim(session)
        await #expect(throws: ServerUIStoreError.revisionConflict) { try await cache.restore(nil, replacing: record(9), session: session) }
        try await cache.restore(nil, replacing: record(5), session: session)
        #expect(try await cache.load() == nil)
        try await cache.clear()
    }
}
