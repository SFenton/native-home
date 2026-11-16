#if os(iOS) && DEBUG
import HassCore
import HassDemoHouse
import HassDesign
import Observation
import UIKit

// MARK: - Isolated gallery providers

/// Explicitly selected gallery services, never an authenticated session or a fallback for live providers.
@MainActor @Observable
final class UKServerUIPreviewFixtures: UKServerUIAccountProvider {
    struct Configuration: Decodable, Sendable {
        let viewerUserID: String
        let administrator: Bool
        let bedroomScenario: String?

        init(viewerUserID: String, administrator: Bool, bedroomScenario: String? = nil) {
            self.viewerUserID = viewerUserID
            self.administrator = administrator
            self.bedroomScenario = bedroomScenario
        }
    }

    let configuration: Configuration
    let store: EntityStore
    let caller: UKServerUIPreviewFixtureCaller
    let recordService: UKServerUIPreviewFixtureRecords
    /// The signed-in person's key, which the gallery's resident-aware nodes read.
    let viewerKey: String
    private let viewerUserID: String
    private let recordAccessToken: @MainActor () async throws -> String
    let location: LocationCoordinator
    let feedback = FeedbackFixtureFiler()
    private(set) var records: UKServerUIRecords
    private(set) var settings: [String: any UKServerUISettingsProvider] = [:]
    var isCurrent: Bool { recordService.isCurrent }
    private(set) var copiedVersion: String?
    private var iconName: String?
    private let name: String
    private let defaults: UserDefaults
    private let defaultsName = "ServerUIPreviewFixtures-" + UUID().uuidString

