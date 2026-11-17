#if os(iOS) && DEBUG
import HassCore
import HassDesign
import ImageIO
import UIKit

// MARK: - Downloaded composition preview

/// A debug-only publication journey, with fixtures or an isolated, read-only Home Assistant connection.
///
/// Launch with `--server-ui-preview`. `Application Support/ServerUIPreview/bootstrap.json` supplies either synthetic entities or
/// `live` connection metadata, and `publication.json` beside it is the published envelope. Assets are read from `assets/<sha256>`.
/// The preview is fed by those local files through the same store the app uses, as if the integration had sent a `published`
/// event: there is no publisher HTTP endpoint.
///
/// The live bearer comes from the launch environment: ``environmentCredentialName`` (`simctl launch` sets it as
/// `SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN`). It is taken and removed from the process environment with `unsetenv` in
/// ``init(directory:environmentName:)``, before any step that can fail, so a failed bootstrap, fixtures mode or a late error
/// cannot leave it in the environment. A launch without `--server-ui-preview` removes it at start through
/// ``discardEnvironmentCredential(named:)`` (called from `UKGalleryRouter.requested()` first). The value is held in memory only
/// until the live path takes it (or the load ends, which drops it); fixtures mode never uses it. It is never logged, written
/// or put in a diagnostic string. There is no file source: a stray `ha-credential` file in the preview directory is never read.
/// Compiled out of release builds.
@MainActor
final class UKServerUIPreview: UIViewController {
    struct Configuration: Decodable, Sendable {
        struct State: Decodable, Sendable {
            let state: String
            let attributes: [String: JSONValue]
        }
        let entities: [String: State]?
        let live: UKServerUIPreviewLiveData.Configuration?
        let gallery: UKServerUIPreviewFixtures.Configuration?
        /// DEBUG state flags (``UKServerUIPreviewFlags``); the launch environment is laid over them.
        let flags: UKServerUIPreviewFlags?

        func validate() throws {
            guard (entities != nil) != (live != nil) else { throw Failure.bootstrap }
            guard gallery == nil || entities != nil else { throw Failure.bootstrap }
            _ = try live?.validatedServer()
        }
    }

    @MainActor final class Prepared {
        let assets: ServerUIStagedAssets
        let backdrop: HouseBackdropStore
        let renderDirectory: URL
        let renderer: UKServerUIRenderer

        init(publication: ServerUICompositionPublication, context: UKContext,
             assets: ServerUIStagedAssets, backdrop: HouseBackdropStore, renderDirectory: URL,
             weatherReader: ServerUIWeatherReader? = nil, cameraReader: UKCameraReadProvider? = nil,
             fixtures: UKServerUIPreviewFixtures? = nil, live: UKServerUIPreviewLiveProviders.Supply? = nil) throws {
            try fixtures?.prepare(publication, backdrop: backdrop)
            renderer = try UKServerUIRenderer(publication: publication, context: context, backdrop: backdrop,
                collections: live?.collections ?? fixtures?.collections() ?? [:],
                records: live?.records ?? fixtures?.records ?? .init(),
                bedroomProviders: live?.bedrooms ?? [:], remoteProviders: live?.remotes ?? [:],
                deviceResponder: live?.responder ?? fixtures?.caller, scheduleStorage: live?.schedules,
                canEditBedroom: live?.canEditBedroom ?? (fixtures?.configuration.administrator == true),
                roomResidentId: { live?.roomResidentId() ?? fixtures?.viewerKey },
                weatherReader: weatherReader, cameraReader: cameraReader, accountProvider: live?.account ?? fixtures,
                settingsProviders: live?.settings ?? fixtures?.settings ?? [:], shellHeader: live?.shellHeader ?? fixtures?.header)
            self.assets = assets
            self.backdrop = backdrop
            self.renderDirectory = renderDirectory
        }
    }

