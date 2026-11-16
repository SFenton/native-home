#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import UIKit

// MARK: - Typed composition host

/// Schema-2's synthetic first slice, not a feature-screen dispatcher or an asset/publishing service.
///
/// The parent preflights and prepares this host and its canonical backdrop before durable promotion,
/// then mounts or updates it after final validation. Scene navigation and native instances survive
/// compatible updates. This API makes no visual-certification or all-app-parity claim.
@MainActor
final class UKServerUIRenderer: UIViewController, UITabBarControllerDelegate, UIGestureRecognizerDelegate {
    typealias D = ServerUICompositionDocument
    private(set) var publication: ServerUICompositionPublication
    /// The typed navigation state: the selected root, each stack's page ids and the presented modal.
    let navigation: ServerUINavigationState
    /// The document's data sources bound to live entity boxes and providers.
    let bindings: UKServerUIBindings
    /// The document's authored local values (tab selections, drafts), observed by the nodes that read them.
    let localState: ServerUILocalState
    private(set) var collections: [String: ServerUIRowCollection]
    private(set) var records: UKServerUIRecords
    /// The signed-in account the profile nodes read, or `nil` when the host supplies none.
    let accountProvider: (any UKServerUIAccountProvider)?
    private(set) var settingsProviders: [String: any UKServerUISettingsProvider]
    /// What the native shell header (quick links, profile, reconnecting arc) shows, or `nil` when the host supplies none.
    let shellHeader: UKServerUIShellHeaderSource?
    /// The push-notification state the bootstrap notice nodes read.
    let notificationSource: UKServerUINotificationSource
    /// Sends authored `call-service` actions and holds the optimistic values they show.
    let enabledMemory = UKEnabledMemory()
    let callRunner: UKServerUICallRunner
    /// Whether this device negotiated `sh.state-style@1`. False makes every `state-tile` use its built-in style alone; the app
    /// negotiates it, so only a test or an older host turns it off.
    var stateStylesEnabled = ServerUICompositionPublication.supportedCapabilities.contains(serverUIStateStyleCapability)
    /// Who is signed in, for `viewer` operands and predicates.
    let viewerSource = UKServerUIViewerSource()
    /// The context every page and atom of this host is built with: the surface is `.page` and the shell is shared.
    let pageContext: UKContext
    /// The shell environment (window fold, vertical bar, canvas size) pages lay out against.
    let environment: UKShellEnvironment
    /// The tab bar controller whose tabs are the document's tabs; a tab rule changes its members in place.
    let tabController = UITabBarController()
    private(set) var stacks: [ServerUINavigationState.Root: UINavigationController] = [:]
    private var logicalStacks: [ServerUINavigationState.Root: [UKServerUIPage]] = [:]
    private(set) var modal: UKHassModalController?
    private var modalPresentationID: UUID?
    private var modalToken: UUID?
    private struct AdaptivePresentation {
        let id: UUID
        let owner: UKServerUIPage
        var pages: [UKServerUIPage]
    }
    private var adaptive: AdaptivePresentation?
    private var columnSize: CGSize = .zero
    private var columnRegular = false
    private var delegates: [ObjectIdentifier: UKServerUIStackDelegate] = [:]
    private var backdropStore: HouseBackdropStore
    private var backdrop: UKBackdropView?
    private var flyout: UKNavigationFlyoutView?
    private var flyoutOpen = false
    /// Observable stamp for the busy inputs below, read by ``isEnabled(_:from:)``.
    let busyState = UKServerUIBusyState()
    private var modalFlight = false { didSet { if modalFlight != oldValue { busyState.changed() } } }
    /// The push whose animation is running, settled when the stack shows its destination.
    private var navigationMeasurement: NavigationMeasurement?
    private var pending: Pending?
    private var handoff = false { didSet { if handoff != oldValue { busyState.changed() } } }
    private let bag = UKObservationBag()
    private let tabBag = UKObservationBag()
    private var tabShown: [String: Bool] = [:]
    private var accessibilityObservers: UKObserverTokens?
    private var edgePan: UIScreenEdgePanGestureRecognizer?
    private var standaloneSignals: UKDeviceSignals?
    private let needsSignals: Bool
    private let sheetFitNamespace = UUID().uuidString
    private var remoteProviders: [String: ServerUIRemoteSession]
    private var suppliedBedrooms: [String: UKServerUIBedroomProvider]
    private var suppliedCollections: [String: ServerUIRowCollection]
    private let deviceResponder: (any HassServiceResponding)?
    private var canEditBedroom: Bool
    private(set) var deviceProviders: ServerUIDeviceProviders
    /// Resolves an app's artwork URL from its provider id and app id; never an authored URL.
    let remoteArtwork: (String, String) -> URL?
    private let weatherReader: ServerUIWeatherReader?
    private let cameraReader: UKCameraReadProvider?
    /// The id of the resident whose room the room nodes treat as current, if known.
    let roomResidentId: () -> String?
    private static let barHeight = UINavigationBar().sizeThatFits(CGSize(width: 1000, height: 1000)).height
    private var allPages: [UIViewController] {
        var seen: Set<ObjectIdentifier> = []
        return (logicalStacks.values.flatMap { $0 } + (adaptive?.pages ?? []) + (modal?.viewControllers ?? []))
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// Parent-owned reporting may attach an explicit recovery UI. The default logs sanitized diagnostics.
    var onError: (UKServerUIRendererError) -> Void = { NSLog("ServerUI %@", $0.description) }
    /// Asks whether a page may be left, and prompts for a discard when its settings or bedroom drafts would be lost.
    var nativeExitGate: UKServerUIExitGate?

    /// Whether a component shows now: the record collections and the room rules both allow it.
    /// - Parameter value: The component to test.
    func componentVisible(_ value: D.Component) -> Bool {
        records.isVisible(value) && bindings.roomVisible(value)
    }

    /// The environment authored expressions are evaluated against: entity boxes, the optimistic overlay and the signed-in person.
    func reader(control: JSONValue? = nil) -> UKServerUIReader {
        UKServerUIReader(bindings: bindings, viewerSource: viewerSource, runner: callRunner, controlValue: control)
    }

    /// The record or bedroom collection registered under `id`, or `nil`.
    /// - Parameter id: The collection's provider id.
    func recordCollection(_ id: String) -> (any UKServerUICollectionSource)? {
        records.collections[id] ?? bindings.bedroomRegistry?.collections[id]
    }

    /// Runs before UIKit mutates a stack, including the custom interactive edge pop.
    func requestNativeExit(from page: UKServerUIPage, leaving: [UKServerUIPage]? = nil, completion: @escaping () -> Void) {
        let pages = leaving ?? [page]
        let forms = pages.compactMap(\.formView)
        func blockedPage() -> Bool { pages.contains(where: \.blocksRecordExit) || forms.contains(where: \.blocksExit) }
        guard !isBusy, activeAlert == nil, !blockedPage() else { onError(blocked()); return }
        let finish = { [weak self, weak page] in
            guard let self, let page, !self.isBusy, self.activeAlert == nil, !blockedPage() else { return }
            let approved = { [weak self, weak page] in
                guard let self, page != nil, !self.isBusy, self.activeAlert == nil, !blockedPage() else { return }
                do { for form in forms { try form.discard() } }
                catch { self.onError(self.blocked()); return }
                completion()
            }
            if let gate = self.nativeExitGate { gate.request(page, approved) }
            else { approved() }
        }
        if forms.contains(where: \.needsDiscard) { UKDiscardGuard.confirm(from: page, source: .none, onDiscard: finish) }
        else { finish() }
    }

    /// Main-actor UIKit support gate. It does not accept, cache or visibly apply a publication.
    static func preflight(_ publication: ServerUICompositionPublication,
                          collections: [String: ServerUIRowCollection] = [:],
                          records: UKServerUIRecords = .init(),
                          remoteProviders: [String: ServerUIRemoteSession] = [:], store: EntityStore? = nil,
                          accountProvider: (any UKServerUIAccountProvider)? = nil,
                          settingsProviders: [String: any UKServerUISettingsProvider] = [:],
                          shellHeader: UKServerUIShellHeaderSource? = nil) throws {
        try UKServerUIPreflight.validate(publication, collections: collections)
        try UKServerUISettingsProviders.validate(publication.document, providers: settingsProviders)
        try records.validate(publication.document)
        if publication.capabilities.contains("sh.shell-header@1"), shellHeader == nil {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/navigation/chrome")
        }
        if let store {
            try UKServerUIRemoteProviders.validate(publication.document, providers: remoteProviders, store: store)
        } else if publication.document.dataSources.contains(where: {
            if case .mediaRemote = $0 { return true }; return false
        }) {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        if accountProvider == nil, publication.document.dataSources.contains(where: {
            if case .profileAccount = $0 { return true }
            return false
        }) {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
    }

    /// `backdrop` must already be prepared by the parent's asset/promotion transaction.
    init(publication: ServerUICompositionPublication, context: UKContext, backdrop: HouseBackdropStore,
         collections: [String: ServerUIRowCollection] = [:],
         records: UKServerUIRecords = .init(),
         bedroomProviders: [String: UKServerUIBedroomProvider] = [:],
         remoteProviders: [String: ServerUIRemoteSession] = [:],
         deviceResponder: (any HassServiceResponding)? = nil,
         scheduleStorage: (any HassScheduleStoring)? = nil,
         canEditBedroom: Bool = false,
         remoteArtwork: @escaping (String, String) -> URL? = { _, _ in nil },
         roomResidentId: @escaping () -> String? = { nil },
         vacuums: UKServerUIVacuumEnvironment = .init(),
         cameraPool: CameraStreamPool = .shared,
         weatherReader: ServerUIWeatherReader? = nil,
         cameraReader: UKCameraReadProvider? = nil,
         accountProvider: (any UKServerUIAccountProvider)? = nil,
         settingsProviders: [String: any UKServerUISettingsProvider] = [:],
         shellHeader: UKServerUIShellHeaderSource? = nil) throws {
        let prepared = try UKServerUIDeviceProviders(sources: publication.document.dataSources, context: context,
            responder: deviceResponder, canEditBedroom: canEditBedroom, bedrooms: bedroomProviders,
            remotes: remoteProviders, collections: collections, retaining: nil)
        try Self.preflight(publication, collections: prepared.collections,
                           records: prepared.bedroomRegistry.addingCollections(to: records), remoteProviders: prepared.remotes,
                           store: context.store, accountProvider: accountProvider, settingsProviders: settingsProviders,
                           shellHeader: shellHeader)
        self.settingsProviders = settingsProviders
        self.deviceProviders = prepared.domain
        self.deviceResponder = deviceResponder
        self.canEditBedroom = canEditBedroom
        suppliedBedrooms = bedroomProviders
        suppliedCollections = collections
        self.remoteProviders = remoteProviders
        self.remoteArtwork = remoteArtwork
        self.weatherReader = weatherReader
        self.cameraReader = cameraReader
        try Self.validateWeatherProvider(publication.document, context: context, reader: weatherReader)
        try Self.validateCameraProvider(publication.document, context: context, reader: cameraReader)
        self.roomResidentId = roomResidentId
        for source in publication.document.dataSources {
            if case .camera(_, let configuration) = source, !cameraPool.accepts(configuration.camera(title: "")) {
                throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
            }
        }
        self.publication = publication
        self.collections = prepared.collections
        self.records = records
        localState = try ServerUILocalState(fields: publication.document.localState)
        self.accountProvider = accountProvider
        self.shellHeader = shellHeader
        backdropStore = backdrop
        navigation = try ServerUINavigationState(catalog: ServerUINavigationCatalog(composition: publication.document))
        let environment = context.shell ?? UKShellEnvironment()
        self.environment = environment
        needsSignals = context.shell == nil
        pageContext = context.with {
            $0.surface = .page
            $0.backdrop = backdrop
            $0.shell = environment
        }
        bindings = UKServerUIBindings(sources: publication.document.dataSources, context: pageContext,
                                      scheduleStorage: scheduleStorage,
                                      bedroomProviders: prepared.bedrooms, bedroomRegistry: prepared.bedroomRegistry,
                                      remoteProviders: prepared.remotes,
                                      deviceProviders: prepared.domain,
                                      vacuums: vacuums, cameraPool: cameraPool, weatherReader: weatherReader, cameraReader: cameraReader)
        try bindings.validateBedroomSources(publication.document.dataSources)
        notificationSource = UKServerUINotificationSource(push: context.push)
        callRunner = UKServerUICallRunner(context: pageContext)
        super.init(nibName: nil, bundle: nil)
        bindings.readerProvider = { [unowned self] in self.reader() }
        nativeExitGate = .init(blocksExit: { [weak self] page in
            guard let self else { return true }
            return self.attachedSettingsProviders(from: page).contains(where: \.blocksExit)
                || self.attachedBedroomDrafts(from: page).contains(where: \.blocksExit)
        }, request: { [weak self] page, completion in
            self?.requestSettingsExit(from: page, completion: completion)
        }, canDiscard: { [weak self] page in
            guard let self else { return false }
            return self.attachedSettingsProviders(from: page).filter(\.blocksExit).allSatisfy(\.canDiscard)
                && self.attachedBedroomDrafts(from: page).filter(\.blocksExit).allSatisfy(\.canDiscard)
        })
        overrideUserInterfaceStyle = .dark
        // The cached publication's user is known before the socket answers, so rules on the viewer's id resolve at the first frame.
        if let session = context.session, let connection = context.connection {
            viewerSource.seed(userID: session.cachedPublicationUserID(for: connection))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Must run before durable promotion when an existing host is active; a build is not acceptance.
    func validateUpdate(_ candidate: ServerUICompositionPublication,
                        collections nextCollections: [String: ServerUIRowCollection]? = nil,
                        records nextRecords: UKServerUIRecords? = nil,
                        settingsProviders nextSettings: [String: any UKServerUISettingsProvider]? = nil,
                        bedroomProviders nextBedrooms: [String: UKServerUIBedroomProvider]? = nil,
                        remoteProviders nextRemotes: [String: ServerUIRemoteSession]? = nil,
                        canEditBedroom nextCanEditBedroom: Bool? = nil) throws {
        try Self.validateWeatherProvider(candidate.document, context: pageContext, reader: weatherReader)
        try Self.validateCameraProvider(candidate.document, context: pageContext, reader: cameraReader)
        let prepared = try prepareDeviceProviders(candidate, collections: nextCollections, bedrooms: nextBedrooms, remotes: nextRemotes,
                                                  canEditBedroom: nextCanEditBedroom)
        let replacementRecords = nextRecords ?? records
        let replacesRecords = replacementRecords.identity != records.identity
        let replacementSettings = nextSettings ?? settingsProviders
        let replacesSettings = replacementSettings.keys.contains { settingsProviders[$0] !== replacementSettings[$0] }
            || settingsProviders.keys.contains { replacementSettings[$0] == nil }
        let replacesCollections = nextCollections.map { next in
            next.keys.contains { suppliedCollections[$0] !== next[$0] }
                || suppliedCollections.keys.contains { next[$0] == nil }
        } ?? false
        try Self.preflight(candidate, collections: prepared.collections,
                           records: prepared.bedroomRegistry.addingCollections(to: replacementRecords), remoteProviders: prepared.remotes,
                           store: pageContext.store, accountProvider: accountProvider, settingsProviders: replacementSettings,
                           shellHeader: shellHeader)
        guard candidate.document.id == publication.document.id, candidate.publisherId == publication.publisherId else {
            throw UKServerUIRendererError(code: .differentDocument, pointer: "/document/id")
        }

        guard !isBusy, !flyoutOpen, flyout?.isBlockingTouches != true, activeAlert == nil else { throw blocked() }
        if candidate.document != publication.document || replacesSettings || replacesCollections,
           settingsProviders.values.contains(where: \.protectsPublication) {
            throw blocked("/document/dataSources")
        }
        if candidate.document != publication.document || replacesRecords, records.hasPendingIntent { throw blocked("/document/dataSources") }
        let pages = allPages
        if replacesRecords, pages.contains(where: { ($0 as? UKServerUIPage)?.formView?.session != nil }) {
            throw blocked("/document/form")
        }
        for case let page as UKServerUIPage in pages where page.presentationID == nil {
            let old = publication.document.pages.first { $0.id == page.surfaceID }
            let new = candidate.document.pages.first { $0.id == page.surfaceID }
            if old?.navigation != new?.navigation || old?.columnPlaceholder != new?.columnPlaceholder
                || old?.standaloneColumns != new?.standaloneColumns || old?.columnsOnDemand != new?.columnsOnDemand { throw blocked("/document/pages") }
        }
        if pages.contains(where: {
            guard let page = $0 as? UKServerUIPage else { return false }
            return page.blocksShellPublication
        }) { throw blocked("/document/localState") }
        for case let page as UKServerUIPage in pages {
            if let form = page.formView, let definition = form.definition, form.session != nil {
                let surfaces = candidate.document.pages.map(\.surface) + candidate.document.modals.map(\.surface)
                let replacement = surfaces.first { $0.id == page.surfaceID }?.components.compactMap { node -> D.Form? in
                    if case .form(let form) = node, form.node.id == definition.node.id { return form }
                    return nil
                }.first
                if replacement != definition { throw blocked("/document/form") }
            }
        }
        do { try localState.validateReplacement(candidate.document.localState) }
        catch { throw blocked("/document/localState") }
        try bindings.validateBedroomSources(candidate.document.dataSources, providers: prepared.bedrooms, registry: prepared.bedroomRegistry)
        if let nextRemotes {
            for (id, provider) in remoteProviders where nextRemotes[id] !== provider && provider.hasInteraction {
                throw blocked("/document/dataSources")
            }
        }
        for (id, provider) in bindings.bedroomProviders
            where prepared.bedrooms[id]?.identity != provider.identity && (provider.protectsPublication || hasFocusedBedroomInput) {
            throw blocked("/document/dataSources")
        }
        if candidate.document != publication.document, deviceProviders.protectsPublication {
            throw blocked("/document/dataSources")
        }
        // A draft, delayed schedule write or optimistic echo must not lose its source, control or attachment.
        if candidate.document != publication.document,
           bindings.bedroomProviders.values.contains(where: \.protectsPublication) || hasFocusedBedroomInput {
            throw blocked("/document")
        }
        if notificationSource.pendingNode != nil { throw blocked("/document/pages") }
        if navigation.snapshot.selection == .initial, !candidate.document.navigation.tabs.isEmpty {
            throw blocked("/document/navigation/initialTabId")
        }

        try bindings.validateReplacement(candidate.document.dataSources)
        if candidate.document.navigation != publication.document.navigation,
           bindings.alarms.values.contains(where: \.hasPendingIntent) || bindings.doors.values.contains(where: \.hasPendingIntent) {
            throw blocked()
        }
        if candidate.document != publication.document,
           bindings.climates.values.contains(where: \.hasPendingIntent) {
            throw blocked("/document/pages")
        }
        if bindings.roomVisits?.pendingCount ?? 0 > 0, candidate.document != publication.document {
            throw blocked("/document/dataSources")
        }
        let nextSurfaces = candidate.document.pages.map(\.surface) + candidate.document.modals.map(\.surface)
        for surface in publication.document.pages.map(\.surface) + publication.document.modals.map(\.surface) {
            for (index, component) in surface.components.enumerated() where bindings.roomHasPendingCommand(component) {
                // Keep the command's containing layout attached without freezing unrelated page copy.
                guard let next = nextSurfaces.first(where: { $0.id == surface.id }),
                      next.components.indices.contains(index), next.components[index] == component else {
                    throw blocked("/document/dataSources")
                }
            }
        }
        let nextRemoteAttachments = UKServerUIRemoteProviders.attachments(candidate.document)
        for (sourceID, attachments) in UKServerUIRemoteProviders.attachments(publication.document) {
            if bindings.remotes[sourceID]?.hasInteraction == true, attachments != nextRemoteAttachments[sourceID] {
                throw blocked("/document/dataSources")
            }
        }
        try validateActionRebindings(candidate.document)
        try validateHomeRebindings(candidate.document)
        // A map gesture, draft, report route or pending command keeps its exact attachment and ancestors.
        // Rejecting the affected surface edit is deliberately stricter than silently losing its interaction state.
        for surface in publication.document.pages.map(\.surface) + publication.document.modals.map(\.surface) {
            func pinned(_ components: [D.Component]) -> Bool {
                components.contains {
                    if case .vacuum(let value) = $0 { return bindings.vacuums[value.sourceId]?.isPinned == true }
                    return pinned($0.childComponents)
                }
            }
            if pinned(surface.components) {
                let next = (candidate.document.pages.map(\.surface) + candidate.document.modals.map(\.surface)).first { $0.id == surface.id }
                if next != surface { throw blocked("/document/pages") }
            }
        }
        let nextCameras = cameraAttachments(candidate.document)
        for (id, attachment) in cameraAttachments(publication.document) where nextCameras[id] != attachment {
            if bindings.cameras[attachment.sourceID]?.hasPendingIntent == true { throw blocked("/document/dataSources") }
        }
        // Presentation options are immutable in the canonical modal. Never approximate an active policy edit.
        for current in navigation.snapshot.presentations {
            let old = publication.document.modals.first { $0.id == current.modalID }
            let next = candidate.document.modals.first { $0.id == current.modalID }
            if let next, old?.presentation != next.presentation { throw blocked("/document/modals") }
        }
    }

    /// Runs before adoption, including replacement publications; missing reads cannot replace a last-good page.
    private static func validateWeatherProvider(_ document: D, context: UKContext, reader: ServerUIWeatherReader?) throws {
        for (index, source) in document.dataSources.enumerated() {
            guard case .homeWeather(_, let configuration) = source else { continue }
            let available = reader.map { $0.entityIds.contains(configuration.weatherEntityId) } ?? (context.connection != nil)
            guard available else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)")
            }
        }
    }

    private static func validateCameraProvider(_ document: D, context: UKContext, reader: UKCameraReadProvider?) throws {
        for (index, source) in document.dataSources.enumerated() {
            guard case .camera(_, let configuration) = source else { continue }
            guard reader?.accepts(configuration) ?? (context.connection != nil) else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources/\(index)")
            }
        }
    }

    private var hasFocusedBedroomInput: Bool {
        func focused(_ view: UIView) -> Bool { view.isFirstResponder || view.subviews.contains(where: focused) }
        return isViewLoaded && !bindings.bedroomProviders.isEmpty && focused(view)
    }

    private func validateActionRebindings(_ candidate: D) throws {
        func targets(_ document: D) -> [String: D.PowerAction] {
            var targets: [String: D.PowerAction] = [:]
            func groups(_ groups: [D.ChromeGroup]) {
                for item in groups.flatMap(\.items) {
                    if case .button(let button) = item, case .domain(let action) = button.action {
                        targets["chrome." + button.id] = action
                    }
                }
            }
            func components(_ nodes: [D.Component]) {
                for node in nodes {
                    for action in node.ownActions {
                        if case .domain(let action) = action { targets["node." + node.node.id] = action }
                    }
                    components(node.childComponents)
                }
            }
            groups(document.navigation.chrome.groups)
            for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
                components(surface.components)
                if case .replace(let value) = surface.toolbar { groups(value) }
            }
            return targets
        }
        let next = targets(candidate)
        for (id, action) in targets(publication.document) where next[id] != action {
            if bindings.powers[action.sourceId]?.hasPendingIntent == true { throw blocked("/document/dataSources") }
        }
        let nextAlarms = alarmTiles(candidate)
        for (id, attachment) in alarmTiles(publication.document) where nextAlarms[id] != attachment {
            if let sourceID = attachment.tile.alarm?.sourceId, bindings.alarms[sourceID]?.hasPendingIntent == true {
                throw blocked("/document/dataSources")
            }
        }
        let nextSecurity = securityControls(candidate)
        for (id, attachment) in securityControls(publication.document) where nextSecurity[id] != attachment {
            let source: String
            switch attachment.component {
            case .alarmPanel(let panel): source = panel.sourceId
            case .doorTile(let tile): source = tile.sourceId
            default: continue
            }
            if bindings.alarms[source]?.hasPendingIntent == true || bindings.doors[source]?.hasPendingIntent == true {
                throw blocked("/document/dataSources")
            }
        }
        let nextDevices = deviceControls(candidate)
        let sourceChanged = candidate.dataSources != publication.document.dataSources
        for (id, attachment) in deviceControls(publication.document) where nextDevices[id] != attachment || sourceChanged {
            if bindings.devices[attachment.control.sourceId]?.hasPendingIntent == true { throw blocked("/document/dataSources") }
            let pages = allPages
            for page in pages.compactMap({ $0 as? UKServerUIPage }) {
                if let atom = page.nodes[id]?.view as? UKServerUIRoomDeviceAtom,
                   atom.hasLocalEdits || atom.hasFocusedControl { throw blocked("/document/pages") }
            }
        }
    }

    private struct SecurityAttachment: Equatable {
        let surfaceID: String
        let component: D.Component
    }

    private func securityControls(_ document: D) -> [String: SecurityAttachment] {
        var result: [String: SecurityAttachment] = [:]
        func visit(_ components: [D.Component], surfaceID: String) {
            for component in components {
                switch component {
                case .alarmPanel, .doorTile:
                    result[component.node.id] = .init(surfaceID: surfaceID, component: component)
                default: break
                }
                visit(component.childComponents, surfaceID: surfaceID)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            visit(surface.components, surfaceID: surface.id)
        }
        return result
    }

    private struct DeviceAttachment: Equatable {
        let surfaceID: String
        let control: ServerUIRoomDeviceControl
    }

    private func deviceControls(_ document: D) -> [String: DeviceAttachment] {
        var result: [String: DeviceAttachment] = [:]
        func visit(_ components: [D.Component], surfaceID: String) {
            for component in components {
                switch component {
                case .roomDeviceControl(let control): result[control.node.id] = DeviceAttachment(surfaceID: surfaceID, control: control)
                default: break
                }
                visit(component.childComponents, surfaceID: surfaceID)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) { visit(surface.components, surfaceID: surface.id) }
        return result
    }

    private struct AlarmAttachment: Equatable {
        let surfaceID: String
        let tile: D.NavigationTile
    }

    private struct CameraAttachment: Equatable {
        let surfaceID: String
        let sourceID: String
        let ancestry: [String]
        let component: D.Component
    }

    private func cameraAttachments(_ document: D) -> [String: CameraAttachment] {
        var result: [String: CameraAttachment] = [:]
        func visit(_ components: [D.Component], surfaceID: String, ancestry: [String]) {
            for component in components {
                visit(component.childComponents, surfaceID: surfaceID, ancestry: ancestry + [component.node.id])
                let source: String
                switch component {
                case .cameraTile(let value): source = value.sourceId
                case .cameraVideo(let value): source = value.sourceId
                case .cameraControls(let value): source = value.sourceId
                case .cameraViewer(let value): source = value.sourceId
                default: continue
                }
                result[component.node.id] = .init(surfaceID: surfaceID, sourceID: source, ancestry: ancestry, component: component)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            visit(surface.components, surfaceID: surface.id, ancestry: [])
        }
        return result
    }

    private func alarmTiles(_ document: D) -> [String: AlarmAttachment] {
        var result: [String: AlarmAttachment] = [:]
        func visit(_ components: [D.Component], surfaceID: String) {
            for component in components {
                switch component {
                case .navigationTile(let tile) where tile.alarm != nil:
                    result[tile.node.id] = AlarmAttachment(surfaceID: surfaceID, tile: tile)
                default: break
                }
                visit(component.childComponents, surfaceID: surfaceID)
            }
        }
        for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
            visit(surface.components, surfaceID: surface.id)
        }
        return result
    }

    private struct HomeAttachment: Equatable {
        let surfaceID: String
        let path: [String]
        let component: D.Component
        var sourceID: String {
            switch component {
            case .homeLightTile(let tile): tile.sourceId
            case .weatherPanel(let panel): panel.sourceId
            default: ""
            }
        }
    }

    private func validateHomeRebindings(_ candidate: D) throws {
        func attachments(_ document: D) -> [String: HomeAttachment] {
            var result: [String: HomeAttachment] = [:]
            func visit(_ components: [D.Component], surfaceID: String, path: [String] = []) {
                for (index, component) in components.enumerated() {
                    let path = path + ["\(component.node.id):\(index)"]
                    switch component {
                    case .homeLightTile, .weatherPanel:
                        result[component.node.id] = .init(surfaceID: surfaceID, path: path, component: component)
                    default: break
                    }
                    visit(component.childComponents, surfaceID: surfaceID, path: path)
                }
            }
            for surface in document.pages.map(\.surface) + document.modals.map(\.surface) {
                visit(surface.components, surfaceID: surface.id)
            }
            return result
        }
        let controllers = stacks.values.flatMap(\.viewControllers) + (modal?.viewControllers ?? [])
        let interacting = Set(controllers.compactMap { $0 as? UKServerUIPage }.flatMap { page in
            page.nodes.values.compactMap { entry -> String? in
                // Visible weather policies are immutable until Shell can migrate paging/focus state.
                if let panel = entry.view as? UKServerUIWeatherPanel, panel.window != nil { return panel.definition.sourceId }
                guard let view = entry.view as? UKServerUIHomeLightView, view.hasActiveInteraction else { return nil }
                return view.sourceID
            }
        })
        let nextSources = Dictionary(uniqueKeysWithValues: candidate.dataSources.map { ($0.id, $0) })
        for id in interacting where bindings.definitions[id] != nextSources[id] {
            throw blocked("/document/dataSources")
        }
        let next = attachments(candidate)
        for (id, current) in attachments(publication.document) where current != next[id] {
            if bindings.lights[current.sourceID]?.hasPendingIntent == true || interacting.contains(current.sourceID) {
                throw blocked("/document/dataSources")
            }
        }
    }

    /// Reconciles only a durably accepted candidate. Unchanged page/node/action-model identities are retained.
    func apply(publication candidate: ServerUICompositionPublication, backdrop: HouseBackdropStore,
               collections nextCollections: [String: ServerUIRowCollection]? = nil,
               records nextRecords: UKServerUIRecords? = nil,
               settingsProviders nextSettings: [String: any UKServerUISettingsProvider]? = nil,
               bedroomProviders nextBedrooms: [String: UKServerUIBedroomProvider]? = nil,
               remoteProviders nextRemotes: [String: ServerUIRemoteSession]? = nil,
               canEditBedroom nextCanEditBedroom: Bool? = nil) throws {
        if candidate == publication, backdrop === backdropStore, nextRecords == nil, nextBedrooms == nil, nextRemotes == nil,
           nextCanEditBedroom == nil, nextSettings == nil, nextCollections == nil { return }
        try validateUpdate(candidate, collections: nextCollections, records: nextRecords, settingsProviders: nextSettings,
                           bedroomProviders: nextBedrooms, remoteProviders: nextRemotes,
                           canEditBedroom: nextCanEditBedroom)
        let prepared = try prepareDeviceProviders(candidate, collections: nextCollections, bedrooms: nextBedrooms, remotes: nextRemotes,
                                                  canEditBedroom: nextCanEditBedroom)
        try navigation.apply(catalog: ServerUINavigationCatalog(composition: candidate.document))
        try localState.apply(candidate.document.localState)
        if let nextRecords { records = nextRecords }
        if let nextSettings { settingsProviders = nextSettings }
        if let nextCollections { suppliedCollections = nextCollections }
        if let nextRemotes { remoteProviders = nextRemotes }
        if let nextBedrooms { suppliedBedrooms = nextBedrooms }
        if let nextCanEditBedroom { canEditBedroom = nextCanEditBedroom }
        deviceProviders = prepared.domain
        collections = prepared.collections
        bindings.install(prepared)
        bindings.apply(candidate.document.dataSources)
        let backgroundChanged = publication.document.theme.background != candidate.document.theme.background
        publication = candidate
        if backdrop !== backdropStore {
            backdropStore = backdrop
            if isViewLoaded { installBackdrop() }
        } else if backgroundChanged, isViewLoaded {
            installBackdrop()
        }

        if isViewLoaded {
            observeTabVisibility()
            reconcile(animated: false, updateBodies: true)
        }
    }

    private func prepareDeviceProviders(_ candidate: ServerUICompositionPublication,
                                        collections: [String: ServerUIRowCollection]? = nil,
                                        bedrooms: [String: UKServerUIBedroomProvider]? = nil,
                                        remotes: [String: ServerUIRemoteSession]? = nil,
                                        canEditBedroom nextCanEditBedroom: Bool? = nil) throws -> UKServerUIDeviceProviders {
        try UKServerUIDeviceProviders(sources: candidate.document.dataSources, context: pageContext,
            responder: deviceResponder, canEditBedroom: nextCanEditBedroom ?? canEditBedroom, bedrooms: bedrooms ?? suppliedBedrooms,
            remotes: remotes ?? remoteProviders, collections: collections ?? suppliedCollections, retaining: deviceProviders,
            retainingBedrooms: bindings.bedroomRegistry)
    }

    // MARK: - Native shell

    /// Artwork comes from the same retained remote descriptor as its controls, never an authored URL.
    func artworkURL(providerID: String, appID: String) -> URL? {
        if let supplied = remoteArtwork(providerID, appID) { return supplied }
        guard let connection = pageContext.connection,
              pageContext.session?.isCurrentConnection(connection) == true,
              let path = remoteProviders[providerID]?.controller.config.apps.first(where: { $0.id == appID })?.imagePath else { return nil }
        return connection.server.url(path)
    }

    /// Navigation accepts the tap before its immutable visit command starts; dismissal never cancels the command.
    func activateRoom(_ destination: D.RoomDestination, sourceId: String, from page: UKServerUIPage, source: UIView) throws {
        guard !isBusy, activeAlert == nil,
              case .roomNavigation(_, let configuration) = bindings.definitions[sourceId],
              configuration.items.contains(destination), bindings.roomVisible(destination.visibility) else {
            throw blocked("/document/dataSources")
        }
        try perform(destination.action, from: page, source: source)
        if let call = ServerUIRooms.visitCall(destination, configuration: configuration) {
            guard let visits = bindings.roomVisits else {
                onError(UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources"))
                return
            }
            visits.record(call) { [weak self] _ in
                self?.onError(UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources"))
            }
        }
    }

    /// Installs the tab controller, backdrop, observers and first reconciliation, and starts loading the signed-in user.
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        installBackdrop()
        addChild(tabController)
        tabController.view.frame = view.bounds
        tabController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabController.view.backgroundColor = .clear
        tabController.view.isOpaque = false
        tabController.delegate = self
        view.addSubview(tabController.view)
        tabController.didMove(toParent: self)
        let flyout = UKNavigationFlyoutView(shell: environment, onDismiss: { [weak self] in self?.closeMenu() },
                                           onSelect: { [weak self] id in self?.selectFromMenu(id) })
        flyout.frame = view.bounds
        flyout.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flyout)
        self.flyout = flyout
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        pan.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        pan.delegate = self
        view.addGestureRecognizer(pan)
        edgePan = pan
        if needsSignals { standaloneSignals = UKDeviceSignals(view: view, environment: environment) }
        accessibilityObservers = UKObserverTokens(environment.observeAccessibilitySettings())
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.environment.windowFold
            _ = self.environment.inVerticalBar
            self.updateStyle()
        }
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (host: UKServerUIRenderer, _) in
            host.updateStyle()
            host.bindings.appState.updateWindow(size: host.view.bounds.size, traits: host.traitCollection)
        }
        if let connection = pageContext.connection {
            Task { [weak self] in
                guard let self else { return }
                await self.viewerSource.load(from: connection)
            }
        }
        observeTabVisibility()
        reconcile(animated: false, updateBodies: false)
    }

    /// Keeps the shell environment's canvas and the backdrop window in step with the view's size.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        standaloneSignals?.refresh()
        let canvas = view.bounds.size
        bindings.appState.updateWindow(size: canvas, traits: traitCollection)
        if environment.canvas != canvas {
            environment.canvas = canvas
            backdropStore.setWindow(canvas, scale: Double(traitCollection.displayScale))
        }
        let cap = HeaderEdgeFade.edgeCap(statusTop: view.safeAreaInsets.top.rounded(), barHeight: Self.barHeight,
                                        barIsRail: environment.inVerticalBar)
        if environment.headerEdgeCap != cap { environment.headerEdgeCap = cap }
        updateStyle()
        if columnSize != view.bounds.size || columnRegular != (traitCollection.horizontalSizeClass == .regular) {
            columnGeometryChanged()
        }
    }

