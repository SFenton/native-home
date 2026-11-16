#if os(iOS) && DEBUG
import Foundation
import FentonActivityModel
import HassCore
import Observation
import UIKit

// MARK: - Read-only live providers

/// The provider set the production route builds from its connection and `house_config`, built here from the preview's own
/// read-only connection.
///
/// The preview's live mode used to hand the renderer an empty provider set, so a layout that names a household, away, profile or
/// feedback provider, a to-do, inventory or recipe collection, a data flow, a media remote or a bedroom was refused whole
/// (`unavailable_source`). This type builds each of those the way ``UKServerUIProductionProviders`` does, through the same static
/// builders (``UKServerUIHouseholdProviders``, ``UKServerUIRecordProviders``, ``UKServerUIProductionProviders/bedroomProviders(_:store:caller:canEdit:)``,
/// ``UKServerUIProductionProviders/flowHost(connection:entitySources:user:appState:call:)`` and the rest), so the two cannot drift. The
/// differences are the ones the preview's read-only rule forces and nothing else:
///
/// - Every write goes through ``UKServerUIPreviewReadOnlyServices``, which passes reads (to-do items, schedules, the current user)
///   and refuses services, uploads and schedule updates.
/// - A data flow's service call is refused; its feed and entity reads run.
/// - Sign-out, Home Assistant's web pages and feedback filing are refused at the action, not at acceptance, so the rows still draw.
/// - Preferences use an isolated defaults suite and an in-memory app-icon choice.
///
/// The inputs the production route waits for (the house document and the signed-in user) arrive over the same websocket. Call
/// ``awaitInputs(timeout:)`` before ``supply(for:blur:)``; a supply asked for before the house document arrives throws
/// ``UKServerUIRendererError/Code/inputsPending``, as production does.
@MainActor @Observable
final class UKServerUIPreviewLiveProviders: UKServerUIAccountProvider {
    /// What one renderer is built with, in the argument shapes `UKServerUIRenderer` takes.
    struct Supply {
        let settings: [String: any UKServerUISettingsProvider]
        let records: UKServerUIRecords
        let collections: [String: ServerUIRowCollection]
        let bedrooms: [String: UKServerUIBedroomProvider]
        let remotes: [String: ServerUIRemoteSession]
        let canEditBedroom: Bool
        let responder: any HassServiceResponding
        let schedules: any HassScheduleStoring
        let account: any UKServerUIAccountProvider
        let shellHeader: UKServerUIShellHeaderSource
        let roomResidentId: @MainActor () -> String?
    }

    /// The person Home Assistant says is signed in; `nil` until it answers (``awaitInputs(timeout:)``; a test sets it).
    var user: HassUser?
    private(set) var accountUnavailable = false
    /// The document the server serves, followed over the preview's websocket and published into `HouseConfigSource.shared`.
    let houseConfig: HouseConfigStore
    let services: UKServerUIPreviewReadOnlyServices

    private let live: UKServerUIPreviewLiveData
    private let defaults: UserDefaults
    /// The house-document source the store publishes into, and what it held before this preview started.
    private let source: HouseConfigSource
    private let previousDocument: HouseConfig?
    private var inputTasks: [Task<Void, Never>] = []
    private let window = UUID()
    private let flows = UKServerUIFlowWindows()
    private var settings: [String: any UKServerUISettingsProvider] = [:]
    private var remotes: [String: ServerUIRemoteSession] = [:]
    private var bedrooms: [String: UKServerUIBedroomProvider] = [:]
    private var configured: HouseConfig?
    private var recordProviders: UKServerUIRecordProviders?
    private var iconName: String?
    private var copiedVersion: String?

    private static let pending = UKServerUIRendererError(code: .inputsPending, pointer: "/document/dataSources")

