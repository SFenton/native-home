#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// `FENTON_GALLERY=bedroom`: the wake-light and both bed tiles on fixture state with a recording caller that answers like Home Assistant
/// (`BedroomGallery`). `FENTON_GALLERY_SCENARIO` picks a fixture (`default`, `ringing`, `solo-trip`, `unavailable`, `waking`, `hot-flash`),
/// `FENTON_GALLERY_SHEET` opens `wake-light`, `stephens-bed` or `stephs-bed` at launch, `FENTON_GALLERY_TAB` picks its first tab.
@MainActor
final class UKBedroomGalleryViewController: UKPageViewController {
    private enum OpenSheet: Equatable {
        case wakeLight(WakeLightSheet.Tab)
        case bed(BedSide, BedSideSheet.Tab)
    }

    private let store: EntityStore
    private let recorder: BedroomGalleryRecorder
    private let devices: BedroomDevices
    private var initial: OpenSheet?
    private var queued: OpenSheet?

    init() {
        let environment = ProcessInfo.processInfo.environment
        let scenario = environment["FENTON_GALLERY_SCENARIO"].flatMap(BedroomFixtures.Scenario.init(rawValue:)) ?? .default
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(scenario), freshness: .live)
        let recorder = BedroomGalleryRecorder(store: store)
        self.store = store
        self.recorder = recorder
        devices = BedroomDevices(store: store, caller: recorder)
        let ctx = UKGalleryChrome.context(store: store, caller: recorder)
        let tab = environment["FENTON_GALLERY_TAB"]
        initial = environment["FENTON_GALLERY_SHEET"].flatMap { sheet in
            if sheet == "wake-light" { return .wakeLight(tab.flatMap(WakeLightSheet.Tab.init(rawValue:)) ?? .alarms) }
            return MasterBedroom.bed(id: sheet).map { .bed($0.side, tab.flatMap(BedSideSheet.Tab.init(rawValue:)) ?? .temperature) }
        }
        super.init(context: ctx, title: "Bedroom Devices")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.08)
        let scroll = UKColumnScroll(maxWidth: nil, spacing: HassTokens.Spacing.l)
        install(scrollView: scroll)
        let header = UILabel.uk(.title3, weight: .bold, ink: .label)
        header.text = "Sleep & Wake"
        header.accessibilityTraits = .header
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: UKFont.scaled(160, relativeTo: .subheadline, traits: traitCollection), maxColumns: 3))
        var tiles: [UKGridItem] = [UKGridItem(UKBedroomTile.wakeLight(devices.wakeLight, context: context) { [weak self] in self?.open(.wakeLight(.alarms)) })]
        for bed in devices.beds {
            tiles.append(UKGridItem(UKBedroomTile.bedSide(bed, context: context) { [weak self] in self?.open(.bed(bed.config.side, .temperature)) }))
        }
        grid.setItems(tiles)
        scroll.stack.addArrangedSubview(header)
        scroll.stack.addArrangedSubview(UKGridHost(grid))
        if !GalleryEnvironment.isClean {
            let line = UKGalleryLastCallView()
            bag.observe { [recorder, line] in line.record(recorder.lastCall) }
            scroll.stack.addArrangedSubview(line)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let initial, presentedViewController == nil {
            self.initial = nil
            open(initial)
        }
    }

    private func open(_ sheet: OpenSheet) {
        let accessory: UIView? = GalleryEnvironment.isClean ? nil : UKLastCallBar { [recorder] in recorder.lastCall }
        let modal: UKHassModalController
        switch sheet {
        case let .wakeLight(tab):
            modal = UKWakeLightSheet.make(devices: devices, initialTab: tab, context: context, accessory: accessory) { [weak self] side in
                // The host queues it until this sheet has closed.
                self?.open(.bed(side, .alarms))
            }
        case let .bed(side, tab):
            modal = UKBedSideSheet.make(devices: devices, side: side, initialTab: tab, context: context, accessory: accessory)
        }
        modal.present(from: self)
    }
}
#endif