    private enum Failure: Error { case bootstrap, image, render, unsupportedBackground, publication }
    private let status = UILabel()
    private var started = false
    private var publicationStore: ServerUIPublicationStore<Prepared>?
    private(set) var renderer: UKServerUIRenderer?
    private let entities = EntityStore()
    private lazy var caller = PageGalleryRecorder(store: entities)
    private lazy var failing = UKServerUIPreviewFailingCaller()
    /// The caller of a preview with no gallery fixtures: the recorder, or under `failCalls` one that fails every call.
    private var stateCaller: any HassServiceCalling { flags.failCalls ? failing : caller }
    private var live: UKServerUIPreviewLiveData?
    private var liveProviders: UKServerUIPreviewLiveProviders?
    private var fixtures: UKServerUIPreviewFixtures?
    private let observations = UKObservationBag()
    private var loadTask: Task<Void, Never>?
    private let directory: URL
    /// The launch environment the flags are read from; tests inject one.
    private let launchEnvironment: [String: String]
    /// Puts the process-wide switches the flags set back when the preview leaves the screen.
    private var restoreSwitches: (() -> Void)?
    /// The flags in force, once the bootstrap is read; none before.
    private(set) var flags = UKServerUIPreviewFlags()
    /// The bearer taken from the environment at init; dropped by the live path or when the load ends.
    private var credential: Result<String, UKServerUIPreviewLiveData.Failure>?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    deinit {
        loadTask?.cancel()
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Takes the bearer from the environment first thing, so nothing that fails later can leave it there.
    /// - Parameters:
    ///   - directory: Where the bootstrap, publication, assets and receipt live; tests inject a temporary one.
    ///   - environmentName: The variable that carries the bearer.
    ///   - launchEnvironment: The variables the state flags are read from (``UKServerUIPreviewFlags/overlaying(environment:)``).
    init(directory: URL = UKServerUIPreview.directory, environmentName: String = UKServerUIPreview.environmentCredentialName,
         launchEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.directory = directory
        self.launchEnvironment = launchEnvironment
        credential = Result { try Self.liveCredential(environmentName: environmentName) }
            .mapError { $0 as? UKServerUIPreviewLiveData.Failure ?? .credential }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The preview's default folder, `Application Support/ServerUIPreview`.
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ServerUIPreview", isDirectory: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        overrideUserInterfaceStyle = .dark
        status.text = "Downloading configuration..."
        status.textColor = .label
        status.font = .preferredFont(forTextStyle: .body)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textAlignment = .center
        status.accessibilityIdentifier = "server-ui.preview.status"
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        loadTask = Task { [weak self] in await self?.loadPublication() }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            loadTask?.cancel()
            observations.removeAll()
            live?.lifecycle.stop()
            liveProviders?.stop()
            restoreSwitches?()
            restoreSwitches = nil
        }
    }

    /// Name of the launch-environment variable that carries the live preview's Home Assistant bearer.
    static let environmentCredentialName = "FENTON_PREVIEW_HA_TOKEN"

