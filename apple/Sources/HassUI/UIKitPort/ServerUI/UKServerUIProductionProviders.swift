#if os(iOS)
import Foundation
import CryptoKit
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Authenticated production providers

/// One account-scoped provider set. Identifiers address domain configuration, never compiled pages.
@MainActor
@Observable
final class UKServerUIProductionProviders: UKServerUIAccountProvider {
    private var accountUnavailable = false
    var account: UKServerUIAccountValue {
        guard let session, session.isCurrentConnection(connection) else { return .unavailable }
        guard let user else { return accountUnavailable ? .unavailable : .loading }
        return .ready(name: user.name, server: connection.server.baseURL.host ?? "", avatar: session.avatars.viewerBox)
    }
    private(set) var remotes: [String: ServerUIRemoteSession] = [:]
    private(set) var bedrooms: [String: UKServerUIBedroomProvider] = [:]
    private(set) var generation = 0
    let caller: UKServerUISessionCaller
    private weak var session: AppSession?
    private let connection: HassConnection
    private let reconnecting: UKReconnectingHost
    private var configured: HouseConfig?
    private var user: HassUser?
    private let recordCacheRoot: URL
    private let validationSceneID = UUID()
    private let emptyRecords = UKServerUIRecords()
    private var recordWindows: [UUID: UKServerUIRecordProviders] = [:]
    private var recordStore: TodoStore?
    private var recordUserID: String?
    private var recordCacheFile: URL?
    private let preferencesDefaults: UserDefaults
    private var settingsWindows: [UUID: [String: any UKServerUISettingsProvider]] = [:]
    private var settingsConfigurations: [UUID: HouseConfig] = [:]
    /// The household controls each window's household providers were built from; a publication that changes them rebuilds.
    private var settingsHouseholdControls: [UUID: [ServerUISettingsControl]] = [:]
    private var presentationRecords: [UUID: (base: UUID, settings: [String: ObjectIdentifier], records: UKServerUIRecords)] = [:]
    private var visiblePreferenceWindows: Set<UUID> = []
    var canEditBedroom: Bool { user?.isAdmin == true && session?.isCurrentConnection(connection) == true }

    init(session: AppSession, connection: HassConnection,
         recordCacheRoot: URL = URL.applicationSupportDirectory.appendingPathComponent("ServerUIRecords", isDirectory: true),
         preferencesDefaults: UserDefaults = .standard) {
        self.session = session
        self.connection = connection
        reconnecting = UKReconnectingHost(connection: connection)
        self.recordCacheRoot = recordCacheRoot
        self.preferencesDefaults = preferencesDefaults
        caller = UKServerUISessionCaller(session: session, connection: connection)
    }

    /// Only the existing websocket supplies identity, permissions and configuration.
    func connected() async {
        do {
            let user = try await connection.currentUser()
            guard let session, session.isCurrentConnection(connection) else { return }
            guard recordUserID == nil || recordUserID == user.id else { session.sessionExpired(); return }
            if self.user?.isAdmin != user.isAdmin { generation += 1 }
            self.user = user
            accountUnavailable = false
            session.avatars.setViewer(userID: user.id)
            for provider in bedrooms.values {
                if case .wake(let controller) = provider { controller.canEdit = user.isAdmin }
            }
            await session.waitForSystemServices()
            guard session.isCurrentConnection(connection) else { return }
            await session.push.didConnect(userID: user.id, userName: user.name)
        } catch {
            if user == nil { accountUnavailable = true }
            NSLog("ServerUI authenticated account provider unavailable.")
        }
    }

    var roomResidentID: String? {
        guard let session, session.isCurrentConnection(connection),
              let identity = user?.id ?? session.cachedPublicationUserID(for: connection) else { return nil }
        return session.houseConfig?.current?.chores.people.first { $0.haUserId.lowercased() == identity.lowercased() }?.key
    }

    var shellHeader: UKServerUIShellHeaderSource {
        .init(state: { [weak self] in
            guard let self, let session, session.isCurrentConnection(connection) else { return .init(profileName: nil) }
            let identity = user?.id ?? session.cachedPublicationUserID(for: connection)
            let indicator = reconnecting.indicator
            return .init(profileName: ScreenshotPrivacy.isRedacting ? nil : user?.name,
                attentionCount: ShellAttention.count(store: connection.store, viewerUserId: identity),
                isOffline: connection.isOffline, reconnectingPresent: indicator.isPresent,
                reconnectingLit: indicator.isLit, isFirstConnect: indicator.isFirstConnect)
        }, avatar: { [weak self] in
            guard let self, let session, session.isCurrentConnection(connection), !ScreenshotPrivacy.isRedacting else { return nil }
            return session.avatars.viewerBox
        })
    }