    private func installBackdrop() {
        let store: HouseBackdropStore?
        switch publication.document.theme.background {
        case .solid: store = nil
        case .downloaded: store = backdropStore
        }
        // A changed backdrop rebinds the one view, so its photo cross-fades instead of the view being replaced.
        if let backdrop {
            backdrop.rebind(store: store)
            return
        }
        let view = UKBackdropView(store: store, shell: environment)
        view.frame = self.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.insertSubview(view, at: 0)
        backdrop = view
    }

    private func updateStyle() {
        let style = ShellNavigationStyle.resolve(isRegularWidth: traitCollection.horizontalSizeClass == .regular,
                                                 hasHinge: environment.windowFold.hinge != nil)
        let chrome = ShellChrome.resolve(style: style, inVerticalBar: environment.inVerticalBar)
        if environment.style != style { environment.style = style }
        if environment.chrome != chrome { environment.chrome = chrome }
        edgePan?.isEnabled = chrome.edgeSwipe
        let hidden = style == .flyout || publication.document.navigation.tabs.isEmpty
        if UKGlassEra.hasIOS18, #available(iOS 18.0, *) {
            if tabController.isTabBarHidden != hidden { tabController.setTabBarHidden(hidden, animated: false) }
        } else { tabController.tabBar.isHidden = hidden }
        if !chrome.showsMenuButton, flyoutOpen { closeMenu() }
    }

    // MARK: - Keyed controller reconciliation

    private func reconcile(animated: Bool, updateBodies: Bool) {
        let previous = allPages.compactMap { $0 as? UKServerUIPage }
        defer { retireRemovedBedroomDrafts(previous) }
        let snapshot = navigation.snapshot
        let roots: [ServerUINavigationState.Root] = publication.document.navigation.tabs.isEmpty
            ? [.initial] : publication.document.navigation.tabs.map { .tab($0.id) }
        for root in roots {
            guard let path = snapshot.stacks[root] else { continue }
            let nav = stacks[root] ?? makeStack()
            stacks[root] = nav
            sync(nav, path: path, root: root, presentation: nil, animated: animated, updateBodies: updateBodies)
            if case .tab(let id) = root, let tab = publication.document.navigation.tabs.first(where: { $0.id == id }) {
                nav.tabBarItem.title = tab.label
                nav.tabBarItem.image = UIImage(systemName: tab.icon.drawn)
                nav.tabBarItem.accessibilityLabel = tab.label
                nav.tabBarItem.accessibilityIdentifier = tab.id
            }
        }
        let controllers = roots.filter(isRootShown).compactMap { stacks[$0] }
        if tabController.viewControllers != controllers { tabController.setViewControllers(controllers, animated: false) }
        if let selected = stacks[snapshot.selection], tabController.selectedViewController !== selected {
            // A tab switch is a cut: the content swaps with no transition (`.agents/design/motion.md` section 4.1).
            UIView.performWithoutAnimation { tabController.selectedViewController = selected }
        }
        let removed = stacks.keys.filter { !roots.contains($0) }
        for key in removed {
            if let nav = stacks.removeValue(forKey: key) { delegates.removeValue(forKey: ObjectIdentifier(nav)) }
            logicalStacks.removeValue(forKey: key)
        }
        if let adaptive {
            if let current = snapshot.presentations.first(where: { $0.id == adaptive.id }),
               let nav = stacks[current.root] {
                sync(nav, path: [current.modalID] + current.pages, root: current.root,
                     presentation: current.id, animated: animated, updateBodies: updateBodies)
            } else { removeAdaptive(dismissState: false) }
        }
        if let current = snapshot.presentations.first(where: { $0.id == modalPresentationID }), let modal {
            sync(modal, path: [current.modalID] + current.pages, root: current.root,
                 presentation: current.id, animated: animated, updateBodies: updateBodies)
        } else if let modal {
            // A publication removed an unguarded modal or its presenting path.
            modalFlight = true
            modal.dismiss(animated: animated) { [weak self] in self?.finishDismissal() }
        }
        refreshNavigation()
        updateStyle()
        updateFlyout()
    }

    private func makeStack() -> UINavigationController {
        let nav = UKServerUIStack()
        nav.requestPop = { [weak self, weak nav] leaving, completion in
            guard let self, let page = nav?.topViewController as? UKServerUIPage else { return }
            self.requestNativeExit(from: page, leaving: leaving.compactMap { $0 as? UKServerUIPage }, completion: completion)
        }
        UKNavigationBarStyle.apply(to: nav.navigationBar, large: true)
        nav.view.backgroundColor = .clear
        nav.view.isOpaque = false
        let delegate = UKServerUIStackDelegate(navigation: nav, renderer: self)
        delegates[ObjectIdentifier(nav)] = delegate
        nav.delegate = delegate
        return nav
    }

    private func sync(_ nav: UINavigationController, path: [String], root: ServerUINavigationState.Root,
                      presentation: UUID?, animated: Bool, updateBodies: Bool) {
        let modalDefinition = navigation.snapshot.presentations.first(where: { $0.id == presentation }).flatMap { instance in
            publication.document.modals.first { $0.id == instance.modalID }
        }
        let inherited: [D.ChromeGroup]
        if presentation != nil, let modalDefinition, case .replace(let groups) = modalDefinition.surface.toolbar {
            inherited = groups
        } else { inherited = publication.document.navigation.chrome.groups }
        let close = presentation == nil ? nil : modalDefinition?.presentation.close
        let context = pageContext.with { $0.surface = presentation == nil ? .page : .sheet }
        let existing: [UIViewController] = presentation == nil ? logicalStacks[root] ?? [] :
            presentation == adaptive?.id ? adaptive?.pages ?? [] : nav.viewControllers
        var desired: [UIViewController] = []
        for (depth, id) in path.enumerated() {
            let surface = presentation != nil && depth == 0 ? modalDefinition?.surface
                : publication.document.pages.first(where: { $0.id == id })?.surface
            guard let surface else {
                // The catalog and the navigation diverged: keep the last good stacks rather than trap.
                onError(UKServerUIRendererError(code: .differentDocument, pointer: "/document/pages"))
                return
            }
            if depth < existing.count, let page = existing[depth] as? UKServerUIPage,
               page.surfaceID == id, desired.count == depth {
                if updateBodies { page.update(surface, inheritedGroups: inherited, close: close) }
                desired.append(page)
            } else {
                desired.append(UKServerUIPage(surface: surface, context: context, root: root, presentationID: presentation,
                    depth: depth, inheritedGroups: inherited, close: close, renderer: self,
                    columnPlaceholder: presentation == nil ? publication.document.pages.first { $0.id == id }?.columnPlaceholder : nil))
            }
        }
        if presentation == nil {
            logicalStacks[root] = desired.compactMap { $0 as? UKServerUIPage }
            arrangeColumns(nav, pages: logicalStacks[root] ?? [], animated: animated)
            return
        }
        if presentation == adaptive?.id {
            adaptive?.pages = desired.compactMap { $0 as? UKServerUIPage }
            placeAdaptive()
            return
        }
        if nav.viewControllers != desired {
            nav.setViewControllers(desired, animated: animated && nav.view.window != nil && !nav.viewControllers.isEmpty)
        }
    }

    private func refreshNavigation() {
        allPages.compactMap { $0 as? UKServerUIPage }.forEach { $0.refreshNavigation() }
    }

    private func arrangeColumns(_ nav: UINavigationController, pages: [UKServerUIPage], animated: Bool) {
        let wide = SplitPolicy.allowsSplit(size: nav.view.bounds.size, isRegularWidth: nav.traitCollection.horizontalSizeClass == .regular)
        var hostIndex: Int?
        if wide {
            for (index, page) in pages.enumerated() {
                let config = publication.document.pages.first { $0.id == page.surfaceID }
                if config?.navigation == .stack { hostIndex = nil }
                else if hostIndex == nil || config?.standaloneColumns == true { hostIndex = index }
            }
        }
        let host = hostIndex.map { pages[$0] }
        for page in pages where page !== host { page.columns?.setWide(false) }
        if let index = hostIndex, let host {
            host.loadViewIfNeeded()
            let prefix: [UIViewController] = Array(pages.prefix(index + 1))
            let onDemand = publication.document.pages.first { $0.id == host.surfaceID }?.columnsOnDemand == true
            host.columns?.setWide(!onDemand || pages.count > index + 1 || adaptive?.owner === host)
            if nav.viewControllers != prefix { nav.setViewControllers(prefix, animated: false) }
            let tail = Array(pages.dropFirst(index + 1))
            host.columns?.reconcile(tags: tail.map { AnyHashable($0.surfaceID) }, make: { key in
                tail.first { AnyHashable($0.surfaceID) == key }!
            }, animated: animated && host.view.window != nil)
        } else if nav.viewControllers != pages {
            nav.setViewControllers(pages, animated: animated && nav.view.window != nil && !nav.viewControllers.isEmpty)
        }
    }

    /// Re-arranges the pages of the selected stack when the column geometry or the wide/narrow state changes.
    /// - Parameter animatePresentation: Whether the move animates.
    func columnGeometryChanged(animatePresentation: Bool = false) {
        guard !isBusy else { return }
        columnSize = view.bounds.size
        columnRegular = traitCollection.horizontalSizeClass == .regular
        for (root, nav) in stacks { arrangeColumns(nav, pages: logicalStacks[root] ?? [], animated: false) }
        placeAdaptive(animated: animatePresentation)
        refreshNavigation()
    }

    /// Called when a column transition has finished, so a deferred reconciliation can run.
    func columnsSettled() {
        busyState.changed()
        columnGeometryChanged()
        releaseTouchesWhenSettled()
        drainPending()
    }

    /// Records that the person popped pages in the column by gesture, so navigation state follows the stack.
    /// - Parameters:
    ///   - page: The page the pop started from.
    ///   - kept: How many pages remain.
    func columnPopped(from page: UKServerUIPage, kept: Int) {
        do {
            if let adaptive, adaptive.owner === page {
                let retained = page.columns?.entries.compactMap { $0.controller as? UKServerUIPage }
                    .filter { $0.presentationID == adaptive.id } ?? []
                if retained.isEmpty {
                    for child in adaptive.pages { try child.formView?.discard() }
                    removeAdaptive()
                } else {
                    for child in adaptive.pages.dropFirst(retained.count) { try child.formView?.discard() }
                    try navigation.trimVisiblePath(toDepth: retained.count - 1)
                    self.adaptive?.pages = retained
                }
            }
            try navigation.trimVisiblePath(toDepth: page.depth + kept, onRoot: true)
            reconcile(animated: false, updateBodies: false)
        } catch { onError(blocked()) }
    }

    // MARK: - Validated intents

    private struct Pending {
        weak var page: UKServerUIPage?
        weak var source: UIView?
        let action: D.Action
        let symbol: String
    }

    private var activeAlert: UIViewController? {
        if let modal {
            return modal.topViewController?.presentedViewController ?? modal.presentedViewController
        }
        if let alert = adaptive?.pages.last?.presentedViewController { return alert }
        return (logicalStacks[navigation.snapshot.selection] ?? []).reversed().compactMap(\.presentedViewController).first
    }

    /// Parent-owned notification/shortcut mapping enters here after resolving an authored tab and page.
    /// Rejected busy/dirty intents must remain pending at that boundary, never silently consume a deep link.
    func routeExternal(tabID: String, pageID: String? = nil) throws {
        guard !isBusy, activeAlert == nil, modal == nil, !flyoutOpen,
              let tab = publication.document.navigation.tabs.first(where: { $0.id == tabID }),
              pageID == nil || publication.document.pages.contains(where: { $0.id == pageID }) else { throw blocked() }
        let target = ServerUINavigationState.Root.tab(tabID)
        var seen: Set<ObjectIdentifier> = []
        let leaving = ((logicalStacks[navigation.snapshot.selection] ?? []) + (logicalStacks[target] ?? []) + (adaptive?.pages ?? []))
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        guard !leaving.contains(where: { $0.blocksRecordExit || $0.formView?.blocksExit == true || $0.formView?.needsDiscard == true
            || nativeExitGate?.blocksExit($0) == true }) else {
            throw blocked("/document/form")
        }
        for page in leaving { try page.formView?.discard() }
        removeAdaptive()
        try navigation.selectTab(tabID)
        try navigation.trimVisiblePath(toDepth: 0, onRoot: true)
        if let pageID, pageID != tab.pageId { try navigation.push(pageID: pageID, fromDepth: 0, onRoot: true) }
        reconcile(animated: false, updateBodies: false)
    }

    private var isBusy: Bool {
        // UIKit may retain a coordinator after didShow; that must not leave the touch shield latched.
        modalFlight || handoff || delegates.values.contains { $0.isTransitioning }
            || logicalStacks.values.joined().contains { $0.columns?.isTransitioning == true }
    }

    private func blocked(_ pointer: String = "/document/navigation") -> UKServerUIRendererError {
        UKServerUIRendererError(code: .interactionBlocked, pointer: pointer)
    }

    private func senderStack(_ page: UKServerUIPage) -> UINavigationController? {
        let snapshot = navigation.snapshot
        let nav: UINavigationController?
        if let current = snapshot.presentations.last, modal != nil {
            guard page.presentationID == current.id else { return nil }
            nav = modal
        } else if let adaptive, page.presentationID == adaptive.id {
            guard page.depth < adaptive.pages.count, adaptive.pages[page.depth] === page else { return nil }
            return stacks[page.root]
        } else {
            guard page.presentationID == nil, page.root == snapshot.selection else { return nil }
            nav = stacks[page.root]
        }
        let pages: [UIViewController] = page.presentationID == nil ? logicalStacks[page.root] ?? [] : nav?.viewControllers ?? []
        guard let nav, page.depth < pages.count, pages[page.depth] === page else { return nil }
        return nav
    }

    /// UI entry point: failures remain explicit and sanitized instead of becoming successful no-ops.
    ///
    /// - Parameters:
    ///   - control: The new value of the control that sent a `call-service` action (the `control` operand).
    ///   - site: Names the call site for the optimistic path; defaults to the sending view's accessibility identifier.
    ///   - confirmed: The sender already asked the question (a tile presents the action's confirmation itself).
    func activate(_ action: D.Action, from page: UKServerUIPage, source: UIView? = nil, symbol: String = "",
                  control: JSONValue? = nil, site: String? = nil, confirmed: Bool = false) {
        // An action chosen by rule is resolved here, once, from the house as it is now; no case holding runs nothing.
        guard let action = action.resolved(reader(control: control)) else { return }
        if settingsExit(action), attachedSettingsProviders(from: page).contains(where: \.blocksExit) {
            requestSettingsExit(from: page) { [weak self, weak page, weak source] in
                guard let self, let page else { return }
                self.activate(action, from: page, source: source, symbol: symbol, control: control, site: site, confirmed: confirmed)
            }
            return
        }
        if action.leavesForm, let gate = nativeExitGate, gate.blocksExit(page) {
            gate.request(page) { [weak self, weak page, weak source] in
                guard let self, let page else { return }
                self.activate(action, from: page, source: source, symbol: symbol)
            }
            return
        }
        let leaving = exitForms(action, from: page)
        if leaving.contains(where: \.needsDiscard) {
            guard !leaving.contains(where: \.blocksExit) else { onError(blocked()); return }
            UKDiscardGuard.confirm(from: page, source: source.map(UKPopoverSource.view) ?? .none) { [weak self, weak page] in
                guard let self, let page else { return }
                do {
                    for form in leaving { try form.discard() }
                    try self.perform(action, from: page, source: source, symbol: symbol)
                } catch { self.onError(self.blocked()) }
            }
            return
        }
        do { try perform(action, from: page, source: source, symbol: symbol, control: control, site: site, confirmed: confirmed) }
        catch let error as UKServerUIRendererError { onError(error) }
        catch { onError(blocked()) }
    }

    /// The same intent boundary is available to hosted tests and the parent's integration adapter.
    func perform(_ action: D.Action, from page: UKServerUIPage, source: UIView? = nil, symbol: String = "",
                 control: JSONValue? = nil, site: String? = nil, confirmed: Bool = false) throws {
        guard let action = action.resolved(reader(control: control)) else { return }
        guard let nav = senderStack(page), activeAlert == nil else { throw blocked() }
        if settingsExit(action), attachedSettingsProviders(from: page).contains(where: \.blocksExit) { throw blocked() }
        if action.leavesForm, nativeExitGate?.blocksExit(page) == true { throw blocked("/document/form") }
        switch action {
        case .domain, .setLocal, .callService: break
        default:
            if page.blocksRecordExit || adaptive?.pages.contains(where: \.blocksRecordExit) == true {
                throw blocked("/document/dataSources")
            }
        }
        for form in exitForms(action, from: page) {
            guard !form.blocksExit, !form.needsDiscard else { throw blocked("/document/form") }
        }
        if isBusy {
            if case .domain = action { throw blocked() }
            if case .callService = action { throw blocked() }
            if case .setLocal = action { throw blocked("/document/localState") }
            if let pending, pending.page !== page { throw blocked() }
            pending = Pending(page: page, source: source, action: action, symbol: symbol)
            return
        }
        for form in exitForms(action, from: page) { try form.discard() }
        do {
            switch action {
            case .setLocal(let id, let value):
                try localState.set(value, for: id)
            case .push(let push):
                if page.presentationID == nil { removeAdaptive() }
                try navigation.push(pageID: push.pageId, fromDepth: page.depth, onRoot: page.presentationID == nil)
                navigationMeasurement = pageContext.motion?.measure(.push(measuredName(forPage: push.pageId)))
                reconcile(animated: true, updateBodies: false)
            case .selectTab(let id): removeAdaptive(); try selectTab(id)
            case .back:
                guard page.depth > 0 else { throw blocked() }
                if page.parent is UKColumnsViewController {
                    try navigation.trimVisiblePath(toDepth: page.depth - 1, onRoot: page.presentationID == nil)
                    reconcile(animated: true, updateBodies: false)
                } else {
                    // The delegate's willShow records the pop (a tap and an edge swipe take the same path).
                    nav.popViewController(animated: nav.view.window != nil)
                }
            case .present(let id, _, let policy):
                if policy == .replace, page.presentationID != nil {
                    try replaceModal(id, from: page)
                } else { try presentModal(id, from: page) }
            case .dismiss:
                guard page.presentationID != nil else { throw blocked() }
                if modal == nil, page.presentationID == adaptive?.id { removeAdaptive(); refreshNavigation() }
                else { dismissModal() }
            case .dismissThenPush(let push):
                guard let presentation = navigation.snapshot.presentations.last,
                      let presenter = adaptive?.owner ?? logicalStacks[presentation.root]?.last else { throw blocked() }
                handoff = true
                tabController.view.isUserInteractionEnabled = false
                modal?.view.isUserInteractionEnabled = false
                dismissModal { [weak self, weak presenter] in
                    guard let self else { return }
                    self.handoff = false
                    do {
                        guard let presenter, self.senderStack(presenter) != nil else { throw self.blocked() }
                        try self.navigation.push(pageID: push.pageId, fromDepth: presenter.depth, onRoot: presenter.presentationID == nil)
                        self.reconcile(animated: true, updateBodies: false)
                    } catch let error as UKServerUIRendererError { self.onError(error) }
                    catch { self.onError(self.blocked()) }
                    self.releaseTouchesWhenSettled()
                }
            case .domain(let action): try power(action, from: page, source: source, symbol: symbol)
            case .callService(let call):
                try runCall(call, from: page, source: source, control: control, site: site, confirmed: confirmed)
            case .conditional: break  // resolved to a plain action before this switch
            }
            if settingsExit(action) { attachedSettingsProviders(from: page).forEach { $0.didExit() } }
        } catch is ServerUINavigationState.Failure { throw blocked() }
    }

    private func exitForms(_ action: D.Action, from page: UKServerUIPage) -> [UKServerUIFormView] {
        let pages: [UKServerUIPage]
        switch action {
        case .push:
            pages = page.presentationID == nil ? Array((logicalStacks[page.root] ?? []).dropFirst(page.depth + 1)) + (adaptive?.pages ?? [])
                : Array((adaptive?.pages ?? []).dropFirst(page.depth + 1))
        case .selectTab:
            pages = (logicalStacks[page.root] ?? []) + (adaptive?.pages ?? [])
        case .back:
            pages = [page]
        case .dismiss, .dismissThenPush:
            pages = modal?.viewControllers.compactMap { $0 as? UKServerUIPage } ?? adaptive?.pages ?? []
        case .present(let id, _, let policy):
            pages = policy == .replace ? modal?.viewControllers.compactMap { $0 as? UKServerUIPage } ?? adaptive?.pages ?? []
                : publication.document.modals.first(where: { $0.id == id })?.presentation.adaptive == true ? adaptive?.pages ?? [] : []
        case .domain, .setLocal, .callService, .conditional: pages = []
        }
        return pages.compactMap(\.formView)
    }

    /// Whether `action` names the destination that is currently selected (a tab or the current page), for selected states.
    /// - Parameters:
    ///   - action: The action to test.
    ///   - page: The page asking.
    func isSelected(_ action: D.Action, from page: UKServerUIPage) -> Bool {
        switch action {
        case .push(let push):
            let snapshot = navigation.snapshot
            let path = page.presentationID == nil ? snapshot.stacks[page.root]
                : snapshot.presentations.first(where: { $0.id == page.presentationID })?.pages
            return path?.dropFirst(page.presentationID == nil ? page.depth + 1 : page.depth).contains(push.pageId) == true
        case .selectTab(let id): return navigation.snapshot.selection == .tab(id)
        case .present(let id, _, _): return navigation.snapshot.presentations.last?.modalID == id
        default: return false
        }
    }

    /// Whether `action` can run now: not blocked by a busy command, an alert, a flight or an exit guard.
    /// - Parameters:
    ///   - action: The action to test.
    ///   - page: The page asking.
    func isEnabled(_ action: D.Action, from page: UKServerUIPage) -> Bool {
        _ = busyState.revision
        if isBusy || activeAlert != nil || page.formView?.blocksExit == true { return false }
        switch action {
        case .back: return page.depth > 0
        case .dismiss, .dismissThenPush: return page.presentationID != nil
        case .selectTab: return modal == nil
        case .present(_, _, let policy): return modal == nil || (policy == .replace && page.presentationID != nil)
        case .domain(let action):
            guard let id = bindings.entityID(for: action.sourceId).value,
                  let power = bindings.powers[action.sourceId] else { return false }
            return power.projection(entityID: id, symbol: "").spec.phase == .ready
        case .push: return true
        case .callService: return pageContext.caller != nil
        case .setLocal(let id, let value):
            return publication.document.localState.first(where: { $0.id == id })?.accepts(value) == true
        case .conditional(let rule):
            // Resolved at the tap; the control is enabled while any action it could run can run.
            return rule.actions.contains { isEnabled($0, from: page) }
        }
    }

    // MARK: - Tabs and flyout

    /// System entry points use the same validated page graph and native interaction guards.
    ///
    /// A path no route carries opens the app and navigates nowhere; an anchor the route does not author opens the page
    /// without it; no path opens the publication's initial page.
    /// - Parameter request: The route a push link, Live Activity tap, Spotlight result or shortcut asked for.
    /// - Returns: Whether the request reached a page. False for a path no route carries: nothing is shown or blocked.
    /// - Throws: When the shell cannot move now (a modal, a busy command or an exit guard); the request then stays pending.
    @discardableResult
    func openSystemRoute(_ request: RouteRequest) throws -> Bool {
        guard let target = publication.document.target(for: request) else { return false }
        let id = target.pageId
        let modalID = target.modalId
        try validateUpdate(publication)
        guard navigation.snapshot.presentations.isEmpty,
              let page = stacks[navigation.snapshot.selection]?.topViewController as? UKServerUIPage else { throw blocked() }
        guard nativeExitGate?.blocksExit(page) != true else { throw blocked("/document/dataSources") }
        if let tab = publication.document.navigation.tabs.first(where: { $0.pageId == id }) {
            try navigation.selectTab(tab.id)
            try navigation.trimVisiblePath(toDepth: 0)
        } else {
            if let tab = target.tabId { try navigation.selectTab(tab) }
            try navigation.push(pageID: id, fromDepth: target.tabId == nil ? page.depth : 0)
        }
        if let modalID { try navigation.present(modalID: modalID) }
        reconcile(animated: false, updateBodies: false)
        return true
    }

    private func selectTab(_ id: String) throws {
        guard isTabShown(id) else { throw blocked() }
        if navigation.snapshot.selection == .tab(id) {
            guard navigation.snapshot.presentations.isEmpty, let nav = stacks[.tab(id)] else { throw blocked() }
            if (logicalStacks[.tab(id)]?.count ?? 0) > 1 {
                try navigation.trimVisiblePath(toDepth: 0, onRoot: true)
                reconcile(animated: true, updateBodies: false)
            }
            else { (nav.topViewController as? UKPageViewController)?.scrollToTop() }
        } else {
            try navigation.selectTab(id)
            let label = publication.document.navigation.tabs.first { $0.id == id }?.label ?? id
            pageContext.motion?.measureCut(.tabSwitch(label))
            reconcile(animated: false, updateBodies: false)
        }
    }

    /// Routes a tab-bar tap through the validated `selectTab` intent and always returns `false`, so UIKit never switches tabs itself.
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard !isBusy, modal == nil,
              let root = stacks.first(where: { $0.value === viewController })?.key, case .tab(let id) = root else { return false }
        if let page = stacks[navigation.snapshot.selection]?.topViewController as? UKServerUIPage {
            activate(.selectTab(tabId: id), from: page)
        }
        return false
    }

    /// Opens the navigation flyout from `page`.
    /// - Parameter page: The page that asked.
    func openMenu(from page: UKServerUIPage) {
        guard senderStack(page) != nil, page.depth == 0, page.presentationID == nil,
              environment.chrome.showsMenuButton, !isBusy, activeAlert == nil else { return }
        flyoutOpen = true
        updateFlyout()
    }

    private func closeMenu() {
        guard flyoutOpen else { return }
        flyoutOpen = false
        updateFlyout()
        (stacks[navigation.snapshot.selection]?.viewControllers.first as? UKServerUIPage)?.focusMenu()
    }

    private func selectFromMenu(_ id: String) {
        guard !isBusy else { onError(blocked()); return }
        guard let page = stacks[navigation.snapshot.selection]?.topViewController as? UKServerUIPage else { return }
        closeMenu()
        activate(.selectTab(tabId: id), from: page)
    }

    private func updateFlyout() {
        let destinations = publication.document.navigation.tabs.filter { isTabShown($0.id) }.map {
            UKFlyoutDestination(id: $0.id, title: $0.label, symbol: $0.icon.drawn, identifier: $0.id)
        }
        let selected: String?
        if case .tab(let id) = navigation.snapshot.selection { selected = id } else { selected = nil }
        tabController.view.accessibilityElementsHidden = flyoutOpen
        flyout?.update(destinations: destinations, selection: selected, isOpen: flyoutOpen)
    }

    @objc private func edgePanned(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard pan.state == .ended, let page = stacks[navigation.snapshot.selection]?.topViewController as? UKServerUIPage else { return }
        let direction: CGFloat = pan.edges == .right ? -1 : 1
        let translation = pan.translation(in: view)
        if NavigationFlyoutMetrics.edgeSwipeOpens(startX: 0, translation: CGSize(width: direction * translation.x, height: translation.y)) {
            openMenu(from: page)
        }
    }

    /// Lets the edge pan begin only when the shell allows an edge swipe, nothing is presented, no command is running and the selected stack is at its root.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        environment.chrome.edgeSwipe && navigation.snapshot.presentations.isEmpty && !isBusy &&
            stacks[navigation.snapshot.selection]?.viewControllers.count == 1
    }

    // MARK: - Modal instances and completed pops

    private func replaceModal(_ id: String, from page: UKServerUIPage) throws {
        guard publication.document.modals.contains(where: { $0.id == id }),
              let presentation = navigation.snapshot.presentations.last,
              presentation.id == page.presentationID,
              let presenter = adaptive?.owner ?? logicalStacks[presentation.root]?.last else {
            throw blocked("/document/modals")
        }
        handoff = true
        tabController.view.isUserInteractionEnabled = false
        modal?.view.isUserInteractionEnabled = false
        dismissModal { [weak self, weak presenter] in
            guard let self else { return }
            self.handoff = false
            do {
                guard let presenter, self.senderStack(presenter) != nil else { throw self.blocked() }
                try self.presentModal(id, from: presenter)
            } catch let error as UKServerUIRendererError { self.onError(error) }
            catch { self.onError(self.blocked()) }
            self.releaseTouchesWhenSettled()
        }
    }

    private func presentModal(_ id: String, from page: UKServerUIPage) throws {
        guard modal == nil, page.view.window != nil, let definition = publication.document.modals.first(where: { $0.id == id }) else {
            throw blocked("/document/modals")
        }
        if definition.presentation.adaptive {
            removeAdaptive()
            if page.wantsColumns {
                try navigation.trimVisiblePath(toDepth: page.depth, onRoot: true)
                reconcile(animated: false, updateBodies: false)
            }
        }
        let instance = try navigation.present(modalID: id, asColumn: definition.presentation.adaptive)
        func resetTabs(_ components: [D.Component]) throws {
            for component in components {
                if case .localTabs(let tabs) = component, tabs.resetOnPresentation,
                   let field = publication.document.localState.first(where: { $0.id == tabs.stateId }) {
                    try localState.set(field.initial, for: field.id)
                }
                try resetTabs(component.childComponents)
            }
        }
        try resetTabs(definition.surface.components)
        let inherited: [D.ChromeGroup]
        if case .replace(let groups) = definition.surface.toolbar { inherited = groups } else { inherited = [] }
        let root = UKServerUIPage(surface: definition.surface, context: pageContext.with { $0.surface = .sheet },
                                  root: navigation.snapshot.selection, presentationID: instance, depth: 0,
                                  inheritedGroups: inherited, close: definition.presentation.close, renderer: self)
        if definition.presentation.adaptive {
            adaptive = .init(id: instance, owner: page, pages: [root])
            columnGeometryChanged(animatePresentation: true)
        } else { installModal(definition, pages: [root], instance: instance, from: page) }
    }

    /// Moves the retained controllers, never reopens a factory or replaces its draft on rotation.
    private func placeAdaptive(animated: Bool = false) {
        guard !modalFlight, let adaptive,
              let instance = navigation.snapshot.presentations.first(where: { $0.id == adaptive.id }),
              let definition = publication.document.modals.first(where: { $0.id == instance.modalID }) else { return }
        let owner = adaptive.owner
        let wide = owner.wantsColumns && owner.columns?.isWide == true
        if wide, let columns = owner.columns {
            if let modal, modalPresentationID == adaptive.id {
                modalFlight = true
                modalToken = nil
                modal.dismiss(animated: false) { [weak self, weak modal] in
                    guard let self, let modal else { return }
                    modal.setViewControllers([], animated: false)
                    delegates.removeValue(forKey: ObjectIdentifier(modal))
                    self.modal = nil
                    modalPresentationID = nil
                    modalFlight = false
                    columnGeometryChanged()
                    drainPending()
                }
                return
            }
            if modal != nil { return }
            let current = columns.entries.map(\.controller)
            var common = 0
            while common < min(current.count, adaptive.pages.count), current[common] === adaptive.pages[common] { common += 1 }
            if common < current.count {
                for child in current.dropFirst(common).reversed() { columns.remove(child, animated: false) }
            }
            for child in adaptive.pages.dropFirst(common) {
                columns.open(child, tag: nil, atDepth: columns.entries.count,
                             animated: animated && owner.view.window != nil, pushesWhenNarrow: false)
            }
            refreshNavigation()
        } else if modal == nil {
            for child in adaptive.pages.reversed() { owner.columns?.remove(child, animated: false) }
            installModal(definition, pages: adaptive.pages, instance: adaptive.id, from: owner)
        } else if modalPresentationID == adaptive.id, modal?.viewControllers != adaptive.pages {
            modal?.setViewControllers(adaptive.pages, animated: false)
        }
    }

    private func removeAdaptive(dismissState: Bool = true) {
        guard let previous = adaptive else { return }
        adaptive = nil
        for child in previous.pages.reversed() { previous.owner.columns?.remove(child, animated: false) }
        if dismissState, navigation.snapshot.presentations.contains(where: { $0.id == previous.id }) {
            do { try navigation.dismiss(presentationID: previous.id) }
            catch { onError(blocked()) }
        }
        previous.pages.forEach { $0.retireBedroomDrafts() }
        if let nav = stacks[previous.owner.root] {
            arrangeColumns(nav, pages: logicalStacks[previous.owner.root] ?? [], animated: false)
        }
    }

    private func installModal(_ definition: D.Modal, pages: [UKServerUIPage], instance: UUID, from page: UKServerUIPage) {
        guard let root = pages.first else { return }
        let id = definition.id
        let token = UUID()
        modalToken = token
        modalPresentationID = instance
        let geometry = "\(view.bounds.size.width)x\(view.bounds.size.height)@\(traitCollection.displayScale)"
        let fitKey = [sheetFitNamespace, publication.documentSha256, id, geometry,
                      traitCollection.preferredContentSizeCategory.rawValue,
                      "\(view.effectiveUserInterfaceLayoutDirection.rawValue)"].joined(separator: ".")
        var options = UKHassModalOptions(title: nil, fitKey: fitKey)
        options.showsClose = false
        options.width = definition.presentation.width == .form ? .form : .page
        switch definition.presentation.height {
        case .full: options.height = .full
        case .fitted(let follows, _): options.height = follows == .root ? .fitted : .fittedToTopPage
        }
        options.appearance = definition.presentation.appearance == .dark ? .dark : .system
        options.isFullScreen = definition.presentation.fullScreen
        options.closeStaysInBar = definition.presentation.close.rail == .keepHorizontalWhenAllowed
        options.onClose = { [weak self] in
            guard let self else { return }
            guard let page = self.modal?.topViewController as? UKServerUIPage else {
                self.onError(self.blocked()); return
            }
            self.activate(.dismiss(scope: .currentModal), from: page)
        }
        options.onDismissed = { [weak self] in
            guard let self, modalToken == token else { return }
            finishDismissal()
        }
        let modal = UKHassModalController(root: root, options: options)
        modal.requestPop = { [weak self, weak modal] leaving, completion in
            guard let self, let page = modal?.topViewController as? UKServerUIPage else { return }
            self.requestNativeExit(from: page, leaving: leaving.compactMap { $0 as? UKServerUIPage }, completion: completion)
        }
        if pages.count > 1 { modal.setViewControllers(pages, animated: false) }
        self.modal = modal
        modal.onAttemptToDismiss = { [weak self, weak root] in
            guard let self, let root else { return }
            self.activate(.dismiss(scope: .currentModal), from: root)
        }
        updateSettingsExitGuard()
        UKNavigationBarStyle.apply(to: modal.navigationBar, large: false)
        let delegate = UKServerUIStackDelegate(navigation: modal, renderer: self, modal: modal)
        delegates[ObjectIdentifier(modal)] = delegate
        modal.delegate = delegate
        modalFlight = true
        let measurement = pageContext.motion?.measure(.sheetPresent(definition.surface.title.isEmpty ? "Sheet" : definition.surface.title))
        modal.present(from: page) { [weak self] in
            measurement?.settled()
            guard let self else { return }
            self.modalFlight = false
            self.columnGeometryChanged()
            self.drainPending()
        }
    }

    private func dismissModal(completion: (() -> Void)? = nil) {
        guard let modal else {
            guard adaptive != nil else { onError(blocked()); return }
            removeAdaptive()
            completion?()
            refreshNavigation()
            releaseTouchesWhenSettled()
            return
        }
        modalFlight = true
        tabController.view.isUserInteractionEnabled = false
        modal.view.isUserInteractionEnabled = false
        modal.dismiss(animated: modal.view.window != nil) { [weak self] in
            self?.finishDismissal()
            completion?()
        }
    }

    private func finishDismissal() {
        guard let dismissed = modalPresentationID else { return }
        if let page = modal?.viewControllers.last as? UKServerUIPage {
            attachedSettingsProviders(from: page).forEach { $0.didExit() }
        }
        if navigation.snapshot.presentations.contains(where: { $0.id == dismissed }) {
            do { try navigation.dismiss(presentationID: dismissed) }
            catch { onError(blocked()) }
        }
        modal?.viewControllers.compactMap { $0 as? UKServerUIPage }.forEach { $0.retireBedroomDrafts() }
        if let modal { delegates.removeValue(forKey: ObjectIdentifier(modal)) }
        modal = nil
        modalToken = nil
        modalPresentationID = nil
        modalFlight = false
        if adaptive?.id == dismissed { removeAdaptive(dismissState: false) }
        else { placeAdaptive() }
        refreshNavigation()
        if !handoff { releaseTouchesWhenSettled(); drainPending() }
        DispatchQueue.main.async { [weak self] in self?.releaseTouchesWhenSettled(); self?.drainPending() }
    }

    private func retireRemovedBedroomDrafts(_ previous: [UKServerUIPage]) {
        let retained = Set(allPages.map(ObjectIdentifier.init))
        for page in previous where !retained.contains(ObjectIdentifier(page)) { page.retireBedroomDrafts() }
    }

    /// UIKit calls this after a pop completes or cancels; only a genuinely shorter stack commits.
    /// The name a navigation measurement is recorded under: the destination page's title.
    private func measuredName(forPage id: String) -> String {
        publication.document.pages.first { $0.id == id }.map(\.surface.title) ?? "Page"
    }

    /// Records a back tap or swipe that the stack animates, from its start to the coordinator's completion.
    func stackWillPop(to remaining: [UKServerUIPage], previous: [UKServerUIPage], coordinator: (any UIViewControllerTransitionCoordinator)?) {
        guard remaining.count < previous.count, let leaving = previous.last else { return }
        let measurement = pageContext.motion?.measure(.pop(leaving.title ?? "Page"))
        coordinator?.animate(alongsideTransition: nil) { _ in measurement?.settled() }
    }

    /// Settles navigation state, measurements and retired drafts when a stack has shown its destination.
    /// - Parameters:
    ///   - nav: The stack that finished.
    ///   - previous: The pages it showed before.
    func stackDidShow(_ nav: UINavigationController, previous: [UKServerUIPage]) {
        defer { retireRemovedBedroomDrafts(previous) }
        navigationMeasurement?.settled()
        navigationMeasurement = nil
        guard let top = nav.topViewController as? UKServerUIPage else { return }
        if top.columns?.isWide == true {
            refreshNavigation()
            releaseTouchesWhenSettled()
            drainPending()
            DispatchQueue.main.async { [weak self] in self?.releaseTouchesWhenSettled(); self?.drainPending() }
            return
        }
        let snapshot = navigation.snapshot
        let expected = top.presentationID == nil ? snapshot.stacks[top.root]?.count
            : snapshot.presentations.first(where: { $0.id == top.presentationID }).map { $0.pages.count + 1 }
        if let expected, nav.viewControllers.count < expected, senderStack(top) != nil {
            do {
                if top.presentationID == nil {
                    for page in (logicalStacks[top.root] ?? []).dropFirst(top.depth + 1) {
                        try page.formView?.discard()
                        page.retireBedroomDrafts()
                    }
                    logicalStacks[top.root] = nav.viewControllers.compactMap { $0 as? UKServerUIPage }
                } else if let presentationID = top.presentationID, presentationID == adaptive?.id {
                    adaptive?.pages = nav.viewControllers.compactMap { $0 as? UKServerUIPage }
                }
                try navigation.trimVisiblePath(toDepth: top.depth, onRoot: top.presentationID == nil)
            }
            catch { onError(blocked()) }
        }
        refreshNavigation()
        releaseTouchesWhenSettled()
        drainPending()
        DispatchQueue.main.async { [weak self] in self?.releaseTouchesWhenSettled(); self?.drainPending() }
    }

    private func releaseTouchesWhenSettled() {
        if !isBusy { tabController.view.isUserInteractionEnabled = true }
    }

    private func drainPending() {
        guard !isBusy, let intent = pending else { return }
        pending = nil
        guard let page = intent.page, senderStack(page) != nil else { onError(blocked()); return }
        activate(intent.action, from: page, source: intent.source, symbol: intent.symbol)
    }

    // MARK: - Domain actions and immutable confirmation

    /// The settings provider the document binds to `sourceId`, or `nil`.
    /// - Parameter sourceId: The data source id.
    func settingsProvider(for sourceId: String) -> (any UKServerUISettingsProvider)? {
        guard case .settingsProvider(_, let source) = publication.document.dataSources.first(where: { $0.id == sourceId }) else { return nil }
        return settingsProviders[source.providerId]
    }

    private func settingsExit(_ action: D.Action) -> Bool {
        switch action {
        case .back, .dismiss, .dismissThenPush, .selectTab: true
        case .present(_, _, .replace): true
        case .conditional(let rule): rule.actions.contains(where: settingsExit)
        default: false
        }
    }

    private func attachedPages(from page: UKServerUIPage) -> [UKServerUIPage] {
        var pages = [page] + (page.navigationController?.viewControllers ?? []).compactMap { $0 as? UKServerUIPage }
        let columns = (page.parent as? UKColumnsViewController) ?? page.columns
        pages += columns?.entries.compactMap { $0.controller as? UKServerUIPage } ?? []
        var seen = Set<ObjectIdentifier>()
        return pages.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func attachedBedroomDrafts(from page: UKServerUIPage) -> [ServerUIBedroomDraft] {
        var seen = Set<ObjectIdentifier>()
        return attachedPages(from: page).flatMap { $0.bedroomDrafts.values }
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func attachedSettingsProviders(from page: UKServerUIPage) -> [any UKServerUISettingsProvider] {
        var sourceIDs = Set<String>()
        func visit(_ components: [D.Component]) {
            for component in components {
                if case .settingsControl(let value) = component { sourceIDs.insert(value.sourceId) }
                visit(component.childComponents)
            }
        }
        attachedPages(from: page).forEach { visit($0.definition.components) }
        return sourceIDs.compactMap { settingsProvider(for: $0) }
    }

    /// Also used by the shell's native Back/interactive-pop gate; no domain draft is serialized.
    func requestSettingsExit(from page: UKServerUIPage, completion: @escaping () -> Void) {
        let attached = attachedSettingsProviders(from: page)
        let owners = attached.filter(\.blocksExit)
        let drafts = attachedBedroomDrafts(from: page).filter(\.blocksExit)
        guard !owners.isEmpty || !drafts.isEmpty else { attached.forEach { $0.didExit() }; completion(); return }
        guard owners.allSatisfy(\.canDiscard), drafts.allSatisfy(\.canDiscard), activeAlert == nil else { onError(blocked()); return }
        UKDiscardGuard.confirm(from: page, source: .none) { [weak self] in
            guard let self, owners.allSatisfy(\.canDiscard), drafts.allSatisfy(\.canDiscard) else { return }
            guard drafts.allSatisfy({ $0.discard() }) else { self.onError(self.blocked()); return }
            owners.forEach { $0.discard() }
            attached.forEach { $0.didExit() }
            self.updateSettingsExitGuard()
            completion()
        }
    }

    /// Re-evaluates whether any attached settings provider has an unsaved change that blocks leaving.
    func updateSettingsExitGuard() {
        if let page = modal?.viewControllers.last as? UKServerUIPage {
            modal?.isModalInPresentation = nativeExitGate?.blocksExit(page) == true
        }
    }

    /// Runs a door tile's reserved action after re-checking the tile against the published document.
    /// - Parameters:
    ///   - tile: The authored tile.
    ///   - expected: The action the tile showed.
    ///   - page: The page that owns it.
    ///   - source: The view that was tapped.
    func activateDoor(_ tile: D.DoorTile, expected: TileActionSpec, from page: UKServerUIPage, source: UIView) {
        do {
            guard senderStack(page) != nil, !isBusy, activeAlert == nil,
                  securityControls(publication.document)[tile.node.id] == SecurityAttachment(surfaceID: page.surfaceID, component: .doorTile(tile)),
                  let model = bindings.doors[tile.sourceId] else { throw blocked() }
            try model.execute(model.reserve(expected: expected))
        } catch let error as UKServerUIRendererError { onError(error) }
        catch { onError(blocked()) }
    }

    /// Runs an alarm panel mode change and reports any failure through ``onError``.
    func activateAlarmPanel(_ panel: D.AlarmPanel, mode: String, expected: TileActionSpec,
                            from page: UKServerUIPage, source: UIView) {
        do { try performAlarmPanel(panel, mode: mode, expected: expected, from: page, source: source) }
        catch let error as UKServerUIRendererError { onError(error) }
        catch { onError(blocked()) }
    }

    /// Validates an alarm panel mode change against the published document and sends it; throws when the document no longer agrees.
    func performAlarmPanel(_ panel: D.AlarmPanel, mode: String, expected: TileActionSpec,
                           from page: UKServerUIPage, source: UIView) throws {
        let attachment = SecurityAttachment(surfaceID: page.surfaceID, component: .alarmPanel(panel))
        guard senderStack(page) != nil, !isBusy, activeAlert == nil, panel.modes.contains(where: { $0.state == mode }),
              securityControls(publication.document)[panel.node.id] == attachment,
              let model = bindings.alarms[panel.sourceId] else { throw blocked() }
        let ticket = try model.reserveMode(mode, expected: expected, confirmation: panel.confirmation.spec)
        try runAlarm(ticket, model: model, identifier: panel.node.id, from: page, source: source) { [weak self] in
            guard let self else { return false }
            return self.bindings.alarms[panel.sourceId] === model
                && self.securityControls(self.publication.document)[panel.node.id] == attachment
        }
    }

    /// The navigation body never reaches this boundary. Only the configured provider disc does.
    func activateAlarm(_ tile: D.NavigationTile, expected: TileActionSpec, from page: UKServerUIPage, source: UIView) {
        do { try performAlarm(tile, expected: expected, from: page, source: source) }
        catch let error as UKServerUIRendererError { onError(error) }
        catch { onError(blocked()) }
    }

    /// Sends an alarm tile's intent once its ticket and the published document agree.
    func performAlarm(_ tile: D.NavigationTile, expected: TileActionSpec, from page: UKServerUIPage, source: UIView) throws {
        guard senderStack(page) != nil, !isBusy, activeAlert == nil,
              alarmTiles(publication.document)[tile.node.id] == AlarmAttachment(surfaceID: page.surfaceID, tile: tile),
              let binding = tile.alarm,
              let model = bindings.alarms[binding.sourceId] else { throw blocked() }
        let ticket = try model.reserve(expected: expected)
        try runAlarm(ticket, model: model, identifier: tile.node.id, from: page, source: source) { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.bindings.alarms[binding.sourceId] === model
                && self.alarmTiles(self.publication.document)[tile.node.id] == AlarmAttachment(surfaceID: page.surfaceID, tile: tile)
        }
    }

    private func runAlarm(_ ticket: UKServerUIAlarmSource.Ticket, model: UKServerUIAlarmSource, identifier: String,
                          from page: UKServerUIPage, source: UIView, attached: @escaping () -> Bool) throws {
        guard let confirmation = ticket.spec.confirmation else {
            try model.execute(ticket)
            return
        }
        guard page.view.window != nil else { model.cancel(ticket); throw blocked() }
        let revision = publication.revision
        let alert = UIAlertController(title: confirmation.title, message: confirmation.message,
                                      preferredStyle: confirmation.style == .dialog ? .actionSheet : .alert)
        let confirm = UIAlertAction(title: confirmation.confirmVerb, style: confirmation.isDestructive ? .destructive : .default) { [weak self, weak page] _ in
            defer { model.cancel(ticket) }
            guard let self else { return }
            do {
                guard let page, self.senderStack(page) != nil, self.publication.revision == revision,
                      attached()
                else { throw self.blocked() }
                try model.execute(ticket)
            } catch let error as UKServerUIRendererError { self.onError(error) }
            catch { self.onError(self.blocked()) }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in model.cancel(ticket) })
        alert.addAction(confirm)
        if !confirmation.isDestructive { alert.preferredAction = confirm }
        if let popover = alert.popoverPresentationController {
            popover.sourceView = source
            popover.sourceRect = source.bounds
        }
        page.ukPresent(alert, identifiers: [confirmation.confirmVerb: identifier + ".confirm", "Cancel": identifier + ".cancel"])
    }

    // MARK: - Authored service calls

    /// Resolves an authored call at gesture time and sends it, after the authored question when there is one.
    ///
    /// Operands are evaluated here, from the boxes as they are now, never observed; a call that cannot be resolved sends nothing and
    /// reports an unavailable source. The call goes through the one connection (`HassServiceCalling`) and its declared optimistic
    /// values are feedback only.
    private func runCall(_ call: ServerUICallService, from page: UKServerUIPage, source: UIView?, control: JSONValue?,
                         site: String?, confirmed: Bool) throws {
        guard pageContext.caller != nil, let resolved = call.resolve(reader(control: control)) else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        let identifier = site ?? source?.accessibilityIdentifier ?? "call-service"
        let send: (ServerUICallService.Resolved) -> Void = { [weak self] resolved in
            guard let self else { return }
            let entities = call.optimistic.compactMap { entry in
                self.bindings.entityID(for: entry.sourceId).value.map { (entityID: $0, value: entry) }
            }
            self.callRunner.run(site: identifier, call: call, resolved: resolved, entities: entities)
        }
        guard !confirmed, call.asksConfirmation(of: reader().viewer, in: reader()),
              case .additional(let style, let title, let message, let confirmLabel, let cancelLabel, let destructive) = call.confirmation else {
            send(resolved)
            return
        }
        let revision = publication.revision
        let alert = UIAlertController(title: title, message: message, preferredStyle: style == .dialog ? .actionSheet : .alert)
        let confirm = UIAlertAction(title: confirmLabel, style: destructive ? .destructive : .default) { [weak self, weak page] _ in
            guard let self else { return }
            do {
                // What is confirmed is what the house says now: operands are resolved again.
                guard let page, self.senderStack(page) != nil, self.publication.revision == revision,
                      let fresh = call.resolve(self.reader(control: control)) else { throw self.blocked() }
                send(fresh)
            } catch let error as UKServerUIRendererError { self.onError(error) }
            catch { self.onError(self.blocked()) }
        }
        alert.addAction(UIAlertAction(title: cancelLabel, style: .cancel))
        alert.addAction(confirm)
        if !destructive { alert.preferredAction = confirm }
        if let popover = alert.popoverPresentationController {
            popover.sourceView = source ?? page.view
            popover.sourceRect = (source ?? page.view).bounds
        }
        page.ukPresent(alert, identifiers: [confirmLabel: identifier + ".confirm", cancelLabel: identifier + ".cancel"])
    }

    // MARK: - Tab rules

    /// Whether a root's tab is in the tab bar: a tab whose rule says hidden leaves it, except the one being shown (it goes when the
    /// person leaves it), so a rule change never pulls the page out from under them.
    private func isRootShown(_ root: ServerUINavigationState.Root) -> Bool {
        guard case .tab(let id) = root else { return true }
        return isTabShown(id) || navigation.snapshot.selection == root
    }

    /// Whether a tab's rule currently lets it be reached.
    func isTabShown(_ id: String) -> Bool { tabShown[id] ?? true }

    /// One observation per tab with a rule, each reading only the entities its rule names.
    private func observeTabVisibility() {
        tabBag.removeAll()
        let rules = publication.document.navigation.tabs.compactMap { tab in tab.visibleWhen.map { (tab.id, $0) } }
        tabShown = tabShown.filter { id, _ in rules.contains { $0.0 == id } }
        for (id, rule) in rules {
            tabBag.observe { [weak self] in
                guard let self else { return }
                let shown = rule.isShown(self.reader(), previous: self.tabShown[id])
                guard self.tabShown[id] != shown else { return }
                self.tabShown[id] = shown
                self.refreshTabBar()
            }
        }
    }

    /// Puts the tab bar and the menu in line with the tab rules, in place: pages, stacks and the selection are untouched.
    private func refreshTabBar() {
        guard isViewLoaded else { return }
        let roots: [ServerUINavigationState.Root] = publication.document.navigation.tabs.map { .tab($0.id) }
        let controllers = roots.filter(isRootShown).compactMap { stacks[$0] }
        if !controllers.isEmpty, tabController.viewControllers != controllers { tabController.setViewControllers(controllers, animated: false) }
        updateFlyout()
    }

    private func power(_ action: D.PowerAction, from page: UKServerUIPage, source: UIView?, symbol: String) throws {
        guard let id = bindings.entityID(for: action.sourceId).value, let model = bindings.powers[action.sourceId] else {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }

        let spec = model.projection(entityID: id, symbol: symbol).spec
        guard spec.phase == .ready else { throw blocked("/document/dataSources") }
        switch action.confirmation {
        case .policy: try model.perform(entityID: id, spec: spec)
        case .additional where !ServerUIControlRules.asksFirst(action.confirmWhen, in: reader()):
            try model.perform(entityID: id, spec: spec)
        case .additional(let style, let title, let message, let confirmLabel, let cancelLabel, let destructive):
            let revision = publication.revision
            let alert = UIAlertController(title: title, message: message, preferredStyle: style == .dialog ? .actionSheet : .alert)
            let confirm = UIAlertAction(title: confirmLabel, style: destructive ? .destructive : .default) { [weak self, weak page] _ in
                guard let self else { return }
                do {
                    guard let page, self.senderStack(page) != nil, self.publication.revision == revision,
                          self.bindings.entityID(for: action.sourceId).value == id,
                          self.bindings.powers[action.sourceId] === model else { throw self.blocked() }
                    try model.perform(entityID: id, spec: spec)
                } catch let error as UKServerUIRendererError { self.onError(error) }
                catch { self.onError(self.blocked()) }
            }
            alert.addAction(UIAlertAction(title: cancelLabel, style: .cancel))
            alert.addAction(confirm)
            if !destructive { alert.preferredAction = confirm }
            if let popover = alert.popoverPresentationController {
                popover.sourceView = source ?? page.view
                popover.sourceRect = (source ?? page.view).bounds
            }
            let identifier = source?.accessibilityIdentifier ?? action.sourceId
            page.ukPresent(alert, identifiers: [confirmLabel: identifier + ".confirm", cancelLabel: identifier + ".cancel"])
        }
    }
}

