#if os(iOS) && DEBUG
import CryptoKit
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
/// event: there is no publisher HTTP endpoint. The `ha-credential` file is consumed once; bearers stay in memory only.
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
             fixtures: UKServerUIPreviewFixtures? = nil) throws {
            try fixtures?.prepare(publication, backdrop: backdrop)
            renderer = try UKServerUIRenderer(publication: publication, context: context, backdrop: backdrop,
                collections: fixtures?.collections() ?? [:], records: fixtures?.records ?? .init(),
                deviceResponder: fixtures?.caller, canEditBedroom: fixtures?.configuration.administrator == true,
                roomResidentId: { fixtures?.viewerKey },
                weatherReader: weatherReader, cameraReader: cameraReader, accountProvider: fixtures,
                settingsProviders: fixtures?.settings ?? [:], shellHeader: fixtures?.header)
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
    private var live: UKServerUIPreviewLiveData?
    private var fixtures: UKServerUIPreviewFixtures?
    private let observations = UKObservationBag()
    private var loadTask: Task<Void, Never>?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    deinit {
        loadTask?.cancel()
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
    }

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
        }
    }

    /// Credentials are consumed before use, including invalid UTF-8/empty files, and never written into a receipt.
    static func consumeCredential(at file: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let bytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        guard let value = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            throw UKServerUIPreviewLiveData.Failure.credential
        }
        return value
    }

    private func loadPublication() async {
        do {
            try writeReceipt(status: "loading")
            let configuration = try JSONDecoder().decode(Configuration.self,
                from: Data(contentsOf: Self.directory.appendingPathComponent("bootstrap.json")))
            try configuration.validate()
            let account = configuration.live.map { "live-preview:\($0.server):\($0.accountID)" } ?? "isolated-preview"
            let partition = try ServerUIPublicationPartition(
                server: HassServer(baseURL: URL(string: "https://preview.invalid")!))
            let root = partition.storageDirectory(in: Self.directory.appendingPathComponent("publications", isDirectory: true))
            let stager = try ServerUIAssetStager(partition: partition, partitionDirectory: root,
                transport: UKServerUIPreviewAssetFiles(directory: Self.directory.appendingPathComponent("assets", isDirectory: true)))
            if let liveConfiguration = configuration.live {
                guard let token = try Self.consumeCredential(at: Self.directory.appendingPathComponent("ha-credential")) else {
                    throw UKServerUIPreviewLiveData.Failure.credential
                }
                live = try UKServerUIPreviewLiveData(configuration: liveConfiguration, credential: token,
                                                    directory: root.appendingPathComponent("live"), store: entities)
            } else if let fixtures = configuration.entities {
                entities.replaceAll(fixtures.map { id, value in
                    EntityState(entityId: id, state: value.state, attributes: value.attributes)
                })
                if let gallery = configuration.gallery {
                    GalleryHouse.install()
                    self.fixtures = try UKServerUIPreviewFixtures(configuration: gallery, store: entities)
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
            await store.bind(userID: "preview")
            await store.apply(try Self.publishedEvent(from: Self.directory.appendingPathComponent("publication.json")))
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
        guard bytes.count <= 2_162_688,
              let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let revision = envelope["revision"] as? Int else { throw Failure.publication }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let reply = try JSONSerialization.data(withJSONObject: [
            "state": "published", "epoch": "preview", "revision": revision, "envelopeSha256": hash, "envelope": envelope,
        ] as [String: Any])
        return ServerUIPublicationEvent.judge(.success(reply))
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
                context: live?.context ?? fixtures?.context ?? UKContext(store: entities, caller: caller),
                assets: assets, backdrop: backdrop, renderDirectory: directory,
                weatherReader: live?.weatherReader(for: publication.document) ?? fixtures?.weatherReader(for: publication.document),
                cameraReader: live?.cameraReader(for: publication.document), fixtures: fixtures)
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
        value["diagnostic"] = diagnostic
        if let publication {
            value["revision"] = publication.revision
            value["documentSha256"] = publication.documentSha256
            value["publisherId"] = publication.publisherId
        }
        value["assets"] = assets?.assets.map(\.sha256) ?? []
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            .write(to: Self.directory.appendingPathComponent("receipt.json"), options: .atomic)
    }
}
#endif