    init(configuration: Configuration, store: EntityStore) throws {
        let bedroomScenario = configuration.bedroomScenario.flatMap(BedroomFixtures.Scenario.init(rawValue:))
        guard configuration.bedroomScenario == nil || bedroomScenario != nil else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/preview/gallery/bedroomScenario")
        }
        guard HouseConfigSource.active.current == DemoHouse.config,
              let person = DemoHouse.config.chores.people.first(where: { $0.haUserId == configuration.viewerUserID }),
              let defaults = UserDefaults(suiteName: defaultsName) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/preview/gallery")
        }
        self.configuration = configuration
        self.store = store
        self.defaults = defaults
        name = person.name
        if let bedroomScenario { store.apply(BedroomFixtures.states(bedroomScenario)) }
        recordService = UKServerUIPreviewFixtureRecords(store: store)
        caller = UKServerUIPreviewFixtureCaller(store: store, isCurrent: { [recordService] in recordService.isCurrent })
        viewerKey = person.key
        viewerUserID = person.haUserId
        recordAccessToken = { [recordService] in
            try recordService.requireCurrent()
            return "fixture-only"
        }
        records = UKServerUIRecords()
        let push = PushCoordinator.inert()
        location = LocationCoordinator(platform: GalleryLocationPlatform(.notDetermined), mobileApp: push.mobileApp,
                                       defaults: defaults)
    }

    deinit { UserDefaults().removePersistentDomain(forName: defaultsName) }

    var context: UKContext { UKContext(store: store, caller: caller) }
    var account: UKServerUIAccountValue {
        isCurrent ? .ready(name: name, server: "Isolated gallery", avatar: nil) : .unavailable
    }
    var header: UKServerUIShellHeaderSource {
        .init(state: { [weak self] in
            guard let self, isCurrent else { return .init(profileName: nil) }
            return .init(profileName: name,
                attentionCount: ShellAttention.count(store: store, viewerUserId: configuration.viewerUserID))
        })
    }

    func weatherReader(for document: ServerUICompositionDocument) -> ServerUIWeatherReader {
        let ids = document.dataSources.compactMap { source -> String? in
            guard case .homeWeather(_, let configuration) = source else { return nil }
            return configuration.weatherEntityId
        }
        return ServerUIWeatherReader(entityIds: Set(ids), caller: WeatherFixtureCaller(mode: .normal), connected: { true })
    }

    /// Existing models own selections and drafts; each provider is retained for this preview's lifetime.
    func prepare(_ publication: ServerUICompositionPublication, backdrop: HouseBackdropStore) throws {
        let current = { [weak self] in self?.isCurrent == true }
        recordService.allowCompletionScripts(from: publication.document)
        // The record pages are the publication's, as in the app: the demo house supplies the people and nothing else.
        let recordProviders = try UKServerUIRecordProviders(
            definition: .init(people: DemoHouse.config.chores.people, document: publication.document),
            authenticatedUserID: viewerUserID, service: recordService,
            recipes: FixtureRecipeService(mode: .normal, delay: .zero),
            todos: TodoStore(service: recordService), store: store,
            accessToken: recordAccessToken, isCurrentSession: { [recordService] in recordService.isCurrent })
        records = recordProviders.records
        for source in publication.document.dataSources {
            guard case .settingsProvider(_, let definition) = source else { continue }
            if let existing = settings[definition.providerId] {
                guard existing.definition == definition else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                continue
            }
            let provider: any UKServerUISettingsProvider
            switch definition.domain {
            case .household:
                provider = try UKServerUIHouseholdProviders.household(id: definition.providerId,
                    configuration: DemoHouse.config, document: publication.document, store: store, caller: caller, current: current)
            case .away:
                let away = try UKServerUIHouseholdProviders.away(id: definition.providerId,
                    configuration: UKServerUIPreviewPlaceholders.houseConfig(for: publication.document,
                                                                             awayProviderId: definition.providerId),
                    authenticatedUserID: configuration.viewerUserID,
                    store: store, caller: caller, current: current)
                try away.addPresentations(to: &records)
                provider = away
            case .preferences:
                let icons = AppIconPlatform(supportsAlternateIcons: { true },
                    currentName: { [weak self] in self?.iconName },
                    setName: { [weak self] name in self?.iconName = name })
                provider = UKServerUIPreferencesProvider(id: definition.providerId, blur: backdrop.blur,
                    icons: AppIconPickerModel(platform: icons),
                    about: AboutSettingsModel(pasteboard: { [weak self] in self?.copiedVersion = $0 }),
                    defaults: defaults, isCurrentSession: current)
            case .performance:
                provider = try UKServerUIPerformanceProvider(id: definition.providerId, isCurrentSession: current)
            case .profile:
                provider = profile(id: definition.providerId, current: current)
            case .feedback:
                let kind: FeedbackKind
                switch definition.providerId {
                case "feedback-bug": kind = .bug
                case "feedback-feature": kind = .feature
                default: throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                let feedback = UKServerUIFeedbackProvider(id: definition.providerId,
                    model: FeedbackFormModel(kind: kind, services: FeedbackServices(filer: feedback)),
                    platform: FeedbackPlatform.resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                      hasHinge: HingePresence.shared.hasHinge),
                    isCurrentSession: current) { traits in
                        .init(app: AppBuildInfo.versionText(Bundle.main.infoDictionary),
                              system: UIDevice.current.systemVersion, device: "Isolated gallery", window: "Fixture",
                              homeAssistant: "No connection", accessibility: traits.preferredContentSizeCategory.rawValue,
                              locale: Locale.current.identifier)
                    }
                records.actionStates["modal-" + definition.providerId + "-cancel"] = { [weak feedback] in
                    .init(enabled: feedback?.isCurrentSession == true && feedback?.canDiscard == true)
                }
                provider = feedback
            }
            settings[definition.providerId] = provider
        }
    }

    func collections() throws -> [String: ServerUIRowCollection] {
        var result: [String: ServerUIRowCollection] = [:]
        for case let provider as UKServerUIPerformanceProvider in settings.values {
            for (key, value) in provider.collections {
                let id = "performance-" + key
                guard result[id] == nil else {
                    throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
                }
                result[id] = value
            }
        }
        return result
    }

    private func profile(id: String, current: @escaping () -> Bool) -> UKServerUIProfileProvider {
        let ids = store.allValues.keys.filter { $0.hasPrefix("person.") }.sorted()
        let project: (String) -> (ProfileSummary.Person, AvatarBox?)? = { [store] id in
            guard current(), let entity = store.entity(id).state,
                  let person = ProfileSummary.people([entity]).first else { return nil }
            return (person, nil)
        }
        let people = Dictionary(uniqueKeysWithValues: DemoHouse.config.chores.people.map { person in
            (person.personEntityId, { project(person.personEntityId) })
        })
        let unavailable: (UIViewController) -> Void = { page in
            let alert = UIAlertController(title: "Unavailable in Gallery",
                message: "This isolated preview does not open an authenticated Home Assistant web session.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            page.present(alert, animated: true)
        }
        return UKServerUIProfileProvider(id: id, location: location, people: people,
            allPeople: { ids.compactMap(project) }, isCurrentSession: current,
            signOut: { [weak self] in self?.recordService.isCurrent = false }, homeAssistant: unavailable,
            homeAssistantSnapshot: { [name, configuration] in
                .init(address: "Isolated gallery", connection: "No connection", version: nil,
                    houseLayout: .init(hasDocument: true, status: nil, missing: []), account: name,
                    role: configuration.administrator ? "Administrator" : "User", canAdminister: configuration.administrator)
            }, openHomeAssistantWeb: { _, page in unavailable(page) })
    }
}
#endif
