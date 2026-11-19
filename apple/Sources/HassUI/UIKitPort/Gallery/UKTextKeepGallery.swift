#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// MARK: - Kept text gallery (T-text-keep)

/// Gallery page for kept text (`FENTON_GALLERY=text-keep`; `sh.text-keep@1`): a real composition with one `keep` slot per host the contract
/// reaches, on synthetic entities, whose source a button row drives. Kept text is drawn and spoken exactly as live text.
///
/// Launch with:
/// - `FENTON_GALLERY_KEPT_TEXT_STATE=live|kept|before|loading`: where the source starts. `kept` answers first and goes unavailable after
///   `FENTON_GALLERY_KEPT_TEXT_DELAY_MS` (400 by default, so a journey can open a sheet while live); `before` is unavailable with no answer
///   yet; `loading` has heard nothing yet.
///
/// The buttons `keptText.set.live`, `.kept`, `.before` (unavailable, for a page built after no answer), `.loading` (reconnect: the store is
/// emptied and the page is pending again) and `.recover` (live again) drive it, and `keptText.state` carries the state's name.
@MainActor
enum UKTextKeepGallery {
    /// The gallery page.
    static func make() -> UIViewController { UKTextKeepGalleryViewController() }
}

/// What the synthetic sensors are doing.
enum UKTextKeepSourceState: String, CaseIterable {
    case live, kept, before, loading, recover
}

@MainActor
final class UKTextKeepGalleryViewController: UIViewController {
    /// The synthetic entities' store; a test reads its freshness.
    let store = EntityStore()
    private var renderer: UKServerUIRenderer?
    private let stateMarker = UILabel()
    private let environment = ProcessInfo.processInfo.environment
    private let startState: UKTextKeepSourceState

    /// A gallery page.
    /// - Parameter start: Where the source starts; `nil` reads `FENTON_GALLERY_KEPT_TEXT_STATE` (live by default).
    init(start: UKTextKeepSourceState? = nil) {
        startState = start ?? ProcessInfo.processInfo.environment["FENTON_GALLERY_KEPT_TEXT_STATE"].flatMap(UKTextKeepSourceState.init(rawValue:)) ?? .live
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The answered values, then what an unavailable sensor reads.
    private static let answers: [(id: String, state: String)] = [
        ("sensor.demo_keep_temperature", "21.5 degrees"), ("sensor.demo_keep_battery", "80 percent"),
        ("sensor.demo_keep_long_text", "Reading from the upstairs bathroom sensor, last reported this evening"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        let start = startState
        do {
            var context = UKContext(store: store)
            context.valuesPending = true
            let publication = try ServerUICompositionPublication.decode(Data(UKTextKeepGalleryFixture.envelope.utf8))
            let renderer = try UKServerUIRenderer(publication: publication, context: context, backdrop: Self.backdrop())
            self.renderer = renderer
            show(start == .kept ? .live : start)
            addChild(renderer)
            renderer.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(renderer.view)
            renderer.didMove(toParent: self)
            let controls = buttons()
            NSLayoutConstraint.activate([
                renderer.view.topAnchor.constraint(equalTo: view.topAnchor),
                renderer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                renderer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                renderer.view.bottomAnchor.constraint(equalTo: controls.topAnchor),
                controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            if start == .kept {
                let delay = environment["FENTON_GALLERY_KEPT_TEXT_DELAY_MS"].flatMap(Int.init) ?? 400
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(delay))
                    self?.show(.kept)
                }
            }
        } catch {
            let failure = UILabel()
            failure.text = "Kept text gallery failed: \(error)"
            failure.numberOfLines = 0
            failure.textColor = .white
            failure.accessibilityIdentifier = "keptText.failure"
            failure.frame = view.bounds.insetBy(dx: 16, dy: 80)
            view.addSubview(failure)
        }
    }

    /// A one-colour wallpaper store, as the hosted renderer tests use.
    private static func backdrop() throws -> HouseBackdropStore {
        guard let image = HouseBackdropStore.fixturePhoto() else { throw CocoaError(.fileReadCorruptFile) }
        let defaults = UserDefaults(suiteName: "text-keep-gallery-\(UUID().uuidString)") ?? .standard
        return HouseBackdropStore(verifiedPhoto: image, directory: URL.temporaryDirectory.appending(path: "text-keep-gallery-\(UUID().uuidString)"),
                                  blur: BackdropBlurSettings(defaults: defaults))
    }

    /// The state buttons and the marker that names the state.
    private func buttons() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = HassTokens.Spacing.xs
        row.translatesAutoresizingMaskIntoConstraints = false
        for state in UKTextKeepSourceState.allCases {
            let button = UKPrimaryButton(state.rawValue.capitalized) { [weak self] in self?.show(state) }
            button.accessibilityIdentifier = "keptText.set.\(state.rawValue)"
            row.addArrangedSubview(button)
        }
        stateMarker.font = .preferredFont(forTextStyle: .caption2)
        stateMarker.textColor = .white
        stateMarker.accessibilityIdentifier = "keptText.state"
        stateMarker.translatesAutoresizingMaskIntoConstraints = false
        let column = UIStackView(arrangedSubviews: [stateMarker, row])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.xs
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        return column
    }

    /// Puts the synthetic sensors in `state`.
    private func show(_ state: UKTextKeepSourceState) {
        switch state {
        case .live, .recover:
            _ = store.replaceAll(Self.answers.map { EntityState(entityId: $0.id, state: $0.state) })
        case .kept, .before:
            // Unavailable: after an answer the slots keep it; before one they draw their fallback. The whole state is handed over, so the
            // store has heard from the server: `apply` alone leaves an empty store empty, and every slot reads "not heard yet" (loading).
            _ = store.replaceAll(Self.answers.map { EntityState(entityId: $0.id, state: "unavailable") })
        case .loading:
            store.reset()
        }
        stateMarker.text = state.rawValue
        stateMarker.accessibilityLabel = state.rawValue
    }
}
#endif
