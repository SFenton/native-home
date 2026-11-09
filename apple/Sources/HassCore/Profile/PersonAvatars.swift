import CoreGraphics
import Foundation
import Observation

/// The signed-in app's people photos: syncs them with Home Assistant, keeps them on the device, and hands each view an
/// observable ``AvatarBox`` (pattern: `.agents/patterns/avatar.md`; design: `.agents/design/profile-photos.md`).
///
/// - **Source:** the `person.*` entities in the ``EntityStore`` (their `entity_picture`), watched with Observation: person
///   boxes and the store's `freshness` only. A live change to any other entity never reaches this class, and a person whose
///   picture did not change (a GPS tick) returns before any disk access.
/// - **Work is off the main actor:** the cache read, the request, the file write and the decode run in
///   ``PersonAvatarSyncer``; the main actor receives one finished image and writes one box.
/// - **First frame:** ``box(for:)`` decodes the cached photo the first time a view asks, so a cold launch draws it with no fade.
///   That is one small ImageIO thumbnail (a 384 px decode of a file under 100 KB) per person, once per launch; people
///   do not scale with the house. The signed-in person is remembered on disk (``viewerPersonID``) so the Profile button
///   knows whose photo to draw before the network answers.
/// - **Sign-out:** ``removeAll()`` deletes every file and clears every box.
@MainActor
@Observable
public final class PersonAvatars {
    /// The `person.*` entity of the signed-in user, nil until it is known (it is remembered across launches).
    public private(set) var viewerPersonID: String?

    @ObservationIgnored private let syncer: PersonAvatarSyncer
    @ObservationIgnored private var boxes: [String: AvatarBox] = [:]
    @ObservationIgnored private var server: PersonAvatarSyncer.Server?
    @ObservationIgnored private weak var entityStore: EntityStore?
    @ObservationIgnored private var viewerUserID: String?
    /// People whose picture path has been confirmed with the server in this launch (the conditional request runs once).
    @ObservationIgnored private var validated: Set<String> = []
    /// The picture key each person had when last reconciled (`nil` key = no picture).
    @ObservationIgnored private var lastSeen: [String: String?] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// Bumped by ``removeAll()`` and ``stop()``: a result from an older generation is dropped.
    @ObservationIgnored private var generation = 0
    /// People whose last request failed: not asked again for the same picture until `until` (a 404 must not be retried on every
    /// position tick of the person entity).
    @ObservationIgnored private var cooling: [String: (key: String?, until: Date)] = [:]
    @ObservationIgnored private let retryCooldown: TimeInterval
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Creates the people photos.
    /// - Parameters:
    ///   - store: Where photos are kept (a temporary directory in tests).
    ///   - session: The URL session photos are fetched with (a stub in tests).
    ///   - retryCooldown: Seconds before a failed picture is asked for again.
    ///   - now: The clock.
    public init(store: PersonAvatarStore = PersonAvatarStore(), session: URLSession? = nil, retryCooldown: TimeInterval = 300,
                now: @escaping @Sendable () -> Date = { .now }) {
        self.retryCooldown = retryCooldown
        self.now = now
        syncer = PersonAvatarSyncer(store: store, session: session, now: now)
        viewerPersonID = store.viewerPersonID
    }

    /// The photo store.
    public var store: PersonAvatarStore { syncer.store }

    // MARK: - Reading

    /// The observable box for a person. Always the same box for the same id. The first call decodes the cached photo
    /// (if any) so the first frame has it.
    public func box(for personID: String) -> AvatarBox {
        if let box = boxes[personID] { return box }
        var first: CGImage?
        var late: Data?
        if let data = syncer.store.data(for: personID) {
            // Files in the store passed the download gate, so this is normally a 512 px image and the decode takes a few
            // milliseconds. Anything else (a file from an older build, a damaged one) must never cost the first frame: it is
            // decoded off the main actor and fades in when ready, and one that does not decode is deleted so it cannot fail again.
            if let pixels = PersonAvatarSyncer.pixelCount(data) {
                if pixels <= Self.firstFramePixels {
                    first = PersonAvatarSyncer.decode(data)
                    if first == nil { discardUndecodable(personID) }
                } else {
                    late = data
                }
            } else {
                discardUndecodable(personID)
            }
        }
        let box = AvatarBox(id: personID, image: first)
        boxes[personID] = box
        if let late {
            let started = generation
            Task { [weak self] in
                let image = await PersonAvatarSyncer.decodeOffMain(late)
                // A sign-out in the meantime wiped the file; the photo must not come back on screen.
                guard let self, self.generation == started else { return }
                if let image { box.apply(image) } else { discardUndecodable(personID) }
            }
        }
        return box
    }

    /// The most pixels decoded synchronously for a first frame (a 1024 px square).
    static let firstFramePixels = 1024 * 1024

    private func discardUndecodable(_ personID: String) {
        syncer.store.delete(personID: personID)
        lastSeen[personID] = nil
    }

    /// The signed-in person's box, nil until their person is known.
    public var viewerBox: AvatarBox? { viewerPersonID.map(box(for:)) }

