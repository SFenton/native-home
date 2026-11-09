#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A controller's sheet (`SprinklerControllerSheet`; web `SprinklerController.tsx` modal): status, zones, Stop watering, rain delay and
/// smart watering, and each program. A zone pushes Water now; a program pushes its schedule editor (HIG: Sheets, a navigation stack
/// inside the sheet in place of the web's in-modal detail pages). A page sheet at full height (`hassSheet(.page, height: .full)`),
/// since detail pages push inside it.
@MainActor
enum UKSprinklerSheet {
    /// Presents `controller`'s sheet over `presenter`.
    /// - Parameters:
    ///   - initialDetail: A detail page already pushed on it (gallery and journeys).
    ///   - context: The page's context; the sheet takes its own with `surface` `.sheet`.
    static func present(controller: SprinklerController, initialDetail: SprinklerDetail?, context: UKContext, from presenter: UIViewController) {
        let navigator = UKSprinklerSheetNavigator(controller: controller, context: context.with { $0.surface = .sheet })
        let overview = UKSprinklerOverviewController(controller: controller, context: navigator.context, navigator: navigator)
        var options = UKHassModalOptions(title: controller.config.title)
        options.width = .page
        // Detail pages push inside it.
        options.height = .full
        // The overview is content of a sheet page, like the pushed pages (`UKSprinklerPinnedPage`).
        overview.loadViewIfNeeded()
        let root = UKSheetPinnedBarPage(content: overview, bar: nil, scrollView: overview.collectionView)
        overview.host = root
        let modal = UKHassModalController(root: root, options: options)
        navigator.modal = modal
        controller.clearError()
        if let initialDetail { navigator.open(initialDetail, animated: false) }
#if DEBUG
        UKRoomsLastCall.attach(to: modal, caller: context.caller)
#endif
        modal.present(from: presenter)
    }
}

/// Pushes, pops and closes inside one controller's sheet (the `path` of `HassPathModal` and its `dismiss`).
@MainActor
final class UKSprinklerSheetNavigator {
    weak var modal: UKHassModalController?
    let controller: SprinklerController
    let context: UKContext

    init(controller: SprinklerController, context: UKContext) {
        self.controller = controller
        self.context = context
    }

    /// Pushes a detail page.
    func open(_ detail: SprinklerDetail, animated: Bool = true) {
        guard let modal else { return }
        let page: UIViewController
        switch detail {
        case let .water(zone):
            // Close on every level, so the sheet closes from a pushed page too (HIG: Sheets).
            page = UKSprinklerWaterPage.make(controller: controller, zone: zone, context: context, done: { [weak self] in self?.pop() },
                                            close: { [weak self] in self?.close() })
        case let .schedule(zone):
            // The schedule editor carries its own Close and Back, which ask before dropping edits.
            page = UKSprinklerSchedulePage.make(controller: controller, zone: zone, context: context, done: { [weak self] in self?.pop() },
                                               close: { [weak self] in self?.close() })
        }
        modal.push(page, animated: animated)
    }

    func pop() {
        guard let modal, modal.viewControllers.count > 1 else { return }
        modal.popViewController(animated: true)
    }

    func close() { modal?.close() }
}

// MARK: - Overview

/// The sheet's root list: status pills, zones, controls, settings and the schedule (`SprinklerOverview`).
@MainActor
final class UKSprinklerOverviewController: UKSprinklerListController {
    private let controller: SprinklerController
    private let context: UKContext
    private let navigator: UKSprinklerSheetNavigator
    private let format = SprinklerFormat()
    private let bag = UKObservationBag()
    /// The sheet page that holds this list (its navigation item is the sheet's).
    weak var host: UIViewController? { didSet { if isViewLoaded { refresh() } } }