    /// - Parameters:
    ///   - live: The preview's read-only connection owner.
    ///   - houseConfigCache: Where the followed document is kept; inside the preview's own directory.
    ///   - defaultsName: The isolated defaults suite the preferences provider writes to.
    ///   - source: Where the followed document is published for the `*Config` facades (the shared source, as production does);
    ///     ``stop()`` puts back what it held before.
    ///   - houseConfig: The store to follow; the preview passes none and gets one over its own websocket, a test passes one over a canned transport.
    init(live: UKServerUIPreviewLiveData, houseConfigCache: HouseConfigCache, defaultsName: String,
         source: HouseConfigSource = .shared, houseConfig: HouseConfigStore? = nil) throws {
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/preview/live")
        }
        self.live = live
        self.defaults = defaults
        self.source = source
        previousDocument = source.current
        services = UKServerUIPreviewReadOnlyServices(connection: live.connection, caller: live.caller)
        self.houseConfig = houseConfig ?? HouseConfigStore(server: live.connection.server,
            transport: HassHouseConfigTransport(connection: live.connection), cache: houseConfigCache, source: source,
            timeout: .seconds(60))
    }

    /// Ends the flows, the pending input reads and the house-document subscription, and puts the shared house document back.
    ///
    /// The preview calls it when it is removed or fails. The document the live preview published is not left behind for the next
    /// preview in the process: the source holds again what it held before this one started, or nothing.
    func stop() {
        inputTasks.forEach { $0.cancel() }
        inputTasks = []
        flows.endSession()
        houseConfig.stop()
        source.set(previousDocument)
    }

    // MARK: - Inputs

    /// Follows the house document and asks who is signed in, then returns when both have answered, `timeout` passes, the caller is
    /// cancelled or ``stop()`` runs.
    ///
    /// A timeout is not an error: the supply then throws ``UKServerUIRendererError/Code/inputsPending`` for whatever still lacks an input.
    /// The reads hold the connection and the house store, never this object, so none of them keeps it alive after ``stop()``.
    func awaitInputs(timeout: Duration) async {
        guard !Task.isCancelled else { return }
        houseConfig.start()
        let connection = live.connection, document = houseConfig
        let gate = Gate(count: 2)
        let user = Task { [weak self] in
            let fetched = await Self.fetchUser(connection)
            if !Task.isCancelled { self?.adopt(user: fetched) }
            gate.arrive()
        }
        let config = Task {
            await Self.firstDocument(document)
            gate.arrive()
        }
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            gate.finish()
        }
        inputTasks += [user, config, deadline]
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.install(continuation)
            }
        } onCancel: {
            user.cancel(); config.cancel(); deadline.cancel()
            gate.finish()
        }
        deadline.cancel()
    }

    private func adopt(user fetched: HassUser?) {
        if let fetched { user = fetched; accountUnavailable = false }
        else { accountUnavailable = true }
    }

    private static func fetchUser(_ connection: HassConnection) async -> HassUser? {
        try? await connection.currentUser()
    }

    private static func firstDocument(_ store: HouseConfigStore) async {
        guard store.current == nil else { return }
        for await _ in store.changes() { return }
    }

    /// Resumes the waiting caller once: when every input has arrived, or at once when the deadline or a cancel finishes it.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private var continuation: CheckedContinuation<Void, Never>?
        private var done = false

        init(count: Int) { remaining = count }

        func install(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if done { lock.unlock(); continuation.resume(); return }
            self.continuation = continuation
            lock.unlock()
        }

        func arrive() {
            lock.lock()
            remaining -= 1
            let finished = remaining <= 0
            lock.unlock()
            if finished { finish() }
        }

        func finish() {
            lock.lock()
            done = true
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume()
        }
    }

    // MARK: - Account

    /// The signed-in person's name and the server's host, `loading` until Home Assistant answers and `unavailable` when it did not.
    var account: UKServerUIAccountValue {
        guard let user else { return accountUnavailable ? .unavailable : .loading }
        return .ready(name: user.name, server: live.connection.server.baseURL.host ?? "", avatar: nil)
    }

    /// The shell header's profile name, attention count and offline flag, read from the preview's own store and connection.
    var shellHeader: UKServerUIShellHeaderSource {
        .init(state: { [weak self] in
            guard let self else { return .init(profileName: nil) }
            return .init(profileName: user?.name,
                attentionCount: ShellAttention.count(store: live.connection.store, viewerUserId: user?.id),
                isOffline: live.connection.isOffline)
        })
    }

    /// The key of the house-document person whose Home Assistant user is the signed-in one, for resident-aware nodes; `nil` until both are known.
    var roomResidentID: String? {
        guard let identity = user?.id else { return nil }
        return houseConfig.current?.chores.people.first { $0.haUserId.lowercased() == identity.lowercased() }?.key
    }

    // MARK: - Supply

    /// Builds the providers the document names, as the production route does, over the read-only connection.
    /// - Parameters:
    ///   - publication: The publication being prepared.
    ///   - blur: The staged backdrop's blur, which the preferences provider adopts.
    /// - Throws: ``UKServerUIRendererError/Code/inputsPending`` while the house document has not arrived, or the builders' own refusal.
    func supply(for publication: ServerUICompositionPublication, blur: BackdropBlurSettings) throws -> Supply {
        guard let configuration = houseConfig.current else { throw Self.pending }
        let store = live.connection.store
        if configuration != configured {
            remotes = Dictionary(uniqueKeysWithValues: configuration.media.remotes.map {
                ($0.id, UKServerUIProductionProviders.remoteSession($0, store: store, caller: services))
            })
            bedrooms = UKServerUIProductionProviders.bedroomProviders(configuration.bedroom, store: store, caller: services,
                                                                      canEdit: user?.isAdmin == true)
            settings = settings.filter { ![.household, .away, .profile].contains($0.value.definition.domain) }
            configured = configuration
        }
        let settings = try settings(for: publication, configuration: configuration, blur: blur)
        let records = try UKServerUIProductionProviders.presentations(
            of: try baseRecords(for: publication, configuration: configuration), settings: settings)
        let entities = UKServerUIProductionProviders.entitySources(of: publication.document)
        var collections = flows.collections(for: publication.document, window: window, start: true, hostKey: entities) {
            flowHost(entitySources: entities)
        }
        try UKServerUIProductionProviders.addPerformanceCollections(from: settings, to: &collections)
        let supplied = UKServerUIProductionProviders.supplementalProviders(for: publication, bedrooms: bedrooms, remotes: remotes)
        return Supply(settings: settings, records: records, collections: collections, bedrooms: supplied.bedrooms,
                      remotes: supplied.remotes, canEditBedroom: user?.isAdmin == true, responder: services, schedules: services,
                      account: self, shellHeader: shellHeader, roomResidentId: { [weak self] in self?.roomResidentID })
    }

    /// The host every Data Flow of this preview runs on: the production host over the preview's connection, whose service call is refused.
    func flowHost(entitySources: [String: String]) -> ServerUIFlowHost {
        let services = services
        return UKServerUIProductionProviders.flowHost(connection: live.connection, entitySources: entitySources,
            user: { [weak self] in self?.user }, appState: nil, call: { _, _, _, _, _ in try services.rejectFlowCall() })
    }

    private func settings(for publication: ServerUICompositionPublication, configuration: HouseConfig,
                          blur: BackdropBlurSettings) throws -> [String: any UKServerUISettingsProvider] {
        let store = live.connection.store
        let current: () -> Bool = { true }
        var result = settings
        for source in publication.document.dataSources {
            guard case .settingsProvider(_, let definition) = source else { continue }
            if let existing = result[definition.providerId] {
                guard existing.definition == definition else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                continue
            }
            switch definition.domain {
            case .preferences:
                let icons = AppIconPlatform(supportsAlternateIcons: { true },
                    currentName: { [weak self] in self?.iconName },
                    setName: { [weak self] name in self?.iconName = name })
                result[definition.providerId] = UKServerUIPreferencesProvider(id: definition.providerId, blur: blur,
                    icons: AppIconPickerModel(platform: icons, iconStore: .init(defaults: nil)),
                    about: AboutSettingsModel(pasteboard: { [weak self] in self?.copiedVersion = $0 }),
                    defaults: defaults, isCurrentSession: current)
            case .performance:
                result[definition.providerId] = try UKServerUIPerformanceProvider(id: definition.providerId, isCurrentSession: current)
            case .household:
                result[definition.providerId] = try UKServerUIHouseholdProviders.household(id: definition.providerId,
                    configuration: configuration, document: publication.document, store: store, caller: services, current: current)
            case .away:
                guard let identity = user?.id else { throw Self.pending }
                result[definition.providerId] = try UKServerUIHouseholdProviders.away(id: definition.providerId,
                    configuration: configuration, authenticatedUserID: identity, store: store, caller: services, current: current)
            case .profile:
                result[definition.providerId] = profile(id: definition.providerId, configuration: configuration)
            case .feedback:
                result[definition.providerId] = try UKServerUIProductionProviders.feedbackProvider(id: definition.providerId,
                    filer: RefusedFeedbackFiler(), connection: live.connection, current: current)
            }
        }
        settings = result
        return result
    }

    private func baseRecords(for publication: ServerUICompositionPublication,
                             configuration: HouseConfig) throws -> UKServerUIRecords {
        guard UKServerUIRecordProviders.required(by: publication.document) else { return recordProviders?.records ?? .init() }
        guard let identity = user?.id else { throw Self.pending }
        let definition = UKServerUIRecordProviders.Definition(people: configuration.chores.people, document: publication.document)
        if let existing = recordProviders, existing.definition == definition { return existing.records }
        let registry = try UKServerUIRecordProviders(definition: definition, authenticatedUserID: identity,
            service: services, recipes: EverShelfRecipeService(caller: services), todos: TodoStore(service: services),
            store: live.connection.store, accessToken: { [services] in try await services.accessToken() },
            isCurrentSession: { true }, retaining: recordProviders)
        recordProviders = registry
        return registry.records
    }

    /// The profile page over the connection's reads; leaving the account and opening Home Assistant's web pages are refused at the action.
    private func profile(id: String, configuration: HouseConfig) -> UKServerUIProfileProvider {
        let store = live.connection.store, connection = live.connection
        let project: (String) -> (ProfileSummary.Person, AvatarBox?)? = { id in
            guard let state = store.entity(id).state, let person = ProfileSummary.people([state]).first else { return nil }
            return (person, nil)
        }
        let people = Dictionary(uniqueKeysWithValues: configuration.chores.people.map { person in
            (person.personEntityId, { project(person.personEntityId) })
        })
        let refuse: (UIViewController) -> Void = { page in
            let alert = UIAlertController(title: "Unavailable in Preview",
                message: "This read-only preview does not leave the account or open Home Assistant's web pages.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            page.present(alert, animated: true)
        }
        return UKServerUIProfileProvider(id: id, location: nil, people: people,
            allPeople: { store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted().compactMap(project) },
            supportsLocation: false, isCurrentSession: { true },
            signOut: { [caller = live.caller] in try caller.reject() }, homeAssistant: refuse,
            homeAssistantSnapshot: { [weak self, houseConfig] in
                let document = houseConfig.current
                let missing = document?.missingEntityIds(hasReceivedFirstState: store.hasReceivedFirstState) { store.value($0) } ?? []
                let user = self?.user
                return .init(address: HomeAssistantSettingsView.displayedServer(connection.server),
                    connection: HomeAssistantSettingsView.statusText(connection.status, isOffline: connection.isOffline),
                    version: HomeAssistantSettingsView.version(connection.status),
                    houseLayout: HouseLayoutSummary(hasDocument: document != nil, status: houseConfig.status, missing: missing),
                    account: user.map { HomeAssistantSettingsView.displayedName($0) } ?? "Loading",
                    role: user?.roleTitle, canAdminister: user?.isAdmin == true || user?.isOwner == true)
            }, openHomeAssistantWeb: { _, page in refuse(page) })
    }

    /// Feedback's form draws; filing is a write and is refused.
    private struct RefusedFeedbackFiler: FeedbackFiling {
        func isAvailable() async throws -> Bool { false }
        func upload(_ attachment: FeedbackAttachment) async throws -> URL { throw FeedbackFilingError.notConfigured }
        func submit(_ report: FeedbackReport) async throws -> FiledIssue { throw FeedbackFilingError.notConfigured }
    }
}
#endif