    /// Whether the house configuration differs from the one the controllers were built for. A cheap comparison made before any
    /// preflight, so an unchanged house costs nothing when the layout is revalidated.
    var hasPendingConfiguration: Bool {
        guard let session, session.isCurrentConnection(connection), let config = session.houseConfig?.current else { return false }
        return config != configured
    }

    /// Controllers are pinned to immutable descriptors for their lifetime. A changed house config
    /// never retargets a retained controller, draft, optimistic echo or in-flight operation.
    func prepare(_ publication: ServerUICompositionPublication) throws {
        guard let session, session.isCurrentConnection(connection) else { throw CancellationError() }
        if let config = session.houseConfig?.current, config != configured {
            let nextRemotes = Dictionary(uniqueKeysWithValues: config.media.remotes.map { descriptor in
                let retained = remotes[descriptor.id].flatMap { $0.controller.config == descriptor ? $0 : nil }
                return (descriptor.id, retained ?? ServerUIRemoteSession(
                    controller: MediaRemoteController(config: descriptor, store: connection.store, caller: caller)))
            })
            var nextBedrooms = bedrooms
            if configured?.bedroom != config.bedroom {
                let room = config.bedroom
                let wake = WakeLightController(config: room.wakeLight, store: connection.store, caller: caller, canEdit: user?.isAdmin == true)
                nextBedrooms = [room.wakeLight.id: .wake(wake)]
                let environment = BedSideEnvironment(scheduleEntityId: room.scheduleEntityId, scheduleSetTopic: room.scheduleSetTopic,
                    hotFlashBrokerScript: room.hotFlashBrokerScript, householdAwayEntityId: room.householdAwayEntityId,
                    householdAwayScript: room.householdAwayScript, wakeLight: room.wakeLight)
                for bed in room.beds {
                    nextBedrooms[bed.id] = .bed(BedSideController(config: bed, store: connection.store, caller: caller, environment: environment))
                }
            }
            remotes = nextRemotes
            bedrooms = nextBedrooms
            configured = config
            generation += 1
        }
        let supplied = supplementalProviders(for: publication)
        let settings = try settings(for: publication)
        let prepared = try UKServerUIDeviceProviders(sources: publication.document.dataSources,
            context: UKContext(store: connection.store, caller: caller), responder: caller,
            canEditBedroom: canEditBedroom, bedrooms: supplied.bedrooms, remotes: supplied.remotes,
            collections: try presentationCollections(settings), retaining: nil)
        try UKServerUIRenderer.preflight(publication, collections: prepared.collections,
            records: prepared.bedroomRegistry.addingCollections(to: records(for: publication)),
            remoteProviders: prepared.remotes, store: connection.store, accountProvider: self, settingsProviders: settings,
            shellHeader: shellHeader)
    }

    /// An input the document binds (house configuration, the signed-in user) has not arrived: the layout waits, it is not rejected.
    private static let pending = UKServerUIRendererError(code: .inputsPending, pointer: "/document/dataSources")

    /// Device preferences override the authored default only after an explicit local choice.
    func preferredBlurPercent(fallback: Int) -> Int {
        guard let stored = preferencesDefaults.object(forKey: BackdropBlur.defaultsKey) else { return fallback }
        return BackdropBlur.percent(fromStored: stored)
    }

