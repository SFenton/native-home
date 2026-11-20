#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// MARK: - Fold sides gallery

/// Gallery page for sections that take sides (`FENTON_GALLERY=fold-sides`; `sh.fold-sides@1`): a real composition whose page has `foldSides: auto`, a
/// status rail with chips, a note that spans the top and four sections, and two buttons that stand in for the Duo's pose by publishing the fold the way the shell does
/// (`UKReflow` around the write): `foldSides.pose.partly` writes a band down the middle of the window, `foldSides.pose.flat` takes it away.
/// The page then does what it does on a Duo, wherever the window is wide enough to split (an iPad in landscape, the Duo); a narrower window stays one column.
/// `foldSides.pose` carries the pose's name.
@MainActor
enum UKFoldSidesGallery {
    /// The gallery page.
    static func make() -> UIViewController { UKFoldSidesGalleryViewController() }
}

/// The gallery's view controller: the fold-sides composition rendered by a ``UKServerUIRenderer`` above two buttons that publish the flat and partly folded poses.
@MainActor
final class UKFoldSidesGalleryViewController: UIViewController {
    private var renderer: UKServerUIRenderer?
    private let shell = UKShellEnvironment()
    private let poseMarker = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKBackdropView.base
        do {
            guard let image = HouseBackdropStore.fixturePhoto() else { throw CocoaError(.fileReadCorruptFile) }
            let defaults = UserDefaults(suiteName: "fold-sides-gallery-\(UUID().uuidString)") ?? .standard
            let backdrop = HouseBackdropStore(verifiedPhoto: image, directory: URL.temporaryDirectory.appending(path: "fold-sides-gallery-\(UUID().uuidString)"),
                                              blur: BackdropBlurSettings(defaults: defaults))
            var context = UKContext(store: EntityStore())
            context.shell = shell
            let publication = try ServerUICompositionPublication.decode(Data(UKFoldSidesGalleryFixture.envelope.utf8))
            let renderer = try UKServerUIRenderer(publication: publication, context: context, backdrop: backdrop)
            self.renderer = renderer
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
            setPose(partly: false)
        } catch {
            let failure = UILabel()
            failure.text = "Fold sides gallery failed: \(error)"
            failure.numberOfLines = 0
            failure.textColor = .white
            failure.accessibilityIdentifier = "foldSides.failure"
            failure.frame = view.bounds.insetBy(dx: 16, dy: 80)
            view.addSubview(failure)
        }
    }

    private func buttons() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = HassTokens.Spacing.xs
        for (name, partly) in [("flat", false), ("partly", true)] {
            let button = UKPrimaryButton(name.capitalized) { [weak self] in self?.setPose(partly: partly) }
            button.accessibilityIdentifier = "foldSides.pose.\(name)"
            row.addArrangedSubview(button)
        }
        poseMarker.font = .preferredFont(forTextStyle: .caption2)
        poseMarker.textColor = .white
        poseMarker.accessibilityIdentifier = "foldSides.pose"
        let column = UIStackView(arrangedSubviews: [poseMarker, row])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.xs
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        return column
    }

    /// Publishes the fold as `UKDeviceSignals.refresh` does for a posture change: the old picture first (Reduce Motion), the write, then the animated reflow.
    private func setPose(partly: Bool) {
        let band = CGRect(x: view.bounds.midX - 20.2, y: 0, width: 40.4, height: view.bounds.height)
        let changes = partly != (shell.windowHinge != nil)
        let before = changes && poseMarker.text != nil ? UKReflow.begin(view) : nil
        shell.windowFold = WindowFold(hinge: band, isFolding: partly)
        shell.windowHinge = partly ? band : nil
        if changes, poseMarker.text != nil { UKReflow.commit(view, before: before) }
        poseMarker.text = partly ? "partly" : "flat"
        poseMarker.accessibilityLabel = poseMarker.text
    }
}
#endif