    /// Reads the bearer from the process environment once, then removes it with `unsetenv`.
    ///
    /// The variable is removed even when its value is malformed, so a bad value cannot linger. Returns `nil` when it is unset.
    /// - Throws: ``UKServerUIPreviewLiveData/Failure/credential`` for an empty value or one containing whitespace.
    static func consumeEnvironmentCredential(named name: String = environmentCredentialName) throws -> String? {
        guard let raw = getenv(name) else { return nil }
        let value = String(cString: raw)
        unsetenv(name)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            throw UKServerUIPreviewLiveData.Failure.credential
        }
        return value
    }

    /// The live bearer, from the launch environment only.
    /// - Throws: ``UKServerUIPreviewLiveData/Failure/credential`` when the variable is unset, empty or malformed.
    static func liveCredential(environmentName: String = environmentCredentialName) throws -> String {
        guard let token = try consumeEnvironmentCredential(named: environmentName) else {
            throw UKServerUIPreviewLiveData.Failure.credential
        }
        return token
    }

    /// Removes the bearer from the environment when the preview is not running, so no launch keeps it.
    static func discardEnvironmentCredential(named name: String = environmentCredentialName) {
        unsetenv(name)
    }

    /// Loads the bootstrap and publication, then mounts the renderer; failures show a diagnostic and write a receipt.
    func loadPublication() async {
        defer { credential = nil }
        do {
            try writeReceipt(status: "loading")
            let configuration = try JSONDecoder().decode(Configuration.self,
                from: Data(contentsOf: directory.appendingPathComponent("bootstrap.json")))
            try configuration.validate()
            flags = (configuration.flags ?? .init()).overlaying(environment: launchEnvironment)
            if !flags.isDefault, restoreSwitches == nil { restoreSwitches = flags.applyProcessSwitches() }
            let account = configuration.live.map { "live-preview:\($0.server):\($0.accountID)" } ?? "isolated-preview"
            let partition = try ServerUIPublicationPartition(
                server: HassServer(baseURL: URL(string: "https://preview.invalid")!))
            let root = partition.storageDirectory(in: directory.appendingPathComponent("publications", isDirectory: true))
            let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: root,
                transport: UKServerUIPreviewAssetFiles(directory: directory.appendingPathComponent("assets", isDirectory: true)))
            if let liveConfiguration = configuration.live {
                guard let taken = credential else { throw UKServerUIPreviewLiveData.Failure.credential }
                credential = nil
                let token = try taken.get()
                live = try UKServerUIPreviewLiveData(configuration: liveConfiguration, credential: token,
                                                    directory: root.appendingPathComponent("live"), store: entities)
                if let live {
                    liveProviders = try UKServerUIPreviewLiveProviders(live: live,
                        houseConfigCache: HouseConfigCache(fileURL: root.appendingPathComponent("live/HouseConfig.json")),
                        defaultsName: "ServerUIPreviewLive-" + liveConfiguration.accountID)
                }
            } else if let fixtures = configuration.entities {
                entities.replaceAll(fixtures.map { id, value in
                    EntityState(entityId: id, state: value.state, attributes: value.attributes)
                })
                if let gallery = configuration.gallery {
                    GalleryHouse.install()
                    self.fixtures = try UKServerUIPreviewFixtures(configuration: gallery, store: entities, flags: flags)
                }
            }
            let canvas = view.bounds.size, scale = Double(traitCollection.displayScale)
            let store = ServerUIPublicationStore<Prepared>(partition: partition, cacheDirectory: root,
                prepare: { [weak self] publication, context in
                    guard let self else { throw CancellationError() }
                    return try await self.prepare(publication, context: context, stager: stager,
                                                  root: root, canvas: canvas, scale: scale)
                }, discard: { candidate, protected in
                    try await Self.discard(candidate, retaining: protected, stager: stager)
                })
            publicationStore = store
            if let live, let liveProviders {
                // Production waits for the same two inputs (the house document and the signed-in user) before it builds providers.
                if view.window?.windowScene?.activationState == .foregroundActive { live.lifecycle.didBecomeActive() }
                await liveProviders.awaitInputs(timeout: .seconds(20))
                try Task.checkCancellation()
            }
            await store.bind(userID: "preview")
            // The gate: the first layout waits and the status line stays up, as the reference's content gate does (`gateDelayMs`).
            if let delay = flags.gateDelay { try await Task.sleep(for: delay) }
            await store.apply(try Self.publishedEvent(from: directory.appendingPathComponent("publication.json")))
            try Task.checkCancellation()
            guard let publication = store.current, let prepared = store.prepared else {
                status.text = "Configuration unavailable: \(store.status)"
                try writeReceipt(status: "\(store.status)")
                return
            }
            let host = prepared.renderer
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
            renderer = host
            status.isHidden = true
            try writeReceipt(status: "\(store.status)", publication: publication, assets: prepared.assets)
            if let live {
                observeScene()
                observations.observe { [weak self, weak live] in
                    guard let self, let live else { return }
                    do {
                        try self.writeReceipt(status: "\(store.status)", publication: publication, assets: prepared.assets)
                    } catch {
                        self.report("Preview receipt could not be saved.")
                    }
                    if live.connection.status == .rejected {
                        self.report("Home Assistant rejected the preview credential.")
                    }
                }
                if view.window?.windowScene?.activationState == .foregroundActive { live.lifecycle.didBecomeActive() }
            }
        } catch {
            live?.lifecycle.stop()
            liveProviders?.stop()
            let diagnostic: String
            switch error {
            case let value as ServerUIStoreError: diagnostic = "\(value)"
            case let value as ServerUIAssetError: diagnostic = "\(value)"
            case let value as UKServerUIRendererError: diagnostic = value.description
            case let value as UKServerUIPreviewLiveData.Failure: diagnostic = value.errorDescription ?? "Live preview failed."
            case is CancellationError: diagnostic = "Preview cancelled."
            case is DecodingError, Failure.bootstrap, Failure.publication: diagnostic = "Invalid preview bootstrap configuration."
            default: diagnostic = "Preview preparation failed."
            }
            report(diagnostic)
            do { try writeReceipt(status: "failed", diagnostic: diagnostic) }
            catch { NSLog("ServerUI preview: failure receipt could not be saved.") }
        }
    }

    /// The `published` event the integration would send for the envelope in `file`, judged by the same code the app uses.
    static func publishedEvent(from file: URL) throws -> ServerUIPublicationEvent {
        try publishedEvent(envelope: Data(contentsOf: file))
    }

    /// The `published` event for an envelope's bytes.
    static func publishedEvent(envelope bytes: Data) throws -> ServerUIPublicationEvent {
        do { return try ServerUIAcceptance.publishedEvent(envelope: bytes) }
        catch is ServerUIAcceptance.EnvelopeError { throw Failure.publication }
    }

    private func report(_ diagnostic: String) {
        status.text = diagnostic
        status.isHidden = false
        status.backgroundColor = .secondarySystemBackground
        view.bringSubviewToFront(status)
        NSLog("ServerUI preview: %@", diagnostic)
    }

    private func observeScene() {
        for name in [UIScene.didActivateNotification, UIScene.didEnterBackgroundNotification] {
            sceneObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sceneID = (note.object as? UIScene).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.view.window?.windowScene,
                          sceneID == ObjectIdentifier(scene) else { return }
                    if name == UIScene.didActivateNotification { self.live?.lifecycle.didBecomeActive() }
                    else { self.live?.lifecycle.didEnterBackground() }
                }
            })
        }
    }

    private func prepare(_ publication: ServerUICompositionPublication,
                         context: ServerUIPreparationContext<Prepared>, stager: ServerUIAssetStager,
                         root: URL, canvas: CGSize, scale: Double) async throws -> Prepared {
        try renderer?.validateUpdate(publication)
        guard case let .downloaded(assetID, _, blur, _, _, _) = publication.document.theme.background else {
            throw Failure.unsupportedBackground
        }
        let assets = try await stager.stage(publication, documentDigest: publication.documentSha256,
                                             reservingBytes: context.cacheWriteBytes)
        let directory = root.appendingPathComponent("renders", isDirectory: true)
            .appendingPathComponent(publication.documentSha256, isDirectory: true)
        do {
            guard let file = assets.assets.first(where: { $0.id == assetID })?.fileURL else { throw Failure.image }
            let image = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.image }
                return image
            }.value
            let defaultsName = "ServerUIPreview-\(publication.documentSha256)"
            guard let defaults = UserDefaults(suiteName: defaultsName) else { throw Failure.bootstrap }
            let percent: Int
            switch blur {
            case .fixed(let value): percent = value
            case .preference(_, let initial): percent = initial
            }
            defaults.set(percent, forKey: BackdropBlur.defaultsKey)
            let backdrop = HouseBackdropStore(verifiedPhoto: image, directory: directory,
                                               blur: BackdropBlurSettings(defaults: defaults))
            backdrop.setWindow(canvas, scale: scale)
            await backdrop.refresh()
            try Task.checkCancellation()
            guard backdrop.image != nil else { throw Failure.render }
            return try Prepared(publication: publication,
                context: live?.context ?? fixtures?.context ?? UKContext(store: entities, caller: stateCaller),
                assets: assets, backdrop: backdrop, renderDirectory: directory,
                weatherReader: live?.weatherReader(for: publication.document) ?? fixtures?.weatherReader(for: publication.document)
                    ?? UKServerUIPreviewPlaceholders.weatherReader(for: publication.document),
                cameraReader: live?.cameraReader(for: publication.document)
                    ?? UKServerUIPreviewPlaceholders.cameraReader(for: publication.document), fixtures: fixtures,
                live: liveProviders?.supply(for: publication, blur: backdrop.blur))
        } catch {
            try await stager.discard(assets, retaining: context.protected.map(\.assets))
            try Self.removeRender(directory, retaining: context.protected)
            throw error
        }
    }

    private static func discard(_ candidate: Prepared, retaining protected: [Prepared],
                                stager: ServerUIAssetStager) async throws {
        try await stager.discard(candidate.assets, retaining: protected.map(\.assets))
        try removeRender(candidate.renderDirectory, retaining: protected)
    }

    private static func removeRender(_ directory: URL, retaining protected: [Prepared]) throws {
        guard !protected.contains(where: { $0.renderDirectory == directory }),
              FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func writeReceipt(status: String, publication: ServerUICompositionPublication? = nil,
                              assets: ServerUIStagedAssets? = nil, diagnostic: String? = nil) throws {
        var value: [String: Any] = ["status": status, "fixtureActionsOnly": live == nil,
                                  "dataMode": live == nil ? "fixtures" : "live-read-only",
                                  "liveActionsEnabled": false, "updatedAt": Date().ISO8601Format()]
        value["live"] = live?.receipt
        if !flags.isDefault { value["flags"] = flags.receipt }
        value["diagnostic"] = diagnostic
        if let publication {
            value["revision"] = publication.revision
            value["documentSha256"] = publication.documentSha256
            value["publisherId"] = publication.publisherId
        }
        value["assets"] = assets?.assets.map(\.sha256) ?? []
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            .write(to: directory.appendingPathComponent("receipt.json"), options: .atomic)
    }
}
#endif