    init(controller: SprinklerController, context: UKContext, navigator: UKSprinklerSheetNavigator) {
        self.controller = controller
        self.context = context
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The sheet is tinted with the action ink (`.tint(HassTokens.Ink.action)`).
        view.tintColor = UKInk.action
        collectionView.accessibilityIdentifier = "sprinkler.overview"
        bag.observe { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let controller = controller
        let navigator = navigator
        let format = format
        let snapshot = controller.snapshot
        let valuesPending = context.valuesPending
        UKSheetSubtitle.apply(format.subtitle(snapshot), to: (host ?? self).navigationItem)
        var sections: [UKSprinklerSection] = []

        if let error = controller.errorMessage {
            sections.append(UKSprinklerSection(id: "error", rows: [
                UKSprinklerRow(id: "error", make: { UKSprinklerAlertContent() },
                               update: { ($0 as? UKSprinklerAlertContent)?.show(message: error) }, edgeToEdge: true),
            ]))
        }

        sections.append(UKSprinklerSection(id: "status", header: "Status", rows: [
            UKSprinklerRow(id: "pills", make: { UKSprinklerPillsRow(valuesPending: valuesPending) },
                           update: { ($0 as? UKSprinklerPillsRow)?.show(snapshot) }, edgeToEdge: true),
        ]))

        let zones = snapshot.zones.enumerated().map { index, zone in
            let active = controller.activeValve == zone.config.valveEntityId
            // Open while another zone waters (Water now explains and disables Start there): a disabled row dims its name below 4.5:1
            // and hides the zone's status from VoiceOver.
            return UKSprinklerRow(
                id: "zone.\(index)", make: { UKSprinklerRowContent() },
                update: {
                    ($0 as? UKSprinklerRowContent)?.show(
                        symbol: SprinklerStyle.symbol, isActive: active, title: zone.name,
                        lines: [!zone.available ? "Unavailable" : active ? "Watering" : "Closed", format.lastStart(zone.lastRun)],
                        hint: "Water now", identifier: "sprinkler.zone.\(index)", isEnabled: zone.available)
                },
                disclosure: true, action: zone.available ? { navigator.open(.water(zone: index)) } : nil, isEnabled: zone.available)
        }
        sections.append(UKSprinklerSection(id: "zones", header: "Zones", rows: zones))

        let watering = controller.isWatering
        sections.append(UKSprinklerSection(id: "controls", header: "Controls", rows: [
            UKSprinklerRow(id: "stop", make: { UKSprinklerButtonContent() },
                           update: {
                               ($0 as? UKSprinklerButtonContent)?.show(title: "Stop Watering", symbol: "stop.circle",
                                                                       ink: watering ? UKInk.danger : UKInk.secondary, isEnabled: watering,
                                                                       identifier: "sprinkler.stop")
                           },
                           action: watering ? { controller.stopWatering() } : nil, isEnabled: watering),
        ]))

        let rainDelay = controller.rainDelay
        let smartWatering = controller.smartWatering
        sections.append(UKSprinklerSection(id: "settings", header: "Settings", rows: [
            UKSprinklerRow(id: "rainDelay", make: { UKSprinklerToggleContent(symbol: "cloud.heavyrain") },
                           update: {
                               ($0 as? UKSprinklerToggleContent)?.show(title: "Rain Delay · 24 Hours", isOn: rainDelay, isEnabled: snapshot.available,
                                                                       identifier: "sprinkler.rainDelay") { controller.setRainDelay($0) }
                           }),
            UKSprinklerRow(id: "smartWatering", make: { UKSprinklerToggleContent(symbol: "wand.and.stars") },
                           update: {
                               ($0 as? UKSprinklerToggleContent)?.show(title: "Smart Watering", isOn: smartWatering, isEnabled: snapshot.available,
                                                                       identifier: "sprinkler.smartWatering") { controller.setSmartWatering($0) }
                           }),
        ]))

        // Zones without a program are left out, so every row is one program row.
        let programs = snapshot.zones.indices.compactMap { index in
            controller.program(index).map { (index: index, zone: snapshot.zones[index], program: $0) }
        }.map { entry in
            UKSprinklerRow(id: "program.\(entry.index)", make: { UKSprinklerProgramContent() }, update: {
                ($0 as? UKSprinklerProgramContent)?.show(
                    index: entry.index, name: format.programName(zone: entry.zone.name), isOn: entry.program.enabled,
                    lines: [format.summary(entry.program), format.details(entry.program, zone: entry.zone.name)],
                    isAvailable: entry.program.available, open: { navigator.open(.schedule(zone: entry.index)) },
                    send: { controller.setProgramEnabled(zone: entry.index, $0) })
            })
        }
        sections.append(UKSprinklerSection(id: "schedule", header: "Schedule", rows: programs))

        setSections(sections, animated: isViewLoaded && view.window != nil)
    }
}
#endif