    // MARK: - Syncing

    /// Starts keeping photos in step with `entityStore`: on the first live delivery, and whenever a person's entity changes.
    /// - Parameters:
    ///   - entityStore: The app's one store.
    ///   - server: The signed-in server; its host is the only one sent the Bearer token.
    public func start(entityStore: EntityStore, server: PersonAvatarSyncer.Server) {
        self.entityStore = entityStore
        self.server = server
        // A user id from a session that has ended must never pick the next session's person.
        viewerUserID = nil
        reconcile()
        observe()
    }

    /// Tells the class who is signed in, so the matching `person.*` entity shows on the Profile button.
    /// - Parameters:
    ///   - userID: `auth/current_user`'s id.
    public func setViewer(userID: String) {
        // The user lookup is async and may finish after sign-out: with no session there is nobody to match.
        guard entityStore != nil else { return }
        viewerUserID = userID
        resolveViewer()
    }

    /// Stops watching and cancels any request (the session ended). Does not delete files; ``removeAll()`` does.
    public func stop() {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        entityStore = nil
        server = nil
    }

    /// Deletes every cached photo and clears every box: sign-out and an expired session.
    public func removeAll() {
        stop()
        validated = []
        lastSeen = [:]
        cooling = [:]
        viewerUserID = nil
        viewerPersonID = nil
        syncer.store.removeAll()
        for box in boxes.values { box.apply(nil) }
    }

    // MARK: - Observation

    /// Watches the person entities and `freshness`; re-arms after each change.
    private func observe() {
        let generation = generation
        guard let entityStore else { return }
        withObservationTracking {
            _ = entityStore.freshness
            _ = entityStore.peopleRevision
            for id in Self.personIDs(in: entityStore) { _ = entityStore.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.reconcile()
                self.observe()
            }
        }
    }

    private static func personIDs(in entityStore: EntityStore) -> [String] {
        entityStore.allValues.keys.filter { $0.hasPrefix("person.") }
    }

    private func resolveViewer() {
        guard let userID = viewerUserID, let entityStore else { return }
        if let id = AvatarSyncPlan.personID(forUser: userID, in: entityStore.allValues.values) {
            guard id != viewerPersonID else { return }
            viewerPersonID = id
            syncer.store.viewerPersonID = id
        } else if entityStore.freshness == .live, viewerPersonID != nil {
            // Home Assistant has loaded and no person belongs to this user: the remembered one was someone else's.
            viewerPersonID = nil
            syncer.store.viewerPersonID = nil
        }
    }

    /// Syncs every person whose picture is new to this launch or changed since the last look.
    func reconcile() {
        guard let entityStore, let server, entityStore.freshness == .live else { return }
        resolveViewer()
        for id in Self.personIDs(in: entityStore) {
            guard let state = entityStore.value(id) else { continue }
            let picture = state.attributes["entity_picture"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            let key = picture.map(AvatarSyncPlan.pictureKey)
            // A GPS tick: same picture, already confirmed. No disk, no task.
            if validated.contains(id), let seen = lastSeen[id], seen == key { continue }
            guard tasks[id] == nil else { continue }
            if let cool = cooling[id], cool.key == key, cool.until > now() { continue }
            // Created before the work starts, so a view that appears mid-sync is seeded from the old file and fades.
            let box = box(for: id)
            lastSeen[id] = .some(key)
            cooling[id] = nil
            let generation = generation
            let syncer = syncer
            // The plan compares the cached key first, so a changed picture is fetched even when this id was confirmed.
            let alreadyValidated = validated.contains(id)
            tasks[id] = Task { [weak self] in
                let outcome = await syncer.sync(personID: id, picture: picture, entityLoaded: true,
                                                validatedThisLaunch: alreadyValidated, server: server)
                var image: CGImage?
                if case .updated = outcome {
                    image = await syncer.storedImage(for: id)
                }
                self?.finish(id, box: box, outcome: outcome, image: image, key: key, generation: generation)
            }
        }
    }

    private func finish(_ id: String, box: AvatarBox, outcome: PersonAvatarSyncer.Outcome, image: CGImage?, key: String?,
                        generation: Int) {
        // The session ended while this ran. Its writes were refused by the store's generation, so there is nothing to clean up.
        guard generation == self.generation else { return }
        tasks[id] = nil
        switch outcome {
        case let .unchanged(confirmed):
            if confirmed {
                validated.insert(id)
            } else {
                lastSeen[id] = nil
                cooling[id] = (key, now().addingTimeInterval(retryCooldown))
            }
        case .updated:
            validated.insert(id)
            if let image { box.apply(image) }
        case .removed:
            validated.insert(id)
            box.apply(nil)
        }
        // The picture changed while this ran: look again.
        if let entityStore, let state = entityStore.value(id) {
            let current = state.attributes["entity_picture"]?.string.flatMap { $0.isEmpty ? nil : $0 }.map(AvatarSyncPlan.pictureKey)
            if current != key { reconcile() }
        }
    }
}