    /// The validation registry has no visible backdrop. Window registries receive their staged store.
    func settings(for publication: ServerUICompositionPublication, sceneID: UUID? = nil,
                  blur: BackdropBlurSettings? = nil) throws -> [String: any UKServerUISettingsProvider] {
        guard let session, session.isCurrentConnection(connection) else { throw CancellationError() }
        let key = sceneID ?? validationSceneID
        var result = settingsWindows[key] ?? [:]
        let configuration = session.houseConfig?.current
        let householdControls = publication.document.dataSources.flatMap { source -> [ServerUISettingsControl] in
            guard case .settingsProvider(_, let definition) = source, definition.domain == .household else { return [] }
            return publication.document.settingsControls(overProvider: definition.providerId)
        }
        if configuration != settingsConfigurations[key] {
            result = result.filter { ![.household, .away, .profile].contains($0.value.definition.domain) }
        } else if householdControls != settingsHouseholdControls[key] {
            result = result.filter { $0.value.definition.domain != .household }
        }
        let current = { [weak session, connection] in session?.isCurrentConnection(connection) == true }
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
                result[definition.providerId] = UKServerUIPreferencesProvider(id: definition.providerId,
                    blur: blur ?? BackdropBlurSettings(initialPercent: preferredBlurPercent(fallback: BackdropBlur.defaultPercent)),
                    icons: AppIconPickerModel(platform: .system), about: AboutSettingsModel(),
                    defaults: preferencesDefaults, isCurrentSession: current, blurChanged: { [weak self] percent in
                        guard let self else { return }
                        for id in self.visiblePreferenceWindows {
                            for case let preferences as UKServerUIPreferencesProvider in (self.settingsWindows[id] ?? [:]).values {
                                preferences.blur.set(percent)
                            }
                        }
                    })
            case .performance:
                result[definition.providerId] = try UKServerUIPerformanceProvider(id: definition.providerId, isCurrentSession: current)
            case .household:
                guard let configuration else { throw Self.pending }
                result[definition.providerId] = try UKServerUIHouseholdProviders.household(id: definition.providerId,
                    configuration: configuration, document: publication.document, store: connection.store,
                    caller: UKServerUISessionCaller(session: session, connection: connection, configuration: configuration),
                    current: { [weak session] in current() && session?.houseConfig?.current == configuration })
            case .away:
                guard let configuration, let identity = user?.id ?? session.cachedPublicationUserID(for: connection) else {
                    throw Self.pending
                }
                result[definition.providerId] = try UKServerUIHouseholdProviders.away(id: definition.providerId,
                    configuration: configuration, authenticatedUserID: identity, store: connection.store,
                    caller: UKServerUISessionCaller(session: session, connection: connection, configuration: configuration),
                    current: { [weak session] in current() && session?.houseConfig?.current == configuration })
            case .profile:
                result[definition.providerId] = profile(id: definition.providerId, session: session, current: current)
            case .feedback:
                let kind: FeedbackKind
                switch definition.providerId {
                case "feedback-bug": kind = .bug
                case "feedback-feature": kind = .feature
                default: throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                let filer = UKServerUISessionFeedbackFiler(filer: HomeAssistantFeedbackClient(server: connection.server) { [caller] in
                    try await caller.accessToken()
                }, isCurrentSession: current)
                let platform = FeedbackPlatform.resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                       hasHinge: HingePresence.shared.hasHinge)
                result[definition.providerId] = UKServerUIFeedbackProvider(id: definition.providerId,
                    model: FeedbackFormModel(kind: kind, services: FeedbackServices(filer: filer)), platform: platform,
                    isCurrentSession: current) { [connection] traits in
                        FeedbackDiagnosticsCollector(platform: platform, traits: .init(
                            dynamicTypeSize: WeatherCarouselPaging.dynamicTypeSize(traits.preferredContentSizeCategory),
                            colorScheme: traits.userInterfaceStyle == .dark ? .dark : .light,
                            regularWidth: traits.horizontalSizeClass == .regular,
                            voiceOver: UIAccessibility.isVoiceOverRunning,
                            reduceMotion: UIAccessibility.isReduceMotionEnabled)).collect(connection: connection)
                    }
            }
        }
        settingsWindows[key] = result
        settingsConfigurations[key] = configuration
        settingsHouseholdControls[key] = householdControls
        return result
    }

    private func profile(id: String, session: AppSession, current: @escaping () -> Bool) -> UKServerUIProfileProvider {
        let project: (String) -> (ProfileSummary.Person, AvatarBox?)? = { [weak session, connection] id in
            guard current(), let state = connection.store.entity(id).state,
                  let person = ProfileSummary.people([state]).first else { return nil }
            return (person, ScreenshotPrivacy.isRedacting ? nil : session?.avatars.box(for: id))
        }
        let people = Dictionary(uniqueKeysWithValues: (session.houseConfig?.current?.chores.people ?? []).map { person in
            (person.personEntityId, { project(person.personEntityId) })
        })
        let open: (HomeAssistantSettingsView.WebPage, UIViewController) -> Void = { [weak session, connection] destination, presenter in
            guard let session, current() else { return }
            let page = UKHomeAssistantWebPageViewController(page: destination, session: session, connection: connection) { [weak presenter] in
                presenter?.dismiss(animated: true)
            }
            var options = UKHassModalOptions(title: destination.title)
            options.isFullScreen = true
            options.closeIdentifier = "haSettings.done"
            UKHassModalController(root: page, options: options).present(from: presenter)
        }
        var peopleRevision = -1
        var personIDs: [String] = []
        // A launch with no location coordinator (a debug journey, the gallery) has no location to show, so the location rows hide
        // instead of failing acceptance of the whole layout.
        return UKServerUIProfileProvider(id: id, location: session.location, people: people, allPeople: { [connection] in
            if peopleRevision != connection.store.peopleRevision {
                peopleRevision = connection.store.peopleRevision
                personIDs = connection.store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted()
            }
            return personIDs.compactMap(project).sorted {
                ($0.0.isHome ? 0 : 1, $0.0.name) < ($1.0.isHome ? 0 : 1, $1.0.name)
            }
        }, supportsLocation: session.location != nil, isCurrentSession: current, signOut: { [weak session] in
            guard let session, current() else { throw CancellationError() }
            try await session.confirmedSignOut()
        }, homeAssistant: { open(.settings, $0) }, homeAssistantSnapshot: { [weak self, weak session, connection] in
            let document = session?.houseConfig?.current
            let missing = document?.missingEntityIds(hasReceivedFirstState: connection.store.hasReceivedFirstState) {
                connection.store.value($0)
            } ?? []
            let user = self?.user
            return .init(address: HomeAssistantSettingsView.displayedServer(connection.server),
                connection: HomeAssistantSettingsView.statusText(connection.status, isOffline: connection.isOffline),
                version: HomeAssistantSettingsView.version(connection.status),
                houseLayout: HouseLayoutSummary(hasDocument: document != nil, status: session?.houseConfig?.status, missing: missing),
                account: user.map { HomeAssistantSettingsView.displayedName($0) } ?? (self?.accountUnavailable == true ? "Unavailable offline" : "Loading"),
                role: user?.roleTitle, canAdminister: current() && (user?.isAdmin == true || user?.isOwner == true))
        }, openHomeAssistantWeb: open)
    }

    func adoptPreferences(sceneID: UUID, blur: BackdropBlurSettings) {
        for case let preferences as UKServerUIPreferencesProvider in (settingsWindows[sceneID] ?? [:]).values {
            preferences.adoptBlur(blur)
        }
        visiblePreferenceWindows.insert(sceneID)
    }

    func presentationCollections(_ settings: [String: any UKServerUISettingsProvider]) throws -> [String: ServerUIRowCollection] {
        var result: [String: ServerUIRowCollection] = [:]
        for case let provider as UKServerUIPerformanceProvider in settings.values {
            for (key, collection) in provider.collections {
                let id = "performance-" + key
                guard result[id] == nil else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                result[id] = collection
            }
        }
        return result
    }

    /// Never seeds Summary permissions from the legacy remembered viewer preference.
    func records(for publication: ServerUICompositionPublication, sceneID: UUID? = nil) throws -> UKServerUIRecords {
        guard session?.isCurrentConnection(connection) == true else { throw CancellationError() }
        let key = sceneID ?? validationSceneID
        let base = try baseRecords(for: publication, sceneID: key)
        let settings = try settings(for: publication, sceneID: key)
        let identities = settings.mapValues { ObjectIdentifier($0) }
        if let existing = presentationRecords[key], existing.base == base.identity, existing.settings == identities {
            return existing.records
        }
        var result = base
        for case let away as UKServerUIAwayProvider in settings.values { try away.addPresentations(to: &result) }
        for case let feedback as UKServerUIFeedbackProvider in settings.values {
            let id = "modal-" + feedback.definition.providerId + "-cancel"
            guard result.actionStates[id] == nil else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            result.actionStates[id] = { [weak feedback] in
                .init(enabled: feedback?.isCurrentSession == true && feedback?.canDiscard == true)
            }
        }
        presentationRecords[key] = (base.identity, identities, result)
        return result
    }

    private func baseRecords(for publication: ServerUICompositionPublication, sceneID: UUID) throws -> UKServerUIRecords {
        let key = sceneID
        guard UKServerUIRecordProviders.required(by: publication.document) else { return recordWindows[key]?.records ?? emptyRecords }
        guard let session, session.isCurrentConnection(connection) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        guard let identity = user?.id ?? session.cachedPublicationUserID(for: connection),
              let people = session.houseConfig?.current?.chores.people else { throw Self.pending }
        let definition = UKServerUIRecordProviders.Definition(people: people, document: publication.document)
        if let existing = recordWindows[key], recordUserID == identity, existing.definition == definition {
            return existing.records
        }
        if let recordUserID, recordUserID != identity { throw CancellationError() }
        if recordStore == nil {
            let identityBytes = try JSONEncoder().encode([connection.server.baseURL.absoluteString, identity])
            let digest = SHA256.hash(data: identityBytes).map { String(format: "%02x", $0) }.joined()
            let file = recordCacheRoot.appendingPathComponent(digest).appendingPathComponent("todo.json")
            recordStore = TodoStore(service: caller, cache: TodoItemsCache(server: connection.server, fileURL: file))
            recordCacheFile = file
            recordUserID = identity
        }
        guard let recordStore else { throw CancellationError() }
        let registry = try UKServerUIRecordProviders(definition: definition, authenticatedUserID: identity,
            service: caller, recipes: EverShelfRecipeService(caller: caller), todos: recordStore, store: connection.store,
            accessToken: { [caller] in try await caller.accessToken() },
            isCurrentSession: { [weak session, connection] in session?.isCurrentConnection(connection) == true },
            retaining: recordWindows[key])
        recordWindows[key] = registry
        return registry.records
    }

    func detachRecordWindow(_ id: UUID) {
        recordWindows[id] = nil
        settingsWindows[id] = nil
        settingsConfigurations[id] = nil
        settingsHouseholdControls[id] = nil
        presentationRecords[id] = nil
        visiblePreferenceWindows.remove(id)
    }

    func endSession() {
        recordWindows.removeAll()
        settingsWindows.removeAll()
        settingsConfigurations.removeAll()
        settingsHouseholdControls.removeAll()
        presentationRecords.removeAll()
        visiblePreferenceWindows.removeAll()
        recordStore = nil
        if let recordCacheFile, FileManager.default.fileExists(atPath: recordCacheFile.path) {
            do { try FileManager.default.removeItem(at: recordCacheFile) }
            catch { NSLog("ServerUI account record cache cleanup failed.") }
        }
        recordCacheFile = nil
        recordUserID = nil
    }

    /// Authored descriptors own their keys. House-config providers only fill legacy references.
    func supplementalProviders(for publication: ServerUICompositionPublication) -> (
        bedrooms: [String: UKServerUIBedroomProvider], remotes: [String: ServerUIRemoteSession]
    ) {
        var authoredBedrooms = Set<String>(), authoredRemotes = Set<String>()
        for source in publication.document.dataSources {
            guard case .deviceProvider(let id, let descriptor) = source else { continue }
            switch descriptor {
            case .bedroom(let room):
                authoredBedrooms.formUnion(room.beds.map(\.providerId))
                authoredBedrooms.insert(room.wakeProviderId)
            case .remote: authoredRemotes.insert(id)
            case .lights, .sprinkler: break
            }
        }
        return (bedrooms.filter { !authoredBedrooms.contains($0.key) },
                remotes.filter { !authoredRemotes.contains($0.key) })
    }
}