// MARK: - Canonical stack delegation

/// Forwards modal fitting; only wallpaper stacks replace UIKit's navigation motion.
@MainActor
final class UKServerUIStackDelegate: NSObject, UINavigationControllerDelegate {
    /// The wallpaper stack motion, or `nil` for UIKit's own transition.
    let motion: UKStackMotion?
    private weak var renderer: UKServerUIRenderer?
    private weak var modal: UKHassModalController?
    private var settledPages: [UKServerUIPage]
    private(set) var isTransitioning = false {
        didSet { if isTransitioning != oldValue { renderer?.busyState.changed() } }
    }

    init(navigation: UINavigationController, renderer: UKServerUIRenderer, modal: UKHassModalController? = nil) {
        self.renderer = renderer
        self.modal = modal
        settledPages = navigation.viewControllers.compactMap { $0 as? UKServerUIPage }
        motion = modal == nil ? UKStackMotion(navigation: navigation) : nil
    }

    /// Prepares the page about to appear.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        isTransitioning = animated
        if animated {
            renderer?.stackWillPop(to: navigationController.viewControllers.compactMap { $0 as? UKServerUIPage },
                                   previous: settledPages, coordinator: navigationController.transitionCoordinator)
        }
        modal?.navigationController(navigationController, willShow: viewController, animated: animated)
    }

    /// Reports a shown page to the renderer.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        isTransitioning = false
        let previous = settledPages
        settledPages = navigationController.viewControllers.compactMap { $0 as? UKServerUIPage }
        modal?.navigationController(navigationController, didShow: viewController, animated: animated)
        motion?.navigationController(navigationController, didShow: viewController, animated: animated)
        renderer?.stackDidShow(navigationController, previous: previous)
    }

    /// Supplies the wallpaper stack motion for a push or pop.
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        motion?.navigationController(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
    }

    /// Supplies the interactive transition for the edge pop.
    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        motion?.navigationController(navigationController, interactionControllerFor: animationController)
    }
}

/// VoiceOver Escape uses the same completed-pop boundary as a system Back tap.
@MainActor
private final class UKServerUIStack: UKNativeExitNavigationController {
    /// Forwards the VoiceOver escape gesture to the visible page.
    override func accessibilityPerformEscape() -> Bool { topViewController?.accessibilityPerformEscape() ?? false }
}
#endif