/// A delayed command from an ended account cannot use a later session's authority.
@MainActor
final class UKServerUISessionCaller: HassServiceResponding, HassScheduleStoring, TodoServicing {
    private weak var session: AppSession?
    private let connection: HassConnection
    private let configuration: HouseConfig?
    init(session: AppSession, connection: HassConnection, configuration: HouseConfig? = nil) {
        self.session = session
        self.connection = connection
        self.configuration = configuration
    }
    private func validate() throws {
        guard session?.isCurrentConnection(connection) == true else { throw CancellationError() }
        if let configuration, session?.houseConfig?.current != configuration { throw CancellationError() }
    }
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try validate()
        try await connection.callService(domain, service, data: data)
        try validate()
    }
    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try validate()
        let response = try await connection.callServiceWithResponse(domain, service, data: data)
        try validate()
        return response
    }

    // MARK: - Scoped record services

    func accessToken() async throws -> String {
        try validate()
        guard let tokens = session?.tokens else { throw CancellationError() }
        let token = try await tokens.validAccessToken()
        try validate()
        return token
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try validate()
        let response = try await connection.callServiceForResponse(domain, service, data: data)
        try validate()
        return response
    }

    func todoItems(entityId: String) async throws -> [TodoItem] {
        try validate()
        let items = try await connection.todoItems(entityId: entityId)
        try validate()
        return items
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        try validate()
        try await connection.uploadAdminTodo(upload, accessToken: accessToken)
        try validate()
    }

    // MARK: - Scoped schedules

    func listSchedules() async throws -> [HassSchedule] {
        try validate()
        let schedules = try await connection.listSchedules()
        try validate()
        return schedules
    }

    func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule {
        try validate()
        let schedule = try await connection.updateSchedule(message)
        try validate()
        return schedule
    }

    func userIsAdmin() async throws -> Bool {
        try validate()
        let isAdmin = try await connection.userIsAdmin()
        try validate()
        return isAdmin
    }
}
#endif
